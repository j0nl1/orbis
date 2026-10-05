/* SPDX-License-Identifier: MIT */

#import "OrbisAppDelegate.h"
#import <objc/runtime.h>

/* Replace the RDP transport for this test; the real app delegate is linked. */
@implementation OrbisSessionController
@synthesize delegate = _delegate;
- (id)initWithProfile:(OrbisProfile *)profile password:(NSString *)password
             transport:(id<OrbisConnectionTransport>)transport
{
	(void)profile;
	(void)password;
	(void)transport;
	return [super init];
}
- (BOOL)start { return YES; }
- (void)stop {}
- (BOOL)canAddVirtualDisplay { return NO; }
- (void)addVirtualDisplay:(id)sender { (void)sender; }
@end

static void Require(BOOL condition, const char *message)
{
	if (!condition)
	{
		fprintf(stderr, "FAIL: %s\n", message);
		exit(1);
	}
}

int main(void)
{
	@autoreleasepool
	{
		OrbisAppDelegate *delegate = [[OrbisAppDelegate alloc] init];
		NSError *error = nil;
		SPUUpdater *updater = (SPUUpdater *)[[[NSObject alloc] init] autorelease];
		SUAppcastItem *item = (SUAppcastItem *)[[[NSObject alloc] init] autorelease];
		Require([delegate updater:updater mayPerformUpdateCheck:SPUUpdateCheckUpdatesInBackground error:&error],
		        "An idle app must allow background checks");
		__block NSUInteger installs = 0;
		void (^install)(void) = ^{ installs++; };
		Require(![delegate updater:updater shouldPostponeRelaunchForUpdate:item untilInvokingBlock:install],
		        "An idle app must allow immediate installation");

		/* Model a session starting while a previously allowed check is in flight. */
		OrbisSessionController *session = [[OrbisSessionController alloc] init];
		object_setIvar(delegate, class_getInstanceVariable([OrbisAppDelegate class], "_sessionController"), session);
		Require(![delegate updater:updater mayPerformUpdateCheck:SPUUpdateCheckUpdatesInBackground error:&error] && error,
		        "An active session must defer new checks with a useful error");
		error = nil;
		Require(![delegate updater:updater shouldProceedWithUpdate:item updateCheck:SPUUpdateCheckUpdates error:&error] && error,
		        "An in-flight check must not present an update after a session starts");
		Require([delegate updater:updater shouldPostponeRelaunchForUpdate:item untilInvokingBlock:install],
		        "Installation must wait when a session starts after download");
		Require(installs == 0, "Installation must not run during a session");
		[delegate sessionControllerDidFinish:nil error:nil];
		Require(installs == 0, "An unrelated completion must not trigger installation");
		[delegate sessionControllerDidFinish:session error:nil];
		Require(installs == 1, "Finishing the active session must resume installation once");
		Require([delegate updater:updater mayPerformUpdateCheck:SPUUpdateCheckUpdates error:NULL],
		        "Checks must become available after session completion");
		[delegate release];
		Require(installs == 1, "Releasing the delegate must not repeat installation");
	}
	puts("PASS: updater session lifecycle");
	return 0;
}
