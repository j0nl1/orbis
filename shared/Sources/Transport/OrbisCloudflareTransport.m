/* SPDX-License-Identifier: MIT */

#import "OrbisCloudflareTransport.h"
#import "OrbisTunnelBridge.h"

@interface OrbisCloudflareTransportSession : NSObject <OrbisTransportSession>
@property(nonatomic, strong) OrbisTunnelBridge *bridge;
@property(nonatomic, copy) OrbisTransportReady completion;
@property(nonatomic) BOOL closed;
- (void)finishPreparationOnPort:(uint16_t)port error:(NSError *)error;
@end

@implementation OrbisCloudflareTransportSession
- (NSError *)connectionError { return self.bridge.lastHandshakeError; }
- (void)finishPreparationOnPort:(uint16_t)port error:(NSError *)error
{
	if (!self.completion)
		return;
	OrbisTransportReady completion = self.completion;
	self.completion = nil;
	if (self.closed)
		error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError
		                       userInfo:@{ NSLocalizedDescriptionKey : @"Connection cancelled." }];
	OrbisTransportDestination *destination = !error && port
	    ? [[OrbisTransportDestination alloc] initWithHostname:@"127.0.0.1" port:port] : nil;
	completion(destination, error);
}
- (void)close
{
	NSAssert([NSThread isMainThread], @"Close transports on the main queue");
	if (self.closed)
		return;
	self.closed = YES;
	[self.bridge stop];
	// Bridge cancellation may suppress listener readiness; complete pending attempts ourselves.
	dispatch_async(dispatch_get_main_queue(), ^{ [self finishPreparationOnPort:0 error:nil]; });
}
- (void)dealloc { [_bridge stop]; }
@end

@implementation OrbisCloudflareTransport
{
	NSURL *_endpoint;
	NSString *_clientID;
	NSString *_clientSecret;
}
- (instancetype)initWithEndpoint:(NSURL *)endpoint clientID:(NSString *)clientID
                    clientSecret:(NSString *)clientSecret error:(NSError **)error
{
	// Use the bridge's endpoint and header validation before retaining credentials.
	OrbisTunnelBridge *validated = [[OrbisTunnelBridge alloc] initWithEndpoint:endpoint
	    clientID:clientID clientSecret:clientSecret error:error];
	if (!validated)
		return nil;
	if ((self = [super init]))
	{
		_endpoint = [endpoint copy];
		_clientID = [clientID copy];
		_clientSecret = [clientSecret copy];
	}
	return self;
}
- (NSString *)displayName { return @"Cloudflare Tunnel"; }
- (id<OrbisTransportSession>)prepareWithCompletion:(OrbisTransportReady)completion
{
	NSAssert([NSThread isMainThread], @"Prepare transports on the main queue");
	OrbisCloudflareTransportSession *session = [OrbisCloudflareTransportSession new];
	session.completion = [completion copy];
	NSError *error = nil;
	session.bridge = [[OrbisTunnelBridge alloc] initWithEndpoint:_endpoint clientID:_clientID
	    clientSecret:_clientSecret error:&error];
	if (!session.bridge)
		dispatch_async(dispatch_get_main_queue(), ^{ [session finishPreparationOnPort:0 error:error]; });
	else
	{
		__weak OrbisCloudflareTransportSession *weakSession = session;
		[session.bridge startOnPort:0 ready:^(uint16_t port, NSError *readyError) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[weakSession finishPreparationOnPort:port error:readyError];
			});
		} streamFailure:^(NSError *streamError) {
			// RDP owns established-stream errors and login handoff. It may consult connectionError.
			(void)streamError;
		}];
	}
	return session;
}
@end
