/* SPDX-License-Identifier: MIT */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// A loopback TCP listener carrying each accepted stream over a separate WebSocket.
// Call stop before releasing the bridge. Callbacks run on a private serial queue.
@interface OrbisTunnelBridge : NSObject

+ (nullable NSURL *)endpointForHostname:(NSString *)hostname error:(NSError **)error;
@property(atomic, readonly, strong, nullable) NSError *lastHandshakeError;

- (nullable instancetype)initWithEndpoint:(NSURL *)endpoint
                                clientID:(NSString *)clientID
                            clientSecret:(NSString *)clientSecret
                                   error:(NSError **)error;

// Port zero asks the system to allocate a port. The listener binds only to 127.0.0.1.
- (void)startOnPort:(uint16_t)port
             ready:(void (^)(uint16_t port, NSError *_Nullable error))ready
     streamFailure:(void (^)(NSError *error))streamFailure;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
