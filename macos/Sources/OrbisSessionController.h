/* SPDX-License-Identifier: MIT */

#import <AppKit/AppKit.h>
#import "OrbisDisplayLayout.h"
#import "OrbisInputCapture.h"
#import "OrbisSessionCapabilities.h"

@class OrbisProfile;
@class OrbisDisplaySettings;
@class OrbisSessionController;
@protocol OrbisConnectionTransport;
@protocol OrbisTransportSession;
@class OrbisTransportDestination;
typedef struct OrbisRDPTransportRoute OrbisRDPTransportRoute;

@protocol OrbisSessionControllerDelegate <NSObject>

- (void)sessionControllerDidFinish:(OrbisSessionController *)controller error:(NSError *)error;

@end

@interface OrbisSessionController : NSObject <NSWindowDelegate, OrbisInputCaptureDelegate>
{
	OrbisSessionCapabilities *_capabilities;
	uint64_t _capabilityGeneration;
	id<OrbisSessionControllerDelegate> _delegate;
	OrbisProfile *_profile;
	OrbisDisplaySettings *_displaySettings;
	NSString *_password;
	NSWindow *_window, *_secondaryWindow, *_closingSecondaryWindow;
	BOOL _displayMatchesWindow[2];
	NSUInteger _windowResolutionDirty;
	BOOL _pendingResolutionIsAutomatic;
	id _secondaryView;
	NSLock *_displayLock;
	void *_displayChannel;
	uint32_t _displayMaxMonitors;
	uint64_t _displayMaxArea;
	OrbisDisplayLayout _displayLayout, _pendingDisplayLayout;
	BOOL _displayChangePending;
	NSInteger _pendingResolutionDisplayIndex;
	NSTimer *_displayChangeTimer;
	id _remoteView;
	NSView *_connectingOverlay;
	NSTextField *_connectingStatusLabel;
	id _modifierEventMonitor;
	NSTimer *_modifierPollTimer;
	OrbisInputCapture *_inputCapture;
	void *_context;
	BOOL _stopping;
	BOOL _stopCompletionDelivered;
	BOOL _connectionPending;
	BOOL _microphonePermissionPending;
	BOOL _microphonePermissionRequested;
	BOOL _microphoneEnabled;
	BOOL _wasConnected;
	BOOL _retryPending;
	unsigned int _transientConnectRetryCount;
	NSError *_finishError;
	id<OrbisConnectionTransport> _transport;
	id<OrbisTransportSession> _transportSession;
	OrbisTransportDestination *_transportDestination;
	OrbisRDPTransportRoute *_transportRoute;
	BOOL _transportPreparing;
	BOOL _transportPrepared;
	uint64_t _transportDiagnosticID;
	NSUInteger _stopSource;
}

@property(nonatomic, assign) id<OrbisSessionControllerDelegate> delegate;
@property(nonatomic, readonly) OrbisSessionCapabilitiesSnapshot *capabilities;

- (id)initWithProfile:(OrbisProfile *)profile password:(NSString *)password
             transport:(id<OrbisConnectionTransport>)transport;
- (BOOL)start;
- (void)stop;
- (BOOL)canAddVirtualDisplay;
- (void)addVirtualDisplay:(id)sender;
- (NSInteger)activeRemoteDisplayIndex;
- (NSSize)activeDisplayResolution;
- (NSSize)activeScreenResolution;
- (BOOL)canChangeActiveDisplayResolution;
- (BOOL)canSetActiveDisplayResolution:(NSSize)resolution;
- (void)setActiveDisplayResolution:(NSSize)resolution;
- (BOOL)activeDisplayMatchesWindow;
- (void)setActiveDisplayMatchesWindow:(BOOL)enabled;

@end
