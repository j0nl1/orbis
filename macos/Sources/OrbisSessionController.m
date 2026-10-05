/* SPDX-License-Identifier: MIT */

#import "OrbisSessionController.h"

#import <freerdp/client.h>
#import <freerdp/client/disp.h>
#import <freerdp/client/cmdline.h>
#import <freerdp/event.h>
#import <freerdp/freerdp.h>

#import <CoreGraphics/CoreGraphics.h>

#import "MRDPView.h"
#import "OrbisRemoteView.h"
#import "mf_client.h"
#import "mfreerdp.h"
#import "OrbisConnectionRetryPolicy.h"
#import "OrbisProfile.h"
#import "OrbisDisplaySettings.h"
#import "OrbisConnectionTransport.h"
#import "OrbisRDPTransportRoute.h"
#import "OrbisSessionEndPolicy.h"

static NSString *const OrbisSessionErrorDomain = @"com.dnexus.orbis.session";

_Static_assert(FREERDP_ERROR_CONNECT_FAILED == ORBIS_FREERDP_CONNECT_FAILED,
               "Orbis retry policy must match FreeRDP's connection-failed code");
_Static_assert(ERRINFO_NONE == ORBIS_ERRINFO_NONE,
               "Orbis session policy must match FreeRDP's no-error sentinel");
_Static_assert(ERRINFO_LOGOFF_BY_USER == ORBIS_ERRINFO_LOGOFF_BY_USER,
               "Orbis session policy must match FreeRDP's user-logoff code");

@interface OrbisSessionController ()
- (BOOL)beginConnection;
- (void)buildConnectingOverlay;
- (void)completeStop;
- (void)disposeConnectionContext;
- (void)closeTransportSession;
- (void)hideConnectingOverlay;
- (void)pollModifierFlags:(NSTimer *)timer;
- (void)remoteViewDidPresentFirstFrame:(NSNotification *)notification;
- (void)retryCurrentConnection;
- (NSPoint)remoteView:(MRDPView *)view remotePointForEvent:(NSEvent *)event;
- (void)updateDisplayControls;
- (void)desktopDidResize:(NSNotification *)notification;
- (void)displayChangeTimedOut:(NSTimer *)timer;
- (void)removeSecondaryWindow;
- (BOOL)sendDisplayLayout:(OrbisDisplayLayout)layout;
- (void)requestDisplayLayout:(OrbisDisplayLayout)layout;
- (void)displayChannelConnected:(DispClientContext *)channel;
- (void)displayChannelDisconnected:(DispClientContext *)channel;
- (void)displayControlCaps:(uint32_t)count area:(uint64_t)area;
- (void)setConnectingStatus:(NSString *)status;
- (BOOL)layoutForActiveResolution:(NSSize)resolution result:(OrbisDisplayLayout *)layout;
- (BOOL)canChangeDisplayResolution;
- (BOOL)layoutForResolution:(NSSize)resolution display:(NSInteger)index result:(OrbisDisplayLayout *)layout;
- (BOOL)canSetDisplayResolution:(NSSize)resolution display:(NSInteger)index;
- (void)applyWindowResolutions;
- (void)scheduleWindowResolutions;
- (void)displayCapabilitiesChanged;
@end

@implementation OrbisRemoteView
@synthesize sessionController;
- (NSPoint)remotePointForEvent:(NSEvent *)event
{
	return sessionController ? [sessionController remoteView:self remotePointForEvent:event]
	                         : [super remotePointForEvent:event];
}
@end

static OrbisSessionController *OrbisControllerForContext(void *value)
{
	rdpContext *context = (rdpContext *)value;
	if (!context)
		return nil;
	mfContext *macContext = (mfContext *)context;
	OrbisRemoteView *view = (OrbisRemoteView *)macContext->view;
	return [view sessionController];
}

static void OrbisConnectionResultHandler(void *context, const ConnectionResultEventArgs *event)
{
	OrbisSessionController *controller = OrbisControllerForContext(context);
	if (!controller)
		return;
	[controller performSelectorOnMainThread:@selector(handleConnectionResult:)
	                            withObject:[NSNumber numberWithInt:event->result]
	                         waitUntilDone:NO];
}

static void OrbisErrorInfoHandler(void *context, const ErrorInfoEventArgs *event)
{
	OrbisSessionEndDisposition disposition =
	    OrbisSessionEndDispositionForErrorInfo(event->code);
	if (disposition == OrbisSessionEndDispositionIgnore)
		return;
	OrbisSessionController *controller = OrbisControllerForContext(context);
	if (!controller)
		return;
	if (disposition == OrbisSessionEndDispositionEnded)
	{
		[controller performSelectorOnMainThread:@selector(handleSessionEnded)
		                            withObject:nil
		                         waitUntilDone:NO];
		return;
	}
	const char *message = freerdp_get_error_info_string(event->code);
	NSString *text = message ? [NSString stringWithUTF8String:message] : @"The remote session ended.";
	[controller performSelectorOnMainThread:@selector(handleSessionError:)
	                            withObject:text
	                         waitUntilDone:NO];
}

static UINT OrbisDisplayControlCaps(DispClientContext *channel, UINT32 count, UINT32 a, UINT32 b)
{
	OrbisSessionController *controller = (OrbisSessionController *)channel->custom;
	uint64_t area = (uint64_t)a * b;
	// Only layouts up to two 8192-square monitors are offered; saturate untrusted caps.
	uint64_t ceiling = 2ULL * 8192 * 8192;
	area = count && area > ceiling / count ? ceiling : area * count;
	[controller displayControlCaps:count area:area];
	return CHANNEL_RC_OK;
}

static void OrbisDisplayChannelConnected(void *context, const ChannelConnectedEventArgs *event)
{
	if (strcmp(event->name, DISP_DVC_CHANNEL_NAME) == 0)
		[OrbisControllerForContext(context) displayChannelConnected:(DispClientContext *)event->pInterface];
}

static void OrbisDisplayChannelDisconnected(void *context, const ChannelDisconnectedEventArgs *event)
{
	if (strcmp(event->name, DISP_DVC_CHANNEL_NAME) == 0)
		[OrbisControllerForContext(context) displayChannelDisconnected:(DispClientContext *)event->pInterface];
}

@implementation OrbisSessionController

@synthesize delegate = _delegate;

- (id)initWithProfile:(OrbisProfile *)profile password:(NSString *)password
             transport:(id<OrbisConnectionTransport>)transport
{
	if (!(self = [super init]))
		return nil;
	NSParameterAssert(transport != nil);
	_transport = [transport retain];
	_profile = [profile copy];
	_displaySettings = [[OrbisDisplaySettings loadMigratingProfile:profile] copy];
	_displayMatchesWindow[0] = ![_displaySettings primaryWidth] && ![_displaySettings primaryHeight];
	_displayMatchesWindow[1] = ![_displaySettings secondaryWidth] && ![_displaySettings secondaryHeight];
	_password = [password copy];
	_displayLock = [[NSLock alloc] init];
	_pendingResolutionDisplayIndex = -1;
	return self;
}

- (BOOL)start
{
	if (_context || _connectionPending || _stopping)
		return NO;

	NSScreen *screen = [NSScreen mainScreen] ?: [[NSScreen screens] firstObject];
	NSRect fullscreenFrame = [screen frame];
	_window = [[NSWindow alloc]
	    initWithContentRect:fullscreenFrame
	              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
	                        NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable |
	                        NSWindowStyleMaskFullSizeContentView
	                backing:NSBackingStoreBuffered
	                  defer:NO];
	[_window setTitle:[_profile name]];
	[_window setTitleVisibility:NSWindowTitleHidden];
	[_window setTitlebarAppearsTransparent:YES];
	[_window setBackgroundColor:[NSColor blackColor]];
	[_window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
	[_window setDelegate:self];
	[_window setReleasedWhenClosed:NO];

	OrbisRemoteView *remoteView = [[OrbisRemoteView alloc] initWithFrame:[[_window contentView] bounds]];
	[remoteView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[remoteView setMapsCommandShortcutsToControl:YES];
	[remoteView setSessionController:self];
	[[_window contentView] addSubview:remoteView];
	_remoteView = remoteView;
	[self buildConnectingOverlay];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(desktopDidResize:)
	    name:MRDPViewDidResizeDesktopNotification object:remoteView];
	[[NSNotificationCenter defaultCenter]
	    addObserver:self
	       selector:@selector(remoteViewDidPresentFirstFrame:)
	           name:MRDPViewDidPresentFirstFrameNotification
	         object:remoteView];
	[_window center];
	[_window makeKeyAndOrderFront:nil];
	[_window makeFirstResponder:remoteView];
	[NSApp activateIgnoringOtherApps:YES];
	_modifierEventMonitor =
	    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskFlagsChanged
	                                        handler:^NSEvent *(NSEvent *event) {
		MRDPView *focusedView = [self focusedRemoteView];
		if (!_stopping && focusedView && [focusedView is_connected])
		{
			[focusedView flagsChanged:event];
			return nil;
		}
		return event;
	}];
	_modifierPollTimer =
	    [[NSTimer scheduledTimerWithTimeInterval:0.01
	                                    target:self
	                                  selector:@selector(pollModifierFlags:)
	                                  userInfo:nil
	                                   repeats:YES] retain];

	// Native fullscreen is asynchronous. Start RDP only after AppKit reports the
	// final content bounds, otherwise the server keeps the temporary window's
	// smaller desktop size and merely stretches it after the transition.
	_connectionPending = YES;
	[_window toggleFullScreen:nil];
	// AppKit can omit windowDidEnterFullScreen when a new fullscreen window is
	// opened immediately after a failed session closes. Never leave the user in
	// a black window waiting on that callback forever; the window already uses
	// the screen frame, so its current content bounds remain a safe fallback.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
	               dispatch_get_main_queue(), ^{
		if (_connectionPending && !_stopping)
			[self beginConnection];
	});
	return YES;
}

- (void)buildConnectingOverlay
{
	NSView *contentView = [_window contentView];
	_connectingOverlay = [[NSView alloc] initWithFrame:[contentView bounds]];
	[_connectingOverlay setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[_connectingOverlay setWantsLayer:YES];
	NSColor *codexBlack = [NSColor colorWithSRGBRed:24.0 / 255.0
	                                        green:24.0 / 255.0
	                                         blue:24.0 / 255.0
	                                        alpha:1.0];
	[[_connectingOverlay layer] setBackgroundColor:[codexBlack CGColor]];
	[contentView addSubview:_connectingOverlay positioned:NSWindowAbove relativeTo:_remoteView];

	NSVisualEffectView *panel = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
	[panel setMaterial:NSVisualEffectMaterialHUDWindow];
	[panel setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
	[panel setState:NSVisualEffectStateActive];
	[panel setWantsLayer:YES];
	[[panel layer] setCornerRadius:24.0];
	[[panel layer] setMasksToBounds:YES];
	[panel setTranslatesAutoresizingMaskIntoConstraints:NO];
	[_connectingOverlay addSubview:panel];

	NSProgressIndicator *spinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
	[spinner setStyle:NSProgressIndicatorStyleSpinning];
	[spinner setControlSize:NSControlSizeLarge];
	[spinner setIndeterminate:YES];
	[spinner setDisplayedWhenStopped:YES];
	[spinner setTranslatesAutoresizingMaskIntoConstraints:NO];
	[spinner startAnimation:nil];
	[panel addSubview:spinner];

	_connectingStatusLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[_connectingStatusLabel setBezeled:NO];
	[_connectingStatusLabel setDrawsBackground:NO];
	[_connectingStatusLabel setEditable:NO];
	[_connectingStatusLabel setSelectable:NO];
	[_connectingStatusLabel setAlignment:NSTextAlignmentCenter];
	[_connectingStatusLabel setFont:[NSFont systemFontOfSize:19.0 weight:NSFontWeightSemibold]];
	[_connectingStatusLabel setTextColor:[NSColor labelColor]];
	[_connectingStatusLabel setStringValue:
	                           [NSString stringWithFormat:@"Connecting to %@…", [_profile name]]];
	[_connectingStatusLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
	[panel addSubview:_connectingStatusLabel];

	NSTextField *detailLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[detailLabel setBezeled:NO];
	[detailLabel setDrawsBackground:NO];
	[detailLabel setEditable:NO];
	[detailLabel setSelectable:NO];
	[detailLabel setAlignment:NSTextAlignmentCenter];
	[detailLabel setFont:[NSFont systemFontOfSize:13.0]];
	[detailLabel setTextColor:[NSColor secondaryLabelColor]];
	[detailLabel setStringValue:@"Preparing your remote desktop"];
	[detailLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
	[panel addSubview:detailLabel];

	[NSLayoutConstraint activateConstraints:@[
		[panel.centerXAnchor constraintEqualToAnchor:_connectingOverlay.centerXAnchor],
		[panel.centerYAnchor constraintEqualToAnchor:_connectingOverlay.centerYAnchor],
		[panel.widthAnchor constraintEqualToConstant:360.0],
		[panel.heightAnchor constraintEqualToConstant:190.0],
		[spinner.centerXAnchor constraintEqualToAnchor:panel.centerXAnchor],
		[spinner.topAnchor constraintEqualToAnchor:panel.topAnchor constant:32.0],
		[spinner.widthAnchor constraintEqualToConstant:32.0],
		[spinner.heightAnchor constraintEqualToConstant:32.0],
		[_connectingStatusLabel.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor
		                                                    constant:24.0],
		[_connectingStatusLabel.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor
		                                                     constant:-24.0],
		[_connectingStatusLabel.topAnchor constraintEqualToAnchor:spinner.bottomAnchor
		                                                constant:22.0],
		[detailLabel.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:24.0],
		[detailLabel.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-24.0],
		[detailLabel.topAnchor constraintEqualToAnchor:_connectingStatusLabel.bottomAnchor
		                                      constant:8.0],
	]];

	[detailLabel release];
	[spinner release];
	[panel release];
}

- (void)setConnectingStatus:(NSString *)status
{
	if (_connectingStatusLabel && [status length] > 0)
		[_connectingStatusLabel setStringValue:status];
}

- (void)remoteViewDidPresentFirstFrame:(NSNotification *)notification
{
	[self desktopDidResize:notification];
	if ([notification object] == _remoteView)
		[self hideConnectingOverlay];
}

- (void)hideConnectingOverlay
{
	if (!_connectingOverlay || [_connectingOverlay isHidden])
		return;
	[NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
		[context setDuration:0.28];
		[[_connectingOverlay animator] setAlphaValue:0.0];
	} completionHandler:^{
		[_connectingOverlay setHidden:YES];
		[_connectingOverlay removeFromSuperview];
		[_connectingStatusLabel release]; _connectingStatusLabel = nil;
		[_connectingOverlay release]; _connectingOverlay = nil;
	}];
}

- (MRDPView *)focusedRemoteView
{
	if ([_window isKeyWindow] && [_window firstResponder] == _remoteView) return _remoteView;
	if ([_secondaryWindow isKeyWindow] && [_secondaryWindow firstResponder] == _secondaryView) return _secondaryView;
	return nil;
}

- (void)pollModifierFlags:(NSTimer *)timer
{
	(void)timer;
	MRDPView *view = [self focusedRemoteView];
	if (_stopping || !view || ![view is_connected])
	{
		[_remoteView cancelPendingCommandTap]; [_secondaryView cancelPendingCommandTap];
		return;
	}
	BOOL commandIsDown = (CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState) & kCGEventFlagMaskCommand) != 0;
	[view setCommandKeyDown:commandIsDown];
}

- (BOOL)beginConnection
{
	if (_context || _stopping)
		return NO;
	_connectionPending = NO;
	if (!_transportPrepared)
	{
		if (_transportPreparing)
			return YES;
		_transportPreparing = YES;
		[self setConnectingStatus:[NSString stringWithFormat:@"Preparing %@…", [_transport displayName]]];
		_transportSession = [[_transport prepareWithCompletion:^(OrbisTransportDestination *destination, NSError *error) {
			_transportPreparing = NO;
			if (_stopping)
				return;
			if (error)
				[self finishWithMessage:[error localizedDescription] code:[error code]];
			else
			{
				_transportDestination = [destination retain];
				_transportPrepared = YES;
				[self beginConnection];
			}
		}] retain];
		return YES;
	}
	[_window makeFirstResponder:_remoteView];
	NSRect contentBounds = [[_window contentView] bounds];

	RDP_CLIENT_ENTRY_POINTS entryPoints = WINPR_C_ARRAY_INIT;
	entryPoints.Size = sizeof(RDP_CLIENT_ENTRY_POINTS);
	entryPoints.Version = RDP_CLIENT_INTERFACE_VERSION;
	RdpClientEntry(&entryPoints);
	rdpContext *context = freerdp_client_context_new(&entryPoints);
	if (!context)
	{
		[self finishWithMessage:@"FreeRDP could not create a client context." code:1];
		return NO;
	}
	_context = context;
	mfContext *macContext = (mfContext *)context;
	macContext->view = _remoteView;
	macContext->view_ownership = FALSE;

	NSUInteger width = (NSUInteger)MAX(800.0, contentBounds.size.width);
	NSUInteger height = (NSUInteger)MAX(600.0, contentBounds.size.height);
	// GNOME Remote Desktop 46 rejects odd RDP desktop widths. Rounding down one
	// point keeps the requested aspect and the smart-sized window unchanged.
	width -= width % 2;
	if ([_displaySettings primaryWidth] && [_displaySettings primaryHeight])
	{
		width = [_displaySettings primaryWidth]; height = [_displaySettings primaryHeight];
	}
	width = MIN(8192, MAX(200, width)); height = MIN(8192, MAX(200, height));
	OrbisDisplayLayoutMake((uint32_t)width, (uint32_t)height, 0, 0,
	    [_displaySettings arrangement], false, &_displayLayout);
	[_remoteView setDisplayRegion:NSMakeRect(0, 0, width, height)];
	NSMutableArray *arguments = [NSMutableArray arrayWithObjects:
	    @"orbis",
	    [NSString stringWithFormat:@"/v:%@:%lu", [_profile host], (unsigned long)[_profile port]],
	    [NSString stringWithFormat:@"/size:%lux%lu", (unsigned long)width, (unsigned long)height],
	    @"/bpp:32", @"/smart-sizing", @"/disp", @"/clipboard", @"/network:auto", @"/gfx", @"+fonts", nil];
	if ([[_profile username] length] > 0)
		[arguments addObject:[NSString stringWithFormat:@"/u:%@", [_profile username]]];
	if ([_password length] > 0)
		[arguments addObject:[NSString stringWithFormat:@"/p:%@", _password]];
	if ([_profile acceptAllCertificates])
		[arguments addObject:@"/cert:ignore"];

	int argc = (int)[arguments count];
	char **argv = calloc((size_t)argc, sizeof(char *));
	if (!argv)
	{
		[self finishWithMessage:@"Orbis could not allocate the connection arguments." code:2];
		return NO;
	}
	for (int index = 0; index < argc; index++)
		argv[index] = strdup([[arguments objectAtIndex:(NSUInteger)index] UTF8String]);

	int parseStatus =
	    freerdp_client_settings_parse_command_line(context->settings, argc, argv, FALSE);
	for (int index = 0; index < argc; index++)
	{
		if (argv[index] && _password && strstr(argv[index], "/p:") == argv[index])
			memset(argv[index], 0, strlen(argv[index]));
		free(argv[index]);
	}
	free(argv);
	if (parseStatus != 0)
	{
		[self finishWithMessage:@"The Remote Desktop profile could not be configured." code:3];
		return NO;
	}
	if (_transportDestination)
	{
		_transportRoute = OrbisRDPTransportRouteInstall(context,
		    [[_transportDestination hostname] UTF8String], [_transportDestination port]);
		if (!_transportRoute)
		{
			[self finishWithMessage:@"FreeRDP could not configure the connection transport." code:5];
			return NO;
		}
	}

	(void)freerdp_settings_set_string(context->settings, FreeRDP_WindowTitle,
	                                  [[_profile name] UTF8String]);
	PubSub_SubscribeConnectionResult(context->pubSub, OrbisConnectionResultHandler);
	PubSub_SubscribeErrorInfo(context->pubSub, OrbisErrorInfoHandler);
	PubSub_SubscribeChannelConnected(context->pubSub, OrbisDisplayChannelConnected);
	PubSub_SubscribeChannelDisconnected(context->pubSub, OrbisDisplayChannelDisconnected);
	[_remoteView addObserver:self
	            forKeyPath:@"is_connected"
	               options:NSKeyValueObservingOptionNew
	               context:NULL];

	int startStatus = freerdp_client_start(context);
	if (startStatus != 0)
	{
		[self finishWithMessage:@"FreeRDP could not start the Remote Desktop session." code:startStatus];
		return NO;
	}
	return YES;
}

- (void)displayChannelConnected:(DispClientContext *)channel
{
	[_displayLock lock];
	_displayChannel = channel; _displayMaxMonitors = 0;
	channel->custom = self; channel->DisplayControlCaps = OrbisDisplayControlCaps;
	[_displayLock unlock];
}

- (void)displayChannelDisconnected:(DispClientContext *)channel
{
	[_displayLock lock];
	if (_displayChannel == channel)
	{
		channel->custom = NULL; channel->DisplayControlCaps = NULL;
		_displayChannel = NULL; _displayMaxMonitors = 0; _displayMaxArea = 0;
	}
	[_displayLock unlock];
	[self performSelectorOnMainThread:@selector(updateDisplayControls) withObject:nil waitUntilDone:NO];
}

- (void)displayControlCaps:(uint32_t)count area:(uint64_t)area
{
	[_displayLock lock]; _displayMaxMonitors = count; _displayMaxArea = area; [_displayLock unlock];
	[self performSelectorOnMainThread:@selector(displayCapabilitiesChanged) withObject:nil waitUntilDone:NO];
}

- (void)displayCapabilitiesChanged
{
	_windowResolutionDirty |= 3;
	[self scheduleWindowResolutions];
	[self updateDisplayControls];
}

- (BOOL)canAddVirtualDisplay
{
	[_displayLock lock]; BOOL supported = _displayChannel && _displayMaxMonitors >= 2; [_displayLock unlock];
	return supported && _wasConnected && !_stopping && !_displayChangePending &&
	    !_secondaryWindow && !_closingSecondaryWindow;
}

- (NSInteger)activeRemoteDisplayIndex
{
    if (!_wasConnected || _stopping || !_displayLayout.count) return -1;
    NSWindow *window = [NSApp keyWindow] ?: [NSApp mainWindow];
    if (!window || [window attachedSheet]) return -1;
    if (window == _window) return 0;
    if (window == _secondaryWindow && _displayLayout.count == 2) return 1;
    return -1;
}

- (NSSize)activeDisplayResolution
{
    NSInteger index = [self activeRemoteDisplayIndex];
    if (index < 0 || (uint32_t)index >= _displayLayout.count) return NSZeroSize;
    OrbisDisplayRect rect = _displayLayout.monitors[index];
    return NSMakeSize(rect.width, rect.height);
}

- (NSSize)activeScreenResolution
{
    NSInteger index = [self activeRemoteDisplayIndex];
    if (index < 0) return NSZeroSize;
    NSWindow *window = index ? _secondaryWindow : _window;
    NSSize size = [[window screen] frame].size;
    if (!size.width || !size.height) return NSZeroSize;
    size.width = MIN(8192, MAX(200, floor(size.width)));
    size.height = MIN(8192, MAX(200, floor(size.height)));
    size.width -= (NSUInteger)size.width % 2;
    return size;
}

- (BOOL)canChangeActiveDisplayResolution
{
    return [self activeRemoteDisplayIndex] >= 0 && [self canChangeDisplayResolution];
}

- (BOOL)canChangeDisplayResolution
{
    if (!_wasConnected || _stopping || _displayChangePending || _closingSecondaryWindow ||
        !_displayLayout.count) return NO;
    [_displayLock lock];
    DispClientContext *channel = _displayChannel;
    BOOL supported = channel && channel->SendMonitorLayout && _displayMaxMonitors >= _displayLayout.count;
    [_displayLock unlock];
    return supported;
}

- (BOOL)layoutForActiveResolution:(NSSize)resolution result:(OrbisDisplayLayout *)layout
{
    return [self layoutForResolution:resolution display:[self activeRemoteDisplayIndex] result:layout];
}

- (BOOL)layoutForResolution:(NSSize)resolution display:(NSInteger)index result:(OrbisDisplayLayout *)layout
{
    if (index < 0 || (uint32_t)index >= _displayLayout.count ||
        !(resolution.width >= 200 && resolution.width <= 8192 && resolution.height >= 200 && resolution.height <= 8192) ||
        floor(resolution.width) != resolution.width || floor(resolution.height) != resolution.height ||
        !OrbisDisplayResolutionIsValid((uint32_t)resolution.width, (uint32_t)resolution.height)) return NO;
    OrbisDisplayRect primary = _displayLayout.monitors[0], second = _displayLayout.monitors[1];
    if (index) { second.width = (uint32_t)resolution.width; second.height = (uint32_t)resolution.height; }
    else { primary.width = (uint32_t)resolution.width; primary.height = (uint32_t)resolution.height; }
    int32_t offset = [_displaySettings arrangement] < OrbisMonitorAbove ? second.y : second.x;
    return OrbisDisplayLayoutMakeWithOffset(primary.width, primary.height, second.width, second.height,
        [_displaySettings arrangement], offset, _displayLayout.count == 2, layout);
}

- (BOOL)canSetActiveDisplayResolution:(NSSize)resolution
{
    if (![self canChangeActiveDisplayResolution]) return NO;
    return [self canSetDisplayResolution:resolution display:[self activeRemoteDisplayIndex]];
}

- (BOOL)canSetDisplayResolution:(NSSize)resolution display:(NSInteger)index
{
    if (![self canChangeDisplayResolution]) return NO;
    OrbisDisplayLayout layout;
    if (![self layoutForResolution:resolution display:index result:&layout]) return NO;
    uint64_t area = 0;
    for (uint32_t i = 0; i < layout.count; i++) area += (uint64_t)layout.monitors[i].width * layout.monitors[i].height;
    [_displayLock lock]; BOOL valid = _displayMaxArea && area <= _displayMaxArea; [_displayLock unlock];
    return valid;
}

- (void)setActiveDisplayResolution:(NSSize)resolution
{
    if (![self canSetActiveDisplayResolution:resolution]) return;
    NSInteger index = [self activeRemoteDisplayIndex];
    if (NSEqualSizes(resolution, [self activeDisplayResolution]))
    {
        _displayMatchesWindow[index] = NO;
        _windowResolutionDirty &= ~(1UL << index);
        [self updateDisplayControls];
        return;
    }
    OrbisDisplayLayout layout;
    if (![self layoutForActiveResolution:resolution result:&layout]) return;
    [self requestDisplayLayout:layout];
    if (_displayChangePending)
    { _pendingResolutionDisplayIndex = index; _pendingResolutionIsAutomatic = NO; }
}

- (BOOL)activeDisplayMatchesWindow
{
    NSInteger index = [self activeRemoteDisplayIndex];
    return index >= 0 && _displayMatchesWindow[index];
}

- (void)setActiveDisplayMatchesWindow:(BOOL)enabled
{
    if (![self canChangeActiveDisplayResolution]) return;
    NSInteger index = [self activeRemoteDisplayIndex];
    _displayMatchesWindow[index] = enabled;
    if (enabled) _windowResolutionDirty |= 1UL << index;
    else _windowResolutionDirty &= ~(1UL << index);
    [self scheduleWindowResolutions];
    [self updateDisplayControls];
}

- (void)scheduleWindowResolutions
{
    if (_stopping) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyWindowResolutions) object:nil];
    [self performSelector:@selector(applyWindowResolutions) withObject:nil afterDelay:0.35];
}

- (void)windowDidResize:(NSNotification *)notification
{
    NSWindow *window = [notification object];
    NSInteger index = window == _window ? 0 : window == _secondaryWindow ? 1 : -1;
    if (index < 0 || !_displayMatchesWindow[index] || _stopping) return;
    _windowResolutionDirty |= 1UL << index;
    [self scheduleWindowResolutions];
}

- (void)windowDidEndLiveResize:(NSNotification *)notification
{
    [self windowDidResize:notification];
}

- (void)applyWindowResolutions
{
    if (![self canChangeDisplayResolution]) return;
    for (NSInteger index = 0; index < 2; index++)
    {
        NSUInteger bit = 1UL << index;
        if (!(_windowResolutionDirty & bit)) continue;
        NSWindow *window = index ? _secondaryWindow : _window;
        if (!_displayMatchesWindow[index] || !window || (uint32_t)index >= _displayLayout.count)
        { _windowResolutionDirty &= ~bit; continue; }
        if ([window inLiveResize]) continue;
        NSSize size = [[window contentView] bounds].size;
        size.width = MIN(8192, MAX(200, floor(size.width)));
        size.height = MIN(8192, MAX(200, floor(size.height)));
        size.width -= (NSUInteger)size.width % 2;
        _windowResolutionDirty &= ~bit;
        OrbisDisplayRect current = _displayLayout.monitors[index];
        if (size.width == current.width && size.height == current.height) continue;
        if (![self canSetDisplayResolution:size display:index]) continue;
        OrbisDisplayLayout layout;
        if (![self layoutForResolution:size display:index result:&layout]) continue;
        [self requestDisplayLayout:layout];
        if (_displayChangePending)
        {
            _pendingResolutionDisplayIndex = index;
            _pendingResolutionIsAutomatic = YES;
            return;
        }
    }
}

- (void)updateDisplayControls
{
	[[NSApp mainMenu] update];
}

- (NSPoint)remoteView:(MRDPView *)source remotePointForEvent:(NSEvent *)event
{
	NSWindow *eventWindow = [event window] ?: [source window];
	if (!_stopping && _secondaryWindow && eventWindow && _displayLayout.count == 2)
	{
		// AppKit keeps delivering a drag and its release to the window that captured the press.
		// Resolve its screen position against both outputs, keeping that single button sequence.
		NSPoint screenPoint = [eventWindow convertPointToScreen:[event locationInWindow]];
		for (NSWindow *window in [NSApp orderedWindows])
		{
			MRDPView *target = window == _window ? _remoteView :
			    (window == _secondaryWindow ? _secondaryView : nil);
			if (!target || ![window isVisible] || [window isMiniaturized] || ![window isOnActiveSpace]) continue;
			NSPoint point = [window convertPointFromScreen:screenPoint];
			NSPoint local = [target convertPoint:point fromView:nil];
			if (NSPointInRect(local, [target bounds])) return [target remotePointForWindowPoint:point];
		}
	}
	return [source remotePointForWindowPoint:[event locationInWindow]];
}

- (BOOL)sendDisplayLayout:(OrbisDisplayLayout)layout
{
	DISPLAY_CONTROL_MONITOR_LAYOUT monitors[2] = {0};
	uint64_t area = 0;
	for (uint32_t i = 0; i < layout.count; i++)
	{
		OrbisDisplayRect rect = layout.monitors[i];
		monitors[i].Flags = i == 0 ? DISPLAY_CONTROL_MONITOR_PRIMARY : 0;
		monitors[i].Left = rect.x; monitors[i].Top = rect.y;
		monitors[i].Width = rect.width; monitors[i].Height = rect.height;
		monitors[i].DesktopScaleFactor = monitors[i].DeviceScaleFactor = 100;
		area += (uint64_t)rect.width * rect.height;
	}
	[_displayLock lock];
	DispClientContext *channel = _displayChannel;
	BOOL valid = channel && channel->SendMonitorLayout && _displayMaxMonitors >= layout.count &&
	    _displayMaxArea && area <= _displayMaxArea;
	UINT status = valid ? channel->SendMonitorLayout(channel, layout.count, monitors) : CHANNEL_RC_BAD_CHANNEL;
	[_displayLock unlock];
	return valid && status == CHANNEL_RC_OK;
}

- (void)showDisplayError:(NSString *)message
{
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:@"Display configuration could not be applied"];
	[alert setInformativeText:message];
	[alert beginSheetModalForWindow:_secondaryWindow ?: _window completionHandler:nil];
}

- (void)requestDisplayLayout:(OrbisDisplayLayout)layout
{
	if (_displayChangePending || _stopping) return;
	_pendingResolutionDisplayIndex = -1;
	if (![self sendDisplayLayout:layout])
	{
		[self showDisplayError:@"The server cannot accept this display layout or resolution. Your current desktop remains open."];
		return;
	}
	_pendingDisplayLayout = layout; _displayChangePending = YES;
	_displayChangeTimer = [[NSTimer scheduledTimerWithTimeInterval:10.0 target:self
	    selector:@selector(displayChangeTimedOut:) userInfo:nil repeats:NO] retain];
	[self updateDisplayControls];
}

- (void)addVirtualDisplay:(id)sender
{
	(void)sender;
	if (_secondaryWindow || _closingSecondaryWindow || !_wasConnected || _displayChangePending || _stopping) return;
	NSScreen *screen = [_window screen];
	for (NSScreen *candidate in [NSScreen screens]) if (candidate != screen) { screen = candidate; break; }
	NSSize size = [screen frame].size;
	uint32_t sw = [_displaySettings secondaryWidth] ?: (uint32_t)MIN(8192, MAX(800, size.width));
	uint32_t sh = [_displaySettings secondaryHeight] ?: (uint32_t)MIN(8192, MAX(600, size.height));
	sw -= sw % 2;
	OrbisDisplayLayout layout;
	if (OrbisDisplayLayoutMakeWithOffset(_displayLayout.monitors[0].width, _displayLayout.monitors[0].height,
	    sw, sh, [_displaySettings arrangement], [_displaySettings offset], true, &layout)) [self requestDisplayLayout:layout];
}

- (void)removeSecondaryWindow
{
	[_secondaryView detachFromDisplaySource];
	[_secondaryView setSessionController:nil];
	[_secondaryView release]; _secondaryView = nil;
	if (_secondaryWindow && ([_secondaryWindow styleMask] & NSWindowStyleMaskFullScreen))
	{
		_closingSecondaryWindow = _secondaryWindow; _secondaryWindow = nil;
		[_closingSecondaryWindow toggleFullScreen:nil];
	}
	else
	{
		[_secondaryWindow setDelegate:nil]; [_secondaryWindow orderOut:nil];
		[_secondaryWindow release]; _secondaryWindow = nil;
	}
}

- (void)desktopDidResize:(NSNotification *)notification
{
	(void)notification;
	if (_stopping) return;
	NSSize size = [_remoteView desktopPixelSize];
	if (!size.width || !size.height) return;
	if (_displayChangePending)
	{
		if (size.width != _pendingDisplayLayout.width || size.height != _pendingDisplayLayout.height) return;
		_displayLayout = _pendingDisplayLayout; _displayChangePending = NO;
        if (_pendingResolutionDisplayIndex >= 0)
        {
            if (!_pendingResolutionIsAutomatic) _displayMatchesWindow[_pendingResolutionDisplayIndex] = NO;
            OrbisDisplayRect changed = _displayLayout.monitors[_pendingResolutionDisplayIndex];
            if (_pendingResolutionDisplayIndex == 0)
            { _displaySettings.primaryWidth = changed.width; _displaySettings.primaryHeight = changed.height; }
            else
            { _displaySettings.secondaryWidth = changed.width; _displaySettings.secondaryHeight = changed.height; }
            if (_displayLayout.count == 2)
                _displaySettings.offset = _displaySettings.arrangement < OrbisMonitorAbove
                    ? _displayLayout.monitors[1].y : _displayLayout.monitors[1].x;
        }
        _pendingResolutionDisplayIndex = -1;
		[_displayChangeTimer invalidate]; [_displayChangeTimer release]; _displayChangeTimer = nil;
	}
	else if (_displayLayout.count == 1)
		OrbisDisplayLayoutMake((uint32_t)size.width, (uint32_t)size.height, 0, 0,
		    [_displaySettings arrangement], false, &_displayLayout);
	OrbisDisplayRect primary = _displayLayout.pixels[0];
	[_remoteView setDisplayRegion:NSMakeRect(primary.x, primary.y, primary.width, primary.height)];
	if (_displayLayout.count == 2)
	{
		if (!_secondaryWindow)
		{
			NSScreen *screen = [_window screen];
			for (NSScreen *candidate in [NSScreen screens]) if (candidate != screen) { screen = candidate; break; }
			NSRect frame = [screen visibleFrame]; frame.size.width *= 0.8; frame.size.height *= 0.8;
			_secondaryWindow = [[NSWindow alloc] initWithContentRect:frame
			    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable |
			        NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
			[_secondaryWindow setReleasedWhenClosed:NO]; [_secondaryWindow setDelegate:self];
			[_secondaryWindow setTitle:[NSString stringWithFormat:@"%@ — Display 2", [_profile name]]];
			[_secondaryWindow setBackgroundColor:[NSColor blackColor]];
			[_secondaryWindow setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
			_secondaryView = [[OrbisRemoteView alloc] initWithFrame:[[_secondaryWindow contentView] bounds]];
			[_secondaryView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
			[_secondaryView setMapsCommandShortcutsToControl:YES]; [_secondaryView setSessionController:self];
			[_secondaryView attachToDisplaySource:_remoteView];
			[[_secondaryWindow contentView] addSubview:_secondaryView];
			[_secondaryWindow makeKeyAndOrderFront:nil]; [_secondaryWindow makeFirstResponder:_secondaryView];
			_windowResolutionDirty |= 2;
		}
		OrbisDisplayRect second = _displayLayout.pixels[1];
		[_secondaryView setDisplayRegion:NSMakeRect(second.x, second.y, second.width, second.height)];
	}
	else [self removeSecondaryWindow];
	[self updateDisplayControls];
	if (_windowResolutionDirty) [self scheduleWindowResolutions];
}

- (void)displayChangeTimedOut:(NSTimer *)timer
{
	(void)timer;
	[_displayChangeTimer invalidate]; [_displayChangeTimer release]; _displayChangeTimer = nil;
	_displayChangePending = NO;
	_pendingResolutionDisplayIndex = -1;
	[self sendDisplayLayout:_displayLayout];
	[self updateDisplayControls];
	[self showDisplayError:@"The server did not confirm the new desktop size. The previous layout was requested again; you can retry or reconnect."];
	if (_windowResolutionDirty) [self scheduleWindowResolutions];
}

- (void)windowDidChangeScreen:(NSNotification *)notification
{
	[self windowDidResize:notification];
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
	[self windowDidResize:notification];
	if (_connectionPending && !_stopping)
		[self beginConnection];
}

- (void)windowDidFailToEnterFullScreen:(NSWindow *)window
{
	(void)window;
	if (_connectionPending && !_stopping)
		[self beginConnection];
}

- (void)windowDidExitFullScreen:(NSNotification *)notification
{
	[self windowDidResize:notification];
	NSWindow *window = [notification object];
	if (window == _closingSecondaryWindow)
	{
		[_closingSecondaryWindow setDelegate:nil]; [_closingSecondaryWindow orderOut:nil];
		[_closingSecondaryWindow release]; _closingSecondaryWindow = nil;
		[self updateDisplayControls];
		if (_stopping && !([_window styleMask] & NSWindowStyleMaskFullScreen)) [self completeStop];
		return;
	}
	if (window == _window && _stopping) [self completeStop];
}

- (void)handleConnectionResult:(NSNumber *)result
{
	if (_stopping)
		return;
	if ([result intValue] != 0)
	{
		NSError *transportError = [_transportSession connectionError];
		if (transportError)
		{
			[self finishWithMessage:[transportError localizedDescription] code:[transportError code]];
			return;
		}
		rdpContext *context = (rdpContext *)_context;
		DWORD lastError = context ? freerdp_get_last_error(context) : 0;
		OrbisRetryDecision retryDecision = OrbisConnectionRetryDecisionForError(
		    lastError, _transientConnectRetryCount);
		if (!_wasConnected && !_retryPending && retryDecision.shouldRetry)
		{
			_transientConnectRetryCount++;
			_retryPending = YES;
			[self setConnectingStatus:_transientConnectRetryCount == 1
			                              ? @"Finishing the remote sign-in…"
			                              : @"Still connecting…"];
			uint32_t delayMilliseconds = retryDecision.delayMilliseconds;
			dispatch_after(
			    dispatch_time(DISPATCH_TIME_NOW,
			                  (int64_t)delayMilliseconds * (int64_t)NSEC_PER_MSEC),
			    dispatch_get_main_queue(), ^{
				    [self retryCurrentConnection];
			    });
			return;
		}
		BOOL credentialError = lastError == FREERDP_ERROR_AUTHENTICATION_FAILED ||
		                       lastError == FREERDP_ERROR_CONNECT_LOGON_FAILURE ||
		                       lastError == FREERDP_ERROR_CONNECT_WRONG_PASSWORD ||
		                       lastError == FREERDP_ERROR_CONNECT_NO_OR_MISSING_CREDENTIALS;
		NSString *summary = credentialError
		                        ? @"Authentication failed. Check the username and password."
		                        : @"The Remote Desktop server rejected the connection.";
		const char *errorString = freerdp_get_last_error_string(lastError);
		NSString *detail = errorString ? [NSString stringWithUTF8String:errorString] : nil;
		NSString *message = [detail length] > 0
		                        ? [NSString stringWithFormat:@"%@\n\n%@ (0x%08X)", summary,
		                                                     detail, (unsigned int)lastError]
		                        : summary;
		[self finishWithMessage:message code:(NSInteger)lastError];
		return;
	}

	_wasConnected = YES;
	_windowResolutionDirty |= 3;
	[self scheduleWindowResolutions];
	[self updateDisplayControls];
	_retryPending = NO;
	[self setConnectingStatus:@"Opening your desktop…"];
	[_window setTitle:[NSString stringWithFormat:@"%@ — Connected", [_profile name]]];
	[_window makeFirstResponder:_remoteView];
}

- (void)handleSessionError:(NSString *)message
{
	if (!_stopping)
		[self finishWithMessage:message code:4];
}

- (void)handleSessionEnded
{
	if (!_stopping)
		[self stop];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context
{
	(void)object;
	(void)context;
	if (![keyPath isEqualToString:@"is_connected"] || _stopping)
		return;
	BOOL connected = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
	if (!connected && _wasConnected)
		dispatch_async(dispatch_get_main_queue(), ^{
			[self stop];
		});
}

- (void)finishWithMessage:(NSString *)message code:(NSInteger)code
{
	[_finishError release];
	_finishError = [[NSError alloc] initWithDomain:OrbisSessionErrorDomain
	                                        code:code
	                                    userInfo:@{ NSLocalizedDescriptionKey : message }];
	[self stop];
}

- (void)disposeConnectionContext
{
	rdpContext *context = (rdpContext *)_context;
	if (!context)
		return;

	@try
	{
		[_remoteView removeObserver:self forKeyPath:@"is_connected"];
	}
	@catch (NSException *exception)
	{
		(void)exception;
	}
	PubSub_UnsubscribeConnectionResult(context->pubSub, OrbisConnectionResultHandler);
	PubSub_UnsubscribeErrorInfo(context->pubSub, OrbisErrorInfoHandler);
	[self removeSecondaryWindow];
	freerdp_client_stop(context);
	PubSub_UnsubscribeChannelConnected(context->pubSub, OrbisDisplayChannelConnected);
	PubSub_UnsubscribeChannelDisconnected(context->pubSub, OrbisDisplayChannelDisconnected);
	[_displayLock lock];
	_displayChannel = NULL; _displayMaxMonitors = 0; _displayMaxArea = 0;
	[_displayLock unlock];
	OrbisRDPTransportRouteFree(_transportRoute);
	_transportRoute = NULL;
	((mfContext *)context)->view = nil;
	freerdp_client_context_free(context);
	_context = NULL;
}

- (void)closeTransportSession
{
	[_transportSession close];
	[_transportSession release];
	_transportSession = nil;
	[_transportDestination release];
	_transportDestination = nil;
	_transportPrepared = NO;
}

- (void)retryCurrentConnection
{
	if (!_retryPending || _stopping)
		return;
	_retryPending = NO;
	[self closeTransportSession];
	[self disposeConnectionContext];
	if (!_stopping)
		[self beginConnection];
}

- (void)stop
{
	if (_stopping)
		return;
	_stopping = YES;
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyWindowResolutions) object:nil];
	_windowResolutionDirty = 0;
	[_displayChangeTimer invalidate]; [_displayChangeTimer release]; _displayChangeTimer = nil;
	_displayChangePending = NO;
	_pendingResolutionDisplayIndex = -1;
	[self updateDisplayControls];
	_connectionPending = NO;
	[[NSNotificationCenter defaultCenter] removeObserver:self
	                                                name:MRDPViewDidPresentFirstFrameNotification
	                                              object:_remoteView];
	if (_modifierEventMonitor)
	{
		[NSEvent removeMonitor:_modifierEventMonitor];
		_modifierEventMonitor = nil;
	}
	if (_modifierPollTimer)
	{
		[_modifierPollTimer invalidate];
		[_modifierPollTimer release];
		_modifierPollTimer = nil;
	}
	_retryPending = NO;
	[self closeTransportSession];
	[self disposeConnectionContext];

	[(OrbisRemoteView *)_remoteView setSessionController:nil];
	if (([_window styleMask] & NSWindowStyleMaskFullScreen) != 0)
	{
		[_window toggleFullScreen:nil];
		return;
	}
	[self completeStop];
}

- (void)completeStop
{
	if (_stopCompletionDelivered || _closingSecondaryWindow)
		return;
	_stopCompletionDelivered = YES;
	[_window setDelegate:nil];
	[_window orderOut:nil];
	id<OrbisSessionControllerDelegate> delegate = _delegate;
	if (delegate)
		[delegate sessionControllerDidFinish:self error:_finishError];
}

- (BOOL)windowShouldClose:(NSWindow *)sender
{
	if (sender == _secondaryWindow)
	{
		if (_displayChangePending || _stopping) return NO;
		OrbisDisplayLayout layout;
		OrbisDisplayLayoutMake(_displayLayout.monitors[0].width, _displayLayout.monitors[0].height,
		    0, 0, [_displaySettings arrangement], false, &layout);
		[self requestDisplayLayout:layout];
		return NO;
	}
	[self stop];
	return NO;
}

- (void)dealloc
{
	_delegate = nil;
	if (!_stopping)
		[self stop];
	[_finishError release];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_connectingStatusLabel release];
	[_connectingOverlay release];
	[_displayLock release];
	[_remoteView release];
	[_window release];
	[_password release];
	[_profile release];
	[_displaySettings release];
	[_transport release];
	[super dealloc];
}

@end
