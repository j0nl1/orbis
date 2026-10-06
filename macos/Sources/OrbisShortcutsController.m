/* SPDX-License-Identifier: MIT */
#import "OrbisShortcutsController.h"
#import "OrbisWorkspaceShortcuts.h"

@interface OrbisShortcutField : NSButton
@property(nonatomic, copy) BOOL (^record)(NSEvent *event);
@end
@implementation OrbisShortcutField
{ NSString *_previousTitle; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)becomeFirstResponder { [_previousTitle release]; _previousTitle = [self.title copy]; self.title = @"Press a combination…"; return YES; }
- (BOOL)resignFirstResponder { if ([self.title isEqual:@"Press a combination…"]) self.title = _previousTitle ?: @"Not assigned"; return YES; }
- (void)mouseDown:(NSEvent *)event { (void)event; [self.window makeFirstResponder:self]; }
- (void)keyDown:(NSEvent *)event
{
    if (event.isARepeat) return;
    if (_record && _record(event)) [self.window makeFirstResponder:nil];
}
- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    if (self.window.firstResponder != self) return [super performKeyEquivalent:event];
    [self keyDown:event]; return YES;
}
- (void)dealloc { [_record release]; [_previousTitle release]; [super dealloc]; }
@end

@implementation OrbisShortcutsController
{
    OrbisWorkspaceShortcuts *_shortcuts;
    NSMutableDictionary *_fields;
    NSTextField *_feedback;
}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
{
    NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 620, 590)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO] autorelease];
    if (!(self = [super initWithWindow:window])) return nil;
    window.title = @"Keyboard Shortcuts"; window.releasedWhenClosed = NO;
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
        field.toolTip = @"Click, then press a key combination.";
        _fields[action] = field;
        __block OrbisShortcutField *recording = field;
        field.record = ^BOOL(NSEvent *event) {
            NSEventModifierFlags flags = event.modifierFlags;
            OrbisShortcutModifiers modifiers = ((flags & NSEventModifierFlagShift) ? OrbisShortcutShift : 0) |
                ((flags & NSEventModifierFlagControl) ? OrbisShortcutControl : 0) |
                ((flags & NSEventModifierFlagOption) ? OrbisShortcutOption : 0) |
                ((flags & NSEventModifierFlagCommand) ? OrbisShortcutCommand : 0);
            NSString *symbol = @{ @123:@"←", @124:@"→", @125:@"↓", @126:@"↑", @36:@"Return", @53:@"Esc", @51:@"Delete", @48:@"Tab", @49:@"Space" }[@(event.keyCode)]
                ?: event.charactersIgnoringModifiers.uppercaseString;
            if (!symbol.length) symbol = [NSString stringWithFormat:@"Key %hu", event.keyCode];
            NSString *title = [NSString stringWithFormat:@"%@%@%@%@%@", modifiers & OrbisShortcutControl ? @"⌃" : @"",
                modifiers & OrbisShortcutOption ? @"⌥" : @"", modifiers & OrbisShortcutShift ? @"⇧" : @"",
                modifiers & OrbisShortcutCommand ? @"⌘" : @"", symbol];
            NSError *error = nil;
            if (![controller->_shortcuts assignKeyCode:event.keyCode modifiers:modifiers label:title toAction:action.integerValue error:&error]) {
                controller->_feedback.stringValue = error.localizedDescription ?: @"Choose a different combination."; return NO;
            }
            recording.title = title; controller->_feedback.stringValue = @""; return YES;
        };
        NSButton *clear = [NSButton buttonWithTitle:@"Clear" target:self action:@selector(clear:)]; clear.tag = action.integerValue;
        clear.bezelStyle = NSBezelStyleRounded;
        NSMutableArray *controls = [NSMutableArray arrayWithArray:@[label, field, clear]];
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
    cancel.keyEquivalent = @"\033"; save.keyEquivalent = @"\r";
    cancel.bezelStyle = save.bezelStyle = NSBezelStyleRounded;
    [rows addObject:[NSStackView stackViewWithViews:@[cancel, save]]];
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
- (void)finish { if (self.window.sheetParent) [self.window.sheetParent endSheet:self.window]; [self close]; }
- (void)save:(id)sender { (void)sender; [_shortcuts save]; [self finish]; }
- (void)cancel:(id)sender { (void)sender; [self finish]; }
- (void)dealloc { [_shortcuts release]; [_fields release]; [_feedback release]; [super dealloc]; }
@end
