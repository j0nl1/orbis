/* SPDX-License-Identifier: MIT */

#import <AppKit/AppKit.h>

@class OrbisProfile;
@class OrbisSessionController;
@protocol OrbisConnectionTransport;
@protocol OrbisTransportSession;
@class OrbisTransportDestination;
typedef struct OrbisRDPTransportRoute OrbisRDPTransportRoute;

@protocol OrbisSessionControllerDelegate <NSObject>

- (void)sessionControllerDidFinish:(OrbisSessionController *)controller error:(NSError *)error;

@end

@interface OrbisSessionController : NSObject <NSWindowDelegate>
{
	id<OrbisSessionControllerDelegate> _delegate;
	OrbisProfile *_profile;
	NSString *_password;
	NSWindow *_window;
	id _remoteView;
	NSView *_connectingOverlay;
	NSTextField *_connectingStatusLabel;
	id _modifierEventMonitor;
	NSTimer *_modifierPollTimer;
	void *_context;
	BOOL _stopping;
	BOOL _stopCompletionDelivered;
	BOOL _connectionPending;
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
}

@property(nonatomic, assign) id<OrbisSessionControllerDelegate> delegate;

- (id)initWithProfile:(OrbisProfile *)profile password:(NSString *)password
             transport:(id<OrbisConnectionTransport>)transport;
- (BOOL)start;
- (void)stop;

@end
