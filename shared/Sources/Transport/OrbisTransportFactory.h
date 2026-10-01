/* SPDX-License-Identifier: MIT */

#import "OrbisConnectionTransport.h"

@class OrbisProfile;

@interface OrbisTransportFactory : NSObject
// The composition root selects adapters and resolves their Keychain credentials.
// Unknown transport types fail explicitly; they must never fall back to direct RDP.
+ (id<OrbisConnectionTransport>)transportForProfile:(OrbisProfile *)profile error:(NSError **)error;
@end
