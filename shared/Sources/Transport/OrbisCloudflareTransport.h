/* SPDX-License-Identifier: MIT */

#import "OrbisConnectionTransport.h"

NS_ASSUME_NONNULL_BEGIN

@interface OrbisCloudflareTransport : NSObject <OrbisConnectionTransport>
- (nullable instancetype)initWithEndpoint:(NSURL *)endpoint
                                clientID:(NSString *)clientID
                            clientSecret:(NSString *)clientSecret
                                   error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
