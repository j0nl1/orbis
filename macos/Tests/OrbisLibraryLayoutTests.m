/* SPDX-License-Identifier: MIT */

#import <AppKit/AppKit.h>

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
	if ([view isKindOfClass:[NSButton class]] && [[[((NSButton *)view) toolTip] description] isEqualToString:toolTip])
		return (NSButton *)view;
	for (NSView *subview in [view subviews])
	{
		NSButton *match = FindButtonWithToolTip(subview, toolTip);
		if (match)
			return match;
	}
	return nil;
}

int main(void)
{
	@autoreleasepool
	{
		[NSApplication sharedApplication];
		OrbisLibraryViewController *controller = [[OrbisLibraryViewController alloc] init];
		NSWindow *window = [[NSWindow alloc]
		    initWithContentRect:NSMakeRect(0.0, 0.0, 980.0, 680.0)
		              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
		                backing:NSBackingStoreBuffered
		                  defer:NO];
		@try
		{
			[window setContentViewController:controller];
			[[window contentView] layoutSubtreeIfNeeded];
		}
		@catch (NSException *exception)
		{
			fprintf(stderr, "FAIL: Orbis library layout raised %s: %s\n",
			        [[exception name] UTF8String], [[exception reason] UTF8String]);
			[window release];
			[controller release];
			return 1;
		}

		if ([[[window contentView] subviews] count] < 3)
		{
			fprintf(stderr, "FAIL: Orbis library did not create its visible content hierarchy\n");
			[window release];
			[controller release];
			return 1;
		}

		NSView *content = [window contentView];
		NSButton *refresh = FindButtonWithToolTip(content, @"Refresh connections");
		NSButton *add = FindButtonWithToolTip(content, @"New connection");
		NSButton *about = FindButtonWithToolTip(content, @"About Orbis");
		if (!refresh || !add || !about)
		{
			fprintf(stderr, "FAIL: Orbis library header actions are missing\n");
			[window release];
			[controller release];
			return 1;
		}
		NSRect refreshFrame = [refresh convertRect:[refresh bounds] toView:content];
		NSRect aboutFrame = [about convertRect:[about bounds] toView:content];
		if (NSMaxX(aboutFrame) < NSWidth([content bounds]) - 45.0 ||
		    NSMinX(refreshFrame) < NSWidth([content bounds]) * 0.75)
		{
			fprintf(stderr, "FAIL: Orbis library header actions are not right aligned\n");
			[window release];
			[controller release];
			return 1;
		}

		NSView *statusIcon = FindViewWithAccessibilityIdentifier(content, @"connection-status-icon");
		NSView *statusLabel = FindViewWithAccessibilityIdentifier(content, @"connection-status-label");
		if (statusIcon || statusLabel)
		{
			if (!statusIcon || !statusLabel || [statusIcon superview] != [statusLabel superview])
			{
				fprintf(stderr, "FAIL: Orbis ready state is not a unified status badge\n");
				[window release];
				[controller release];
				return 1;
			}
			NSRect iconFrame = [statusIcon convertRect:[statusIcon bounds] toView:[statusIcon superview]];
			NSRect labelFrame = [statusLabel convertRect:[statusLabel bounds] toView:[statusLabel superview]];
			if (fabs(NSMidY(iconFrame) - NSMidY(labelFrame)) > 1.0)
			{
				fprintf(stderr, "FAIL: Orbis ready state content is not vertically centered\n");
				[window release];
				[controller release];
				return 1;
			}
		}

		[window release];
		[controller release];

		OrbisProfile *profile = [[OrbisProfile alloc] init];
		OrbisProfileEditorController *editor = [[OrbisProfileEditorController alloc]
		    initWithProfile:profile
		  hasStoredPassword:NO];
		NSView *editorContent = [[editor window] contentView];
		[editorContent layoutSubtreeIfNeeded];
		NSTextField *nameField = (NSTextField *)FindViewWithAccessibilityIdentifier(
		    editorContent, @"profile-name-field");
		if (!nameField || [nameField bezelStyle] != NSTextFieldRoundedBezel)
		{
			fprintf(stderr, "FAIL: Orbis profile editor does not use rounded native inputs\n");
			[editor release];
			[profile release];
			return 1;
		}
		NSRect nameFrame = [nameField convertRect:[nameField bounds] toView:editorContent];
		if (NSMinX(nameFrame) < 32.0 || NSMaxX(nameFrame) > NSWidth([editorContent bounds]) - 32.0)
		{
			fprintf(stderr, "FAIL: Orbis profile editor fields do not preserve horizontal padding\n");
			[editor release];
			[profile release];
			return 1;
		}
		[editor release];
		[profile release];
	}
	printf("PASS: Orbis macOS library layout\n");
	return 0;
}
