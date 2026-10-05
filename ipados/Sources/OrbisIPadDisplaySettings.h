/* SPDX-License-Identifier: MIT */
#import <Foundation/Foundation.h>

@class ConnectionParams;

@interface OrbisIPadDisplaySettings : NSObject
@property(nonatomic) NSUInteger width;
@property(nonatomic) NSUInteger height;
@property(nonatomic) NSUInteger desktopScale;
@property(nonatomic, readonly) BOOL automaticResolution;

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (BOOL)saveWithError:(NSError **)error;
- (void)applyToConnectionParameters:(ConnectionParams *)parameters;
+ (NSArray<NSNumber *> *)supportedScales;
@end
