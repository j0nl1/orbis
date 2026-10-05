/* SPDX-License-Identifier: MIT */

#import <XCTest/XCTest.h>
#import "OrbisProfile.h"
#import "OrbisController.h"
#import "OrbisProfileEditorController.h"
#import "OrbisAboutController.h"
#import "OrbisIPadDisplaySettings.h"
#import "OrbisIPadWorkspaceShortcuts.h"
#import "OrbisIPadDisplaySettingsController.h"
#import "RDPSessionViewController.h"
#import "OrbisConnectionTransport.h"
#import "OrbisConnectionHealthCheck.h"
#import "OrbisDirectTransport.h"
#import "RDPSession.h"
#import "RDPSessionView.h"
#import "RDPKeyboard.h"
#import "Bookmark.h"
#import "ConnectionParams.h"
#include <winpr/input.h>
#include <math.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <poll.h>
#include <unistd.h>

@interface OrbisController (OrbisTesting)
- (void)startConnectionWithPassword:(NSString *)password;
- (void)setConnectionBusy:(BOOL)busy status:(NSString *)status;
- (void)refreshProfileUI;
- (void)sessionDidEnd:(NSNotification *)notification;
- (void)prepareStatusForCardViews:(NSDictionary *)views selected:(BOOL)selected;
- (void)startHealthMonitoring;
- (void)applicationWillResignActive:(NSNotification *)notification;
- (void)applicationDidBecomeActive:(NSNotification *)notification;
@end

@interface OrbisIPadDisplaySettingsController (OrbisTesting)
- (void)savePressed:(id)sender;
- (void)cancelPressed:(id)sender;
@end
@interface RDPSessionViewController (OrbisDisplayTesting)
- (void)sendViewportResize;
- (IBAction)matchIPadResolution:(id)sender;
- (void)handleScroll:(UIPanGestureRecognizer *)gesture;
@end
@interface OrbisTestViewportController : RDPSessionViewController
@end
@implementation OrbisTestViewportController
- (CGSize)remoteSizeForCurrentViewport { return CGSizeMake(2732, 2048); }
- (void)fitSessionViewToViewport {}
@end

@interface OrbisTestHealthCheck : OrbisConnectionHealthCheck
@property(nonatomic, copy) void (^result)(BOOL available);
@property(nonatomic) BOOL cancelled;
@end
@implementation OrbisTestHealthCheck
- (void)startWithCompletion:(void (^)(BOOL))completion { self.result = completion; }
- (void)cancel { self.cancelled = YES; self.result = nil; }
- (void)dealloc { [_result release]; [super dealloc]; }
@end

@interface OrbisTestHealthLibrary : OrbisController
@property(nonatomic, retain) OrbisTestHealthCheck *lastHealthCheck;
@end
@implementation OrbisTestHealthLibrary
- (OrbisConnectionHealthCheck *)newHealthCheckForProfile:(OrbisProfile *)profile
{
	(void)profile;
	OrbisTestHealthCheck *check = [[OrbisTestHealthCheck alloc] init];
	self.lastHealthCheck = check;
	return check;
}
- (void)dealloc { [_lastHealthCheck release]; [super dealloc]; }
@end
@interface OrbisTestLibrary : OrbisController
@end
@implementation OrbisTestLibrary
- (BOOL)discardStoredCertificateForProfile:(OrbisProfile *)profile error:(NSError **)error
{
	(void)profile; (void)error;
	return YES;
}
@end
@interface OrbisTestProfileStore : NSObject
@property(nonatomic, retain) OrbisProfile *selectedProfile;
@property(nonatomic, retain) NSArray *profiles;
@end
@implementation OrbisTestProfileStore
- (void)dealloc { [_selectedProfile release]; [_profiles release]; [super dealloc]; }
@end

@interface RDPSessionView (OrbisTesting)
- (void)handlePresses:(NSSet *)presses up:(BOOL)up;
@end
@interface OrbisProfileEditorController (OrbisTesting)
- (void)savePressed:(id)sender;
@end

@interface OrbisInputRecorder : NSObject
@property(nonatomic, retain) NSMutableArray *events;
@property(nonatomic, retain) ConnectionParams *params;
@property(nonatomic, assign) id delegate;
- (void)sendInputEvent:(NSDictionary *)event;
- (CGContextRef)bitmapContext;
@end
@implementation OrbisInputRecorder
- (void)sendInputEvent:(NSDictionary *)event { [self.events addObject:event]; }
- (CGContextRef)bitmapContext { return nil; }
- (rdpSettings *)getSessionParams { return NULL; }
- (void)dealloc { [_events release]; [_params release]; [super dealloc]; }
@end

@interface OrbisTestScroll : UIPanGestureRecognizer
@property(nonatomic) CGPoint testTranslation;
@property(nonatomic) UIGestureRecognizerState testState;
@property(nonatomic) UIKeyModifierFlags testModifiers;
@end
@implementation OrbisTestScroll
- (CGPoint)translationInView:(UIView *)view { (void)view; return _testTranslation; }
- (void)setTranslation:(CGPoint)value inView:(UIView *)view { (void)view; _testTranslation = value; }
- (UIGestureRecognizerState)state { return _testState; }
- (UIKeyModifierFlags)modifierFlags { return _testModifiers; }
@end

@interface OrbisTestKey : NSObject
@property(nonatomic) UIKeyboardHIDUsage keyCode;
@property(nonatomic) UIKeyModifierFlags modifierFlags;
@property(nonatomic, copy) NSString *characters;
@property(nonatomic, copy) NSString *charactersIgnoringModifiers;
@end
@implementation OrbisTestKey
- (void)dealloc { [_characters release]; [_charactersIgnoringModifiers release]; [super dealloc]; }
@end
@interface OrbisTestPress : NSObject
@property(nonatomic, retain) OrbisTestKey *key;
@end
@implementation OrbisTestPress
- (void)dealloc { [_key release]; [super dealloc]; }
@end


@interface OrbisTestTransportSession : NSObject <OrbisTransportSession>
@property(nonatomic) BOOL closed;
@property(nonatomic, retain) NSError *connectionError;
@end
@implementation OrbisTestTransportSession
- (void)close { self.closed = YES; }
- (void)dealloc { [_connectionError release]; [super dealloc]; }
@end

@interface OrbisTestTransport : NSObject <OrbisConnectionTransport>
@property(nonatomic, retain) OrbisTestTransportSession *session;
@property(nonatomic, copy) OrbisTransportReady ready;
@property(nonatomic) NSUInteger preparations;
@property(nonatomic, retain) OrbisTransportDestination *destination;
- (void)completeWithError:(NSError *)error;
@end
@implementation OrbisTestTransport
- (NSString *)displayName { return @"Test transport"; }
- (id<OrbisTransportSession>)prepareWithCompletion:(OrbisTransportReady)completion
{
	self.preparations++;
	self.session = [[[OrbisTestTransportSession alloc] init] autorelease];
	self.ready = completion;
	return self.session;
}
- (void)completeWithError:(NSError *)error
{
	OrbisTransportReady ready = [[self.ready copy] autorelease];
	self.ready = nil;
	dispatch_async(dispatch_get_main_queue(), ^{ ready(self.destination, error); });
}
- (void)dealloc { [_session release]; [_ready release]; [_destination release]; [super dealloc]; }
@end

@interface OrbisTestRDPSession : RDPSession
@property(nonatomic) NSUInteger rdpStarts;
@property(nonatomic) NSUInteger resizeRequests;
@property(nonatomic) CGSize requestedSize;
@end
@implementation OrbisTestRDPSession
- (void)beginRDPConnection { self.rdpStarts++; }
- (void)requestDesktopSize:(CGSize)size { self.resizeRequests++; self.requestedSize = size; }
@end

@interface OrbisIPadTests : XCTestCase <OrbisProfileEditorDelegate>
@property(nonatomic, retain) OrbisProfile *savedProfile;
@property(nonatomic, retain) NSDictionary *savedToken;
@end
@implementation OrbisIPadTests
- (BOOL)profileEditor:(OrbisProfileEditorController *)editor didSaveProfile:(OrbisProfile *)profile
             password:(NSString *)password cloudflareToken:(NSDictionary *)token
{
	(void)editor; (void)password;
	self.savedProfile = profile;
	self.savedToken = token;
	return YES;
}
- (void)dealloc { [_savedProfile release]; [_savedToken release]; [super dealloc]; }

- (OrbisProfileEditorController *)editor
{
	OrbisProfileEditorController *editor = [[[OrbisProfileEditorController alloc] initWithProfile:nil] autorelease];
	editor.delegate = self;
	[editor loadViewIfNeeded];
	[[editor valueForKey:@"nameField"] setText:@"Test computer"];
	[[editor valueForKey:@"usernameField"] setText:@"tester"];
	return editor;
}

- (NSUserDefaults *)displayDefaults
{
	NSString *suite = [@"com.dnexus.orbis.tests.display." stringByAppendingString:[[NSUUID UUID] UUIDString]];
	NSUserDefaults *defaults = [[[NSUserDefaults alloc] initWithSuiteName:suite] autorelease];
	[self addTeardownBlock:^{ [defaults removePersistentDomainForName:suite]; }];
	return defaults;
}

- (void)testDisplayDefaultsKeepAutomaticResolution
{
	OrbisIPadDisplaySettings *settings = [[[OrbisIPadDisplaySettings alloc] initWithDefaults:[self displayDefaults]] autorelease];
	XCTAssertTrue(settings.automaticResolution);
}

- (void)testGlobalDisplaySettingsReachNewSessionsWithOneDesktop
{
	NSUserDefaults *defaults = [self displayDefaults];
	OrbisIPadDisplaySettings *settings = [[[OrbisIPadDisplaySettings alloc] initWithDefaults:defaults] autorelease];
	settings.width = 2560; settings.height = 1440;
	XCTAssertTrue([settings saveWithError:nil]);
	for (NSString *host in @[ @"first.local", @"second.local" ])
	{
		OrbisIPadDisplaySettings *loaded = [[[OrbisIPadDisplaySettings alloc] initWithDefaults:defaults] autorelease];
		ConnectionParams *params = [[[ConnectionParams alloc] initWithBaseDefaultParameters] autorelease];
		[params setValue:host forKey:@"hostname"];
		[loaded applyToConnectionParameters:params];
		ComputerBookmark *bookmark = [[[ComputerBookmark alloc] initWithConnectionParameters:params] autorelease];
		RDPSession *session = [[[RDPSession alloc] initWithBookmark:bookmark] autorelease];
		XCTAssertNotNil(session);
		rdpSettings *rdp = [session getSessionParams];
		XCTAssertEqual(freerdp_settings_get_uint32(rdp, FreeRDP_DesktopWidth), 2560u);
		XCTAssertEqual(freerdp_settings_get_uint32(rdp, FreeRDP_DesktopHeight), 1440u);
		XCTAssertEqual(freerdp_settings_get_uint32(rdp, FreeRDP_DesktopScaleFactor), 100u);
		XCTAssertEqual(freerdp_settings_get_uint32(rdp, FreeRDP_DeviceScaleFactor), 100u);
		XCTAssertFalse(freerdp_settings_get_bool(rdp, FreeRDP_UseMultimon));
		XCTAssertFalse([session.params boolForKey:@"match_window_resolution"]);
	}
}

- (void)testInvalidDisplayValuesDoNotOverwriteTheSavedConfiguration
{
	NSUserDefaults *defaults = [self displayDefaults];
	OrbisIPadDisplaySettings *settings = [[[OrbisIPadDisplaySettings alloc] initWithDefaults:defaults] autorelease];
	settings.width = 1920; settings.height = 1080;
	XCTAssertTrue([settings saveWithError:nil]);
	for (NSArray *size in @[ @[ @1919, @1080 ], @[ @0, @1080 ], @[ @1920, @199 ], @[ @8194, @1080 ], @[ @(NSUIntegerMax), @1080 ] ])
	{
		settings.width = [size[0] unsignedIntegerValue]; settings.height = [size[1] unsignedIntegerValue];
		NSError *error = nil;
		XCTAssertFalse([settings saveWithError:&error]);
		XCTAssertNotNil(error);
	}
	OrbisIPadDisplaySettings *loaded = [[[OrbisIPadDisplaySettings alloc] initWithDefaults:defaults] autorelease];
	XCTAssertEqual(loaded.width, 1920u); XCTAssertEqual(loaded.height, 1080u);
}

- (void)testCorruptSavedDisplayValuesFallBackToSafeDefaults
{
	NSUserDefaults *defaults = [self displayDefaults];
	for (id saved in @[ @"invalid", @{ @"width" : @(-1), @"height" : @1080, @"desktopScale" : @900 },
	    @{ @"width" : @1920.5, @"height" : @1080, @"desktopScale" : @"150" } ])
	{
		[defaults setObject:saved forKey:@"OrbisIPadDisplaySettings.v1"];
		OrbisIPadDisplaySettings *settings = [[[OrbisIPadDisplaySettings alloc] initWithDefaults:defaults] autorelease];
		XCTAssertTrue(settings.automaticResolution);
	}
}

- (void)testLegacyScaleIsIgnoredWithoutLosingTheSavedResolution
{
	NSUserDefaults *defaults = [self displayDefaults];
	[defaults setObject:@{ @"width" : @2048, @"height" : @1536, @"desktopScale" : @200 }
	    forKey:@"OrbisIPadDisplaySettings.v1"];
	OrbisIPadDisplaySettings *settings = [[[OrbisIPadDisplaySettings alloc] initWithDefaults:defaults] autorelease];
	XCTAssertEqual(settings.width, 2048u); XCTAssertEqual(settings.height, 1536u);
	ConnectionParams *params = [[[ConnectionParams alloc] initWithBaseDefaultParameters] autorelease];
	[settings applyToConnectionParameters:params];
	XCTAssertFalse([params hasValueForKey:@"desktop_scale_factor"]);
	XCTAssertTrue([settings saveWithError:nil]);
	XCTAssertNil([[defaults dictionaryForKey:@"OrbisIPadDisplaySettings.v1"] objectForKey:@"desktopScale"]);
}

- (void)testSuggestedResolutionsFollowDifferentIPadAndWindowProportions
{
	for (NSArray *pixels in @[ @[ @2732, @2048 ], @[ @2048, @2732 ], @[ @2420, @1668 ],
	    @[ @2360, @1640 ], @[ @1366, @2048 ] ])
	{
		NSUInteger width = [pixels[0] unsignedIntegerValue], height = [pixels[1] unsignedIntegerValue];
		NSArray *sizes = [OrbisIPadDisplaySettings resolutionsForPixelWidth:width height:height];
		XCTAssertEqual(sizes.count, 5u);
		XCTAssertEqualObjects(sizes.firstObject, pixels);
		XCTAssertEqual([[NSSet setWithArray:sizes] count], sizes.count);
		for (NSArray *size in sizes)
		{
			NSUInteger w = [size[0] unsignedIntegerValue], h = [size[1] unsignedIntegerValue];
			XCTAssertEqual(w % 2, 0u);
			XCTAssertGreaterThanOrEqual(w, 200u); XCTAssertGreaterThanOrEqual(h, 200u);
			XCTAssertLessThanOrEqual(w, width); XCTAssertLessThanOrEqual(h, height);
			// Each dimension can differ by at most one pixel after rounding.
			XCTAssertEqualWithAccuracy((double)w / h, (double)width / height,
			    2.0 / MIN(w, h));
		}
	}
}

- (void)testSuggestionsUseTheIPadWindowRatherThanTheSettingsSheet
{
	OrbisIPadDisplaySettingsController *editor = [[[OrbisIPadDisplaySettingsController alloc]
	    initWithDefaults:[self displayDefaults]] autorelease];
	[editor loadViewIfNeeded];
	UIWindow *window = [[[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)] autorelease];
	[window addSubview:editor.view];
	editor.view.frame = CGRectMake(0, 0, 620, 620);
	[editor viewDidLayoutSubviews];
	UIButton *button = [editor valueForKey:@"presetButton"];
	NSArray *sizes = [OrbisIPadDisplaySettings resolutionsForPixelWidth:(NSUInteger)round(1024 * window.screen.nativeScale)
	    height:(NSUInteger)round(768 * window.screen.nativeScale)];
	NSString *expected = [NSString stringWithFormat:@"%@ × %@", sizes[0][0], sizes[0][1]];
	XCTAssertEqualObjects([button.menu.children.firstObject title], expected);
	XCTAssertEqual([editor numberOfSectionsInTableView:editor.tableView], 3);
	[[editor valueForKey:@"automaticSwitch"] setOn:NO];
	[[editor valueForKey:@"widthField"] setText:@"1112"];
	[[editor valueForKey:@"heightField"] setText:@"834"];
	window.frame = CGRectMake(0, 0, 480, 768);
	[editor viewDidLayoutSubviews];
	sizes = [OrbisIPadDisplaySettings resolutionsForPixelWidth:(NSUInteger)round(480 * window.screen.nativeScale)
	    height:(NSUInteger)round(768 * window.screen.nativeScale)];
	expected = [NSString stringWithFormat:@"%@ × %@", sizes[0][0], sizes[0][1]];
	XCTAssertEqualObjects([button.menu.children.firstObject title], expected);
	XCTAssertEqualObjects([[editor valueForKey:@"widthField"] text], @"1112");
	XCTAssertEqualObjects([[editor valueForKey:@"heightField"] text], @"834");
	[editor.view removeFromSuperview];
}

- (void)testSuggestedResolutionsStayInsideRDPBounds
{
	XCTAssertEqual([OrbisIPadDisplaySettings resolutionsForPixelWidth:0 height:2048].count, 0u);
	XCTAssertEqual([OrbisIPadDisplaySettings resolutionsForPixelWidth:100 height:100].count, 0u);
	XCTAssertEqual([OrbisIPadDisplaySettings resolutionsForPixelWidth:200 height:200].count, 1u);
	NSArray *sizes = [OrbisIPadDisplaySettings resolutionsForPixelWidth:16384 height:12288];
	XCTAssertEqualObjects(sizes.firstObject, (@[ @8192, @6144 ]));
	for (NSArray *size in sizes)
	{
		XCTAssertLessThanOrEqual([size[0] unsignedIntegerValue], 8192u);
		XCTAssertLessThanOrEqual([size[1] unsignedIntegerValue], 8192u);
	}
}

- (void)testSettingsCancelDiscardsEditsAndSavePersistsManualDimensions
{
	NSUserDefaults *defaults = [self displayDefaults];
	OrbisIPadDisplaySettingsController *editor = [[[OrbisIPadDisplaySettingsController alloc] initWithDefaults:defaults] autorelease];
	[editor loadViewIfNeeded];
	[[editor valueForKey:@"automaticSwitch"] setOn:NO];
	[[editor valueForKey:@"widthField"] setText:@"2560"];
	[[editor valueForKey:@"heightField"] setText:@"1440"];
	[editor cancelPressed:nil];
	XCTAssertNil([defaults objectForKey:@"OrbisIPadDisplaySettings.v1"]);
	[editor savePressed:nil];
	OrbisIPadDisplaySettings *loaded = [[[OrbisIPadDisplaySettings alloc] initWithDefaults:defaults] autorelease];
	XCTAssertEqual(loaded.width, 2560u); XCTAssertEqual(loaded.height, 1440u);
}

- (void)testManualResolutionSurvivesViewportChangesUntilExplicitMatch
{
	OrbisTestTransport *transport = [[[OrbisTestTransport alloc] init] autorelease];
	OrbisTestRDPSession *session = [self sessionWithTransport:transport];
	[session.params setBool:NO forKey:@"match_window_resolution"];
	OrbisTestViewportController *controller = [[[OrbisTestViewportController alloc]
	    initWithNibName:nil bundle:nil session:session] autorelease];
	[controller setValue:@YES forKey:@"session_connected"];
	[controller sendViewportResize];
	XCTAssertEqual(session.resizeRequests, 0u);
	[controller matchIPadResolution:nil];
	[NSObject cancelPreviousPerformRequestsWithTarget:controller];
	[controller sendViewportResize];
	XCTAssertEqual(session.resizeRequests, 1u);
	XCTAssertTrue(CGSizeEqualToSize(session.requestedSize, CGSizeMake(2732, 2048)));
}

- (void)testDirectProfileKeepsItsDefaultTransport
{
	OrbisProfileEditorController *editor = [self editor];
	[[editor valueForKey:@"hostField"] setText:@"desktop.local"];
	[editor savePressed:nil];
	XCTAssertEqualObjects(self.savedProfile.host, @"desktop.local");
	XCTAssertEqualObjects(self.savedProfile.transportType, OrbisTransportTypeDirect);
	XCTAssertEqual(self.savedProfile.port, 3389u);
	XCTAssertNil(self.savedToken);
}

- (void)testTunnelURLAndCredentialsPreserveTheLogicalServer
{
	OrbisProfileEditorController *editor = [self editor];
	OrbisProfile *profile = [editor valueForKey:@"profile"];
	profile.host = @"internal.local";
	[[editor valueForKey:@"transportControl"] setSelectedSegmentIndex:1];
	[[editor valueForKey:@"gatewayHostnameField"] setText:@"https://rdp.example.com/"];
	[[editor valueForKey:@"clientIDField"] setText:@"test-client"];
	[[editor valueForKey:@"clientSecretField"] setText:@"test-secret"];
	[editor savePressed:nil];
	XCTAssertEqualObjects(self.savedProfile.host, @"internal.local");
	XCTAssertEqualObjects(self.savedProfile.transportHostname, @"rdp.example.com");
	XCTAssertEqualObjects(self.savedProfile.transportType, OrbisTransportTypeCloudflare);
	XCTAssertEqualObjects(self.savedToken[@"secret"], @"test-secret");
	XCTAssertFalse([[self.savedProfile dictionaryRepresentation].description containsString:@"test-secret"]);
}

- (void)testNewTunnelUsesItsHostnameAsInitialServerIdentity
{
	OrbisProfileEditorController *editor = [self editor];
	[[editor valueForKey:@"transportControl"] setSelectedSegmentIndex:1];
	[[editor valueForKey:@"gatewayHostnameField"] setText:@"rdp.example.com"];
	[[editor valueForKey:@"clientIDField"] setText:@"test-client"];
	[[editor valueForKey:@"clientSecretField"] setText:@"test-secret"];
	[editor savePressed:nil];
	XCTAssertEqualObjects(self.savedProfile.host, @"rdp.example.com");
}

- (void)testSavedTokenCanOnlyBePreservedForTheSameHostnameAndClientID
{
	OrbisProfileEditorController *editor = [self editor];
	[[editor valueForKey:@"transportControl"] setSelectedSegmentIndex:1];
	[[editor valueForKey:@"gatewayHostnameField"] setText:@"rdp.example.com"];
	[[editor valueForKey:@"clientIDField"] setText:@"test-client"];
	[editor setValue:@"rdp.example.com" forKey:@"savedTokenHost"];
	[editor setValue:@"test-client" forKey:@"savedTokenClientID"];
	[editor savePressed:nil];
	XCTAssertNotNil(self.savedProfile);
	XCTAssertNil(self.savedToken);
	self.savedProfile = nil;
	[[editor valueForKey:@"gatewayHostnameField"] setText:@"other.example.com"];
	[editor savePressed:nil];
	XCTAssertNil(self.savedProfile);
	[[editor valueForKey:@"gatewayHostnameField"] setText:@"rdp.example.com"];
	[[editor valueForKey:@"clientIDField"] setText:@"other-client"];
	[editor savePressed:nil];
	XCTAssertNil(self.savedProfile);
}

- (void)testInvalidPortAndTunnelURLsAreRejected
{
	OrbisProfileEditorController *editor = [self editor];
	[[editor valueForKey:@"hostField"] setText:@"desktop.local"];
	for (NSString *port in @[ @"3389abc", @"0", @"65536", @"" ])
	{
		[[editor valueForKey:@"portField"] setText:port];
		[editor savePressed:nil];
		XCTAssertNil(self.savedProfile);
	}
	[[editor valueForKey:@"transportControl"] setSelectedSegmentIndex:1];
	[[editor valueForKey:@"clientIDField"] setText:@"test-client"];
	[[editor valueForKey:@"clientSecretField"] setText:@"test-secret"];
	for (NSString *url in @[ @"http://rdp.example.com", @"https://rdp.example.com/path", @"https://user@rdp.example.com", @"https://rdp.example.com:443", @"https://rdp.example.com?q=1" ])
	{
		[[editor valueForKey:@"gatewayHostnameField"] setText:url];
		[editor savePressed:nil];
		XCTAssertNil(self.savedProfile);
	}
}

- (void)sendUsage:(UIKeyboardHIDUsage)usage flags:(UIKeyModifierFlags)flags text:(NSString *)text
              up:(BOOL)up view:(RDPSessionView *)view
{
	OrbisTestKey *key = [[[OrbisTestKey alloc] init] autorelease];
	key.keyCode = usage; key.modifierFlags = flags; key.characters = text; key.charactersIgnoringModifiers = text;
	OrbisTestPress *press = [[[OrbisTestPress alloc] init] autorelease];
	press.key = key;
	[view handlePresses:[NSSet setWithObject:press] up:up];
}

- (RDPSessionView *)inputViewWithRecorder:(OrbisInputRecorder *)recorder
{
	RDPSessionView *view = [[[RDPSessionView alloc] initWithFrame:CGRectZero] autorelease];
	[view awakeFromNib];
	[view setSession:(RDPSession *)recorder];
	[[RDPKeyboard getSharedRDPKeyboard] initWithSession:(RDPSession *)recorder delegate:nil];
	return view;
}

- (OrbisInputRecorder *)recorder
{
	OrbisInputRecorder *recorder = [[[OrbisInputRecorder alloc] init] autorelease];
	recorder.events = [NSMutableArray array];
	recorder.params = [[[ConnectionParams alloc] initWithBaseDefaultParameters] autorelease];
	[recorder.params setBool:YES forKey:@"workspace_shortcuts"];
	return recorder;
}

- (void)testWorkspaceShortcutSettingsPersistAndReachNewConnections
{
	NSUserDefaults *defaults = [self displayDefaults];
	OrbisIPadDisplaySettingsController *editor = [[[OrbisIPadDisplaySettingsController alloc]
	    initWithDefaults:defaults] autorelease];
	[editor loadViewIfNeeded];
	XCTAssertTrue([[editor valueForKey:@"workspaceSwitch"] isOn]);
	[[editor valueForKey:@"workspaceSwitch"] setOn:NO];
	[editor cancelPressed:nil];
	OrbisIPadDisplaySettings *settings = [[[OrbisIPadDisplaySettings alloc] initWithDefaults:defaults] autorelease];
	XCTAssertTrue(settings.workspaceShortcutsEnabled);
	[editor savePressed:nil];
	settings = [[[OrbisIPadDisplaySettings alloc] initWithDefaults:defaults] autorelease];
	XCTAssertFalse(settings.workspaceShortcutsEnabled);
	ConnectionParams *params = [[[ConnectionParams alloc] initWithBaseDefaultParameters] autorelease];
	[settings applyToConnectionParameters:params];
	XCTAssertFalse([params boolForKey:@"workspace_shortcuts"]);
}

- (void)testAltShiftArrowsSwitchWorkspacesOrToggleActivitiesOncePerPress
{
	OrbisInputRecorder *recorder = [self recorder];
	RDPSessionView *view = [self inputViewWithRecorder:recorder];
	UIKeyModifierFlags flags = UIKeyModifierAlternate | UIKeyModifierShift;
	for (NSNumber *usage in @[ @(UIKeyboardHIDUsageKeyboardLeftArrow),
	    @(UIKeyboardHIDUsageKeyboardRightArrow), @(UIKeyboardHIDUsageKeyboardUpArrow) ])
	{
		[recorder.events removeAllObjects];
		[self sendUsage:usage.integerValue flags:flags text:@"" up:NO view:view];
		NSUInteger count = recorder.events.count;
		[self sendUsage:usage.integerValue flags:flags text:@"" up:NO view:view];
		// Repeats and releases must remain consumed after releasing the modifiers first.
		[self sendUsage:UIKeyboardHIDUsageKeyboardLeftAlt flags:0 text:@"" up:YES view:view];
		[self sendUsage:usage.integerValue flags:0 text:@"" up:NO view:view];
		[self sendUsage:usage.integerValue flags:0 text:@"" up:YES view:view];
		BOOL activities = usage.integerValue == UIKeyboardHIDUsageKeyboardUpArrow;
		XCTAssertEqual(count, activities ? 2u : 4u);
		XCTAssertEqual(recorder.events.count, count);
		XCTAssertEqualObjects(recorder.events[0][@"scancode"], @(0x5B));
		if (!activities)
			XCTAssertEqualObjects(recorder.events[1][@"scancode"],
			    @(usage.integerValue == UIKeyboardHIDUsageKeyboardLeftArrow ? 0x49 : 0x51));
		[self sendUsage:usage.integerValue flags:flags text:@"" up:NO view:view];
		[self sendUsage:usage.integerValue flags:0 text:@"" up:YES view:view];
		XCTAssertEqual(recorder.events.count, count * 2);
	}
	[[RDPKeyboard getSharedRDPKeyboard] initWithSession:nil delegate:nil];
}

- (void)testWorkspaceArrowRequiresAltShiftAndCanBeDisabled
{
	UIKeyModifierFlags both = UIKeyModifierAlternate | UIKeyModifierShift;
	for (NSNumber *flags in @[ @0, @(UIKeyModifierAlternate), @(UIKeyModifierShift),
	    @(both | UIKeyModifierControl), @(both | UIKeyModifierCommand), @(both) ])
	{
		OrbisInputRecorder *recorder = [self recorder];
		if (flags.unsignedIntegerValue == both) [recorder.params setBool:NO forKey:@"workspace_shortcuts"];
		RDPSessionView *view = [self inputViewWithRecorder:recorder];
		[self sendUsage:UIKeyboardHIDUsageKeyboardLeftArrow flags:flags.unsignedIntegerValue text:@"" up:NO view:view];
		[self sendUsage:UIKeyboardHIDUsageKeyboardLeftArrow flags:0 text:@"" up:YES view:view];
		[self sendUsage:UIKeyboardHIDUsageKeyboardLeftAlt flags:0 text:@"" up:YES view:view];
		for (NSDictionary *event in recorder.events)
		{
			XCTAssertNotEqualObjects(event[@"scancode"], @(0x5B));
			XCTAssertNotEqualObjects(event[@"scancode"], @(0x49));
		}
		[[RDPKeyboard getSharedRDPKeyboard] initWithSession:nil delegate:nil];
	}
}

- (void)testWorkspaceShortcutMigratesLegacyGesturePreferencesWithoutRestoringGestures
{
	NSUserDefaults *defaults = [self displayDefaults];
	[defaults setObject:@{ @"width" : @1920, @"height" : @1080, @"workspaceGesturesEnabled" : @NO }
	    forKey:@"OrbisIPadDisplaySettings.v1"];
	OrbisIPadDisplaySettings *settings = [[[OrbisIPadDisplaySettings alloc] initWithDefaults:defaults] autorelease];
	XCTAssertTrue(settings.workspaceShortcutsEnabled);
	XCTAssertEqual(settings.width, 1920u);
	XCTAssertTrue([settings saveWithError:nil]);
	XCTAssertNil([defaults dictionaryForKey:@"OrbisIPadDisplaySettings.v1"][@"workspaceGesturesEnabled"]);
}

- (void)testWorkspaceShortcutsSendBalancedExtendedSuperAndPageKeys
{
	OrbisInputRecorder *recorder = [self recorder];
	RDPSessionView *view = [self inputViewWithRecorder:recorder];
	for (NSNumber *action in @[ @(OrbisIPadWorkspacePrevious), @(OrbisIPadWorkspaceNext), @(OrbisIPadWorkspaceActivities) ])
	{
		[recorder.events removeAllObjects];
		[view performWorkspaceAction:action.integerValue];
		NSMutableSet *pressed = [NSMutableSet set];
		for (NSDictionary *event in recorder.events)
		{
			NSNumber *code = event[@"scancode"];
			if ([event[@"flags"] unsignedIntegerValue] & KBD_FLAGS_RELEASE) [pressed removeObject:code];
			else [pressed addObject:code];
		}
		XCTAssertEqual(pressed.count, 0u);
		NSDictionary *superDown = recorder.events[0];
		XCTAssertEqualObjects(superDown[@"scancode"], @(0x5B));
		XCTAssertEqualObjects(superDown[@"flags"], @(KBD_FLAGS_DOWN | KBD_FLAGS_EXTENDED));
		if (action.integerValue != OrbisIPadWorkspaceActivities)
		{
			BOOL previous = action.integerValue == OrbisIPadWorkspacePrevious;
			XCTAssertEqualObjects(recorder.events[1][@"scancode"], @(previous ? 0x49 : 0x51));
		}
		XCTAssertEqual(recorder.events.count, action.integerValue == OrbisIPadWorkspaceActivities ? 2u : 4u);
	}
	[[RDPKeyboard getSharedRDPKeyboard] initWithSession:nil delegate:nil];
}

- (void)testWorkspaceShortcutRestoresHeldAltAndTheSamePhysicalShift
{
	OrbisInputRecorder *recorder = [self recorder];
	RDPSessionView *view = [self inputViewWithRecorder:recorder];
	[self sendUsage:UIKeyboardHIDUsageKeyboardRightShift flags:UIKeyModifierShift text:@"" up:NO view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboardTab flags:UIKeyModifierAlternate | UIKeyModifierShift text:@"\t" up:NO view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboardTab flags:0 text:@"\t" up:YES view:view];
	[recorder.events removeAllObjects];
	[self sendUsage:UIKeyboardHIDUsageKeyboardRightArrow
	    flags:UIKeyModifierAlternate | UIKeyModifierShift text:@"" up:NO view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboardRightArrow flags:0 text:@"" up:YES view:view];
	XCTAssertEqual(recorder.events.count, 8u);
	XCTAssertEqualObjects(recorder.events[0][@"scancode"], @(0x38));
	XCTAssertEqualObjects(recorder.events[0][@"flags"], @(KBD_FLAGS_RELEASE));
	XCTAssertEqualObjects(recorder.events[1][@"scancode"], @(0x36));
	XCTAssertEqualObjects(recorder.events[6][@"scancode"], @(0x36));
	XCTAssertEqualObjects(recorder.events[7][@"scancode"], @(0x38));
	[self sendUsage:UIKeyboardHIDUsageKeyboardRightShift flags:0 text:@"" up:YES view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboardLeftAlt flags:0 text:@"" up:YES view:view];
	XCTAssertEqualObjects(recorder.events[8][@"flags"], @(KBD_FLAGS_RELEASE));
	XCTAssertEqualObjects(recorder.events[9][@"flags"], @(KBD_FLAGS_RELEASE));
	[[RDPKeyboard getSharedRDPKeyboard] initWithSession:nil delegate:nil];
}

- (void)testTrackpadAndMouseWheelAlwaysScrollIncludingAltShiftSwipes
{
	OrbisInputRecorder *recorder = [self recorder];
	RDPSessionView *view = [self inputViewWithRecorder:recorder];
	RDPSessionViewController *controller = [[[RDPSessionViewController alloc]
	    initWithNibName:nil bundle:nil session:(RDPSession *)recorder] autorelease];
	[controller setValue:view forKey:@"session_view"];
	[controller setValue:@YES forKey:@"session_connected"];
	OrbisTestScroll *scroll = [[[OrbisTestScroll alloc] init] autorelease];
	scroll.testState = UIGestureRecognizerStateBegan;
	for (NSNumber *mask in @[ @(UIScrollTypeMaskContinuous), @(UIScrollTypeMaskDiscrete) ])
		for (NSNumber *flags in @[ @0, @(UIKeyModifierAlternate), @(UIKeyModifierAlternate | UIKeyModifierShift) ])
			for (NSValue *translation in @[ [NSValue valueWithCGPoint:CGPointMake(80, 0)],
			    [NSValue valueWithCGPoint:CGPointMake(0, -80)] ])
			{
				[recorder.events removeAllObjects];
				scroll.allowedScrollTypesMask = mask.unsignedIntegerValue;
				scroll.testModifiers = flags.unsignedIntegerValue;
				scroll.testTranslation = translation.CGPointValue;
				[controller handleScroll:scroll];
				XCTAssertEqual(recorder.events.count, 1u);
				XCTAssertEqualObjects(recorder.events.firstObject[@"type"], @"mouse");
				NSUInteger wheel = translation.CGPointValue.x ? PTR_FLAGS_HWHEEL : PTR_FLAGS_WHEEL;
				XCTAssertTrue([recorder.events.firstObject[@"flags"] unsignedIntegerValue] & wheel);
			}
	[recorder.events removeAllObjects];
	[controller setValue:@NO forKey:@"session_connected"];
	scroll.testTranslation = CGPointMake(80, 0);
	[controller handleScroll:scroll];
	XCTAssertEqual(recorder.events.count, 0u);
	[[RDPKeyboard getSharedRDPKeyboard] initWithSession:nil delegate:nil];
}

- (void)testOptionKeyLeftOfOneTogglesActivitiesOnceWithoutTypingOrLeavingAltPressed
{
	OrbisInputRecorder *recorder = [self recorder];
	RDPSessionView *view = [self inputViewWithRecorder:recorder];
	[self sendUsage:UIKeyboardHIDUsageKeyboardLeftAlt flags:UIKeyModifierAlternate text:@"" up:NO view:view];
	for (NSUInteger repeat = 0; repeat < 3; repeat++)
		[self sendUsage:UIKeyboardHIDUsageKeyboardGraveAccentAndTilde flags:UIKeyModifierAlternate text:@"º" up:NO view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboardLeftAlt flags:0 text:@"" up:YES view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboardGraveAccentAndTilde flags:0 text:@"º" up:YES view:view];
	XCTAssertEqual(recorder.events.count, 2u);
	XCTAssertEqualObjects(recorder.events[0][@"scancode"], @(0x5B));
	XCTAssertEqualObjects(recorder.events[1][@"scancode"], @(0x5B));
	XCTAssertEqualObjects(recorder.events[1][@"flags"], @(KBD_FLAGS_EXTENDED | KBD_FLAGS_RELEASE));
	// A later press is a new action, even if the earlier key release came after Alt.
	[self sendUsage:UIKeyboardHIDUsageKeyboardGraveAccentAndTilde flags:UIKeyModifierAlternate text:@"º" up:NO view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboardGraveAccentAndTilde flags:0 text:@"º" up:YES view:view];
	XCTAssertEqual(recorder.events.count, 4u);
	[[RDPKeyboard getSharedRDPKeyboard] initWithSession:nil delegate:nil];
}

- (void)testActivitiesShortcutAcceptsSpanishISOSectionKeyAndPreservesTheAngleBracketKey
{
	OrbisInputRecorder *recorder = [self recorder];
	RDPSessionView *view = [self inputViewWithRecorder:recorder];
	[self sendUsage:UIKeyboardHIDUsageKeyboardNonUSBackslash flags:UIKeyModifierAlternate text:@"º" up:NO view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboardNonUSBackslash flags:0 text:@"º" up:YES view:view];
	XCTAssertEqual(recorder.events.count, 2u);
	XCTAssertEqualObjects(recorder.events[0][@"scancode"], @(0x5B));
	[recorder.events removeAllObjects];
	[self sendUsage:UIKeyboardHIDUsageKeyboardGraveAccentAndTilde flags:UIKeyModifierAlternate text:@"<" up:NO view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboardGraveAccentAndTilde flags:0 text:@"<" up:YES view:view];
	XCTAssertEqual(recorder.events.count, 2u);
	XCTAssertEqualObjects(recorder.events[0][@"subtype"], @"unicode");
	XCTAssertEqualObjects(recorder.events[0][@"unicode_char"], @('<'));
	[[RDPKeyboard getSharedRDPKeyboard] initWithSession:nil delegate:nil];
}

- (void)testOptionBackspaceSendsControlBackspaceWithoutAltOrDuplicateRelease
{
	OrbisInputRecorder *recorder = [self recorder];
	RDPSessionView *view = [self inputViewWithRecorder:recorder];
	[self sendUsage:UIKeyboardHIDUsageKeyboardLeftAlt flags:UIKeyModifierAlternate text:@"" up:NO view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboardDeleteOrBackspace flags:UIKeyModifierAlternate text:@"\b" up:NO view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboardLeftAlt flags:0 text:@"" up:YES view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboardDeleteOrBackspace flags:0 text:@"\b" up:YES view:view];
	XCTAssertEqual(recorder.events.count, 4u);
	XCTAssertEqualObjects(recorder.events[0][@"scancode"], @(0x1D));
	XCTAssertEqualObjects(recorder.events[1][@"scancode"], @(0x0E));
	XCTAssertEqualObjects(recorder.events[2][@"flags"], @(KBD_FLAGS_RELEASE));
	XCTAssertEqualObjects(recorder.events[3][@"flags"], @(KBD_FLAGS_RELEASE));
	[[RDPKeyboard getSharedRDPKeyboard] initWithSession:nil delegate:nil];
}

- (void)testOptionTextUsesUnicodeAndAltTabKeepsRemoteAlt
{
	OrbisInputRecorder *recorder = [self recorder];
	RDPSessionView *view = [self inputViewWithRecorder:recorder];
	for (NSString *text in @[ @"@", @"€", @"{" ])
	{
		[self sendUsage:UIKeyboardHIDUsageKeyboard2 flags:UIKeyModifierAlternate text:text up:NO view:view];
		[self sendUsage:UIKeyboardHIDUsageKeyboard2 flags:0 text:text up:YES view:view];
		XCTAssertEqualObjects([recorder.events firstObject][@"subtype"], @"unicode");
		XCTAssertEqualObjects([recorder.events firstObject][@"unicode_char"], @([text characterAtIndex:0]));
		XCTAssertEqualObjects([recorder.events lastObject][@"flags"], @(KBD_FLAGS_RELEASE));
		XCTAssertEqual(recorder.events.count, 2u);
		[recorder.events removeAllObjects];
	}
	[self sendUsage:UIKeyboardHIDUsageKeyboardTab flags:UIKeyModifierAlternate text:@"\t" up:NO view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboardTab flags:UIKeyModifierAlternate text:@"\t" up:YES view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboardLeftAlt flags:0 text:@"" up:YES view:view];
	XCTAssertEqual(recorder.events.count, 4u);
	XCTAssertEqualObjects(recorder.events[0][@"scancode"], @(0x38));
	XCTAssertEqualObjects(recorder.events[1][@"scancode"], @(0x0F));
	XCTAssertEqualObjects(recorder.events[3][@"flags"], @(KBD_FLAGS_RELEASE));
	[[RDPKeyboard getSharedRDPKeyboard] initWithSession:nil delegate:nil];
}

- (void)testCommandCopyStillMapsToControl
{
	OrbisInputRecorder *recorder = [self recorder];
	RDPSessionView *view = [self inputViewWithRecorder:recorder];
	[self sendUsage:UIKeyboardHIDUsageKeyboardC flags:UIKeyModifierCommand text:@"c" up:NO view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboardC flags:0 text:@"c" up:YES view:view];
	XCTAssertEqual(recorder.events.count, 4u);
	XCTAssertEqualObjects(recorder.events[0][@"scancode"], @(0x1D));
	XCTAssertEqualObjects(recorder.events[1][@"scancode"], @(0x2E));
	[[RDPKeyboard getSharedRDPKeyboard] initWithSession:nil delegate:nil];
}

- (void)testCommandBackspaceSendsForwardDeleteWithoutControl
{
	OrbisInputRecorder *recorder = [self recorder];
	RDPSessionView *view = [self inputViewWithRecorder:recorder];
	[self sendUsage:UIKeyboardHIDUsageKeyboardDeleteOrBackspace flags:UIKeyModifierCommand text:@"\b" up:NO view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboardLeftGUI flags:0 text:@"" up:YES view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboardDeleteOrBackspace flags:0 text:@"\b" up:YES view:view];
	XCTAssertEqual(recorder.events.count, 2u);
	XCTAssertEqualObjects(recorder.events[0][@"scancode"], @(0x53));
	XCTAssertEqualObjects(recorder.events[0][@"flags"], @(KBD_FLAGS_DOWN | KBD_FLAGS_EXTENDED));
	// A key-up after Command was released must not emit a Backspace release.
	XCTAssertEqualObjects(recorder.events[1][@"scancode"], @(0x53));
	[[RDPKeyboard getSharedRDPKeyboard] initWithSession:nil delegate:nil];
}

- (void)testShiftOptionTextRestoresTheSamePhysicalShiftKey
{
	OrbisInputRecorder *recorder = [self recorder];
	RDPSessionView *view = [self inputViewWithRecorder:recorder];
	[self sendUsage:UIKeyboardHIDUsageKeyboardRightShift flags:UIKeyModifierShift text:@"" up:NO view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboard2 flags:UIKeyModifierShift | UIKeyModifierAlternate text:@"{" up:NO view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboard2 flags:0 text:@"{" up:YES view:view];
	[self sendUsage:UIKeyboardHIDUsageKeyboardRightShift flags:0 text:@"" up:YES view:view];
	XCTAssertEqual(recorder.events.count, 6u);
	XCTAssertEqualObjects(recorder.events[0][@"scancode"], @(0x36));
	XCTAssertEqualObjects(recorder.events[1][@"flags"], @(KBD_FLAGS_RELEASE));
	XCTAssertEqualObjects(recorder.events[2][@"unicode_char"], @('{'));
	XCTAssertEqualObjects(recorder.events[4][@"scancode"], @(0x36));
	XCTAssertEqualObjects(recorder.events[5][@"flags"], @(KBD_FLAGS_RELEASE));
	[[RDPKeyboard getSharedRDPKeyboard] initWithSession:nil delegate:nil];
}

- (OrbisTestRDPSession *)sessionWithTransport:(OrbisTestTransport *)transport
{
	ConnectionParams *params = [[[ConnectionParams alloc] initWithBaseDefaultParameters] autorelease];
	[params setValue:@"desktop.local" forKey:@"hostname"];
	[params setValue:@"tester" forKey:@"username"];
	[params setValue:@"test-password" forKey:@"password"];
	ComputerBookmark *bookmark = [[[ComputerBookmark alloc] initWithConnectionParameters:params] autorelease];
	bookmark.label = @"Test computer";
	OrbisTestRDPSession *session = [[[OrbisTestRDPSession alloc] initWithBookmark:bookmark] autorelease];
	session.connectionTransport = transport;
	return session;
}

- (void)testRDPWaitsForTransportReadiness
{
	OrbisTestTransport *transport = [[[OrbisTestTransport alloc] init] autorelease];
	OrbisTestRDPSession *session = [self sessionWithTransport:transport];
	[session connect];
	[session connect];
	XCTAssertEqual(transport.preparations, 1u);
	XCTAssertEqual(session.rdpStarts, 0u);
	[transport completeWithError:nil];
	XCTestExpectation *drained = [self expectationWithDescription:@"transport ready"];
	dispatch_async(dispatch_get_main_queue(), ^{ [drained fulfill]; });
	[self waitForExpectationsWithTimeout:2 handler:nil];
	XCTAssertEqual(session.rdpStarts, 1u);
	[session disconnect];
	XCTAssertTrue(transport.session.closed);
}

- (void)testLoopbackTransportPreservesTheLogicalRDPHostnameAndPort
{
	OrbisTestTransport *transport = [[[OrbisTestTransport alloc] init] autorelease];
	transport.destination = [[[OrbisTransportDestination alloc] initWithHostname:@"127.0.0.1" port:3333] autorelease];
	OrbisTestRDPSession *session = [self sessionWithTransport:transport];
	[session connect];
	[transport completeWithError:nil];
	XCTestExpectation *drained = [self expectationWithDescription:@"physical destination ready"];
	dispatch_async(dispatch_get_main_queue(), ^{ [drained fulfill]; });
	[self waitForExpectationsWithTimeout:2 handler:nil];
	XCTAssertEqual(session.rdpStarts, 1u);
	rdpSettings *settings = [session getSessionParams];
	XCTAssertEqualObjects([NSString stringWithUTF8String:freerdp_settings_get_string(settings, FreeRDP_ServerHostname)], @"desktop.local");
	XCTAssertEqual(freerdp_settings_get_uint32(settings, FreeRDP_ServerPort), 3389u);
	[session disconnect];
	XCTAssertTrue(transport.session.closed);
}

- (void)testCancellingPreparationClosesTransportAndIgnoresLateCompletion
{
	OrbisTestTransport *transport = [[[OrbisTestTransport alloc] init] autorelease];
	OrbisTestRDPSession *session = [self sessionWithTransport:transport];
	XCTestExpectation *ended = [self expectationForNotification:TSXSessionDidDisconnectNotification object:session handler:nil];
	[session connect];
	[session disconnect];
	[session disconnect];
	XCTAssertTrue(transport.session.closed);
	[transport completeWithError:nil];
	XCTestExpectation *drained = [self expectationWithDescription:@"late completion"];
	dispatch_async(dispatch_get_main_queue(), ^{ [drained fulfill]; });
	[self waitForExpectations:@[ ended, drained ] timeout:2];
	XCTAssertEqual(session.rdpStarts, 0u);
}

- (void)testTransportPreparationErrorsArePresentedAndCloseTheAttempt
{
	OrbisTestTransport *transport = [[[OrbisTestTransport alloc] init] autorelease];
	OrbisTestRDPSession *session = [self sessionWithTransport:transport];
	[self expectationForNotification:TSXSessionDidFailToConnectNotification object:session handler:nil];
	[session connect];
	[transport completeWithError:[NSError errorWithDomain:@"test" code:1 userInfo:@{
		NSLocalizedDescriptionKey : @"Tunnel unavailable" }]];
	[self waitForExpectationsWithTimeout:2 handler:nil];
	XCTAssertEqualObjects(session.connectionFailureMessage, @"Tunnel unavailable");
	XCTAssertTrue(transport.session.closed);
	XCTAssertEqual(session.rdpStarts, 0u);
}

- (void)testLibraryKeepsTheSelectedTransportAliveAfterItsAutoreleasePoolDrains
{
	RDPSession *session = nil;
	@autoreleasepool
	{
		OrbisTestLibrary *library = [[[OrbisTestLibrary alloc] init] autorelease];
		UINavigationController *navigation = [[[UINavigationController alloc] initWithRootViewController:library] autorelease];
		OrbisTestProfileStore *store = [[[OrbisTestProfileStore alloc] init] autorelease];
		store.selectedProfile = [[[OrbisProfile alloc] init] autorelease];
		store.selectedProfile.name = @"Test computer";
		store.selectedProfile.host = @"desktop.local";
		store.selectedProfile.username = @"tester";
		[library setValue:store forKey:@"profileStore"];
		[library startConnectionWithPassword:@"test-password"];
		XCTAssertNotEqual(navigation.topViewController, library);
		session = [[navigation.topViewController valueForKey:@"session"] retain];
	}
	XCTAssertEqualObjects([session.connectionTransport displayName], @"Direct RDP");
	[session disconnect];
	[session release];
}

- (void)testAboutHasTheBundledOfflineChangelog
{
	XCTAssertNotNil([[NSBundle mainBundle] pathForResource:@"CHANGELOG" ofType:@"md"]);
	OrbisAboutController *about = [[[OrbisAboutController alloc] init] autorelease];
	[about loadViewIfNeeded];
	XCTAssertNotNil(about.view);
}

- (uint16_t)probeServerWithResponse:(NSData *)response
{
	int listener = socket(AF_INET, SOCK_STREAM, 0);
	XCTAssertGreaterThanOrEqual(listener, 0);
	struct sockaddr_in address = { .sin_len = sizeof(address), .sin_family = AF_INET,
	    .sin_addr.s_addr = htonl(INADDR_LOOPBACK), .sin_port = 0 };
	XCTAssertEqual(bind(listener, (struct sockaddr *)&address, sizeof(address)), 0);
	XCTAssertEqual(listen(listener, 1), 0);
	socklen_t addressSize = sizeof(address);
	XCTAssertEqual(getsockname(listener, (struct sockaddr *)&address, &addressSize), 0);
	XCTestExpectation *serverFinished = [self expectationWithDescription:@"Probe socket closed"];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
		struct pollfd ready = { .fd = listener, .events = POLLIN };
		int client = poll(&ready, 1, 2000) > 0 ? accept(listener, NULL, NULL) : -1;
		close(listener);
		if (client >= 0)
		{
			int noSignal = 1;
			setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
			struct timeval timeout = { .tv_sec = 2 };
			setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
			uint8_t request[19];
			size_t received = 0;
			while (received < sizeof(request))
			{
				ssize_t count = read(client, request + received, sizeof(request) - received);
				if (count <= 0) break;
				received += count;
			}
			XCTAssertEqual(received, sizeof(request));
			XCTAssertEqual(request[5], 0xe0);
			XCTAssertEqual(request[15], 11);
			if (response.length)
			{
				write(client, response.bytes, 3);
				usleep(20000);
				write(client, (const uint8_t *)response.bytes + 3, response.length - 3);
			}
			else
			{
				uint8_t extra;
				XCTAssertEqual(read(client, &extra, 1), 0);
			}
			close(client);
		}
		else
			XCTFail(@"Health check did not connect to its fixture");
		[serverFinished fulfill];
	});
	return ntohs(address.sin_port);
}

- (NSData *)negotiationReply:(uint8_t)type
{
	uint8_t reply[] = { 3, 0, 0, 19, 14, 0xd0, 0, 0, 0, 0, 0, type, 0, 8, 0, 2, 0, 0, 0 };
	return [NSData dataWithBytes:reply length:sizeof(reply)];
}

- (void)checkProbeResponse:(NSData *)response available:(BOOL)expected timeout:(NSTimeInterval)timeout
{
	OrbisProfile *profile = [[[OrbisProfile alloc] init] autorelease];
	profile.host = @"unreachable.invalid";
	profile.port = 3389;
	OrbisTestTransport *transport = [[[OrbisTestTransport alloc] init] autorelease];
	transport.destination = [[[OrbisTransportDestination alloc] initWithHostname:@"127.0.0.1"
	    port:[self probeServerWithResponse:response]] autorelease];
	OrbisConnectionHealthCheck *check = [[[OrbisConnectionHealthCheck alloc] initWithProfile:profile
	    transport:transport timeout:timeout] autorelease];
	XCTestExpectation *result = [self expectationWithDescription:@"Health result"];
	[check startWithCompletion:^(BOOL available) {
		XCTAssertTrue([NSThread isMainThread]);
		XCTAssertEqual(available, expected);
		XCTAssertTrue(transport.session.closed);
		[result fulfill];
	}];
	[transport completeWithError:nil];
	[self waitForExpectationsWithTimeout:3 handler:nil];
}

- (void)testHealthUsesThePreparedTunnelDestinationAndAcceptsFragmentedRDP
{
	[self checkProbeResponse:[self negotiationReply:2] available:YES timeout:1.0];
}

- (void)testHealthChecksADirectProfilesOwnEndpoint
{
	OrbisProfile *profile = [[[OrbisProfile alloc] init] autorelease];
	profile.host = @"127.0.0.1";
	profile.port = [self probeServerWithResponse:[self negotiationReply:2]];
	OrbisDirectTransport *transport = [[[OrbisDirectTransport alloc] init] autorelease];
	OrbisConnectionHealthCheck *check = [[[OrbisConnectionHealthCheck alloc] initWithProfile:profile
	    transport:transport timeout:1.0] autorelease];
	XCTestExpectation *result = [self expectationWithDescription:@"Direct RDP available"];
	[check startWithCompletion:^(BOOL available) { XCTAssertTrue(available); [result fulfill]; }];
	[self waitForExpectationsWithTimeout:3 handler:nil];
}

- (void)testHealthRejectsAnOpenPortThatIsNotAnRDPServer
{
	[self checkProbeResponse:[@"HTTP/1.1 200 OK\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]
	    available:NO timeout:1.0];
}

- (void)testHealthRejectsRDPProtocolNegotiationFailure
{
	[self checkProbeResponse:[self negotiationReply:3] available:NO timeout:1.0];
}

- (void)testHealthTimeoutClosesTheSocketAndTransport
{
	[self checkProbeResponse:nil available:NO timeout:0.2];
}

- (void)testHealthCancellationClosesPendingPreparationAndIgnoresLateCompletion
{
	OrbisTestTransport *transport = [[[OrbisTestTransport alloc] init] autorelease];
	OrbisProfile *profile = [[[OrbisProfile alloc] init] autorelease];
	OrbisConnectionHealthCheck *check = [[[OrbisConnectionHealthCheck alloc] initWithProfile:profile
	    transport:transport timeout:0.1] autorelease];
	XCTestExpectation *result = [self expectationWithDescription:@"Cancelled result"];
	result.inverted = YES;
	[check startWithCompletion:^(BOOL available) { (void)available; [result fulfill]; }];
	[check cancel];
	XCTAssertTrue(transport.session.closed);
	[transport completeWithError:nil];
	[self waitForExpectationsWithTimeout:0.2 handler:nil];
}

- (void)testHealthPreparationFailureClosesItsTransport
{
	OrbisTestTransport *transport = [[[OrbisTestTransport alloc] init] autorelease];
	OrbisProfile *profile = [[[OrbisProfile alloc] init] autorelease];
	OrbisConnectionHealthCheck *check = [[[OrbisConnectionHealthCheck alloc] initWithProfile:profile
	    transport:transport timeout:0.5] autorelease];
	XCTestExpectation *result = [self expectationWithDescription:@"Transport unavailable"];
	[check startWithCompletion:^(BOOL available) {
		XCTAssertFalse(available);
		XCTAssertTrue(transport.session.closed);
		[result fulfill];
	}];
	[transport completeWithError:[NSError errorWithDomain:@"test" code:403 userInfo:nil]];
	[self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testRemoteSessionKeepsTheDisplayAwakeUntilDisconnect
{
	UIApplication *application = [UIApplication sharedApplication];
	BOOL previous = application.idleTimerDisabled;
	[self addTeardownBlock:^{ application.idleTimerDisabled = previous; }];
	OrbisController *library = [[[OrbisController alloc] init] autorelease];
	[library loadViewIfNeeded];
	[library setConnectionBusy:YES status:@"Connecting…"];
	XCTAssertTrue(application.idleTimerDisabled);
	[library viewWillDisappear:NO];
	XCTAssertTrue(application.idleTimerDisabled);
	[[NSNotificationCenter defaultCenter] postNotificationName:TSXSessionDidDisconnectNotification object:nil];
	XCTAssertFalse(application.idleTimerDisabled);
}

- (void)testFailedConnectionRestoresAutomaticScreenLock
{
	UIApplication *application = [UIApplication sharedApplication];
	BOOL previous = application.idleTimerDisabled;
	[self addTeardownBlock:^{ application.idleTimerDisabled = previous; }];
	OrbisController *library = [[[OrbisController alloc] init] autorelease];
	[library loadViewIfNeeded];
	[library setConnectionBusy:YES status:@"Connecting…"];
	XCTAssertTrue(application.idleTimerDisabled);
	[[NSNotificationCenter defaultCenter] postNotificationName:TSXSessionDidFailToConnectNotification object:nil];
	XCTAssertFalse(application.idleTimerDisabled);
}

- (void)testBackgroundingReleasesIdleTimerAndReturningRestoresAnActiveSession
{
	UIApplication *application = [UIApplication sharedApplication];
	BOOL previous = application.idleTimerDisabled;
	[self addTeardownBlock:^{ application.idleTimerDisabled = previous; }];
	OrbisController *library = [[[OrbisController alloc] init] autorelease];
	[library setConnectionBusy:YES status:@"Connecting…"];
	[library applicationWillResignActive:nil];
	XCTAssertFalse(application.idleTimerDisabled);
	[library applicationDidBecomeActive:nil];
	XCTAssertTrue(application.idleTimerDisabled);
	[library sessionDidEnd:nil];
	[library applicationDidBecomeActive:nil];
	XCTAssertFalse(application.idleTimerDisabled);
}

- (void)testDiscardingAnActiveConnectionRestoresAutomaticScreenLock
{
	UIApplication *application = [UIApplication sharedApplication];
	BOOL previous = application.idleTimerDisabled;
	[self addTeardownBlock:^{ application.idleTimerDisabled = previous; }];
	OrbisController *library = [[OrbisController alloc] init];
	[library setConnectionBusy:YES status:@"Connecting…"];
	XCTAssertTrue(application.idleTimerDisabled);
	[library release];
	XCTAssertFalse(application.idleTimerDisabled);
}

- (void)testLeavingASessionDoesNotReplaceAvailabilityWithDisconnected
{
	OrbisController *library = [[[OrbisController alloc] init] autorelease];
	[library loadViewIfNeeded];
	OrbisProfile *profile = [[[OrbisProfile alloc] init] autorelease];
	profile.host = @"desktop.local";
	profile.name = @"Test computer";
	OrbisTestProfileStore *store = [[[OrbisTestProfileStore alloc] init] autorelease];
	store.selectedProfile = profile;
	store.profiles = @[ profile ];
	[library setValue:store forKey:@"profileStore"];
	[library refreshProfileUI];
	NSMutableDictionary *health = [library valueForKey:@"profileHealth"];
	[health setObject:@2 forKey:profile.identifier];
	[library sessionDidEnd:[NSNotification notificationWithName:TSXSessionDidDisconnectNotification object:nil]];
	NSDictionary *views = [[library valueForKey:@"profileCardViews"] objectForKey:profile.identifier];
	XCTAssertEqualObjects([views[@"status-label"] text], @"Available");
	XCTAssertTrue([views[@"connect-button"] isEnabled]);
	[library prepareStatusForCardViews:views selected:NO];
	XCTAssertEqualObjects([views[@"status-label"] text], @"Available");
	[health setObject:@3 forKey:profile.identifier];
	[library prepareStatusForCardViews:views selected:YES];
	XCTAssertEqualObjects([views[@"status-label"] text], @"Unavailable");
	XCTAssertTrue([views[@"connect-button"] isEnabled]);
}

- (void)testLibraryRechecksAfterDisconnectAndCancelsChecksWhileInactive
{
	OrbisTestHealthLibrary *library = [[[OrbisTestHealthLibrary alloc] init] autorelease];
	[library loadViewIfNeeded];
	OrbisProfile *profile = [[[OrbisProfile alloc] init] autorelease];
	profile.host = @"desktop.local";
	profile.name = @"Test computer";
	OrbisTestProfileStore *store = [[[OrbisTestProfileStore alloc] init] autorelease];
	store.selectedProfile = profile;
	store.profiles = @[ profile ];
	[library setValue:store forKey:@"profileStore"];
	[library refreshProfileUI];
	[library setValue:@YES forKey:@"libraryVisible"];
	[library startHealthMonitoring];
	NSDictionary *views = [[library valueForKey:@"profileCardViews"] objectForKey:profile.identifier];
	XCTAssertEqualObjects([views[@"status-label"] text], @"Checking…");
	void (^available)(BOOL) = [[library.lastHealthCheck.result copy] autorelease];
	available(YES);
	XCTAssertEqualObjects([views[@"status-label"] text], @"Available");
	[library sessionDidEnd:[NSNotification notificationWithName:TSXSessionDidDisconnectNotification object:nil]];
	XCTAssertEqualObjects([views[@"status-label"] text], @"Checking…");
	[library applicationWillResignActive:nil];
	XCTAssertTrue(library.lastHealthCheck.cancelled);
	XCTAssertNil([library valueForKey:@"healthTimer"]);
	XCTAssertEqual([[library valueForKey:@"healthChecks"] count], 0u);
	[library applicationDidBecomeActive:nil];
	XCTAssertFalse(library.lastHealthCheck.cancelled);
	XCTAssertNotNil(library.lastHealthCheck.result);
	[library viewWillDisappear:NO];
	XCTAssertTrue(library.lastHealthCheck.cancelled);
	XCTAssertNil([library valueForKey:@"healthTimer"]);
}
@end
