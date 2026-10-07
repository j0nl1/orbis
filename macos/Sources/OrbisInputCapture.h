/* SPDX-License-Identifier: MIT */
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import "OrbisInputEventTap.h"
@class MRDPView;
@class OrbisInputCapture;
@class OrbisKeyboardTextTranslator;

extern NSString *const OrbisFullscreenInputCaptureKey;
extern NSString *const OrbisCapturedMacKeyboardLayoutKey;
extern NSString *const OrbisInputCaptureSettingsDidChangeNotification;

@protocol OrbisInputCaptureDelegate <NSObject>
- (MRDPView *)inputCaptureKeyboardTarget;
- (MRDPView *)inputCapturePointerTargetAtScreenPoint:(NSPoint)point;
@end

// An active event filter exists only during an opted-in foreground fullscreen session.
@interface OrbisInputCapture : NSObject <OrbisInputEventSink>
{
    id<OrbisInputCaptureDelegate> _delegate;
    MRDPView *_target, *_pointerTarget;
    NSWindow *_exitingWindow;
    OrbisInputEventTap *_eventTap;
    BOOL _tapReady, _suspended, _drainModifiers, _drainEscape;
    NSUInteger _menuTracking, _buttons;
    NSTimeInterval _retryAfter;
    OrbisKeyboardTextTranslator *_textTranslator;
}
@property(nonatomic, readonly) BOOL active;
- (instancetype)initWithDelegate:(id<OrbisInputCaptureDelegate>)delegate;
- (void)refresh;
- (void)stop;
- (BOOL)consumeEvent:(CGEventRef)event type:(CGEventType)type;
- (BOOL)suppressesLocalModifiers;
// Separate the OS permission boundary from event routing for native integration tests.
- (BOOL)installTap;
- (BOOL)keyboardCaptureAllowed;
@end
