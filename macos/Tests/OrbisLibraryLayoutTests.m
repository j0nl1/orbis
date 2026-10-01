/* SPDX-License-Identifier: MIT */

#import <AppKit/AppKit.h>
#import <XCTest/XCTest.h>

#import "OrbisLibraryViewController.h"
#import "OrbisProfile.h"
#import "OrbisProfileEditorController.h"
#import "OrbisAboutController.h"

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

@interface OrbisLibraryLayoutTests : XCTestCase
@end

@implementation OrbisLibraryLayoutTests

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
	XCTAssertGreaterThanOrEqual(NSMinX(addFrame), NSWidth([content bounds]) * 0.7);

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
		XCTAssertTrue([card isKindOfClass:[NSBox class]]);
		XCTAssertEqualWithAccuracy([(NSBox *)card contentViewMargins].width, 5.0, 0.01);
		XCTAssertEqualWithAccuracy([(NSBox *)card contentViewMargins].height, 5.0, 0.01);
		NSRect actionFrame = [delete convertRect:[delete bounds] toView:content];
		XCTAssertEqualWithAccuracy(NSMaxX(actionFrame), NSWidth([content bounds]) - 42.0, 1.0,
		    @"Card: %@; content: %@; actions: %@; button: %@; button alignment insets: %@",
		    NSStringFromRect([card convertRect:[card bounds] toView:content]),
		    NSStringFromRect([[(NSBox *)card contentView] convertRect:[[(NSBox *)card contentView] bounds] toView:content]),
		    NSStringFromRect([[delete superview] convertRect:[[delete superview] bounds] toView:content]),
		    NSStringFromRect(actionFrame), NSStringFromNSEdgeInsets([delete alignmentRectInsets]));
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
