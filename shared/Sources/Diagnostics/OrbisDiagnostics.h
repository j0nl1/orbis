/* SPDX-License-Identifier: MIT */
#import <Foundation/Foundation.h>

// App events accept numeric context only. Never pass credentials or input content.
@interface OrbisDiagnostics : NSObject
+ (instancetype)sharedDiagnostics;
- (instancetype)initWithDirectoryURL:(NSURL *)directory;
- (void)start;
- (void)recordEvent:(NSString *)event values:(NSDictionary<NSString *, NSNumber *> *)values;
- (void)recordError:(NSError *)error event:(NSString *)event;
// iPad has one remote session: 0 = idle, 1 = connecting, 2 = connected.
- (void)setActiveSessionState:(NSUInteger)state;
- (NSURL *)exportToDirectory:(NSURL *)directory error:(NSError **)error;
@end
