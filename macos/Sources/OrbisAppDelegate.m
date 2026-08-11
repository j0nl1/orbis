/* SPDX-License-Identifier: MIT */

#import "OrbisAppDelegate.h"

#import "OrbisCredentialStore.h"
#import "OrbisProfile.h"

@interface OrbisAppDelegate ()
- (void)disconnectSession:(id)sender;
- (void)showLibraryWindow;
@end

static void OrbisConfigureWarningAlert(NSAlert *alert)
{
	[alert setAlertStyle:NSAlertStyleWarning];
	NSImage *warning = [NSImage imageNamed:NSImageNameCaution];
	if (warning)
		[alert setIcon:warning];
}

@implementation OrbisAppDelegate

- (void)showLibraryWindow
{
	if (!_window)
		return;
	[NSApp unhide:nil];
	[_window deminiaturize:nil];
	[_window makeKeyAndOrderFront:nil];
	[_window orderFrontRegardless];
	[NSApp activateIgnoringOtherApps:YES];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	(void)notification;
	[self buildMainMenu];

	_libraryViewController = [[OrbisLibraryViewController alloc] init];
	[_libraryViewController setDelegate:self];

	NSRect frame = NSMakeRect(0.0, 0.0, 980.0, 680.0);
	_window = [[NSWindow alloc]
	    initWithContentRect:frame
	              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
	                        NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable |
	                        NSWindowStyleMaskFullSizeContentView
	                backing:NSBackingStoreBuffered
	                  defer:NO];
	[_window setTitle:@"Orbis"];
	[_window setTitleVisibility:NSWindowTitleHidden];
	[_window setTitlebarAppearsTransparent:YES];
	[_window setMovableByWindowBackground:YES];
	[_window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace |
	                               NSWindowCollectionBehaviorFullScreenPrimary];
	[_window setMinSize:NSMakeSize(760.0, 520.0)];
	[_window setContentViewController:_libraryViewController];
	[_window center];
	[self showLibraryWindow];

	OrbisProfile *automatic = [[_libraryViewController profileStore] automaticProfile];
	if (automatic)
		[self libraryViewController:_libraryViewController connectToProfile:automatic];
}

- (void)buildMainMenu
{
	NSMenu *mainMenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];

	NSMenuItem *applicationItem = [[[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""] autorelease];
	NSMenu *applicationMenu = [[[NSMenu alloc] initWithTitle:@"Orbis"] autorelease];
	[applicationMenu addItemWithTitle:@"About Orbis" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
	[applicationMenu addItem:[NSMenuItem separatorItem]];
	[applicationMenu addItemWithTitle:@"Hide Orbis" action:@selector(hide:) keyEquivalent:@"h"];
	[applicationMenu addItemWithTitle:@"Quit Orbis" action:@selector(terminate:) keyEquivalent:@"q"];
	[applicationItem setSubmenu:applicationMenu];
	[mainMenu addItem:applicationItem];

	NSMenuItem *fileItem = [[[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""] autorelease];
	NSMenu *fileMenu = [[[NSMenu alloc] initWithTitle:@"File"] autorelease];
	NSMenuItem *newConnection = [fileMenu addItemWithTitle:@"New Connection…"
	                                              action:@selector(addConnection:)
	                                       keyEquivalent:@"n"];
	[newConnection setTarget:nil];
	[fileMenu addItemWithTitle:@"Connect" action:@selector(connectSelectedProfile:) keyEquivalent:@"\r"];
	[fileItem setSubmenu:fileMenu];
	[mainMenu addItem:fileItem];

	NSMenuItem *viewItem = [[[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""] autorelease];
	NSMenu *viewMenu = [[[NSMenu alloc] initWithTitle:@"View"] autorelease];
	[viewMenu addItemWithTitle:@"Enter Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
	[viewItem setSubmenu:viewMenu];
	[mainMenu addItem:viewItem];

	NSMenuItem *sessionItem =
	    [[[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""] autorelease];
	NSMenu *sessionMenu = [[[NSMenu alloc] initWithTitle:@"Session"] autorelease];
	NSMenuItem *disconnectItem =
	    [sessionMenu addItemWithTitle:@"Disconnect"
	                           action:@selector(disconnectSession:)
	                    keyEquivalent:@"d"];
	[disconnectItem setTarget:self];
	[disconnectItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand |
	                                               NSEventModifierFlagShift];
	[sessionItem setSubmenu:sessionMenu];
	[mainMenu addItem:sessionItem];

	NSMenuItem *windowItem = [[[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""] autorelease];
	NSMenu *windowMenu = [[[NSMenu alloc] initWithTitle:@"Window"] autorelease];
	[windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
	[windowItem setSubmenu:windowMenu];
	[mainMenu addItem:windowItem];
	[NSApp setWindowsMenu:windowMenu];

	[NSApp setMainMenu:mainMenu];
}

- (void)disconnectSession:(id)sender
{
	(void)sender;
	[_sessionController stop];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	if ([menuItem action] == @selector(disconnectSession:))
		return _sessionController != nil;
	return YES;
}

- (void)libraryViewController:(OrbisLibraryViewController *)controller
             connectToProfile:(OrbisProfile *)profile
{
	(void)controller;
	if (_sessionController)
		return;

	NSError *error = nil;
	NSString *password = [OrbisCredentialStore passwordForProfile:profile error:&error];
	if (error)
	{
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		OrbisConfigureWarningAlert(alert);
		[alert setMessageText:@"Password unavailable"];
		[alert setInformativeText:[error localizedDescription]];
		[alert runModal];
		return;
	}

	_sessionController = [[OrbisSessionController alloc] initWithProfile:profile password:password];
	[_sessionController setDelegate:self];
	if (![_sessionController start])
	{
		[_sessionController release];
		_sessionController = nil;
		return;
	}
	[_window orderOut:nil];
}

- (void)sessionControllerDidFinish:(OrbisSessionController *)controller error:(NSError *)error
{
	if (controller != _sessionController)
		return;
	[_sessionController setDelegate:nil];
	[_sessionController autorelease];
	_sessionController = nil;
	[_libraryViewController reloadProfiles];
	[self showLibraryWindow];

	if (error)
	{
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		OrbisConfigureWarningAlert(alert);
		[alert setMessageText:@"Couldn’t connect"];
		[alert setInformativeText:[error localizedDescription]];
		[alert beginSheetModalForWindow:_window completionHandler:nil];
	}
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
	(void)sender;
	(void)flag;
	if (!_sessionController)
		[self showLibraryWindow];
	return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
	(void)sender;
	return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	(void)notification;
	[_sessionController stop];
}

- (void)dealloc
{
	[_sessionController setDelegate:nil];
	[_sessionController release];
	[_libraryViewController release];
	[_window release];
	[super dealloc];
}

@end
