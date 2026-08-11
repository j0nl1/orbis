/* SPDX-License-Identifier: MIT */

#import "OrbisSessionController.h"

#import <freerdp/client.h>
#import <freerdp/client/cmdline.h>
#import <freerdp/event.h>
#import <freerdp/freerdp.h>

#import <CoreGraphics/CoreGraphics.h>

#import "MRDPView.h"
#import "mf_client.h"
#import "mfreerdp.h"
#import "OrbisConnectionRetryPolicy.h"
#import "OrbisProfile.h"

static NSString *const OrbisSessionErrorDomain = @"com.dnexus.orbis.session";

_Static_assert(FREERDP_ERROR_CONNECT_FAILED == ORBIS_FREERDP_CONNECT_FAILED,
               "Orbis retry policy must match FreeRDP's connection-failed code");

@interface OrbisSessionController ()
- (BOOL)beginConnection;
- (void)buildConnectingOverlay;
- (void)completeStop;
- (void)disposeConnectionContext;
- (void)hideConnectingOverlay;
- (void)pollModifierFlags:(NSTimer *)timer;
- (void)remoteViewDidPresentFirstFrame:(NSNotification *)notification;
- (void)retryCurrentConnection;
- (void)setConnectingStatus:(NSString *)status;
@end

@interface OrbisRemoteView : MRDPView
@property(nonatomic, assign) OrbisSessionController *sessionController;
@end

@implementation OrbisRemoteView
@synthesize sessionController;
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
	if (event->code == ERRINFO_NONE)
		return;
	OrbisSessionController *controller = OrbisControllerForContext(context);
	if (!controller)
		return;
	if (event->code == ERRINFO_LOGOFF_BY_USER)
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

@implementation OrbisSessionController

@synthesize delegate = _delegate;

- (id)initWithProfile:(OrbisProfile *)profile password:(NSString *)password
{
	if (!(self = [super init]))
		return nil;
	_profile = [profile copy];
	_password = [password copy];
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

	OrbisRemoteView *remoteView = [[OrbisRemoteView alloc] initWithFrame:[[_window contentView] bounds]];
	[remoteView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[remoteView setMapsCommandShortcutsToControl:YES];
	[remoteView setSessionController:self];
	[[_window contentView] addSubview:remoteView];
	_remoteView = remoteView;
	[self buildConnectingOverlay];
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
		if (!_stopping && [_window isKeyWindow] &&
		    ([_window firstResponder] == _remoteView) && [_remoteView is_connected])
		{
			[_remoteView flagsChanged:event];
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
	}];
}

- (void)pollModifierFlags:(NSTimer *)timer
{
	(void)timer;
	if (_stopping || ![_window isKeyWindow] || ([_window firstResponder] != _remoteView) ||
	    ![_remoteView is_connected])
	{
		[_remoteView cancelPendingCommandTap];
		return;
	}
	const CGEventFlags flags =
	    CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState);
	const BOOL commandIsDown = (flags & kCGEventFlagMaskCommand) != 0;
	[_remoteView setCommandKeyDown:commandIsDown];
}

- (BOOL)beginConnection
{
	if (_context || _stopping)
		return NO;
	_connectionPending = NO;
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
	NSMutableArray *arguments = [NSMutableArray arrayWithObjects:
	    @"orbis",
	    [NSString stringWithFormat:@"/v:%@:%lu", [_profile host], (unsigned long)[_profile port]],
	    [NSString stringWithFormat:@"/size:%lux%lu", (unsigned long)width, (unsigned long)height],
	    @"/bpp:32", @"/smart-sizing", @"/clipboard", @"/network:auto", @"/gfx", @"+fonts", nil];
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

	(void)freerdp_settings_set_string(context->settings, FreeRDP_WindowTitle,
	                                  [[_profile name] UTF8String]);
	PubSub_SubscribeConnectionResult(context->pubSub, OrbisConnectionResultHandler);
	PubSub_SubscribeErrorInfo(context->pubSub, OrbisErrorInfoHandler);
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

- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
	(void)notification;
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
	(void)notification;
	if (_stopping)
		[self completeStop];
}

- (void)handleConnectionResult:(NSNumber *)result
{
	if (_stopping)
		return;
	if ([result intValue] != 0)
	{
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
	freerdp_client_stop(context);
	((mfContext *)context)->view = nil;
	freerdp_client_context_free(context);
	_context = NULL;
}

- (void)retryCurrentConnection
{
	if (!_retryPending || _stopping)
		return;
	_retryPending = NO;
	[self disposeConnectionContext];
	if (!_stopping)
		[self beginConnection];
}

- (void)stop
{
	if (_stopping)
		return;
	_stopping = YES;
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
	if (_stopCompletionDelivered)
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
	(void)sender;
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
	[_remoteView release];
	[_window release];
	[_password release];
	[_profile release];
	[super dealloc];
}

@end
