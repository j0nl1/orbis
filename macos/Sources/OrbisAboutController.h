/* SPDX-License-Identifier: MIT */

#import <AppKit/AppKit.h>

@interface OrbisAboutController : NSWindowController
{
	NSTabView *_tabs;
}

- (void)beginSheetForWindow:(NSWindow *)parentWindow;

@end
