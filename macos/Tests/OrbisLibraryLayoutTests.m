/* SPDX-License-Identifier: MIT */

#import <AppKit/AppKit.h>
#import <XCTest/XCTest.h>

#import "OrbisLibraryViewController.h"
#import "OrbisProfile.h"
#import "OrbisProfileEditorController.h"

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
	XCTAssertNotNil(refresh);
	XCTAssertNotNil(add);
	XCTAssertNotNil(about);

	NSRect refreshFrame = [refresh convertRect:[refresh bounds] toView:content];
	NSRect aboutFrame = [about convertRect:[about bounds] toView:content];
	XCTAssertGreaterThanOrEqual(NSMaxX(aboutFrame), NSWidth([content bounds]) - 45.0);
	XCTAssertGreaterThanOrEqual(NSMinX(refreshFrame), NSWidth([content bounds]) * 0.75);

	NSView *statusIcon = FindViewWithAccessibilityIdentifier(content, @"connection-status-icon");
	NSView *statusLabel = FindViewWithAccessibilityIdentifier(content, @"connection-status-label");
	if (statusIcon || statusLabel)
	{
		XCTAssertNotNil(statusIcon);
		XCTAssertNotNil(statusLabel);
		XCTAssertEqual([statusIcon superview], [statusLabel superview]);
		NSRect iconFrame = [statusIcon convertRect:[statusIcon bounds] toView:[statusIcon superview]];
		NSRect labelFrame = [statusLabel convertRect:[statusLabel bounds] toView:[statusLabel superview]];
		XCTAssertLessThanOrEqual(fabs(NSMidY(iconFrame) - NSMidY(labelFrame)), 1.0);
	}

	[window release];
	[controller release];
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

@end
