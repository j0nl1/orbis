/* SPDX-License-Identifier: MIT */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@protocol OrbisInputEventSink <NSObject>
- (BOOL)consumeEvent:(CGEventRef)event type:(CGEventType)type;
@end

// Owns only the macOS filter and its permissions. The sink owns input policy.
// Start and stop on the main thread, keeping the sink alive until stop.
// A successful start guarantees every requested keyboard and pointer event is available.
@interface OrbisInputEventTap : NSObject
{
    CFMachPortRef _tap;
    CFRunLoopSourceRef _source;
}
+ (BOOL)permissionsGranted;
+ (BOOL)keyboardAccessAllowed;
+ (void)requestPermissions;
- (BOOL)startWithSink:(id<OrbisInputEventSink>)sink;
- (void)stop;
@end
