/* SPDX-License-Identifier: MIT */

#import <Foundation/Foundation.h>

extern NSString *const OrbisProjectNameKey;
extern NSString *const OrbisProjectDetailKey;
extern NSString *const OrbisProjectLicenseKey;
extern NSString *const OrbisProjectURLKey;
extern NSString *const OrbisProductDescription;

@interface OrbisAcknowledgements : NSObject

+ (NSArray *)projects;

@end
