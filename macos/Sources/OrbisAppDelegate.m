/* SPDX-License-Identifier: MIT */

#import "OrbisAppDelegate.h"
#import "OrbisTransportFactory.h"
#import "OrbisDiagnostics.h"

#import "OrbisCredentialStore.h"
#import "OrbisProfile.h"

@interface OrbisAppDelegate ()
- (void)disconnectSession:(id)sender;
- (void)addVirtualDisplay:(id)sender;
- (void)changeDisplayResolution:(NSMenuItem *)sender;
- (void)matchScreenResolution:(id)sender;
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
	[[OrbisDiagnostics sharedDiagnostics] start];
#if ORBIS_ENABLE_UPDATES
	_updaterController = [[SPUStandardUpdaterController alloc]
	    initWithStartingUpdater:NO updaterDelegate:self userDriverDelegate:nil];
#endif
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
#if ORBIS_ENABLE_UPDATES
	[_updaterController startUpdater];
#endif
}

- (void)exportDiagnostics:(id)sender
{
	(void)sender;
	NSSavePanel *panel = [NSSavePanel savePanel];
	panel.nameFieldStringValue = @"orbis-diagnostics.json";
	[panel beginWithCompletionHandler:^(NSModalResponse response) {
		if (response != NSModalResponseOK) return;
		NSURL *destination = panel.URL;
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
			@autoreleasepool
			{
				NSError *error = nil;
				NSURL *temporary = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"OrbisExports"]];
				NSURL *export = [[OrbisDiagnostics sharedDiagnostics] exportToDirectory:temporary error:&error];
				NSData *data = export ? [NSData dataWithContentsOfURL:export options:0 error:&error] : nil;
				BOOL saved = data && [data writeToURL:destination options:NSDataWritingAtomic error:&error];
				if (export) [[NSFileManager defaultManager] removeItemAtURL:export error:nil];
				if (!saved)
				{
					[[OrbisDiagnostics sharedDiagnostics] recordError:error event:@"diagnostics.export_failed"];
					dispatch_async(dispatch_get_main_queue(), ^{
						NSAlert *alert = [[[NSAlert alloc] init] autorelease];
						alert.messageText = @"Could not export diagnostics";
						alert.informativeText = error.localizedDescription ?: @"Choose another destination and try again.";
						[alert runModal];
					});
				}
			}
		});
	}];
}

- (void)buildMainMenu
{
	NSMenu *mainMenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];

	NSMenuItem *applicationItem = [[[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""] autorelease];
	NSMenu *applicationMenu = [[[NSMenu alloc] initWithTitle:@"Orbis"] autorelease];
	NSMenuItem *aboutItem = [applicationMenu addItemWithTitle:@"About Orbis"
	                                               action:@selector(showAbout:)
	                                        keyEquivalent:@""];
	[aboutItem setTarget:self];
	NSMenuItem *exportItem = [applicationMenu addItemWithTitle:@"Export Diagnostics…"
	    action:@selector(exportDiagnostics:) keyEquivalent:@""];
	[exportItem setTarget:self];
#if ORBIS_ENABLE_UPDATES
	NSMenuItem *updatesItem = [applicationMenu addItemWithTitle:@"Check for Updates…"
	                                                  action:@selector(checkForUpdates:)
	                                           keyEquivalent:@""];
	[updatesItem setTarget:_updaterController];
#endif
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

	NSMenuItem *editItem = [[[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""] autorelease];
	NSMenu *editMenu = [[[NSMenu alloc] initWithTitle:@"Edit"] autorelease];
	[editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
	NSMenuItem *redo = [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"z"];
	[redo setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagShift];
	[editMenu addItem:[NSMenuItem separatorItem]];
	[editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
	[editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
	[editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
	[editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
	[editItem setSubmenu:editMenu];
	[mainMenu addItem:editItem];

	NSMenuItem *viewItem = [[[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""] autorelease];
	NSMenu *viewMenu = [[[NSMenu alloc] initWithTitle:@"View"] autorelease];
	[viewMenu addItemWithTitle:@"Enter Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
	[viewItem setSubmenu:viewMenu];
	[mainMenu addItem:viewItem];

	NSMenuItem *sessionItem =
	    [[[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""] autorelease];
	NSMenu *sessionMenu = [[[NSMenu alloc] initWithTitle:@"Session"] autorelease];
	NSMenuItem *displayItem = [sessionMenu addItemWithTitle:@"Add Virtual Display"
	    action:@selector(addVirtualDisplay:) keyEquivalent:@""];
	[displayItem setTarget:self];
	[sessionMenu addItem:[NSMenuItem separatorItem]];
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
    [windowMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *resolutionItem = [windowMenu addItemWithTitle:@"Resolution" action:nil keyEquivalent:@""];
    NSMenu *resolutions = [[[NSMenu alloc] initWithTitle:@"Resolution"] autorelease];
    [resolutions setDelegate:self];
    NSMenuItem *current = [resolutions addItemWithTitle:@"No remote display selected" action:nil keyEquivalent:@""];
    [current setEnabled:NO];
    [resolutions addItem:[NSMenuItem separatorItem]];
    const NSUInteger sizes[][2] = { {1280, 720}, {1600, 900}, {1920, 1080}, {1920, 1200},
        {2560, 1440}, {2560, 1600}, {3840, 2160} };
    for (NSUInteger i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++)
    {
        NSSize size = NSMakeSize(sizes[i][0], sizes[i][1]);
        NSMenuItem *item = [resolutions addItemWithTitle:[NSString stringWithFormat:@"%lu × %lu",
            (unsigned long)sizes[i][0], (unsigned long)sizes[i][1]] action:@selector(changeDisplayResolution:)
            keyEquivalent:@""];
        [item setRepresentedObject:[NSValue valueWithSize:size]];
        [item setTarget:self];
    }
    [resolutions addItem:[NSMenuItem separatorItem]];
    NSMenuItem *automatic = [resolutions addItemWithTitle:@"Automatically Match Window"
        action:@selector(toggleAutomaticResolution:) keyEquivalent:@""];
    [automatic setTarget:self];
    NSMenuItem *match = [resolutions addItemWithTitle:@"Match Mac Screen" action:@selector(matchScreenResolution:)
        keyEquivalent:@""];
    [match setTarget:self];
    [resolutionItem setSubmenu:resolutions];
	[windowItem setSubmenu:windowMenu];
	[mainMenu addItem:windowItem];
	[NSApp setWindowsMenu:windowMenu];

	[NSApp setMainMenu:mainMenu];
}

- (void)addVirtualDisplay:(id)sender
{
	if ([_sessionController canAddVirtualDisplay]) [_sessionController addVirtualDisplay:sender];
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    NSInteger index = _sessionController ? [_sessionController activeRemoteDisplayIndex] : -1;
    NSSize resolution = [_sessionController activeDisplayResolution];
    NSString *title = index < 0 ? @"No remote display selected" :
        [NSString stringWithFormat:@"Display %ld: %.0f × %.0f", (long)index + 1, resolution.width, resolution.height];
    [[menu itemAtIndex:0] setTitle:title];
}

- (void)changeDisplayResolution:(NSMenuItem *)sender
{
    NSValue *value = [sender representedObject];
    if (value) [_sessionController setActiveDisplayResolution:[value sizeValue]];
}

- (void)matchScreenResolution:(id)sender
{
    (void)sender;
    [_sessionController setActiveDisplayResolution:[_sessionController activeScreenResolution]];
}

- (void)toggleAutomaticResolution:(id)sender
{
    (void)sender;
    [_sessionController setActiveDisplayMatchesWindow:![_sessionController activeDisplayMatchesWindow]];
}

- (void)disconnectSession:(id)sender
{
	(void)sender;
	[_sessionController stop];
}

- (void)showAbout:(id)sender
{
	if (_sessionController)
		return;
	[self showLibraryWindow];
	[_libraryViewController showAbout:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    if ([menuItem action] == @selector(toggleAutomaticResolution:))
    {
        [menuItem setState:[_sessionController activeDisplayMatchesWindow] ? NSControlStateValueOn : NSControlStateValueOff];
        return [_sessionController canChangeActiveDisplayResolution];
    }
    if ([menuItem action] == @selector(changeDisplayResolution:))
    {
        NSSize resolution = [[menuItem representedObject] sizeValue];
        BOOL active = _sessionController && [_sessionController activeRemoteDisplayIndex] >= 0;
        [menuItem setState:active && NSEqualSizes(resolution, [_sessionController activeDisplayResolution])
            ? NSControlStateValueOn : NSControlStateValueOff];
        return [_sessionController canSetActiveDisplayResolution:resolution];
    }
    if ([menuItem action] == @selector(matchScreenResolution:))
        return [_sessionController canSetActiveDisplayResolution:[_sessionController activeScreenResolution]];
	if ([menuItem action] == @selector(addVirtualDisplay:))
		return [_sessionController canAddVirtualDisplay];
	if ([menuItem action] == @selector(disconnectSession:))
		return _sessionController != nil;
	if ([menuItem action] == @selector(showAbout:))
		return _sessionController == nil && _window != nil;
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
		[[OrbisDiagnostics sharedDiagnostics] recordError:error event:@"credentials.read_failed"];
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		OrbisConfigureWarningAlert(alert);
		[alert setMessageText:@"Password unavailable"];
		[alert setInformativeText:[error localizedDescription]];
		[alert runModal];
		return;
	}

	id<OrbisConnectionTransport> transport = [OrbisTransportFactory transportForProfile:profile error:&error];
	if (!transport)
	{
		[[OrbisDiagnostics sharedDiagnostics] recordError:error event:@"transport.selection_failed"];
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		OrbisConfigureWarningAlert(alert);
		[alert setMessageText:@"Connection unavailable"];
		[alert setInformativeText:[error localizedDescription]];
		[alert runModal];
		return;
	}
	_sessionController = [[OrbisSessionController alloc] initWithProfile:profile password:password transport:transport];
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
#if ORBIS_ENABLE_UPDATES
	if (_pendingUpdateInstall)
	{
		void (^install)(void) = [_pendingUpdateInstall autorelease];
		_pendingUpdateInstall = nil;
		install();
		return;
	}
#endif
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
	[[OrbisDiagnostics sharedDiagnostics] recordEvent:@"app.terminating" values:nil];
	[_sessionController stop];
}

#if ORBIS_ENABLE_UPDATES
- (BOOL)updater:(SPUUpdater *)updater
    mayPerformUpdateCheck:(SPUUpdateCheck)updateCheck
                    error:(NSError **)error
{
	(void)updater;
	(void)updateCheck;
	if (!_sessionController)
		return YES;
	if (error)
		*error = [NSError errorWithDomain:@"com.dnexus.orbis.updates" code:1
		    userInfo:@{ NSLocalizedDescriptionKey : @"Disconnect the remote session before checking for updates." }];
	return NO;
}

- (BOOL)updater:(SPUUpdater *)updater
    shouldProceedWithUpdate:(SUAppcastItem *)item
                updateCheck:(SPUUpdateCheck)updateCheck
                      error:(NSError **)error
{
	(void)item;
	return [self updater:updater mayPerformUpdateCheck:updateCheck error:error];
}

- (BOOL)updater:(SPUUpdater *)updater
    shouldPostponeRelaunchForUpdate:(SUAppcastItem *)item
                untilInvokingBlock:(void (^)(void))installHandler
{
	(void)updater;
	(void)item;
	if (!_sessionController)
		return NO;
	[_pendingUpdateInstall release];
	_pendingUpdateInstall = [installHandler copy];
	return YES;
}
#endif

- (void)dealloc
{
#if ORBIS_ENABLE_UPDATES
	[_pendingUpdateInstall release];
	[_updaterController release];
#endif
	[_sessionController setDelegate:nil];
	[_sessionController release];
	[_libraryViewController release];
	[_window release];
	[super dealloc];
}

@end
