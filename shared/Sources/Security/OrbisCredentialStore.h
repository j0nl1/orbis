/* SPDX-License-Identifier: MIT */

#import <Foundation/Foundation.h>

@class OrbisProfile;

@interface OrbisCredentialStore : NSObject

+ (NSString *)passwordForProfile:(OrbisProfile *)profile error:(NSError **)error;
+ (BOOL)setPassword:(NSString *)password forProfile:(OrbisProfile *)profile error:(NSError **)error;
+ (BOOL)deletePasswordForProfile:(OrbisProfile *)profile error:(NSError **)error;

// Both fields stay in one Keychain item, bound to the profile's tunnel hostname.
+ (NSDictionary *)cloudflareTokenForProfile:(OrbisProfile *)profile error:(NSError **)error;
+ (BOOL)setCloudflareClientID:(NSString *)clientID secret:(NSString *)secret
                  forProfile:(OrbisProfile *)profile error:(NSError **)error;
+ (BOOL)deleteCloudflareTokenForProfile:(OrbisProfile *)profile error:(NSError **)error;
+ (BOOL)deleteCredentialsForProfile:(OrbisProfile *)profile error:(NSError **)error;

@end
