/* SPDX-License-Identifier: MIT */

#import "OrbisTunnelBridge.h"

#import <Network/Network.h>

static NSString *const OrbisTunnelErrorDomain = @"com.dnexus.orbis.tunnel";
static const size_t OrbisTunnelChunkSize = 64 * 1024;
static const size_t OrbisTunnelMaximumMessageSize = 4 * 1024 * 1024;

static NSError *OrbisTunnelError(NSInteger code, NSString *message)
{
	// Do not attach underlying URLSession errors or requests: they may contain credentials.
	return [NSError errorWithDomain:OrbisTunnelErrorDomain
	                          code:code
	                      userInfo:@{ NSLocalizedDescriptionKey : message }];
}

@interface OrbisTunnelStream : NSObject <NSURLSessionWebSocketDelegate>
@property(nonatomic) nw_connection_t connection;
@property(nonatomic) dispatch_queue_t queue;
@property(nonatomic) NSURLSession *session;
@property(nonatomic) NSURLSessionWebSocketTask *webSocket;
@property(nonatomic) dispatch_source_t heartbeat;
@property(nonatomic, copy) void (^finished)(OrbisTunnelStream *, NSError *);
@property(nonatomic) BOOL opened;
@property(nonatomic) BOOL ended;
- (void)startWithRequest:(NSURLRequest *)request;
- (void)finishWithError:(NSError *)error;
@end

@implementation OrbisTunnelStream

- (void)startWithRequest:(NSURLRequest *)request
{
	__weak OrbisTunnelStream *weakSelf = self;
	nw_connection_set_queue(_connection, _queue);
	nw_connection_set_state_changed_handler(_connection, ^(nw_connection_state_t state, nw_error_t error) {
		(void)error;
		OrbisTunnelStream *stream = weakSelf;
		if (!stream || stream.ended)
			return;
		if (state == nw_connection_state_ready)
		{
			NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
			configuration.HTTPCookieStorage = nil;
			configuration.HTTPShouldSetCookies = NO;
			configuration.URLCache = nil;
			configuration.timeoutIntervalForRequest = 15;
			stream.session = [NSURLSession sessionWithConfiguration:configuration delegate:stream delegateQueue:nil];
			stream.webSocket = [stream.session webSocketTaskWithRequest:request];
			stream.webSocket.maximumMessageSize = OrbisTunnelMaximumMessageSize;
			[stream.webSocket resume];
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), stream.queue, ^{
				OrbisTunnelStream *pending = weakSelf;
				if (pending && !pending.opened && !pending.ended)
					[pending finishWithError:OrbisTunnelError(1, @"The tunnel connection timed out.")];
			});
		}
		else if (state == nw_connection_state_failed)
			[stream finishWithError:OrbisTunnelError(2, @"The local RDP connection failed.")];
	});
	nw_connection_start(_connection);
}

- (void)readFromTCP
{
	if (_ended)
		return;
	__weak OrbisTunnelStream *weakSelf = self;
	nw_connection_receive(_connection, 1, OrbisTunnelChunkSize,
	                      ^(dispatch_data_t content, nw_content_context_t context, bool complete, nw_error_t error) {
		(void)context;
		OrbisTunnelStream *stream = weakSelf;
		if (!stream || stream.ended)
			return;
		if (error)
		{
			[stream finishWithError:OrbisTunnelError(2, @"The local RDP connection failed.")];
			return;
		}
		if (!content || dispatch_data_get_size(content) == 0)
		{
			if (complete)
				[stream finishWithError:nil];
			else
				[stream readFromTCP];
			return;
		}
		const void *bytes = NULL;
		size_t length = 0;
		dispatch_data_t mapped = dispatch_data_create_map(content, &bytes, &length);
		NSData *data = [NSData dataWithBytes:bytes length:length];
		(void)mapped;
		NSURLSessionWebSocketMessage *message = [[NSURLSessionWebSocketMessage alloc] initWithData:data];
		[stream.webSocket sendMessage:message completionHandler:^(NSError *sendError) {
			dispatch_async(stream.queue, ^{
				if (stream.ended)
					return;
				if (sendError)
					[stream finishWithError:OrbisTunnelError(3, @"The tunnel could not send RDP data.")];
				else if (complete)
					[stream finishWithError:nil];
				else
					[stream readFromTCP];
			});
		}];
	});
}

- (void)readFromWebSocket
{
	if (_ended)
		return;
	__weak OrbisTunnelStream *weakSelf = self;
	[_webSocket receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
		OrbisTunnelStream *stream = weakSelf;
		if (!stream)
			return;
		dispatch_async(stream.queue, ^{
			if (stream.ended)
				return;
			if (error)
			{
				[stream finishWithError:OrbisTunnelError(4, @"The tunnel closed or could not receive RDP data.")];
				return;
			}
			if (message.type != NSURLSessionWebSocketMessageTypeData)
			{
				[stream finishWithError:OrbisTunnelError(5, @"The tunnel sent a non-binary message.")];
				return;
			}
			NSData *data = message.data;
			if (data.length == 0)
			{
				[stream readFromWebSocket];
				return;
			}
			// Copy into dispatch-owned storage, preserving message order and applying backpressure.
			dispatch_data_t content = dispatch_data_create(data.bytes, data.length, stream.queue,
			                                               DISPATCH_DATA_DESTRUCTOR_DEFAULT);
			nw_connection_send(stream.connection, content, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, false,
			                   ^(nw_error_t sendError) {
				if (stream.ended)
					return;
				if (sendError)
					[stream finishWithError:OrbisTunnelError(2, @"The local RDP connection failed.")];
				else
					[stream readFromWebSocket];
			});
		});
	}];
}

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)task
    didOpenWithProtocol:(NSString *)protocol
{
	dispatch_async(_queue, ^{
		if (self.ended)
			return;
		self.opened = YES;
		[self readFromTCP];
		[self readFromWebSocket];
		__weak OrbisTunnelStream *weakSelf = self;
		self.heartbeat = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
		dispatch_source_set_timer(self.heartbeat, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC),
		                          30 * NSEC_PER_SEC, NSEC_PER_SEC);
		dispatch_source_set_event_handler(self.heartbeat, ^{
			OrbisTunnelStream *stream = weakSelf;
			[stream.webSocket sendPingWithPongReceiveHandler:^(NSError *error) {
				if (error)
					dispatch_async(stream.queue, ^{
						[stream finishWithError:OrbisTunnelError(4, @"The tunnel heartbeat failed.")];
					});
			}];
		});
		dispatch_resume(self.heartbeat);
	});
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSURLRequest *))completionHandler
{
	// Service tokens must never follow a redirect to an Access login or another host.
	completionHandler(nil);
	dispatch_async(_queue, ^{
		[self finishWithError:OrbisTunnelError(6, @"Access redirected the connection. Check the Service Auth policy.")];
	});
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    didCompleteWithError:(NSError *)error
{
	dispatch_async(_queue, ^{
		NSInteger status = [(NSHTTPURLResponse *)task.response statusCode];
		NSString *message = @"The tunnel connection closed.";
		if (!self.opened)
		{
			if (status == 401 || status == 403)
				message = @"Access denied the connection. Check the service token and Service Auth policy.";
			else if (status >= 300 && status < 400)
				message = @"Access redirected the connection. Check the Service Auth policy.";
			else
				message = @"Could not open the tunnel. Check its hostname, TLS certificate, and RDP route.";
		}
		[self finishWithError:OrbisTunnelError(status ?: 7, message)];
	});
}

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)task
    didCloseWithCode:(NSURLSessionWebSocketCloseCode)code reason:(NSData *)reason
{
	dispatch_async(_queue, ^{
		[self finishWithError:OrbisTunnelError(4, @"The tunnel connection closed.")];
	});
}

- (void)finishWithError:(NSError *)error
{
	if (_ended)
		return;
	_ended = YES;
	if (_heartbeat)
		dispatch_source_cancel(_heartbeat);
	_heartbeat = nil;
	// Publish a sanitized handshake error before closing TCP and waking FreeRDP.
	void (^finished)(OrbisTunnelStream *, NSError *) = _finished;
	_finished = nil;
	if (finished)
		finished(self, error);
	nw_connection_set_state_changed_handler(_connection, nil);
	nw_connection_cancel(_connection);
	[_webSocket cancelWithCloseCode:NSURLSessionWebSocketCloseCodeGoingAway reason:nil];
	[_session invalidateAndCancel];
	_webSocket = nil;
	_session = nil;
}

@end

@interface OrbisTunnelBridge ()
@property(atomic, readwrite, strong) NSError *lastHandshakeError;
@end

@implementation OrbisTunnelBridge
{
	NSURLRequest *_request;
	dispatch_queue_t _queue;
	nw_listener_t _listener;
	NSMutableSet<OrbisTunnelStream *> *_streams;
	void (^_ready)(uint16_t, NSError *);
	void (^_streamFailure)(NSError *);
	BOOL _started;
	BOOL _stopped;
}

+ (NSURL *)endpointForHostname:(NSString *)hostname error:(NSError **)error
{
	if (error)
		*error = nil;
	NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:
	    @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"] invertedSet];
	BOOL valid = hostname.length > 0 && hostname.length <= 253 &&
	             [hostname rangeOfCharacterFromSet:invalid].location == NSNotFound;
	for (NSString *label in [hostname componentsSeparatedByString:@"."])
		valid &= label.length > 0 && label.length <= 63 &&
		         ![label hasPrefix:@"-"] && ![label hasSuffix:@"-"];
	if (!valid)
	{
		if (error)
			*error = OrbisTunnelError(8, @"Enter a tunnel hostname without a URL scheme, port, path, or spaces.");
		return nil;
	}
	return [NSURL URLWithString:[NSString stringWithFormat:@"wss://%@/", hostname.lowercaseString]];
}

- (instancetype)initWithEndpoint:(NSURL *)endpoint clientID:(NSString *)clientID
                    clientSecret:(NSString *)clientSecret error:(NSError **)error
{
	if (!(self = [super init]))
		return nil;
	if (error)
		*error = nil;
	BOOL secure = [endpoint.scheme.lowercaseString isEqualToString:@"wss"];
	// Plain WebSockets are allowed only on numeric loopback for executable local fixtures.
	BOOL localFixture = [endpoint.scheme.lowercaseString isEqualToString:@"ws"] &&
	                    [endpoint.host isEqualToString:@"127.0.0.1"];
	NSCharacterSet *newlines = [NSCharacterSet newlineCharacterSet];
	if ((!secure && !localFixture) || endpoint.host.length == 0 || endpoint.user || endpoint.password ||
	    endpoint.fragment || clientID.length == 0 || clientSecret.length == 0 ||
	    [clientID rangeOfCharacterFromSet:newlines].location != NSNotFound ||
	    [clientSecret rangeOfCharacterFromSet:newlines].location != NSNotFound)
	{
		if (error)
			*error = OrbisTunnelError(8, @"A secure tunnel endpoint and valid service credentials are required.");
		return nil;
	}
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:endpoint];
	[request setValue:clientID forHTTPHeaderField:@"CF-Access-Client-Id"];
	[request setValue:clientSecret forHTTPHeaderField:@"CF-Access-Client-Secret"];
	_request = [request copy];
	_queue = dispatch_queue_create("com.dnexus.orbis.tunnel", DISPATCH_QUEUE_SERIAL);
	_streams = [NSMutableSet new];
	return self;
}

- (void)startOnPort:(uint16_t)port ready:(void (^)(uint16_t, NSError *))ready
     streamFailure:(void (^)(NSError *))streamFailure
{
	dispatch_async(_queue, ^{
		if (self->_started || self->_stopped)
		{
			ready(0, OrbisTunnelError(9, @"The tunnel bridge has already been started or stopped."));
			return;
		}
		self->_started = YES;
		self->_ready = [ready copy];
		self->_streamFailure = [streamFailure copy];
		nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,
		                                                            NW_PARAMETERS_DEFAULT_CONFIGURATION);
		NSString *portString = [NSString stringWithFormat:@"%u", port];
		nw_endpoint_t local = nw_endpoint_create_host("127.0.0.1", portString.UTF8String);
		nw_parameters_set_local_endpoint(parameters, local);
		self->_listener = nw_listener_create(parameters);
		if (!self->_listener)
		{
			[self completeReadyWithPort:0 error:OrbisTunnelError(10, @"Could not create the local tunnel listener.")];
			return;
		}
		__weak OrbisTunnelBridge *weakSelf = self;
		nw_listener_set_queue(self->_listener, self->_queue);
		nw_listener_set_state_changed_handler(self->_listener, ^(nw_listener_state_t state, nw_error_t error) {
			(void)error;
			OrbisTunnelBridge *bridge = weakSelf;
			if (!bridge || bridge->_stopped)
				return;
			if (state == nw_listener_state_ready)
				[bridge completeReadyWithPort:nw_listener_get_port(bridge->_listener) error:nil];
			else if (state == nw_listener_state_failed)
			{
				NSError *failure = OrbisTunnelError(10, @"Could not listen on the requested loopback port.");
				if (bridge->_ready)
					[bridge completeReadyWithPort:0 error:failure];
				else if (bridge->_streamFailure)
					bridge->_streamFailure(failure);
				[bridge stop];
			}
		});
		nw_listener_set_new_connection_handler(self->_listener, ^(nw_connection_t connection) {
			OrbisTunnelBridge *bridge = weakSelf;
			if (!bridge || bridge->_stopped || bridge->_streams.count >= 4)
			{
				nw_connection_cancel(connection);
				return;
			}
			OrbisTunnelStream *stream = [OrbisTunnelStream new];
			stream.connection = connection;
			stream.queue = bridge->_queue;
			stream.finished = ^(OrbisTunnelStream *finished, NSError *error) {
				OrbisTunnelBridge *owner = weakSelf;
				if (!owner)
					return;
				[owner->_streams removeObject:finished];
				if (error && !finished.opened)
					owner.lastHandshakeError = error;
				if (error && owner->_streamFailure)
					owner->_streamFailure(error);
			};
			[bridge->_streams addObject:stream];
			bridge.lastHandshakeError = nil;
			[stream startWithRequest:bridge->_request];
		});
		nw_listener_start(self->_listener);
	});
}

- (void)completeReadyWithPort:(uint16_t)port error:(NSError *)error
{
	void (^ready)(uint16_t, NSError *) = _ready;
	_ready = nil;
	if (ready)
		ready(port, error);
}

- (void)stop
{
	dispatch_async(_queue, ^{
		if (self->_stopped)
			return;
		self->_stopped = YES;
		if (self->_listener)
			nw_listener_cancel(self->_listener);
		self->_listener = nil;
		for (OrbisTunnelStream *stream in [self->_streams copy])
			[stream finishWithError:nil];
		[self->_streams removeAllObjects];
		[self completeReadyWithPort:0 error:OrbisTunnelError(11, @"The tunnel bridge was stopped.")];
		self->_streamFailure = nil;
		self->_request = nil;
	});
}

@end
