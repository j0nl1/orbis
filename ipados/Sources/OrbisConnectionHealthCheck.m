/* SPDX-License-Identifier: MIT */

#import "OrbisConnectionHealthCheck.h"
#import "OrbisProfile.h"
#import <Network/Network.h>

@interface OrbisConnectionHealthCheck ()
@property(nonatomic, copy) NSString *hostname;
@property(nonatomic) NSUInteger port;
@property(nonatomic) NSTimeInterval timeout;
@property(nonatomic, strong) id<OrbisConnectionTransport> transport;
@property(nonatomic, strong) id<OrbisTransportSession> session;
@property(nonatomic, strong) nw_connection_t connection;
@property(nonatomic, strong) dispatch_source_t deadline;
@property(nonatomic, strong) NSMutableData *response;
@property(nonatomic, copy) void (^completion)(BOOL available);
@property(nonatomic) BOOL finished;
@end

@implementation OrbisConnectionHealthCheck
- (instancetype)initWithProfile:(OrbisProfile *)profile
                      transport:(id<OrbisConnectionTransport>)transport
                        timeout:(NSTimeInterval)timeout
{
	if ((self = [super init]))
	{
		_hostname = [profile.host copy];
		_port = profile.port;
		_transport = transport;
		_timeout = timeout;
		_response = [NSMutableData new];
	}
	return self;
}

- (void)startWithCompletion:(void (^)(BOOL))completion
{
	NSAssert([NSThread isMainThread], @"Start health checks on the main queue");
	NSAssert(!self.completion && !self.finished, @"Health checks are single use");
	self.completion = completion;
	__weak OrbisConnectionHealthCheck *weakSelf = self;
	self.deadline = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
	dispatch_source_set_timer(self.deadline,
	    dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(0.01, self.timeout) * NSEC_PER_SEC)),
	    DISPATCH_TIME_FOREVER, 0);
	dispatch_source_set_event_handler(self.deadline, ^{ [weakSelf finish:NO]; });
	dispatch_resume(self.deadline);
	if (!self.transport)
	{
		dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf finish:NO]; });
		return;
	}
	self.session = [self.transport prepareWithCompletion:^(OrbisTransportDestination *destination, NSError *error) {
		OrbisConnectionHealthCheck *check = weakSelf;
		if (!check || check.finished)
			return;
		if (error)
			[check finish:NO];
		else
			[check connectToHostname:destination ? destination.hostname : check.hostname
			                   port:destination ? destination.port : check.port];
	}];
}

- (void)connectToHostname:(NSString *)hostname port:(NSUInteger)port
{
	if (!hostname.length || !port || port > UINT16_MAX)
		return [self finish:NO];
	nw_endpoint_t endpoint = nw_endpoint_create_host(hostname.UTF8String,
	    [[NSString stringWithFormat:@"%lu", (unsigned long)port] UTF8String]);
	self.connection = nw_connection_create(endpoint,
	    nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION));
	nw_connection_set_queue(self.connection, dispatch_get_main_queue());
	__weak OrbisConnectionHealthCheck *weakSelf = self;
	nw_connection_set_state_changed_handler(self.connection, ^(nw_connection_state_t state, nw_error_t error) {
		(void)error;
		OrbisConnectionHealthCheck *check = weakSelf;
		if (!check || check.finished)
			return;
		if (state == nw_connection_state_ready)
			[check sendNegotiationRequest];
		else if (state == nw_connection_state_failed || state == nw_connection_state_cancelled)
			[check finish:NO];
	});
	nw_connection_start(self.connection);
}

- (void)sendNegotiationRequest
{
	// TPKT + X.224 connection request + TLS/NLA negotiation; no account credentials.
	static const uint8_t request[] = {
		3, 0, 0, 19, 14, 0xe0, 0, 0, 0, 0, 0, 1, 0, 8, 0, 11, 0, 0, 0
	};
	dispatch_data_t data = dispatch_data_create(request, sizeof(request), dispatch_get_main_queue(), DISPATCH_DATA_DESTRUCTOR_DEFAULT);
	__weak OrbisConnectionHealthCheck *weakSelf = self;
	nw_connection_send(self.connection, data, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t error) {
		if (error)
			[weakSelf finish:NO];
		else
			[weakSelf receiveResponse];
	});
}

- (void)receiveResponse
{
	if (self.finished)
		return;
	__weak OrbisConnectionHealthCheck *weakSelf = self;
	nw_connection_receive(self.connection, 1, 4096, ^(dispatch_data_t content, nw_content_context_t context,
	                                               bool complete, nw_error_t error) {
		(void)context;
		OrbisConnectionHealthCheck *check = weakSelf;
		if (!check || check.finished)
			return;
		if (content)
		{
			dispatch_data_apply(content, ^bool(dispatch_data_t region, size_t offset, const void *bytes, size_t size) {
				(void)region; (void)offset;
				[check.response appendBytes:bytes length:size];
				return true;
			});
		}
		const uint8_t *bytes = check.response.bytes;
		NSUInteger length = check.response.length;
		if (length >= 4)
		{
			NSUInteger packetLength = ((NSUInteger)bytes[2] << 8) | bytes[3];
			if (bytes[0] != 3 || bytes[1] != 0 || packetLength < 11 || packetLength > 4096)
				return [check finish:NO];
			if (length >= packetLength)
			{
				BOOL available = bytes[5] == 0xd0 && bytes[4] + 5u == packetLength;
				if (packetLength == 11)
					available = available && bytes[4] == 6;
				else
				{
					available = available && packetLength == 19 && bytes[11] == 2 && bytes[13] == 8 && bytes[14] == 0;
					if (available)
						available = (bytes[15] == 0 || bytes[15] == 1 || bytes[15] == 2 || bytes[15] == 8) &&
						            bytes[16] == 0 && bytes[17] == 0 && bytes[18] == 0;
				}
				return [check finish:available];
			}
		}
		if (error || complete)
			[check finish:NO];
		else
			[check receiveResponse];
	});
}

- (void)finish:(BOOL)available
{
	if (self.finished)
		return;
	self.finished = YES;
	if (self.deadline)
		dispatch_source_cancel(self.deadline);
	self.deadline = nil;
	if (self.connection)
		nw_connection_cancel(self.connection);
	self.connection = nil;
	[self.session close];
	self.session = nil;
	self.transport = nil;
	void (^completion)(BOOL) = self.completion;
	self.completion = nil;
	if (completion)
		completion(available);
}

- (void)cancel
{
	NSAssert([NSThread isMainThread], @"Cancel health checks on the main queue");
	self.completion = nil;
	[self finish:NO];
}
@end
