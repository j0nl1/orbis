/* SPDX-License-Identifier: MIT */
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
@class MRDPView;
@class OrbisInputCapture;

extern NSString *const OrbisFullscreenInputCaptureKey;
extern NSString *const OrbisInputCaptureSettingsDidChangeNotification;

@protocol OrbisInputCaptureDelegate <NSObject>
- (MRDPView *)inputCaptureKeyboardTarget;
- (MRDPView *)inputCapturePointerTargetAtScreenPoint:(NSPoint)point;
@end

// An active event filter exists only during an opted-in foreground fullscreen session.
@interface OrbisInputCapture : NSObject
{
    id<OrbisInputCaptureDelegate> _delegate;
    MRDPView *_target, *_pointerTarget;
    NSWindow *_exitingWindow;
    CFMachPortRef _tap;
    CFRunLoopSourceRef _source;
    BOOL _tapReady, _suspended, _drainModifiers, _drainEscape;
    NSUInteger _menuTracking, _buttons;
    NSTimeInterval _retryAfter;
}
@property(nonatomic, readonly) BOOL active;
- (instancetype)initWithDelegate:(id<OrbisInputCaptureDelegate>)delegate;
- (void)refresh;
- (void)stop;
- (BOOL)consumeEvent:(CGEventRef)event type:(CGEventType)type;
- (BOOL)suppressesLocalModifiers;
// Separate the OS permission boundary from event routing for native integration tests.
- (BOOL)installTap;
@end
