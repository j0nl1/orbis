/* SPDX-License-Identifier: MIT */

#import <AppKit/AppKit.h>

#import "OrbisLibraryViewController.h"
#import "OrbisSessionController.h"

#if ORBIS_ENABLE_UPDATES
#import <Sparkle/Sparkle.h>
#endif

@interface OrbisAppDelegate : NSObject <NSApplicationDelegate, OrbisLibraryViewControllerDelegate,
                                         OrbisSessionControllerDelegate, NSMenuDelegate
#if ORBIS_ENABLE_UPDATES
                                         , SPUUpdaterDelegate
#endif
                                         >
{
	NSWindow *_window;
	OrbisLibraryViewController *_libraryViewController;
	OrbisSessionController *_sessionController;
#if ORBIS_ENABLE_UPDATES
	SPUStandardUpdaterController *_updaterController;
	void (^_pendingUpdateInstall)(void);
#endif
}

@end
