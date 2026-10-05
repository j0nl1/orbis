/* SPDX-License-Identifier: MIT */
#import <AppKit/AppKit.h>
#import <freerdp/client/disp.h>
#import "OrbisSessionController.h"
#import "OrbisProfile.h"
#import "OrbisDirectTransport.h"
#import "MRDPView.h"

@interface OrbisSessionController (DisplayTests)
- (void)displayChannelConnected:(DispClientContext *)channel;
- (void)displayControlCaps:(uint32_t)count area:(uint64_t)area;
- (void)addVirtualDisplay:(id)sender;
- (void)desktopDidResize:(NSNotification *)notification;
- (void)displayChangeTimedOut:(NSTimer *)timer;
@end

static NSUInteger failures;
static UINT32 sentCount;
static DISPLAY_CONTROL_MONITOR_LAYOUT sentMonitors[2];
static UINT CaptureLayout(DispClientContext *channel, UINT32 count, DISPLAY_CONTROL_MONITOR_LAYOUT *monitors)
{
    (void)channel;
    sentCount = count;
    memcpy(sentMonitors, monitors, count * sizeof(*monitors));
    return CHANNEL_RC_OK;
}
static void Require(BOOL value, const char *message)
{
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); failures++; }
}

@interface OrbisDisplayFixtureView : MRDPView
@property(nonatomic) NSSize fixtureSize;
@end
@implementation OrbisDisplayFixtureView
@synthesize fixtureSize;
- (NSSize)desktopPixelSize { return fixtureSize; }
- (void)setSessionController:(id)controller { (void)controller; }
@end

@interface OrbisDisplayFixtureController : OrbisSessionController
@property(nonatomic) NSUInteger errorCount;
- (void)prepareFixture;
- (NSWindow *)secondWindow;
- (BOOL)isStopped;
- (BOOL)isChanging;
- (NSRect)primaryPixels;
- (void)setPixelSize:(NSSize)size;
@end
@implementation OrbisDisplayFixtureController
@synthesize errorCount;
- (void)showDisplayError:(NSString *)message { (void)message; errorCount++; }
- (void)prepareFixture
{
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    _remoteView = [[OrbisDisplayFixtureView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    _wasConnected = YES;
    OrbisDisplayLayoutMake(1280, 800, 0, 0, [_profile monitorArrangement], false, &_displayLayout);
}
- (NSWindow *)secondWindow { return _secondaryWindow; }
- (BOOL)isStopped { return _stopping; }
- (BOOL)isChanging { return _displayChangePending; }
- (NSRect)primaryPixels
{
    OrbisDisplayRect r = _displayLayout.pixels[0];
    return NSMakeRect(r.x, r.y, r.width, r.height);
}
- (void)setPixelSize:(NSSize)size { [(OrbisDisplayFixtureView *)_remoteView setFixtureSize:size]; }
@end

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        for (NSInteger arrangement = 0; arrangement < 4; arrangement++)
        {
            OrbisProfile *profile = [[OrbisProfile alloc] init];
            profile.name = @"Fixture";
            profile.secondaryWidth = 1024; profile.secondaryHeight = 768;
            profile.monitorArrangement = (OrbisMonitorArrangement)arrangement;
            OrbisDirectTransport *transport = [[[OrbisDirectTransport alloc] init] autorelease];
            OrbisDisplayFixtureController *controller = [[OrbisDisplayFixtureController alloc]
                initWithProfile:profile password:nil transport:transport];
            [controller prepareFixture];
            DispClientContext channel = {0}; channel.SendMonitorLayout = CaptureLayout;
            [controller displayChannelConnected:&channel];
            [controller displayControlCaps:2 area:8192ULL * 8192 * 2];
            sentCount = 0;
            [controller addVirtualDisplay:nil];
            Require(sentCount == 2 && [controller isChanging], "Add must send two monitors on the existing channel");
            Require(sentMonitors[0].Flags == DISPLAY_CONTROL_MONITOR_PRIMARY &&
                sentMonitors[1].Width == 1024 && sentMonitors[1].Height == 768,
                "The primary flag and saved secondary resolution must reach the protocol");
            Require(![controller secondWindow], "Do not display a second window before the server confirms resizing");
            OrbisDisplayLayout expected;
            OrbisDisplayLayoutMake(1280, 800, 1024, 768, profile.monitorArrangement, true, &expected);
            Require(sentMonitors[1].Left == expected.monitors[1].x &&
                sentMonitors[1].Top == expected.monitors[1].y, "Arrangement must retain signed protocol offsets");
            [controller setPixelSize:NSMakeSize(expected.width, expected.height)];
            [controller desktopDidResize:nil];
            Require([controller secondWindow] != nil && ![controller isChanging], "Confirmed resizing opens the secondary window");
            Require(NSEqualRects([controller primaryPixels], NSMakeRect(expected.pixels[0].x,
                expected.pixels[0].y, 1280, 800)), "Primary pixels must shift when the other monitor is left or above");
            Require(![controller windowShouldClose:[controller secondWindow]] && sentCount == 1,
                "Closing the second window requests one monitor without closing the session");
            Require(![controller isStopped] && [controller secondWindow] != nil,
                "Keep the session and secondary window until removal is confirmed");
            [controller setPixelSize:NSMakeSize(1280, 800)];
            [controller desktopDidResize:nil];
            Require(![controller secondWindow] && ![controller isStopped], "Confirmed removal keeps the main session running");
            [controller addVirtualDisplay:nil];
            [controller displayChangeTimedOut:nil];
            Require(sentCount == 1 && controller.errorCount == 1 && ![controller isChanging],
                "A resize timeout restores the previous layout and reports the failure");
            [controller displayControlCaps:1 area:8192ULL * 8192];
            sentCount = 0; [controller addVirtualDisplay:nil];
            Require(sentCount == 0 && controller.errorCount == 2, "A single-monitor server must not receive a truncated two-monitor request");
            [controller displayControlCaps:2 area:1];
            [controller addVirtualDisplay:nil];
            Require(sentCount == 0 && controller.errorCount == 3, "Reject layouts exceeding the advertised monitor area");
            [controller stop]; [controller release]; [profile release];
        }
        printf("%s: virtual display session lifecycle\n", failures ? "FAIL" : "PASS");
        return failures ? 1 : 0;
    }
}
