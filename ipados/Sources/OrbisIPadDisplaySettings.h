/* SPDX-License-Identifier: MIT */
#import <Foundation/Foundation.h>

@class ConnectionParams;

@interface OrbisIPadDisplaySettings : NSObject
@property(nonatomic) NSUInteger width;
@property(nonatomic) NSUInteger height;
@property(nonatomic, readonly) BOOL automaticResolution;
@property(nonatomic) BOOL workspaceGesturesEnabled;

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (BOOL)saveWithError:(NSError **)error;
- (void)applyToConnectionParameters:(ConnectionParams *)parameters;
+ (NSArray<NSArray<NSNumber *> *> *)resolutionsForPixelWidth:(NSUInteger)width height:(NSUInteger)height;
@end
