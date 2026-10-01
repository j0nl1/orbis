/* SPDX-License-Identifier: MIT */

#import "OrbisDirectTransport.h"

@interface OrbisDirectTransportSession : NSObject <OrbisTransportSession>
@property(nonatomic) BOOL closed;
@end

@implementation OrbisDirectTransportSession
- (NSError *)connectionError { return nil; }
- (void)close
{
	NSAssert([NSThread isMainThread], @"Close transports on the main queue");
	self.closed = YES;
}
@end

@implementation OrbisDirectTransport
- (NSString *)displayName { return @"Direct RDP"; }
- (id<OrbisTransportSession>)prepareWithCompletion:(OrbisTransportReady)completion
{
	NSAssert([NSThread isMainThread], @"Prepare transports on the main queue");
	OrbisDirectTransportSession *session = [OrbisDirectTransportSession new];
	dispatch_async(dispatch_get_main_queue(), ^{
		NSError *error = session.closed
		    ? [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError
		                      userInfo:@{ NSLocalizedDescriptionKey : @"Connection cancelled." }]
		    : nil;
		completion(nil, error);
	});
	return session;
}
@end
