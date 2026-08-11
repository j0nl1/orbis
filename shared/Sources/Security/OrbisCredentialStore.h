/* SPDX-License-Identifier: MIT */

#import <Foundation/Foundation.h>

@class OrbisProfile;

@interface OrbisCredentialStore : NSObject

+ (NSString *)passwordForProfile:(OrbisProfile *)profile error:(NSError **)error;
+ (BOOL)setPassword:(NSString *)password forProfile:(OrbisProfile *)profile error:(NSError **)error;
+ (BOOL)deletePasswordForProfile:(OrbisProfile *)profile error:(NSError **)error;

@end
