/* SPDX-License-Identifier: MIT */
#import "OrbisShortcutsController.h"
#import "OrbisWorkspaceShortcuts.h"
#import "OrbisInputEventTap.h"

static NSString *OrbisShortcutTitle(NSString *symbol, OrbisShortcutModifiers modifiers)
{
    return [NSString stringWithFormat:@"%@%@%@%@%@", modifiers & OrbisShortcutControl ? @"⌃" : @"",
        modifiers & OrbisShortcutOption ? @"⌥" : @"", modifiers & OrbisShortcutShift ? @"⇧" : @"",
        modifiers & OrbisShortcutCommand ? @"⌘" : @"", symbol];
}

@interface OrbisShortcutField : NSButton <OrbisInputEventSink>
@property(nonatomic, copy) BOOL (^record)(NSEvent *event);
@property(nonatomic, copy) void (^captureUnavailable)(void);
@end
@implementation OrbisShortcutField
{
    NSString *_previousTitle;
    OrbisInputEventTap *_eventTap;
    BOOL _hasCapturedKey, _finishingCapture;
    unsigned short _capturedKeyCode;
}
- (instancetype)init
{
    if (!(self = [super init])) return nil;
    _eventTap = [[OrbisInputEventTap alloc] init];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(captureFocusEnded:)
        name:NSApplicationDidResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(captureFocusEnded:)
        name:NSWindowDidResignKeyNotification object:nil];
    [center addObserver:self selector:@selector(captureFocusEnded:)
        name:NSWindowWillCloseNotification object:nil];
    [center addObserver:self selector:@selector(captureFocusEnded:)
        name:NSMenuDidBeginTrackingNotification object:nil];
    return self;
}
- (void)stopCapture { [_eventTap stop]; _hasCapturedKey = NO; }
- (BOOL)recordingWindowActive { return NSApp.isActive && self.window.isKeyWindow; }
- (void)captureFocusEnded:(NSNotification *)note
{
    if (![note.name isEqualToString:NSMenuDidBeginTrackingNotification] &&
        note.object != NSApp && note.object != self.window) return;
    [self stopCapture];
    if (self.window.firstResponder == self) [self.window makeFirstResponder:nil];
}
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)becomeFirstResponder
{
    [_previousTitle release]; _previousTitle = [self.title copy]; self.title = @"Press a combination…";
    _hasCapturedKey = NO;
    if (![_eventTap startWithSink:self] && _captureUnavailable) _captureUnavailable();
    return YES;
}
- (BOOL)resignFirstResponder
{
    if (!_finishingCapture) [self stopCapture];
    if ([self.title isEqual:@"Press a combination…"]) self.title = _previousTitle ?: @"Not assigned";
    return YES;
}
- (BOOL)consumeEvent:(CGEventRef)event type:(CGEventType)type
{
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput)
    { [self stopCapture]; if (_captureUnavailable) _captureUnavailable(); return NO; }
    if (!event) return NO;
    if (![self recordingWindowActive])
    { [self stopCapture]; return NO; }
    unsigned short code = (unsigned short)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    if (_hasCapturedKey && code == _capturedKeyCode)
    {
        if (type == kCGEventKeyUp)
        {
            _hasCapturedKey = NO;
            if (self.window.firstResponder != self) [self stopCapture];
            return YES;
        }
        if (type == kCGEventKeyDown) return YES;
    }
    if (self.window.firstResponder != self) return NO;
    if (type == kCGEventFlagsChanged) return YES;
    if (type != kCGEventKeyDown) return NO;
    if (CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat)) return YES;
    _capturedKeyCode = code; _hasCapturedKey = YES;
    _finishingCapture = YES;
    [self keyDown:[NSEvent eventWithCGEvent:event]];
    _finishingCapture = NO;
    return YES;
}
- (void)recordMouseDown:(NSEvent *)event
{
    NSEventModifierFlags modifiers = event.modifierFlags & (NSEventModifierFlagShift |
        NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand);
    if (self.window.firstResponder == self && (event.buttonNumber >= 2 || modifiers))
    {
        if (_record && _record(event)) [self.window makeFirstResponder:nil];
    }
    else [self.window makeFirstResponder:self];
}
- (void)mouseDown:(NSEvent *)event { [self recordMouseDown:event]; }
- (void)rightMouseDown:(NSEvent *)event { [self recordMouseDown:event]; }
- (void)otherMouseDown:(NSEvent *)event { [self recordMouseDown:event]; }
- (void)keyDown:(NSEvent *)event
{
    if (event.type != NSEventTypeKeyDown || event.isARepeat) return;
    if (_record && _record(event)) [self.window makeFirstResponder:nil];
}
- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    if (self.window.firstResponder != self) return [super performKeyEquivalent:event];
    [self keyDown:event]; return YES;
}
- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self stopCapture]; [_eventTap release];
    [_record release]; [_captureUnavailable release]; [_previousTitle release]; [super dealloc];
}
@end

@implementation OrbisShortcutsController
{
    OrbisWorkspaceShortcuts *_shortcuts;
    NSMutableDictionary *_fields;
    NSTextField *_feedback;
    NSWindow *_mousePicker;
    NSPopUpButton *_mouseButton;
    NSArray *_mouseModifiers;
    NSTextField *_mouseFeedback;
    OrbisWorkspaceAction _mouseAction;
}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
{
    NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 720, 590)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO] autorelease];
    if (!(self = [super initWithWindow:window])) return nil;
    window.title = @"Shortcuts"; window.releasedWhenClosed = NO;
    _shortcuts = [[OrbisWorkspaceShortcuts alloc] initWithDefaults:defaults platform:@"macos"];
    _fields = [[NSMutableDictionary alloc] init];
    NSView *content = window.contentView;
    NSMutableArray *rows = [NSMutableArray array];
    NSTextField *hint = [NSTextField wrappingLabelWithString:OrbisWorkspaceShortcuts.warning];
    hint.textColor = NSColor.secondaryLabelColor; [rows addObject:hint];
    __block OrbisShortcutsController *controller = self;
    for (NSNumber *action in OrbisWorkspaceShortcuts.actions) {
        NSTextField *label = [NSTextField labelWithString:[OrbisWorkspaceShortcuts titleForAction:action.integerValue]];
        OrbisShortcutField *field = [[[OrbisShortcutField alloc] init] autorelease];
        field.title = [_shortcuts labelForAction:action.integerValue];
        field.bezelStyle = NSBezelStyleRounded;
        field.accessibilityLabel = label.stringValue;
        field.accessibilityIdentifier = [NSString stringWithFormat:@"workspace-shortcut-%@", action];
        field.toolTip = @"Click to record, then press a key or click a middle or side mouse button over this field. Shift, Control, Option and Command can be combined with any mouse button.";
        _fields[action] = field;
        __block OrbisShortcutField *recording = field;
        field.captureUnavailable = ^{
            controller->_feedback.stringValue = @"To record Mac system shortcuts, allow Orbis in Accessibility and Input Monitoring. Other shortcuts can still be recorded locally.";
        };
        field.record = ^BOOL(NSEvent *event) {
            NSEventModifierFlags flags = event.modifierFlags;
            OrbisShortcutModifiers modifiers = ((flags & NSEventModifierFlagShift) ? OrbisShortcutShift : 0) |
                ((flags & NSEventModifierFlagControl) ? OrbisShortcutControl : 0) |
                ((flags & NSEventModifierFlagOption) ? OrbisShortcutOption : 0) |
                ((flags & NSEventModifierFlagCommand) ? OrbisShortcutCommand : 0);
            BOOL mouse = event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeRightMouseDown ||
                event.type == NSEventTypeOtherMouseDown;
            NSString *symbol;
            if (mouse) symbol = [NSString stringWithFormat:@"Mouse Button %ld", (long)event.buttonNumber + 1];
            else {
                symbol = @{ @123:@"←", @124:@"→", @125:@"↓", @126:@"↑", @36:@"Return", @53:@"Esc", @51:@"Delete", @48:@"Tab", @49:@"Space" }[@(event.keyCode)]
                    ?: event.charactersIgnoringModifiers.uppercaseString;
                if (!symbol.length) symbol = [NSString stringWithFormat:@"Key %hu", event.keyCode];
            }
            NSString *title = OrbisShortcutTitle(symbol, modifiers);
            NSError *error = nil;
            BOOL assigned = mouse ? [controller->_shortcuts assignMouseButton:event.buttonNumber modifiers:modifiers
                label:title toAction:action.integerValue error:&error] :
                [controller->_shortcuts assignKeyCode:event.keyCode modifiers:modifiers label:title toAction:action.integerValue error:&error];
            if (!assigned) {
                controller->_feedback.stringValue = error.localizedDescription ?: @"Choose a different combination."; return NO;
            }
            recording.title = title; controller->_feedback.stringValue = @""; return YES;
        };
        NSButton *clear = [NSButton buttonWithTitle:@"Clear" target:self action:@selector(clear:)]; clear.tag = action.integerValue;
        clear.bezelStyle = NSBezelStyleRounded;
        NSButton *mouse = [NSButton buttonWithTitle:@"Mouse…" target:self action:@selector(chooseMouse:)];
        mouse.tag = action.integerValue; mouse.bezelStyle = NSBezelStyleRounded;
        mouse.accessibilityIdentifier = [NSString stringWithFormat:@"workspace-mouse-shortcut-%@", action];
        mouse.accessibilityLabel = [NSString stringWithFormat:@"Assign mouse shortcut for %@", label.stringValue];
        mouse.toolTip = @"Choose a mouse button and modifiers without pressing a button that already has a Mac action.";
        NSMutableArray *controls = [NSMutableArray arrayWithArray:@[label, field, mouse, clear]];
        if (action.integerValue == OrbisWorkspaceScreenshotScreen || action.integerValue == OrbisWorkspaceScreenshotWindow) {
            NSButton *suggested = [NSButton buttonWithTitle:action.integerValue == OrbisWorkspaceScreenshotScreen ? @"⌘⇧3" : @"⌘⇧4"
                target:self action:@selector(useSuggested:)];
            suggested.tag = action.integerValue; suggested.bezelStyle = NSBezelStyleRounded;
            suggested.toolTip = @"Assign this combination without recording a macOS screenshot. Full screen input capture is required to forward it.";
            [controls addObject:suggested];
        }
        NSStackView *row = [NSStackView stackViewWithViews:controls];
        row.spacing = 12;
        [label.widthAnchor constraintEqualToConstant:190].active = YES;
        [field.widthAnchor constraintGreaterThanOrEqualToConstant:170].active = YES;
        [rows addObject:row];
    }
    _feedback = [[NSTextField wrappingLabelWithString:@""] retain]; _feedback.textColor = NSColor.systemOrangeColor;
    [rows addObject:_feedback];
    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
    NSButton *save = [NSButton buttonWithTitle:@"Save" target:self action:@selector(save:)];
    NSButton *permission = [NSButton buttonWithTitle:@"Allow Mac shortcut capture…" target:self action:@selector(requestCapturePermission:)];
    permission.bezelStyle = NSBezelStyleRounded;
    permission.toolTip = @"Allow Orbis to intercept Mac system shortcuts while a shortcut field is recording.";
    cancel.keyEquivalent = @"\033"; save.keyEquivalent = @"\r";
    cancel.bezelStyle = save.bezelStyle = NSBezelStyleRounded;
    [rows addObject:[NSStackView stackViewWithViews:@[permission, cancel, save]]];
    NSStackView *stack = [NSStackView stackViewWithViews:rows];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical; stack.alignment = NSLayoutAttributeLeading; stack.spacing = 18;
    stack.translatesAutoresizingMaskIntoConstraints = NO; [content addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:24],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor constant:-24],
        [hint.widthAnchor constraintEqualToAnchor:stack.widthAnchor] ]];
    return self;
}
- (void)requestCapturePermission:(id)sender
{
    (void)sender; [self.window makeFirstResponder:nil]; [OrbisInputEventTap requestPermissions];
}
- (void)chooseMouse:(NSButton *)sender
{
    [self.window makeFirstResponder:nil];
    _mouseAction = sender.tag;
    if (!_mousePicker) {
        _mousePicker = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 360, 310)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        _mousePicker.title = @"Assign mouse shortcut"; _mousePicker.releasedWhenClosed = NO;
        NSTextField *hint = [NSTextField wrappingLabelWithString:
            @"Choose the button without pressing it. This avoids triggering an existing Mac action while assigning the shortcut."];
        _mouseButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        _mouseButton.accessibilityIdentifier = @"mouse-shortcut-button";
        _mouseButton.accessibilityLabel = @"Mouse button";
        for (NSInteger button = 0; button < 32; button++) {
            NSString *kind = button == 0 ? @" (primary)" : button == 1 ? @" (secondary)" :
                button == 2 ? @" (middle)" : (button == 3 || button == 4) ? @" (side)" : @"";
            [_mouseButton addItemWithTitle:[NSString stringWithFormat:@"Mouse Button %ld%@", (long)button + 1, kind]];
            _mouseButton.lastItem.tag = button;
        }
        NSMutableArray *checks = [NSMutableArray array];
        NSArray *names = @[@"Control", @"Option", @"Shift", @"Command"];
        NSArray *flags = @[@(OrbisShortcutControl), @(OrbisShortcutOption), @(OrbisShortcutShift), @(OrbisShortcutCommand)];
        for (NSUInteger index = 0; index < names.count; index++) {
            NSButton *check = [NSButton checkboxWithTitle:names[index] target:nil action:nil];
            check.tag = [flags[index] integerValue];
            check.accessibilityIdentifier = [@"mouse-shortcut-" stringByAppendingString:[names[index] lowercaseString]];
            [checks addObject:check];
        }
        _mouseModifiers = [checks copy];
        _mouseFeedback = [[NSTextField wrappingLabelWithString:@""] retain];
        _mouseFeedback.textColor = NSColor.systemOrangeColor;
        NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelMouse:)];
        NSButton *assign = [NSButton buttonWithTitle:@"Assign" target:self action:@selector(assignMouse:)];
        cancel.keyEquivalent = @"\033"; assign.keyEquivalent = @"\r";
        cancel.bezelStyle = assign.bezelStyle = NSBezelStyleRounded;
        cancel.accessibilityIdentifier = @"mouse-shortcut-cancel";
        assign.accessibilityIdentifier = @"mouse-shortcut-assign";
        NSStackView *stack = [NSStackView stackViewWithViews:@[hint, _mouseButton,
            [NSStackView stackViewWithViews:@[checks[0], checks[1]]],
            [NSStackView stackViewWithViews:@[checks[2], checks[3]]], _mouseFeedback,
            [NSStackView stackViewWithViews:@[cancel, assign]]]];
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading; stack.spacing = 14;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [_mousePicker.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:_mousePicker.contentView.leadingAnchor constant:24],
            [stack.trailingAnchor constraintEqualToAnchor:_mousePicker.contentView.trailingAnchor constant:-24],
            [stack.topAnchor constraintEqualToAnchor:_mousePicker.contentView.topAnchor constant:24],
            [stack.bottomAnchor constraintLessThanOrEqualToAnchor:_mousePicker.contentView.bottomAnchor constant:-24],
            [hint.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
            [_mouseFeedback.widthAnchor constraintEqualToAnchor:stack.widthAnchor] ]];
    }
    NSDictionary *binding = _shortcuts.bindings[[@(_mouseAction) stringValue]];
    [_mouseButton selectItemWithTag:binding[@"button"] ? [binding[@"button"] integerValue] : 3];
    NSUInteger modifiers = binding[@"button"] ? [binding[@"modifiers"] unsignedIntegerValue] : 0;
    for (NSButton *check in _mouseModifiers)
        check.state = (modifiers & check.tag) ? NSControlStateValueOn : NSControlStateValueOff;
    _mouseFeedback.stringValue = @"";
    [self.window beginSheet:_mousePicker completionHandler:nil];
}
- (void)cancelMouse:(id)sender
{
    (void)sender;
    if (_mousePicker.sheetParent) [_mousePicker.sheetParent endSheet:_mousePicker];
    [_mousePicker orderOut:nil];
}
- (void)assignMouse:(id)sender
{
    (void)sender;
    OrbisShortcutModifiers modifiers = 0;
    for (NSButton *check in _mouseModifiers)
        if (check.state == NSControlStateValueOn) modifiers |= check.tag;
    NSUInteger button = _mouseButton.selectedItem.tag;
    NSString *title = OrbisShortcutTitle([NSString stringWithFormat:@"Mouse Button %lu", (unsigned long)button + 1], modifiers);
    NSError *error = nil;
    if (![_shortcuts assignMouseButton:button modifiers:modifiers label:title toAction:_mouseAction error:&error]) {
        _mouseFeedback.stringValue = error.localizedDescription ?: @"Choose a different combination.";
        return;
    }
    [_fields[@(_mouseAction)] setTitle:title]; _feedback.stringValue = @"";
    [self cancelMouse:nil];
}
- (void)useSuggested:(NSButton *)sender
{
    OrbisWorkspaceAction action = sender.tag;
    NSUInteger code = action == OrbisWorkspaceScreenshotScreen ? 20 : 21;
    NSString *label = action == OrbisWorkspaceScreenshotScreen ? @"⇧⌘3" : @"⇧⌘4";
    NSError *error = nil;
    if ([_shortcuts assignKeyCode:code modifiers:OrbisShortcutCommand | OrbisShortcutShift label:label toAction:action error:&error]) {
        [_fields[@(action)] setTitle:label]; [self.window makeFirstResponder:nil]; _feedback.stringValue = @"";
    } else _feedback.stringValue = error.localizedDescription ?: @"Choose a different combination.";
}
- (void)clear:(NSButton *)sender
{
    [_shortcuts clearAction:sender.tag];
    [_fields[@(sender.tag)] setTitle:@"Not assigned"];
    [self.window makeFirstResponder:nil]; _feedback.stringValue = @"";
}
- (void)finish { [self cancelMouse:nil]; if (self.window.sheetParent) [self.window.sheetParent endSheet:self.window]; [self close]; }
- (void)save:(id)sender { (void)sender; [_shortcuts save]; [self finish]; }
- (void)cancel:(id)sender { (void)sender; [self finish]; }
- (void)dealloc
{
    [_mousePicker release]; [_mouseButton release]; [_mouseModifiers release]; [_mouseFeedback release];
    [_shortcuts release]; [_fields release]; [_feedback release]; [super dealloc];
}
@end
