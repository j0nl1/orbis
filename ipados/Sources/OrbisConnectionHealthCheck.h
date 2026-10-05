/* SPDX-License-Identifier: MIT */

#import <Foundation/Foundation.h>
#import "OrbisConnectionTransport.h"

@class OrbisProfile;

// Checks RDP negotiation without logging in or creating a desktop session.
// Start and cancel on the main queue; completion also runs there.
@interface OrbisConnectionHealthCheck : NSObject
- (instancetype)initWithProfile:(OrbisProfile *)profile
                      transport:(id<OrbisConnectionTransport>)transport
                        timeout:(NSTimeInterval)timeout;
- (void)startWithCompletion:(void (^)(BOOL available))completion;
- (void)cancel;
@end
