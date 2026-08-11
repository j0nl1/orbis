/* SPDX-License-Identifier: MIT */

#import <AppKit/AppKit.h>

#import "OrbisLibraryViewController.h"
#import "OrbisSessionController.h"

@interface OrbisAppDelegate : NSObject <NSApplicationDelegate, OrbisLibraryViewControllerDelegate,
                                         OrbisSessionControllerDelegate>
{
	NSWindow *_window;
	OrbisLibraryViewController *_libraryViewController;
	OrbisSessionController *_sessionController;
}

@end
