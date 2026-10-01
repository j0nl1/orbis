/* SPDX-License-Identifier: MIT */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// A physical TCP destination override. Nil means use normal RDP routing,
// including server redirections. Logical server and certificate identity stay in RDP.
@interface OrbisTransportDestination : NSObject
@property(nonatomic, readonly, copy) NSString *hostname;
@property(nonatomic, readonly) uint16_t port;
- (instancetype)initWithHostname:(NSString *)hostname port:(uint16_t)port;
@end

@protocol OrbisTransportSession <NSObject>
// A sanitized transport failure that may explain an RDP connection failure.
@property(nonatomic, readonly, nullable) NSError *connectionError;
// Call on the main queue. Idempotent, including while preparation is pending.
// Close before releasing; keep this session alive until the RDP attempt ends.
- (void)close;
@end

typedef void (^OrbisTransportReady)(OrbisTransportDestination *_Nullable destination,
                                   NSError *_Nullable error);

@protocol OrbisConnectionTransport <NSObject>
@property(nonatomic, readonly, copy) NSString *displayName;
// Call on the main queue. Returns ownership of a separate attempt's session.
// Completion runs exactly once, asynchronously on the main queue, even on cancellation.
// A nil destination and nil error means RDP can use its original TCP destination.
- (id<OrbisTransportSession>)prepareWithCompletion:(OrbisTransportReady)completion;
@end

NS_ASSUME_NONNULL_END
