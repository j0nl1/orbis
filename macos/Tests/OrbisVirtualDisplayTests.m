/* SPDX-License-Identifier: MIT */
#import <AppKit/AppKit.h>
#import <freerdp/client/disp.h>
#import "OrbisSessionController.h"
#import "OrbisProfile.h"
#import "OrbisDirectTransport.h"
#import "MRDPView.h"
#import "OrbisRemoteView.h"
#import "OrbisAppDelegate.h"
#import <objc/runtime.h>

@interface OrbisSessionController (DisplayTests)
- (void)displayChannelConnected:(DispClientContext *)channel;
- (void)displayControlCaps:(uint32_t)count area:(uint64_t)area;
- (void)addVirtualDisplay:(id)sender;
- (void)desktopDidResize:(NSNotification *)notification;
- (void)displayChangeTimedOut:(NSTimer *)timer;
@end

static NSUInteger failures;
static UINT32 sentCount;
static NSMutableArray *pointerEvents;
BOOL OrbisRecordDisplayPointer(rdpClientContext *context, BOOL relative, UINT16 flags, INT32 x, INT32 y)
{
    (void)context; (void)relative;
    [pointerEvents addObject:@{ @"flags": @(flags), @"x": @(x), @"y": @(y) }];
    return TRUE;
}
void OrbisRecordMouseButton(void *context, int button, int x, int y, BOOL down)
{
    (void)context; (void)button; (void)x; (void)y; (void)down;
}

@interface OrbisAppDelegate (DisplayTests)
- (void)buildMainMenu;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
@end

@interface MRDPView (PointerFixture)
- (void)setPointerFixture:(mfContext *)fixture;
@end
@implementation MRDPView (PointerFixture)
- (void)setPointerFixture:(mfContext *)fixture
{
    mfc = fixture; context = (rdpContext *)fixture; instance = context->instance;
    [self setIs_connected:1];
}
@end

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

@interface OrbisDisplayFixtureView : OrbisRemoteView
@property(nonatomic) NSSize fixtureSize;
@end
@implementation OrbisDisplayFixtureView
@synthesize fixtureSize;
- (NSSize)desktopPixelSize { return fixtureSize; }
@end

@interface OrbisDisplayFixtureController : OrbisSessionController
{
    mfContext _fixtureContext;
    freerdp _fixtureInstance;
    rdpInput _fixtureInput;
}
@property(nonatomic) NSUInteger errorCount;
- (void)prepareFixture;
- (NSWindow *)secondWindow;
- (BOOL)isStopped;
- (BOOL)isChanging;
- (NSRect)primaryPixels;
- (void)setPixelSize:(NSSize)size;
- (void)checkCapturedDrag;
@end
@implementation OrbisDisplayFixtureController
@synthesize errorCount;
- (void)showDisplayError:(NSString *)message { (void)message; errorCount++; }
- (void)prepareFixture
{
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    _remoteView = [[OrbisDisplayFixtureView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    _fixtureContext.common.context.instance = &_fixtureInstance;
    _fixtureContext.common.context.input = &_fixtureInput;
    _fixtureInstance.context = (rdpContext *)&_fixtureContext;
    [_remoteView setPointerFixture:&_fixtureContext];
    [_remoteView setSessionController:self];
    [[_window contentView] addSubview:_remoteView];
    [_window setReleasedWhenClosed:NO];
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
- (void)checkCapturedDrag
{
    [_window setFrame:NSMakeRect(80, 80, 640, 440) display:NO];
    [_secondaryWindow setFrame:NSMakeRect(800, 100, 500, 360) display:NO];
    [_remoteView setFrame:[[_window contentView] bounds]];
    [_secondaryView setFrame:[[_secondaryWindow contentView] bounds]];
    [_window orderFront:nil]; [_secondaryWindow orderFront:nil];
    Require([_window toolbar] == nil, "Remote displays must not have a toolbar");
    for (NSUInteger reverse = 0; reverse < 2; reverse++)
    {
        MRDPView *source = reverse ? _secondaryView : _remoteView;
        MRDPView *target = reverse ? _remoteView : _secondaryView;
        NSWindow *sourceWindow = [source window];
        NSPoint startPoint = NSMakePoint(NSMidX([source bounds]), NSMidY([source bounds]));
        NSPoint endPoint = NSMakePoint(NSMidX([target bounds]), NSMidY([target bounds]));
        NSPoint startInWindow = [source convertPoint:startPoint toView:nil];
        NSPoint endInWindow = [target convertPoint:endPoint toView:nil];
        NSPoint endOnScreen = [[target window] convertPointToScreen:endInWindow];
        NSPoint endInSource = [sourceWindow convertPointFromScreen:endOnScreen];
        OrbisDisplayRect r = _displayLayout.pixels[reverse ? 0 : 1];
        NSPoint expected = NSMakePoint(r.x + r.width / 2, r.y + r.height / 2);
        [pointerEvents removeAllObjects];
        const NSEventType types[] = { NSEventTypeLeftMouseDown, NSEventTypeLeftMouseDragged, NSEventTypeLeftMouseUp };
        for (NSUInteger i = 0; i < 3; i++)
        {
            // The drag remains addressed to its original window even over the other output.
            NSEvent *event = [NSEvent mouseEventWithType:types[i] location:i ? endInSource : startInWindow
                modifierFlags:0 timestamp:i + 1 windowNumber:sourceWindow.windowNumber context:nil
                eventNumber:i + 1 clickCount:1 pressure:i == 2 ? 0 : 1];
            if (i == 0) [source mouseDown:event];
            else if (i == 1) [source mouseDragged:event];
            else [source mouseUp:event];
        }
        Require(pointerEvents.count == 3, "Cross-window dragging must preserve one press, one move, and one release");
        if (pointerEvents.count == 3)
        {
            Require([pointerEvents[0][@"flags"] unsignedIntValue] == (PTR_FLAGS_BUTTON1 | PTR_FLAGS_DOWN),
                "A captured drag must start with a button press");
            Require([pointerEvents[1][@"flags"] unsignedIntValue] == PTR_FLAGS_MOVE &&
                [pointerEvents[1][@"x"] intValue] == (int)expected.x &&
                [pointerEvents[1][@"y"] intValue] == (int)expected.y,
                "The captured move must reach the destination monitor rather than the source edge");
            Require([pointerEvents[2][@"flags"] unsignedIntValue] == PTR_FLAGS_BUTTON1 &&
                [pointerEvents[2][@"x"] intValue] == (int)expected.x &&
                [pointerEvents[2][@"y"] intValue] == (int)expected.y,
                "Releasing over the other output must release the button there exactly once");
        }
    }
}

@end

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        pointerEvents = [[NSMutableArray alloc] init];
        OrbisAppDelegate *delegate = [[OrbisAppDelegate alloc] init];
        [delegate buildMainMenu];
        NSMenuItem *displayItem = nil;
        for (NSMenuItem *root in [NSApp mainMenu].itemArray)
            for (NSMenuItem *item in root.submenu.itemArray)
                if ([item.title isEqualToString:@"Add Virtual Display"]) displayItem = item;
        Require(displayItem && [displayItem target] == delegate, "Add Virtual Display belongs in the native menu");
        Require(![delegate validateMenuItem:displayItem], "The menu action must be disabled outside a session");
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
            // Borrow the fixture controller only while exercising real menu forwarding.
            object_setIvar(delegate, class_getInstanceVariable([OrbisAppDelegate class], "_sessionController"), controller);
            Require([delegate validateMenuItem:displayItem], "The menu must enable adding for a capable single-display session");
            sentCount = 0;
            [NSApp sendAction:displayItem.action to:displayItem.target from:displayItem];
            Require(![delegate validateMenuItem:displayItem], "The menu must prevent overlapping layout requests");
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
            [controller checkCapturedDrag];
            Require(![delegate validateMenuItem:displayItem], "The menu must stay disabled when the second display exists");
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
            [controller stop];
            object_setIvar(delegate, class_getInstanceVariable([OrbisAppDelegate class], "_sessionController"), nil);
            [controller release]; [profile release];
        }
        [delegate release]; [pointerEvents release];
        printf("%s: virtual display session lifecycle\n", failures ? "FAIL" : "PASS");
        return failures ? 1 : 0;
    }
}
