/* SPDX-License-Identifier: MIT */

#import <AppKit/AppKit.h>
#import <XCTest/XCTest.h>
#import <objc/runtime.h>

#import "OrbisLibraryViewController.h"
#import "OrbisProfile.h"
#import "OrbisProfileEditorController.h"
#import "OrbisAboutController.h"
#import "OrbisDisplaySettings.h"
#import "OrbisInputCapture.h"
#import "OrbisShortcutsController.h"
#import "OrbisWorkspaceShortcuts.h"

static NSView *FindViewWithAccessibilityIdentifier(NSView *view, NSString *identifier)
{
	if ([[view accessibilityIdentifier] isEqualToString:identifier])
		return view;
	for (NSView *subview in [view subviews])
	{
		NSView *match = FindViewWithAccessibilityIdentifier(subview, identifier);
		if (match)
			return match;
	}
	return nil;
}

static NSButton *FindButtonWithToolTip(NSView *view, NSString *toolTip)
{
	if ([view isKindOfClass:[NSButton class]] && [[(NSButton *)view toolTip] isEqualToString:toolTip])
		return (NSButton *)view;
	for (NSView *subview in [view subviews])
	{
		NSButton *match = FindButtonWithToolTip(subview, toolTip);
		if (match)
			return match;
	}
	return nil;
}

static NSButton *FindButtonWithTitle(NSView *view, NSString *title)
{
	if ([view isKindOfClass:[NSButton class]] && [[(NSButton *)view title] isEqualToString:title])
		return (NSButton *)view;
	for (NSView *subview in [view subviews])
	{
		NSButton *match = FindButtonWithTitle(subview, title);
		if (match)
			return match;
	}
	return nil;
}

static void DrainSheetCompletion(void)
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.5];
	while ([deadline timeIntervalSinceNow] > 0)
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:deadline];
}

@interface OrbisDisplayArrangementView (GeometryTests)
- (void)updateMonitorRects;
@end
@interface OrbisArrangementDragFixture : OrbisDisplayArrangementView
- (void)dragDisplay:(NSInteger)index toRemotePoint:(NSPoint)position;
@end
@implementation OrbisArrangementDragFixture
- (void)dragDisplay:(NSInteger)index toRemotePoint:(NSPoint)position
{
    [self updateMonitorRects];
    OrbisDisplayLayout layout = self.settings.previewLayout;
    NSPoint start = NSMakePoint(NSMidX(_monitorRects[index]), NSMidY(_monitorRects[index]));
    CGFloat direction = index ? 1 : -1;
    NSPoint end = NSMakePoint(start.x + direction * (position.x - layout.monitors[1].x) * _scale,
        start.y + direction * (position.y - layout.monitors[1].y) * _scale);
    NSEventType types[] = { NSEventTypeLeftMouseDown, NSEventTypeLeftMouseDragged, NSEventTypeLeftMouseUp };
    for (NSUInteger i = 0; i < 3; i++)
    {
        NSPoint location = [self convertPoint:i ? end : start toView:nil];
        NSEvent *event = [NSEvent mouseEventWithType:types[i] location:location modifierFlags:0
            timestamp:i + 1 windowNumber:self.window.windowNumber context:nil eventNumber:i + 1
            clickCount:1 pressure:i == 2 ? 0 : 1];
        if (i == 0) [self mouseDown:event]; else if (i == 1) [self mouseDragged:event]; else [self mouseUp:event];
    }
}
@end

@interface OrbisEditorSaveRecorder : NSObject <OrbisProfileEditorControllerDelegate>
@property(nonatomic, retain) OrbisProfile *profile;
@end
@implementation OrbisEditorSaveRecorder
- (BOOL)profileEditorController:(OrbisProfileEditorController *)controller savedProfile:(OrbisProfile *)profile
                      password:(NSString *)password cloudflareToken:(NSDictionary *)token
{
	(void)controller;
	(void)password;
	(void)token;
	self.profile = profile;
	return NO; // Observe the save without closing a sheet or writing credentials.
}
- (void)profileEditorControllerDidFinish:(OrbisProfileEditorController *)controller
{
	(void)controller;
}
- (void)dealloc { [_profile release]; [super dealloc]; }
@end

@interface OrbisProfileEditorController (TestActions)
- (void)save:(id)sender;
@end

@interface OrbisShortcutsController (ShortcutTesting)
- (void)save:(id)sender;
- (void)cancel:(id)sender;
- (void)clear:(NSButton *)sender;
- (void)useSuggested:(NSButton *)sender;
@end

@interface OrbisLibraryLayoutTests : XCTestCase
@end

@interface OrbisRecordingTestTap : OrbisInputEventTap
@property(nonatomic, assign) id<OrbisInputEventSink> sink;
@property(nonatomic) BOOL running;
@end
@implementation OrbisRecordingTestTap
- (BOOL)startWithSink:(id<OrbisInputEventSink>)sink { self.sink = sink; self.running = YES; return YES; }
- (void)stop { self.running = NO; }
@end

@implementation OrbisLibraryLayoutTests

- (void)testShortcutRecorderPersistsOnlySavedDraftsAndRejectsCollisions
{
    NSString *suite = [@"OrbisMacShortcutTests." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[[NSUserDefaults alloc] initWithSuiteName:suite] autorelease];
    [self addTeardownBlock:^{ [defaults removePersistentDomainForName:suite]; }];
    OrbisShortcutsController *editor = [[[OrbisShortcutsController alloc] initWithDefaults:defaults] autorelease];
    NSButton *screen = (NSButton *)FindViewWithAccessibilityIdentifier(editor.window.contentView, @"workspace-shortcut-8");
    NSButton *window = (NSButton *)FindViewWithAccessibilityIdentifier(editor.window.contentView, @"workspace-shortcut-9");
    XCTAssertEqualObjects(screen.title, @"Not assigned");
    XCTAssertNotNil(window);
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:NSEventModifierFlagCommand | NSEventModifierFlagShift timestamp:0 windowNumber:editor.window.windowNumber
        context:nil characters:@"3" charactersIgnoringModifiers:@"3" isARepeat:NO keyCode:20];
    [editor.window makeFirstResponder:screen]; [screen keyDown:event];
    XCTAssertEqualObjects(screen.title, @"⇧⌘3");
    [editor.window makeFirstResponder:window]; [window keyDown:event];
    OrbisWorkspaceShortcuts *draft = [editor valueForKey:@"shortcuts"];
    XCTAssertEqual(draft.bindings.count, 1u);
    XCTAssertTrue([[editor valueForKey:@"feedback"] stringValue].length > 0);
    [editor cancel:nil];
    OrbisWorkspaceShortcuts *saved = [[[OrbisWorkspaceShortcuts alloc] initWithDefaults:defaults platform:@"macos"] autorelease];
    XCTAssertEqual(saved.bindings.count, 0u);
    [editor save:nil];
    saved = [[[OrbisWorkspaceShortcuts alloc] initWithDefaults:defaults platform:@"macos"] autorelease];
    XCTAssertEqual([saved actionForKeyCode:20 modifiers:9], OrbisWorkspaceScreenshotScreen);
    NSButton *clear = [[[NSButton alloc] init] autorelease]; clear.tag = 8;
    [editor clear:clear]; [editor save:nil];
    saved = [[[OrbisWorkspaceShortcuts alloc] initWithDefaults:defaults platform:@"macos"] autorelease];
    XCTAssertEqual(saved.bindings.count, 0u);
    NSButton *suggested = [[[NSButton alloc] init] autorelease];
    suggested.tag = 8; [editor useSuggested:suggested];
    suggested.tag = 9; [editor useSuggested:suggested]; [editor save:nil];
    saved = [[[OrbisWorkspaceShortcuts alloc] initWithDefaults:defaults platform:@"macos"] autorelease];
    XCTAssertEqual([saved actionForKeyCode:20 modifiers:9], OrbisWorkspaceScreenshotScreen);
    XCTAssertEqual([saved actionForKeyCode:21 modifiers:9], OrbisWorkspaceScreenshotWindow);
}

- (void)testMouseShortcutRecorderRequiresActivationAndSavesExactModifiers
{
    NSString *suite = [@"OrbisMacMouseShortcutTests." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[[NSUserDefaults alloc] initWithSuiteName:suite] autorelease];
    [self addTeardownBlock:^{ [defaults removePersistentDomainForName:suite]; }];
    OrbisShortcutsController *editor = [[[OrbisShortcutsController alloc] initWithDefaults:defaults] autorelease];
    NSButton *previous = (id)FindViewWithAccessibilityIdentifier(editor.window.contentView, @"workspace-shortcut-1");
    NSButton *next = (id)FindViewWithAccessibilityIdentifier(editor.window.contentView, @"workspace-shortcut-2");
    NSEvent *activate = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSZeroPoint
        modifierFlags:0 timestamp:1 windowNumber:editor.window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
    [previous mouseDown:activate];
    XCTAssertEqual([[editor valueForKey:@"shortcuts"] bindings].count, 0u, @"The activating click must not become the binding");
    CGEventRef click = CGEventCreateMouseEvent(NULL, kCGEventOtherMouseDown, CGPointZero, (CGMouseButton)3);
    CGEventSetFlags(click, kCGEventFlagMaskControl | kCGEventFlagMaskShift);
    [previous otherMouseDown:[NSEvent eventWithCGEvent:click]];
    XCTAssertEqualObjects(previous.title, @"⌃⇧Mouse Button 4");
    [editor.window makeFirstResponder:next]; [next otherMouseDown:[NSEvent eventWithCGEvent:click]];
    XCTAssertTrue([[editor valueForKey:@"feedback"] stringValue].length > 0, @"Two actions cannot share a mouse combination");
    [editor cancel:nil];
    OrbisWorkspaceShortcuts *saved = [[[OrbisWorkspaceShortcuts alloc] initWithDefaults:defaults platform:@"macos"] autorelease];
    XCTAssertEqual(saved.bindings.count, 0u);
    [editor save:nil];
    saved = [[[OrbisWorkspaceShortcuts alloc] initWithDefaults:defaults platform:@"macos"] autorelease];
    XCTAssertEqual([saved actionForMouseButton:3 modifiers:OrbisShortcutControl | OrbisShortcutShift], OrbisWorkspacePrevious);
    XCTAssertEqual([saved actionForMouseButton:3 modifiers:0], OrbisWorkspaceNone);
    XCTAssertEqual([saved actionForKeyCode:3 modifiers:OrbisShortcutControl | OrbisShortcutShift], OrbisWorkspaceNone);
    CFRelease(click);
}

- (void)testShortcutRecorderReceivesShiftArrowThroughWindowDispatch
{
    NSString *suite = [@"OrbisShiftArrowTests." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[[NSUserDefaults alloc] initWithSuiteName:suite] autorelease];
    [self addTeardownBlock:^{ [defaults removePersistentDomainForName:suite]; }];
    OrbisShortcutsController *editor = [[[OrbisShortcutsController alloc] initWithDefaults:defaults] autorelease];
    NSButton *previous = (id)FindViewWithAccessibilityIdentifier(editor.window.contentView, @"workspace-shortcut-1");
    [editor.window makeFirstResponder:previous];
    NSEvent *shift = [NSEvent keyEventWithType:NSEventTypeFlagsChanged location:NSZeroPoint
        modifierFlags:NSEventModifierFlagShift timestamp:1 windowNumber:editor.window.windowNumber
        context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:56];
    [editor.window sendEvent:shift];
    XCTAssertEqual(editor.window.firstResponder, previous);
    XCTAssertEqual([[editor valueForKey:@"shortcuts"] bindings].count, 0u);
    NSEvent *arrow = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:NSEventModifierFlagShift | NSEventModifierFlagNumericPad | NSEventModifierFlagFunction
        timestamp:2 windowNumber:editor.window.windowNumber context:nil
        characters:@"\uF702" charactersIgnoringModifiers:@"\uF702" isARepeat:NO keyCode:123];
    [editor.window sendEvent:arrow];
    XCTAssertEqualObjects(previous.title, @"⇧←");
    [editor save:nil];
    OrbisWorkspaceShortcuts *saved = [[[OrbisWorkspaceShortcuts alloc] initWithDefaults:defaults platform:@"macos"] autorelease];
    XCTAssertEqual([saved actionForKeyCode:123 modifiers:OrbisShortcutShift], OrbisWorkspacePrevious);
}

- (void)testReservedShortcutIsRecordedBeforeAppKitAndDrainsItsRelease
{
    NSString *suite = [@"OrbisReservedShortcutTests." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[[NSUserDefaults alloc] initWithSuiteName:suite] autorelease];
    [self addTeardownBlock:^{ [defaults removePersistentDomainForName:suite]; }];
    OrbisShortcutsController *editor = [[[OrbisShortcutsController alloc] initWithDefaults:defaults] autorelease];
    NSButton *previous = (id)FindViewWithAccessibilityIdentifier(editor.window.contentView, @"workspace-shortcut-1");
    XCTAssertTrue([previous conformsToProtocol:@protocol(OrbisInputEventSink)],
        @"Recording must have an OS input path for shortcuts consumed before AppKit dispatch");
    if (![previous conformsToProtocol:@protocol(OrbisInputEventSink)]) return;
    // Replace only the OS foreground query without changing AppKit's KVO subclass.
    Method foreground = class_getInstanceMethod(NSClassFromString(@"OrbisShortcutField"),
        NSSelectorFromString(@"recordingWindowActive"));
    IMP original = method_getImplementation(foreground);
    IMP active = imp_implementationWithBlock(^BOOL(id field) { (void)field; return YES; });
    method_setImplementation(foreground, active);
    [self addTeardownBlock:^{ method_setImplementation(foreground, original); imp_removeBlock(active); }];
    OrbisRecordingTestTap *tap = [[[OrbisRecordingTestTap alloc] init] autorelease];
    [previous setValue:tap forKey:@"eventTap"];
    [editor.window makeFirstResponder:previous];
    XCTAssertTrue(tap.running);
    CGEventRef down = CGEventCreateKeyboardEvent(NULL, 123, true);
    CGEventSetFlags(down, kCGEventFlagMaskShift);
    CGEventRef up = CGEventCreateCopy(down); CGEventSetType(up, kCGEventKeyUp);
    CGEventRef repeat = CGEventCreateCopy(down);
    CGEventSetIntegerValueField(repeat, kCGKeyboardEventAutorepeat, 1);
    XCTAssertTrue([tap.sink consumeEvent:repeat type:kCGEventKeyDown]);
    XCTAssertEqual([[editor valueForKey:@"shortcuts"] bindings].count, 0u);
    XCTAssertEqual(editor.window.firstResponder, previous);
    XCTAssertTrue([tap.sink consumeEvent:down type:kCGEventKeyDown]);
    XCTAssertEqualObjects(previous.title, @"⇧←");
    XCTAssertNotEqual(editor.window.firstResponder, previous);
    XCTAssertTrue(tap.running, @"The recorded key release must not reach a Mac system shortcut");
    XCTAssertTrue([tap.sink consumeEvent:up type:kCGEventKeyUp]);
    XCTAssertFalse(tap.running);
    [editor.window makeFirstResponder:previous];
    XCTAssertTrue(tap.running);
    [NSNotificationCenter.defaultCenter postNotificationName:NSApplicationDidResignActiveNotification object:NSApp];
    XCTAssertFalse(tap.running);
    XCTAssertFalse([tap.sink consumeEvent:down type:kCGEventKeyDown]);
    [editor.window makeFirstResponder:previous];
    [NSNotificationCenter.defaultCenter postNotificationName:NSMenuDidBeginTrackingNotification object:nil];
    XCTAssertFalse(tap.running);
    XCTAssertNotEqual(editor.window.firstResponder, previous);
    [editor save:nil];
    OrbisWorkspaceShortcuts *saved = [[[OrbisWorkspaceShortcuts alloc] initWithDefaults:defaults platform:@"macos"] autorelease];
    XCTAssertEqual([saved actionForKeyCode:123 modifiers:OrbisShortcutShift], OrbisWorkspacePrevious);
    CFRelease(down); CFRelease(up); CFRelease(repeat);
}

- (void)testMouseShortcutCanBeAssignedWithoutPressingTheMappedButton
{
    NSString *suite = [@"OrbisManualMouseShortcutTests." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[[NSUserDefaults alloc] initWithSuiteName:suite] autorelease];
    [self addTeardownBlock:^{ [defaults removePersistentDomainForName:suite]; }];
    OrbisShortcutsController *editor = [[[OrbisShortcutsController alloc] initWithDefaults:defaults] autorelease];
    [editor.window orderFront:nil];
    NSButton *choose = (id)FindViewWithAccessibilityIdentifier(editor.window.contentView, @"workspace-mouse-shortcut-1");
    XCTAssertNotNil(choose, @"A system-mapped button must be assignable without triggering its Mac action");
    if (!choose) { [editor cancel:nil]; return; }
    [choose performClick:nil];
    NSWindow *picker = editor.window.attachedSheet;
    XCTAssertNotNil(picker);
    NSPopUpButton *button = (id)FindViewWithAccessibilityIdentifier(picker.contentView, @"mouse-shortcut-button");
    [button selectItemWithTag:4];
    NSButton *control = (id)FindViewWithAccessibilityIdentifier(picker.contentView, @"mouse-shortcut-control");
    NSButton *shift = (id)FindViewWithAccessibilityIdentifier(picker.contentView, @"mouse-shortcut-shift");
    control.state = shift.state = NSControlStateValueOn;
    NSButton *assign = (id)FindViewWithAccessibilityIdentifier(picker.contentView, @"mouse-shortcut-assign");
    XCTAssertNotNil(assign);
    [assign performClick:nil];
    NSButton *field = (id)FindViewWithAccessibilityIdentifier(editor.window.contentView, @"workspace-shortcut-1");
    XCTAssertEqualObjects(field.title, @"⌃⇧Mouse Button 5");
    OrbisWorkspaceShortcuts *saved = [[[OrbisWorkspaceShortcuts alloc] initWithDefaults:defaults platform:@"macos"] autorelease];
    XCTAssertEqual([saved actionForMouseButton:4 modifiers:OrbisShortcutControl | OrbisShortcutShift], OrbisWorkspaceNone);
    [editor save:nil];
    saved = [[[OrbisWorkspaceShortcuts alloc] initWithDefaults:defaults platform:@"macos"] autorelease];
    XCTAssertEqual([saved actionForMouseButton:4 modifiers:OrbisShortcutControl | OrbisShortcutShift], OrbisWorkspacePrevious);
    XCTAssertEqual([saved actionForMouseButton:4 modifiers:0], OrbisWorkspaceNone);
}

- (void)testManualMousePickerPreservesExistingBindingAndRejectsCollisions
{
    NSString *suite = [@"OrbisManualMouseCollisionTests." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[[NSUserDefaults alloc] initWithSuiteName:suite] autorelease];
    [self addTeardownBlock:^{ [defaults removePersistentDomainForName:suite]; }];
    OrbisShortcutsController *editor = [[[OrbisShortcutsController alloc] initWithDefaults:defaults] autorelease];
    OrbisWorkspaceShortcuts *draft = [editor valueForKey:@"shortcuts"];
    XCTAssertTrue([draft assignMouseButton:4 modifiers:OrbisShortcutCommand label:@"⌘Mouse Button 5"
        toAction:OrbisWorkspacePrevious error:nil]);
    [editor.window orderFront:nil];
    NSButton *choose = (id)FindViewWithAccessibilityIdentifier(editor.window.contentView, @"workspace-mouse-shortcut-1");
    [choose performClick:nil];
    NSWindow *picker = editor.window.attachedSheet;
    NSPopUpButton *button = (id)FindViewWithAccessibilityIdentifier(picker.contentView, @"mouse-shortcut-button");
    NSButton *command = (id)FindViewWithAccessibilityIdentifier(picker.contentView, @"mouse-shortcut-command");
    XCTAssertEqual(button.selectedItem.tag, 4);
    XCTAssertEqual(command.state, NSControlStateValueOn);
    [button selectItemWithTag:3];
    NSButton *cancel = (id)FindViewWithAccessibilityIdentifier(picker.contentView, @"mouse-shortcut-cancel");
    [cancel performClick:nil];
    XCTAssertEqual([draft actionForMouseButton:4 modifiers:OrbisShortcutCommand], OrbisWorkspacePrevious);
    XCTAssertEqual([draft actionForMouseButton:3 modifiers:OrbisShortcutCommand], OrbisWorkspaceNone);
    // Allow AppKit to finish dismissing the first sheet before opening another.
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    choose = (id)FindViewWithAccessibilityIdentifier(editor.window.contentView, @"workspace-mouse-shortcut-2");
    [choose performClick:nil];
    picker = editor.window.attachedSheet;
    button = (id)FindViewWithAccessibilityIdentifier(picker.contentView, @"mouse-shortcut-button");
    [button selectItemWithTag:4];
    command = (id)FindViewWithAccessibilityIdentifier(picker.contentView, @"mouse-shortcut-command");
    command.state = NSControlStateValueOn;
    [(NSButton *)FindViewWithAccessibilityIdentifier(picker.contentView, @"mouse-shortcut-assign") performClick:nil];
    XCTAssertEqualObjects(editor.window.attachedSheet, picker, @"A collision must keep the picker open");
    XCTAssertTrue([[editor valueForKey:@"mouseFeedback"] stringValue].length > 0);
    XCTAssertEqual([draft actionForMouseButton:4 modifiers:OrbisShortcutCommand], OrbisWorkspacePrevious);
    XCTAssertEqualObjects([draft labelForAction:OrbisWorkspaceNext], @"Not assigned");
    [editor cancel:nil];
    OrbisWorkspaceShortcuts *saved = [[[OrbisWorkspaceShortcuts alloc] initWithDefaults:defaults platform:@"macos"] autorelease];
    XCTAssertEqual(saved.bindings.count, 0u);
}

+ (void)setUp
{
	[super setUp];
	[NSApplication sharedApplication];
}

- (void)testLibraryBuildsItsVisibleHierarchyAndRightAlignsHeaderActions
{
	OrbisLibraryViewController *controller = [[OrbisLibraryViewController alloc] init];
	NSWindow *window = [[NSWindow alloc]
	    initWithContentRect:NSMakeRect(0.0, 0.0, 980.0, 680.0)
	              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
	                backing:NSBackingStoreBuffered
	                  defer:NO];
	[window setContentViewController:controller];
	[[window contentView] layoutSubtreeIfNeeded];

	NSView *content = [window contentView];
	XCTAssertGreaterThan([[content subviews] count], (NSUInteger)2);

	NSButton *refresh = FindButtonWithToolTip(content, @"Refresh connections");
	NSButton *add = FindButtonWithToolTip(content, @"New connection");
	NSButton *about = FindButtonWithToolTip(content, @"About Orbis");
	XCTAssertNil(refresh);
	XCTAssertNotNil(add);
	XCTAssertNotNil(about);

	NSRect addFrame = [add convertRect:[add bounds] toView:content];
	NSRect aboutFrame = [about convertRect:[about bounds] toView:content];
	XCTAssertGreaterThanOrEqual(NSMaxX(aboutFrame), NSWidth([content bounds]) - 45.0);
	XCTAssertGreaterThanOrEqual(NSMinX(addFrame), NSWidth([content bounds]) * 0.55);

	NSView *statusIcon = FindViewWithAccessibilityIdentifier(content, @"connection-status-icon");
	NSView *statusLabel = FindViewWithAccessibilityIdentifier(content, @"connection-status-label");
	if (statusIcon || statusLabel)
	{
		XCTAssertNotNil(statusIcon);
		XCTAssertNil(statusLabel);
		NSView *identity = [statusIcon superview];
		NSView *name = FindViewWithAccessibilityIdentifier(content, @"connection-name-label");
		XCTAssertEqual([name superview], identity);
	}

	[window release];
	[controller release];
}

- (void)testEditorKeepsSaveAndCancelOutsideTheScrollingForm
{
	OrbisProfile *profile = [[[OrbisProfile alloc] init] autorelease];
	OrbisProfileEditorController *editor = [[[OrbisProfileEditorController alloc]
	    initWithProfile:profile hasStoredPassword:NO] autorelease];
	NSView *content = [[editor window] contentView];
	[content layoutSubtreeIfNeeded];
	NSButton *save = FindButtonWithTitle(content, @"Save connection");
	NSButton *cancel = FindButtonWithTitle(content, @"Cancel");
	XCTAssertNotNil(save);
	XCTAssertNil([save enclosingScrollView]);
	XCTAssertNil([cancel enclosingScrollView]);
	XCTAssertEqual([save superview], [cancel superview]);
	NSRect saveFrame = [save convertRect:[save bounds] toView:content];
	XCTAssertGreaterThanOrEqual(NSMinY(saveFrame), 0.0);
	XCTAssertLessThanOrEqual(NSMaxY(saveFrame), NSHeight([content bounds]));
}

- (void)testAboutProvidesScrollableChangelogAndAcknowledgements
{
	OrbisAboutController *about = [[[OrbisAboutController alloc] init] autorelease];
	NSTabView *tabs = (NSTabView *)FindViewWithAccessibilityIdentifier(
	    [[about window] contentView], @"about-tabs");
	XCTAssertEqual([tabs numberOfTabViewItems], (NSInteger)2);
	XCTAssertEqualObjects([[tabs tabViewItemAtIndex:0] label], @"Changelog");
	XCTAssertEqualObjects([[tabs tabViewItemAtIndex:1] label], @"Acknowledgements");
	NSSegmentedControl *sections = (NSSegmentedControl *)FindViewWithAccessibilityIdentifier(
	    [[about window] contentView], @"about-sections");
	XCTAssertNotNil(sections);
	[sections setSelectedSegment:1];
	[NSApp sendAction:[sections action] to:[sections target] from:sections];
	XCTAssertEqual([tabs selectedTabViewItem], [tabs tabViewItemAtIndex:1]);
	for (NSTabViewItem *item in [tabs tabViewItems])
	{
		XCTAssertTrue([[item view] isKindOfClass:[NSScrollView class]]);
		NSTextView *text = [(NSScrollView *)[item view] documentView];
		XCTAssertFalse([text isEditable]);
		XCTAssertTrue([text isSelectable]);
		XCTAssertGreaterThan([[text string] length], (NSUInteger)0);
	}
}

- (void)testProfileEditorUsesRoundedInputsWithHorizontalPadding
{
	OrbisProfile *profile = [[OrbisProfile alloc] init];
	OrbisProfileEditorController *editor = [[OrbisProfileEditorController alloc]
	    initWithProfile:profile
	  hasStoredPassword:NO];
	NSView *content = [[editor window] contentView];
	[content layoutSubtreeIfNeeded];

	NSTextField *nameField = (NSTextField *)FindViewWithAccessibilityIdentifier(
	    content, @"profile-name-field");
	XCTAssertNotNil(nameField);
	XCTAssertEqual([nameField bezelStyle], NSTextFieldRoundedBezel);

	NSRect nameFrame = [nameField convertRect:[nameField bounds] toView:content];
	XCTAssertGreaterThanOrEqual(NSMinX(nameFrame), 32.0);
	XCTAssertLessThanOrEqual(NSMaxX(nameFrame), NSWidth([content bounds]) - 32.0);

	[editor release];
	[profile release];
}

- (void)testConnectionActionsStayAlignedAtTheMinimumWindowWidth
{
	OrbisLibraryViewController *controller = [[[OrbisLibraryViewController alloc] init] autorelease];
	NSMutableArray *fixtures = [NSMutableArray array];
	for (NSString *name in @[ @"Studio Mac", @"A workstation with a very long connection name" ])
	{
		OrbisProfile *profile = [[[OrbisProfile alloc] init] autorelease];
		[profile setName:name];
		[profile setHost:@"long-workstation-hostname.example.test"];
		[[controller profileStore] saveProfile:profile];
		[fixtures addObject:profile];
	}
	NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 760, 520)
	    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO] autorelease];
	[window setContentViewController:controller];
	[window setContentSize:NSMakeSize(760, 520)];
	NSView *content = [window contentView];
	[content layoutSubtreeIfNeeded];
	XCTAssertEqualWithAccuracy(NSWidth([content bounds]), 760.0, 1.0);
	NSStackView *cards = (NSStackView *)FindViewWithAccessibilityIdentifier(content, @"connection-cards");
	for (NSView *card in [cards arrangedSubviews])
	{
		NSButton *delete = FindButtonWithToolTip(card, @"Delete");
		if (!delete)
			continue;
		// Auto Layout positions the alignment rect; bezel padding varies by macOS.
		NSRect actionFrame = [[delete superview] convertRect:[delete alignmentRectForFrame:[delete frame]]
		    toView:content];
		XCTAssertEqualWithAccuracy(NSMaxX(actionFrame), NSWidth([content bounds]) - 42.0, 1.0,
		    @"Card: %@; content: %@; actions: %@; button alignment: %@; button bounds: %@; trailing inset: %g",
		    NSStringFromRect([card convertRect:[card bounds] toView:content]),
		    NSStringFromRect([[(NSBox *)card contentView] convertRect:[[(NSBox *)card contentView] bounds] toView:content]),
		    NSStringFromRect([[delete superview] convertRect:[[delete superview] bounds] toView:content]),
		    NSStringFromRect(actionFrame), NSStringFromRect([delete convertRect:[delete bounds] toView:content]),
		    [delete alignmentRectInsets].right);
		NSTextField *name = (NSTextField *)FindViewWithAccessibilityIdentifier(card, @"connection-name-label");
		if ([[name stringValue] isEqualToString:@"Studio Mac"])
			XCTAssertGreaterThanOrEqual(NSWidth([name frame]), [[name cell] cellSize].width);
	}
	for (OrbisProfile *profile in fixtures)
		[[controller profileStore] deleteProfileWithIdentifier:[profile identifier]];
}

- (void)testCloudflareEditorShowsTokenFieldsAndHidesTheMappedPort
{
	OrbisProfile *profile = [[OrbisProfile alloc] init];
	OrbisProfileEditorController *editor = [[OrbisProfileEditorController alloc]
	    initWithProfile:profile hasStoredPassword:NO];
	NSView *content = [[editor window] contentView];
	NSPopUpButton *transport = (NSPopUpButton *)FindViewWithAccessibilityIdentifier(content, @"profile-transport-field");
	NSView *clientID = FindViewWithAccessibilityIdentifier(content, @"profile-client-id-field");
	NSView *secret = FindViewWithAccessibilityIdentifier(content, @"profile-client-secret-field");
	NSView *gateway = FindViewWithAccessibilityIdentifier(content, @"profile-gateway-hostname-field");
	NSView *port = FindViewWithAccessibilityIdentifier(content, @"profile-port-field");
	NSView *host = FindViewWithAccessibilityIdentifier(content, @"profile-host-field");
	XCTAssertNotNil(transport);
	XCTAssertTrue([clientID isHiddenOrHasHiddenAncestor]);
	XCTAssertTrue([secret isHiddenOrHasHiddenAncestor]);
	XCTAssertTrue([gateway isHiddenOrHasHiddenAncestor]);
	XCTAssertFalse([port isHiddenOrHasHiddenAncestor]);
	XCTAssertFalse([host isHiddenOrHasHiddenAncestor]);
	[transport selectItemAtIndex:1];
	[NSApp sendAction:[transport action] to:[transport target] from:transport];
	[content layoutSubtreeIfNeeded];
	XCTAssertFalse([clientID isHiddenOrHasHiddenAncestor]);
	XCTAssertFalse([secret isHiddenOrHasHiddenAncestor]);
	XCTAssertFalse([gateway isHiddenOrHasHiddenAncestor]);
	XCTAssertTrue([secret isKindOfClass:[NSSecureTextField class]]);
	XCTAssertTrue([port isHiddenOrHasHiddenAncestor]);
	XCTAssertTrue([host isHiddenOrHasHiddenAncestor]);
	[transport selectItemAtIndex:0];
	[NSApp sendAction:[transport action] to:[transport target] from:transport];
	XCTAssertFalse([host isHiddenOrHasHiddenAncestor]);
	XCTAssertFalse([port isHiddenOrHasHiddenAncestor]);
	XCTAssertTrue([gateway isHiddenOrHasHiddenAncestor]);
	XCTAssertTrue([clientID isHiddenOrHasHiddenAncestor]);
	XCTAssertTrue([secret isHiddenOrHasHiddenAncestor]);
	[editor release];
	[profile release];
}

- (void)testTunnelEditorPreservesLogicalServerAndItsPortWhenSavingGatewayOptions
{
	OrbisProfile *profile = [[OrbisProfile alloc] init];
	[profile setName:@"Workstation"];
	[profile setHost:@"logical-server.example.test"];
	[profile setPort:3390];
	[profile setTransportType:OrbisTransportTypeCloudflare];
	[profile setTransportOptions:@{ @"hostname" : @"gateway.example.test" }];
	OrbisProfileEditorController *editor = [[OrbisProfileEditorController alloc]
	    initWithProfile:profile hasStoredPassword:NO];
	NSView *content = [[editor window] contentView];
	NSTextField *gateway = (NSTextField *)FindViewWithAccessibilityIdentifier(content, @"profile-gateway-hostname-field");
	XCTAssertEqualObjects([gateway stringValue], @"gateway.example.test");
	[(NSTextField *)FindViewWithAccessibilityIdentifier(content, @"profile-client-id-field") setStringValue:@"fixture-client"];
	[(NSTextField *)FindViewWithAccessibilityIdentifier(content, @"profile-client-secret-field") setStringValue:@"fixture-secret"];
	OrbisEditorSaveRecorder *recorder = [[OrbisEditorSaveRecorder alloc] init];
	[editor setDelegate:recorder];
	[editor save:nil];
	XCTAssertNotNil([recorder profile]);
	XCTAssertEqualObjects([[recorder profile] host], @"logical-server.example.test");
	XCTAssertEqual([[recorder profile] port], (NSUInteger)3390);
	XCTAssertEqualObjects([[recorder profile] transportHostname], @"gateway.example.test");
	[editor setDelegate:nil];
	[recorder release];
	[editor release];
	[profile release];
}

- (void)testInputCaptureDefaultsOffAndCancelDoesNotEnableIt
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id original = [[defaults objectForKey:OrbisFullscreenInputCaptureKey] retain];
    id originalLayout = [[defaults objectForKey:OrbisCapturedMacKeyboardLayoutKey] retain];
    [defaults removeObjectForKey:OrbisCapturedMacKeyboardLayoutKey];
    [defaults removeObjectForKey:OrbisFullscreenInputCaptureKey];
    OrbisDisplaySettings *settings = [[[OrbisDisplaySettings alloc] init] autorelease];
    OrbisDisplaySettingsController *editor = [[OrbisDisplaySettingsController alloc] initWithSettings:settings];
    NSButton *capture = (id)FindViewWithAccessibilityIdentifier(editor.window.contentView, @"settings-fullscreen-input-capture");
    XCTAssertNotNil(capture);
    XCTAssertEqual(capture.state, NSControlStateValueOff);
    NSPopUpButton *layout = (id)FindViewWithAccessibilityIdentifier(editor.window.contentView,
        @"settings-captured-keyboard-layout");
    XCTAssertNotNil(layout);
    XCTAssertEqual(layout.numberOfItems, (NSInteger)2);
    XCTAssertEqual(layout.indexOfSelectedItem, (NSInteger)0, @"Physical remote typing with right AltGr is the default");
    [layout selectItemAtIndex:1];
    capture.state = NSControlStateValueOn;
    NSButton *cancel = FindButtonWithTitle(editor.window.contentView, @"Cancel");
    [cancel sendAction:cancel.action to:cancel.target];
    XCTAssertFalse([defaults boolForKey:OrbisFullscreenInputCaptureKey]);
    XCTAssertFalse([defaults boolForKey:OrbisCapturedMacKeyboardLayoutKey], @"Cancel must preserve the typing mode");
    [editor release];
    [defaults setBool:YES forKey:OrbisFullscreenInputCaptureKey];
    [defaults setBool:YES forKey:OrbisCapturedMacKeyboardLayoutKey];
    editor = [[OrbisDisplaySettingsController alloc] initWithSettings:settings];
    capture = (id)FindViewWithAccessibilityIdentifier(editor.window.contentView, @"settings-fullscreen-input-capture");
    XCTAssertEqual(capture.state, NSControlStateValueOn);
    layout = (id)FindViewWithAccessibilityIdentifier(editor.window.contentView, @"settings-captured-keyboard-layout");
    XCTAssertEqual(layout.indexOfSelectedItem, (NSInteger)1, @"Settings must reopen with the saved Mac typing mode");
    [editor release];
    if (original) [defaults setObject:original forKey:OrbisFullscreenInputCaptureKey];
    else [defaults removeObjectForKey:OrbisFullscreenInputCaptureKey];
    [original release];
    if (originalLayout) [defaults setObject:originalLayout forKey:OrbisCapturedMacKeyboardLayoutKey];
    else [defaults removeObjectForKey:OrbisCapturedMacKeyboardLayoutKey];
    [originalLayout release];
}

- (void)testDisplaySettingsPersistResolutionsAndDraggedOffsetsWithoutChangingConnections
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id original = [[defaults objectForKey:@"OrbisDisplaySettings.v1"] retain];
    [defaults removeObjectForKey:@"OrbisDisplaySettings.v1"];
    OrbisProfile *profile = [[[OrbisProfile alloc] init] autorelease];
    profile.name = @"Workstation"; profile.host = @"desktop.example.test";
    profile.primaryWidth = 1280; profile.primaryHeight = 800;
    OrbisDisplaySettings *settings = [[[OrbisDisplaySettings alloc] initWithDefaults:defaults legacyProfile:profile] autorelease];
    XCTAssertEqual(settings.primaryWidth, (NSUInteger)1280);
    profile.primaryWidth = 2560;
    OrbisDisplaySettings *migrated = [[[OrbisDisplaySettings alloc] initWithDefaults:defaults legacyProfile:profile] autorelease];
    XCTAssertEqual(migrated.primaryWidth, (NSUInteger)1280, @"Migration happens once; global settings win over another profile");
    OrbisDisplaySettingsController *editor = [[OrbisDisplaySettingsController alloc] initWithSettings:settings];
    NSView *content = editor.window.contentView;
    NSPopUpButton *primary = (id)FindViewWithAccessibilityIdentifier(content, @"settings-primary-resolution-mode");
    NSPopUpButton *secondary = (id)FindViewWithAccessibilityIdentifier(content, @"settings-secondary-resolution-mode");
    [primary selectItemAtIndex:1]; [primary sendAction:primary.action to:primary.target];
    [secondary selectItemAtIndex:1]; [secondary sendAction:secondary.action to:secondary.target];
    NSTextField *pw = (id)FindViewWithAccessibilityIdentifier(content, @"settings-primary-width");
    NSTextField *ph = (id)FindViewWithAccessibilityIdentifier(content, @"settings-primary-height");
    NSTextField *sw = (id)FindViewWithAccessibilityIdentifier(content, @"settings-secondary-width");
    NSTextField *sh = (id)FindViewWithAccessibilityIdentifier(content, @"settings-secondary-height");
    XCTAssertTrue(pw.enabled && ph.enabled && sw.enabled && sh.enabled);
    pw.stringValue = @"2560"; ph.stringValue = @"1440";
    sw.stringValue = @"1920"; sh.stringValue = @"1080";
    [primary sendAction:primary.action to:primary.target];
    OrbisDisplayArrangementView *arrangement = (id)FindViewWithAccessibilityIdentifier(content, @"display-arrangement");
    [arrangement.settings placeSecondaryAtPoint:NSMakePoint(-1920, 240)];
    NSButton *save = FindButtonWithTitle(content, @"Save settings");
    [save sendAction:save.action to:save.target];
    OrbisDisplaySettings *saved = [OrbisDisplaySettings loadMigratingProfile:nil];
    XCTAssertEqual(saved.primaryWidth, (NSUInteger)2560); XCTAssertEqual(saved.primaryHeight, (NSUInteger)1440);
    XCTAssertEqual(saved.secondaryWidth, (NSUInteger)1920); XCTAssertEqual(saved.secondaryHeight, (NSUInteger)1080);
    XCTAssertEqual(saved.arrangement, OrbisMonitorLeft); XCTAssertEqual(saved.offset, (int32_t)240);
    XCTAssertEqual(profile.primaryWidth, (NSUInteger)2560); XCTAssertEqual(profile.secondaryWidth, (NSUInteger)0);
    for (NSString *invalid in @[ @"1921", @"8194", @"-200", @"1920x", @"", @"199" ])
    {
        sw.stringValue = invalid; [save sendAction:save.action to:save.target];
        XCTAssertEqual([OrbisDisplaySettings loadMigratingProfile:nil].secondaryWidth, (NSUInteger)1920);
    }
    [primary selectItemAtIndex:0]; [secondary selectItemAtIndex:0];
    [save sendAction:save.action to:save.target];
    XCTAssertEqual([OrbisDisplaySettings loadMigratingProfile:nil].primaryWidth, (NSUInteger)0);
    XCTAssertEqual([OrbisDisplaySettings loadMigratingProfile:nil].secondaryWidth, (NSUInteger)0);
    [primary selectItemAtIndex:1]; [secondary selectItemAtIndex:1];
    sw.stringValue = @"1920"; [primary sendAction:primary.action to:primary.target];
    [content layoutSubtreeIfNeeded];
    [arrangement setNeedsDisplay:YES]; [content displayIfNeeded];
    NSString *screenshot = [NSProcessInfo processInfo].environment[@"ORBIS_DISPLAY_OPTIONS_SCREENSHOT"];
    if (screenshot)
    {
        NSBitmapImageRep *image = [content bitmapImageRepForCachingDisplayInRect:content.bounds];
        [content cacheDisplayInRect:content.bounds toBitmapImageRep:image];
        [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:screenshot atomically:YES];
    }
    [editor release];
    if (original) [defaults setObject:original forKey:@"OrbisDisplaySettings.v1"];
    else [defaults removeObjectForKey:@"OrbisDisplaySettings.v1"];
    [original release];
}

- (void)testDraggingEitherMonitorPreservesRelativePositionAndCancelKeepsSavedSettings
{
    OrbisDisplaySettings *settings = [[[OrbisDisplaySettings alloc] init] autorelease];
    settings.primaryWidth = 1920; settings.primaryHeight = 1080;
    settings.secondaryWidth = 1280; settings.secondaryHeight = 1024;
    NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 556, 210)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO] autorelease];
    OrbisArrangementDragFixture *view = [[[OrbisArrangementDragFixture alloc] initWithFrame:NSMakeRect(0, 0, 556, 210)] autorelease];
    view.settings = settings; [window setContentView:view];
    [view dragDisplay:1 toRemotePoint:NSMakePoint(-1280, 240)];
    XCTAssertEqual(settings.arrangement, OrbisMonitorLeft); XCTAssertEqual(settings.offset, (int32_t)240);
    [view dragDisplay:0 toRemotePoint:NSMakePoint(300, -1024)];
    XCTAssertEqual(settings.arrangement, OrbisMonitorAbove); XCTAssertEqual(settings.offset, (int32_t)300);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id original = [[defaults objectForKey:@"OrbisDisplaySettings.v1"] retain];
    [settings saveToDefaults:defaults];
    NSDictionary *before = [[defaults objectForKey:@"OrbisDisplaySettings.v1"] copy];
    OrbisDisplaySettingsController *editor = [[[OrbisDisplaySettingsController alloc] initWithSettings:settings] autorelease];
    [editor beginSheetForWindow:window];
    OrbisDisplayArrangementView *editorView = (id)FindViewWithAccessibilityIdentifier(editor.window.contentView, @"display-arrangement");
    [editorView.settings placeSecondaryAtPoint:NSMakePoint(1920, 200)];
    NSButton *cancel = FindButtonWithTitle(editor.window.contentView, @"Cancel");
    [cancel sendAction:cancel.action to:cancel.target]; DrainSheetCompletion();
    XCTAssertEqualObjects([defaults objectForKey:@"OrbisDisplaySettings.v1"], before);
    [before release];
    if (original) [defaults setObject:original forKey:@"OrbisDisplaySettings.v1"];
    else [defaults removeObjectForKey:@"OrbisDisplaySettings.v1"];
    [original release];
}

- (void)testMonitorPlacementSnapsToEveryEdgeAndClampsInvalidOffsets
{
    OrbisDisplaySettings *settings = [[[OrbisDisplaySettings alloc] init] autorelease];
    settings.primaryWidth = 1920; settings.primaryHeight = 1080;
    settings.secondaryWidth = 1280; settings.secondaryHeight = 1024;
    NSPoint placements[] = { NSMakePoint(2000, 200), NSMakePoint(-1250, -100),
        NSMakePoint(300, -1000), NSMakePoint(-200, 1100) };
    for (NSUInteger i = 0; i < 4; i++)
    {
        [settings placeSecondaryAtPoint:placements[i]];
        XCTAssertEqual(settings.arrangement, (OrbisMonitorArrangement)i);
        OrbisDisplayLayout layout = settings.previewLayout;
        XCTAssertEqual(layout.monitors[1].x, (int32_t)(i == 0 ? 1920 : i == 1 ? -1280 : placements[i].x));
        XCTAssertEqual(layout.monitors[1].y, (int32_t)(i == 2 ? -1024 : i == 3 ? 1080 : placements[i].y));
    }
    OrbisDisplayLayout layout;
    XCTAssertTrue(OrbisDisplayLayoutMakeWithOffset(1920, 1080, 1280, 1024, OrbisMonitorRight, INT32_MIN, true, &layout));
    XCTAssertEqual(layout.monitors[1].y, (int32_t)-1023);
    XCTAssertEqual(layout.pixels[0].y, (int32_t)1023);
    XCTAssertTrue(OrbisDisplayLayoutMakeWithOffset(1920, 1080, 1280, 1024, OrbisMonitorAbove, INT32_MAX, true, &layout));
    XCTAssertEqual(layout.monitors[1].x, (int32_t)1918);
    for (OrbisMonitorArrangement side = OrbisMonitorAbove; side <= OrbisMonitorBelow; side++)
        for (int32_t offset = -1301; offset < 1950; offset += 17)
        {
            XCTAssertTrue(OrbisDisplayLayoutMakeWithOffset(1920, 1080, 1280, 1024, side, offset, true, &layout));
            XCTAssertEqual(layout.width % 2, (uint32_t)0);
            XCTAssertEqual(layout.monitors[1].x % 2, (int32_t)0);
        }
}

- (void)testCancelAndEscapeAllowEditingAgainAndCreatingANewConnection
{
	OrbisLibraryViewController *controller = [[OrbisLibraryViewController alloc] init];
	OrbisProfile *profile = [[OrbisProfile alloc] init];
	[profile setName:@"Editor lifecycle test"];
	[profile setHost:@"desktop.example.test"];
	[[controller profileStore] saveProfile:profile];
	NSWindow *window = [[NSWindow alloc]
	    initWithContentRect:NSMakeRect(0.0, 0.0, 980.0, 680.0)
	              styleMask:NSWindowStyleMaskTitled
	                backing:NSBackingStoreBuffered defer:NO];
	[window setContentViewController:controller];
	[window makeKeyAndOrderFront:nil];

	for (NSUInteger attempt = 0; attempt < 3; attempt++)
	{
		NSString *toolTip = attempt == 2 ? @"New connection" : @"Edit";
		[FindButtonWithToolTip([window contentView], toolTip) performClick:nil];
		NSWindow *sheet = [window attachedSheet];
		XCTAssertNotNil(sheet);
		DrainSheetCompletion();
		if (attempt == 1)
		{
			NSEvent *escape = [NSEvent keyEventWithType:NSEventTypeKeyDown
			    location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:[sheet windowNumber]
			    context:nil characters:@"\033" charactersIgnoringModifiers:@"\033" isARepeat:NO keyCode:53];
			XCTAssertTrue([sheet performKeyEquivalent:escape]);
		}
		else
			[FindButtonWithTitle([sheet contentView], @"Cancel") performClick:nil];
		DrainSheetCompletion();
		XCTAssertNil([window attachedSheet], @"Dismissal attempt %lu", (unsigned long)attempt);
	}
	XCTAssertEqual([[controller profileStore] profiles].count, (NSUInteger)1);
	[[controller profileStore] deleteProfileWithIdentifier:[profile identifier]];
	[window orderOut:nil];
	[window release];
	[controller release];
	[profile release];
}

- (void)testNewTunnelSavesHTTPSURLWithoutRequiringANativeHost
{
	for (NSString *address in @[ @"https://Gateway.example.test/", @"gateway.example.test" ])
	{
		OrbisProfile *profile = [[OrbisProfile alloc] init];
		OrbisProfileEditorController *editor = [[OrbisProfileEditorController alloc]
		    initWithProfile:profile hasStoredPassword:NO];
		NSView *content = [[editor window] contentView];
		NSPopUpButton *transport = (NSPopUpButton *)FindViewWithAccessibilityIdentifier(content, @"profile-transport-field");
		[transport selectItemAtIndex:1];
		[NSApp sendAction:[transport action] to:[transport target] from:transport];
		[(NSTextField *)FindViewWithAccessibilityIdentifier(content, @"profile-name-field") setStringValue:@"Tunnel"];
		[(NSTextField *)FindViewWithAccessibilityIdentifier(content, @"profile-gateway-hostname-field") setStringValue:address];
		[(NSTextField *)FindViewWithAccessibilityIdentifier(content, @"profile-client-id-field") setStringValue:@"fixture-client"];
		[(NSTextField *)FindViewWithAccessibilityIdentifier(content, @"profile-client-secret-field") setStringValue:@"fixture-secret"];
		OrbisEditorSaveRecorder *recorder = [[OrbisEditorSaveRecorder alloc] init];
		[editor setDelegate:recorder];
		[editor save:nil];
		XCTAssertNotNil([recorder profile]);
		XCTAssertEqualObjects([[[recorder profile] transportHostname] lowercaseString], @"gateway.example.test");
		XCTAssertEqualObjects([[recorder profile] host], [[recorder profile] transportHostname]);
		XCTAssertEqualObjects([[recorder profile] transportType], OrbisTransportTypeCloudflare);
		[editor setDelegate:nil];
		[recorder release];
		[editor release];
		[profile release];
	}
}

- (void)testTunnelEditorRejectsInvalidURLsBeforeSaving
{
	OrbisProfile *profile = [[OrbisProfile alloc] init];
	OrbisProfileEditorController *editor = [[OrbisProfileEditorController alloc]
	    initWithProfile:profile hasStoredPassword:NO];
	NSView *content = [[editor window] contentView];
	NSPopUpButton *transport = (NSPopUpButton *)FindViewWithAccessibilityIdentifier(content, @"profile-transport-field");
	[transport selectItemAtIndex:1];
	[NSApp sendAction:[transport action] to:[transport target] from:transport];
	[(NSTextField *)FindViewWithAccessibilityIdentifier(content, @"profile-name-field") setStringValue:@"Tunnel"];
	[(NSTextField *)FindViewWithAccessibilityIdentifier(content, @"profile-client-id-field") setStringValue:@"fixture-client"];
	[(NSTextField *)FindViewWithAccessibilityIdentifier(content, @"profile-client-secret-field") setStringValue:@"fixture-secret"];
	OrbisEditorSaveRecorder *recorder = [[OrbisEditorSaveRecorder alloc] init];
	[editor setDelegate:recorder];
	for (NSString *address in @[ @"", @"http://gateway.example.test", @"https://user:secret@gateway.example.test",
	                             @"https://gateway.example.test/path", @"https://gateway.example.test?query=1",
	                             @"https://gateway.example.test#fragment", @"https://gateway.example.test:8443",
	                             @"bad host", @"https://" ])
	{
		[(NSTextField *)FindViewWithAccessibilityIdentifier(content, @"profile-gateway-hostname-field") setStringValue:address];
		[editor save:nil];
		XCTAssertNil([recorder profile], @"Invalid tunnel URL: %@", address);
	}
	[editor setDelegate:nil];
	[recorder release];
	[editor release];
	[profile release];
}

- (void)testSaveAllowsOpeningAnotherEditor
{
	OrbisLibraryViewController *controller = [[OrbisLibraryViewController alloc] init];
	NSWindow *window = [[NSWindow alloc]
	    initWithContentRect:NSMakeRect(0.0, 0.0, 980.0, 680.0)
	              styleMask:NSWindowStyleMaskTitled
	                backing:NSBackingStoreBuffered defer:NO];
	[window setContentViewController:controller];
	[window makeKeyAndOrderFront:nil];
	[FindButtonWithToolTip([window contentView], @"New connection") performClick:nil];
	NSView *content = [[window attachedSheet] contentView];
	[(NSTextField *)FindViewWithAccessibilityIdentifier(content, @"profile-name-field")
	    setStringValue:@"Saved connection"];
	[(NSTextField *)FindViewWithAccessibilityIdentifier(content, @"profile-host-field")
	    setStringValue:@"desktop.example.test"];
	[FindButtonWithTitle(content, @"Save connection") performClick:nil];
	DrainSheetCompletion();
	XCTAssertNil([window attachedSheet]);
	XCTAssertEqual([[controller profileStore] profiles].count, (NSUInteger)1);
	[FindButtonWithToolTip([window contentView], @"New connection") performClick:nil];
	XCTAssertNotNil([window attachedSheet]);
	[FindButtonWithTitle([[window attachedSheet] contentView], @"Cancel") performClick:nil];
	DrainSheetCompletion();
	[[controller profileStore] deleteProfileWithIdentifier:
	    [[[controller profileStore] selectedProfile] identifier]];
	[window orderOut:nil];
	[window release];
	[controller release];
}

@end
