/* SPDX-License-Identifier: MIT */

#import "OrbisAppDelegate.h"
#import "OrbisProfile.h"
#import "OrbisProfileEditorController.h"

static NSWindow *editingWindow;
static NSUInteger failures;

/* SSH has no foreground application. Supply its window to the responder chain. */
@interface OrbisEditingApplication : NSApplication
@end
@implementation OrbisEditingApplication
- (NSWindow *)keyWindow { return editingWindow ?: [super keyWindow]; }
- (NSWindow *)mainWindow { return editingWindow ?: [super mainWindow]; }
@end

/* The editing test exercises the real application menu without starting RDP. */
@implementation OrbisSessionController
@synthesize delegate = _delegate;
- (id)initWithProfile:(OrbisProfile *)profile password:(NSString *)password
             transport:(id<OrbisConnectionTransport>)transport
{
	(void)profile;
	(void)password;
	(void)transport;
	return [super init];
}
- (BOOL)start { return NO; }
- (void)stop {}
- (BOOL)canAddVirtualDisplay { return NO; }
- (void)addVirtualDisplay:(id)sender { (void)sender; }
- (NSInteger)activeRemoteDisplayIndex { return -1; }
- (NSSize)activeDisplayResolution { return NSZeroSize; }
- (NSSize)activeScreenResolution { return NSZeroSize; }
- (BOOL)canChangeActiveDisplayResolution { return NO; }
- (BOOL)canSetActiveDisplayResolution:(NSSize)resolution { (void)resolution; return NO; }
- (void)setActiveDisplayResolution:(NSSize)resolution { (void)resolution; }
- (BOOL)activeDisplayMatchesWindow { return NO; }
- (void)setActiveDisplayMatchesWindow:(BOOL)enabled { (void)enabled; }
- (MRDPView *)inputCaptureKeyboardTarget { return nil; }
- (MRDPView *)inputCapturePointerTargetAtScreenPoint:(NSPoint)point { (void)point; return nil; }
@end

@interface OrbisAppDelegate (EditingTests)
- (void)buildMainMenu;
@end

static void Require(BOOL condition, const char *message)
{
	if (!condition)
	{
		fprintf(stderr, "FAIL: %s\n", message);
		failures++;
	}
}

static NSView *FindField(NSView *view, NSString *identifier)
{
	if ([[view accessibilityIdentifier] isEqualToString:identifier])
		return view;
	for (NSView *child in [view subviews])
	{
		NSView *found = FindField(child, identifier);
		if (found)
			return found;
	}
	return nil;
}

static void Shortcut(NSWindow *window, NSString *key, unsigned short keyCode)
{
	NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
	    modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:[window windowNumber]
	    context:nil characters:key charactersIgnoringModifiers:key isARepeat:NO keyCode:keyCode];
	[[NSApp mainMenu] update];
	Require([[NSApp mainMenu] performKeyEquivalent:event], "The application must handle the editing shortcut");
}

static void DrainApplicationEvents(void)
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.3];
	while ([deadline timeIntervalSinceNow] > 0)
	{
		NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:deadline
		    inMode:NSDefaultRunLoopMode dequeue:YES];
		if (event)
			[NSApp sendEvent:event];
	}
}

int main(void)
{
	@autoreleasepool
	{
		[OrbisEditingApplication sharedApplication];
		[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
		[NSApp finishLaunching];
		NSMenu *previousMenu = [[NSApp mainMenu] retain];
		NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
		NSMutableArray *previousClipboard = [NSMutableArray array];
		for (NSPasteboardItem *item in [pasteboard pasteboardItems])
		{
			NSPasteboardItem *saved = [[[NSPasteboardItem alloc] init] autorelease];
			for (NSPasteboardType type in [item types])
			{
				NSData *data = [item dataForType:type];
				if (data)
					[saved setData:data forType:type];
			}
			[previousClipboard addObject:saved];
		}
		OrbisAppDelegate *delegate = [[[OrbisAppDelegate alloc] init] autorelease];
		[delegate buildMainMenu];
		OrbisProfile *profile = [[[OrbisProfile alloc] init] autorelease];
		[profile setTransportType:OrbisTransportTypeCloudflare];
		OrbisProfileEditorController *editor = [[[OrbisProfileEditorController alloc]
		    initWithProfile:profile hasStoredPassword:NO] autorelease];
		NSWindow *window = [editor window];
		editingWindow = window;
		[window makeKeyAndOrderFront:nil];
		[NSApp activateIgnoringOtherApps:YES];
		DrainApplicationEvents();
		[window makeKeyWindow];
		Require([NSApp keyWindow] == window, "The keyboard fixture must expose its window to the responder chain");
		for (NSString *identifier in @[ @"profile-name-field", @"profile-client-id-field",
		                               @"profile-client-secret-field", @"profile-password-field" ])
		{
			NSTextField *field = (NSTextField *)FindField([window contentView], identifier);
			Require(field != nil, "The editor must expose the test field");
			[field setStringValue:@"replace-me"];
			[field scrollRectToVisible:[field bounds]];
			Require([window makeFirstResponder:field], "The field must accept keyboard focus");
			NSTextView *fieldEditor = (NSTextView *)[field currentEditor];
			Require(fieldEditor != nil, "The focused input must retain its native field editor");
			NSRect textRect = [fieldEditor convertRect:[fieldEditor bounds] toView:field];
			Require(fabs(NSMidY(textRect) - NSMidY([field bounds])) <= 2.0,
			        "Focused text must remain vertically centered in ordinary and secure inputs");
			[pasteboard clearContents];
			[pasteboard setString:@"fixture-pasted-value" forType:NSPasteboardTypeString];
			Shortcut(window, @"a", 0);
			Shortcut(window, @"v", 9);
			DrainApplicationEvents();
			[window makeFirstResponder:nil];
			Require([[field stringValue] isEqualToString:@"fixture-pasted-value"],
			        "Command-V must replace selected text in ordinary and secure fields");
		}
		[window orderOut:nil];
		editingWindow = nil;
		[NSApp setMainMenu:previousMenu];
		[previousMenu release];
		[pasteboard clearContents];
		[pasteboard writeObjects:previousClipboard];
	}
	if (!failures)
		puts("PASS: native editing shortcuts in connection and secure token fields");
	return failures ? 1 : 0;
}
