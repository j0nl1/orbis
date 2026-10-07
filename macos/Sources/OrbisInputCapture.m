/* SPDX-License-Identifier: MIT */
#import "OrbisInputCapture.h"
#import "OrbisKeyboardCompatibility.h"
#import "MRDPView.h"
#import <ApplicationServices/ApplicationServices.h>

@implementation OrbisInputCapture
- (instancetype)initWithDelegate:(id<OrbisInputCaptureDelegate>)delegate
{
    if (!(self = [super init])) return nil;
    _delegate = delegate;
    _eventTap = [[OrbisInputEventTap alloc] init];
    _textTranslator = [[OrbisKeyboardTextTranslator alloc] init];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(settingsChanged:)
        name:OrbisInputCaptureSettingsDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(menuBegan:) name:NSMenuDidBeginTrackingNotification object:nil];
    [center addObserver:self selector:@selector(menuEnded:) name:NSMenuDidEndTrackingNotification object:nil];
    [center addObserver:self selector:@selector(focusChanged:) name:NSApplicationDidResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(focusChanged:) name:NSWindowDidResignKeyNotification object:nil];
    [center addObserver:self selector:@selector(fullscreenWillExit:) name:NSWindowWillExitFullScreenNotification object:nil];
    [center addObserver:self selector:@selector(fullscreenDidExit:) name:NSWindowDidExitFullScreenNotification object:nil];
    return self;
}
- (BOOL)active { return _tapReady && _target != nil && !_suspended; }
- (BOOL)suppressesLocalModifiers
{
    return _drainModifiers || (_menuTracking &&
        [[NSUserDefaults standardUserDefaults] boolForKey:OrbisFullscreenInputCaptureKey]);
}
- (void)clearTargets
{
    [_textTranslator reset];
    [_target releaseCapturedInput];
    if (_pointerTarget != _target) [_pointerTarget releaseCapturedInput];
    [_target release]; _target = nil;
    [_pointerTarget release]; _pointerTarget = nil;
    _buttons = 0;
}
- (void)removeTap
{
    [_eventTap stop]; _tapReady = NO;
}
- (void)stop
{
    [self clearTargets]; [self removeTap];
    _suspended = _drainModifiers = _drainEscape = NO;
}
- (BOOL)keyboardCaptureAllowed { return [OrbisInputEventTap keyboardAccessAllowed]; }
- (BOOL)installTap { return [_eventTap startWithSink:self]; }
- (void)refresh
{
    BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:OrbisFullscreenInputCaptureKey];
    MRDPView *target = enabled ? [_delegate inputCaptureKeyboardTarget] : nil;
    if (!target || !target.is_connected || target.window == _exitingWindow ||
        !(target.window.styleMask & NSWindowStyleMaskFullScreen))
    {
        [self clearTargets]; [self removeTap]; _suspended = NO;
        _drainModifiers = _drainEscape = NO;
        return;
    }
    if (_menuTracking || ![self keyboardCaptureAllowed])
    {
        // macOS can create a modifier-only tap when keyboard monitoring is denied.
        // Never split one chord between captured modifiers and AppKit key events.
        [self clearTargets]; [self removeTap]; return;
    }
    if (_suspended) return;
    if (!_tapReady)
    {
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (now < _retryAfter) return;
        _tapReady = [self installTap];
        if (!_tapReady) { _retryAfter = now + 2; return; }
    }
    if (_target != target)
    {
        [self clearTargets];
        // End any ordinary mapped chord before switching to physical key forwarding.
        [target releaseCapturedInput];
        _target = [target retain];
    }
    _target.capturesLocalKeyboardLayout = [[NSUserDefaults standardUserDefaults]
        boolForKey:OrbisCapturedMacKeyboardLayoutKey];
}
- (BOOL)sendLocalTextForEvent:(CGEventRef)event
{
    if (!_target.capturesLocalKeyboardLayout) { [_textTranslator reset]; return NO; }
    NSString *text = [_textTranslator textForEvent:event];
    if (!text) return NO;
    [_target sendCapturedText:text forEvent:event];
    return YES;
}
- (void)settingsChanged:(NSNotification *)note
{
    (void)note; [self stop]; _retryAfter = 0; [self refresh];
}
- (void)menuBegan:(NSNotification *)note
{
    (void)note; _menuTracking++; [self clearTargets]; [self removeTap];
    _drainModifiers = _drainEscape = NO;
}
- (void)menuEnded:(NSNotification *)note
{
    (void)note; if (_menuTracking) _menuTracking--; [self refresh];
}
- (void)focusChanged:(NSNotification *)note { (void)note; [self clearTargets]; [self removeTap]; }
- (void)fullscreenWillExit:(NSNotification *)note
{
    if (note.object != _target.window) return;
    _exitingWindow = note.object;
    [self clearTargets]; [self removeTap];
}
- (void)fullscreenDidExit:(NSNotification *)note
{
    if (note.object == _exitingWindow) _exitingWindow = nil;
}
- (BOOL)consumeEvent:(CGEventRef)event type:(CGEventType)type
{
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput)
    {
        // Release the remote state before returning local control. Do not silently recapture.
        [self clearTargets]; _suspended = YES;
        [self removeTap];
        return NO;
    }
    if (!event) return NO;
    CGEventFlags flags = CGEventGetFlags(event);
    CGEventFlags transient = kCGEventFlagMaskControl | kCGEventFlagMaskAlternate |
        kCGEventFlagMaskCommand | kCGEventFlagMaskShift;
    unsigned short code = (unsigned short)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    if (_drainEscape && code == 53 && (type == kCGEventKeyDown || type == kCGEventKeyUp))
    {
        if (type == kCGEventKeyUp) _drainEscape = NO;
        return YES;
    }
    if (_drainModifiers && type == kCGEventFlagsChanged)
    {
        _drainModifiers = (flags & transient) != 0;
        return YES;
    }
    [self refresh];
    if (!self.active) return NO;
    CGEventFlags escape = kCGEventFlagMaskControl | kCGEventFlagMaskAlternate | kCGEventFlagMaskCommand;
    if (type == kCGEventKeyDown && code == 53 && (flags & escape) == escape)
    {
        [self clearTargets]; _suspended = YES;
        _drainModifiers = _drainEscape = YES;
        return YES;
    }
    if (type == kCGEventKeyDown || type == kCGEventKeyUp || type == kCGEventFlagsChanged)
    {
        if (type == kCGEventKeyDown && [self sendLocalTextForEvent:event]) return YES;
        [_target sendCapturedEvent:event windowPoint:NSZeroPoint];
        return YES;
    }
    CGPoint quartz = CGEventGetLocation(event);
    // Quartz is top-down; AppKit screen coordinates use the primary display's bottom-left.
    NSPoint screenPoint = NSMakePoint(quartz.x, NSMaxY([NSScreen screens].firstObject.frame) - quartz.y);
    MRDPView *hit = _pointerTarget ?: [_delegate inputCapturePointerTargetAtScreenPoint:screenPoint];
    if (!hit || !hit.is_connected) return NO;
    BOOL down = type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown || type == kCGEventOtherMouseDown;
    BOOL up = type == kCGEventLeftMouseUp || type == kCGEventRightMouseUp || type == kCGEventOtherMouseUp;
    NSInteger button = (NSInteger)CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);
    if ((down || up) && (button < 0 || button > 31 || ![_target canHandleCapturedMouseEvent:event])) return NO;
    if (down && !_pointerTarget && hit != _target)
    {
        // Preserve ordinary click-to-focus behavior even though the OS event is consumed.
        [hit.window makeKeyWindow]; [hit.window makeFirstResponder:hit]; [self refresh];
        if (!self.active) return NO;
    }
    // Both outputs share one RDP keyboard. Keep modifier state in the focused view;
    // its existing screen-coordinate routing resolves pointer motion across outputs.
    MRDPView *pointer = _pointerTarget ?: _target;
    if (down && !_pointerTarget) _pointerTarget = [pointer retain];
    if (down) _buttons |= 1UL << button;
    [pointer sendCapturedEvent:event windowPoint:[pointer.window convertPointFromScreen:screenPoint]];
    if (up)
    {
        _buttons &= ~(1UL << button);
        if (!_buttons) { [_pointerTarget release]; _pointerTarget = nil; }
    }
    return YES;
}
- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stop]; [_eventTap release]; [_textTranslator release]; [super dealloc];
}
@end
