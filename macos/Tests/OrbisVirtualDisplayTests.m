/* SPDX-License-Identifier: MIT */
#import <AppKit/AppKit.h>
#import <freerdp/client/disp.h>
#import "OrbisSessionController.h"
#import "OrbisProfile.h"
#import "OrbisDisplaySettings.h"
#import "OrbisDirectTransport.h"
#import "MRDPView.h"
#import "OrbisRemoteView.h"
#import "OrbisAppDelegate.h"
#import <objc/runtime.h>

/* Give the SSH fixture a deterministic active window without replacing menu or session code. */
static NSWindow *resolutionFixtureWindow;
@interface OrbisResolutionApplication : NSApplication
@end
@implementation OrbisResolutionApplication
- (NSWindow *)keyWindow { return resolutionFixtureWindow ?: [super keyWindow]; }
- (NSWindow *)mainWindow { return resolutionFixtureWindow ?: [super mainWindow]; }
@end

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
- (void)menuNeedsUpdate:(NSMenu *)menu;
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
- (NSWindow *)primaryWindow;
- (OrbisDisplayLayout)currentLayout;
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
    OrbisDisplayLayoutMake(1280, 800, 0, 0, [_displaySettings arrangement], false, &_displayLayout);
}
- (NSWindow *)secondWindow { return _secondaryWindow; }
- (NSWindow *)primaryWindow { return _window; }
- (OrbisDisplayLayout)currentLayout { return _displayLayout; }
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

static void ConfirmResolution(OrbisDisplayFixtureController *controller)
{
    int32_t minX = 0, minY = 0, maxX = 0, maxY = 0;
    for (uint32_t i = 0; i < sentCount; i++)
    {
        minX = MIN(minX, sentMonitors[i].Left); minY = MIN(minY, sentMonitors[i].Top);
        maxX = MAX(maxX, sentMonitors[i].Left + (int32_t)sentMonitors[i].Width);
        maxY = MAX(maxY, sentMonitors[i].Top + (int32_t)sentMonitors[i].Height);
    }
    [controller setPixelSize:NSMakeSize(maxX - minX, maxY - minY)];
    [controller desktopDidResize:nil];
}

static void CheckResolutionMenu(OrbisAppDelegate *delegate, NSMenu *menu)
{
    NSMenuItem *fullHD = nil, *hd = nil, *match = nil;
    for (NSMenuItem *item in menu.itemArray)
    {
        if ([item.title isEqualToString:@"1920 × 1080"]) fullHD = item;
        if ([item.title isEqualToString:@"1280 × 720"]) hd = item;
        if ([item.title isEqualToString:@"Match Mac Screen"]) match = item;
    }
    Require(fullHD && hd && match, "The Window menu must offer standard resolutions and screen matching");
    Require(![delegate validateMenuItem:fullHD], "Resolution choices must be disabled outside a remote session");
    for (OrbisMonitorArrangement side = OrbisMonitorRight; side <= OrbisMonitorBelow; side++)
    {
        OrbisDisplaySettings *settings = [[[OrbisDisplaySettings alloc] init] autorelease];
        settings.secondaryWidth = 1024; settings.secondaryHeight = 768;
        settings.arrangement = side; settings.offset = 120;
        [settings saveToDefaults:[NSUserDefaults standardUserDefaults]];
        NSDictionary *saved = [[[NSUserDefaults standardUserDefaults] objectForKey:@"OrbisDisplaySettings.v1"] copy];
        OrbisProfile *profile = [[[OrbisProfile alloc] init] autorelease]; profile.name = @"Resolution fixture";
        OrbisDisplayFixtureController *controller = [[OrbisDisplayFixtureController alloc] initWithProfile:profile
            password:nil transport:[[[OrbisDirectTransport alloc] init] autorelease]];
        [controller prepareFixture]; resolutionFixtureWindow = [controller primaryWindow];
        object_setIvar(delegate, class_getInstanceVariable([OrbisAppDelegate class], "_sessionController"), controller);
        Require(![delegate validateMenuItem:fullHD], "A session must wait for server display capabilities");
        DispClientContext channel = {0}; channel.SendMonitorLayout = CaptureLayout;
        [controller displayChannelConnected:&channel]; [controller displayControlCaps:1 area:8192ULL * 8192 * 2];
        Require([delegate validateMenuItem:fullHD], "A single-monitor server can resize its one display");
        [delegate menuNeedsUpdate:menu];
        Require([[menu itemAtIndex:0].title isEqualToString:@"Display 1: 1280 × 800"], "The menu identifies the focused output and actual dimensions");
        sentCount = 0;
        [NSApp sendAction:fullHD.action to:fullHD.target from:fullHD];
        Require(sentCount == 1 && sentMonitors[0].Width == 1920 && [controller isChanging], "Selecting a preset sends one layout on the existing connection");
        Require(NSEqualSizes([controller activeDisplayResolution], NSMakeSize(1280, 800)), "The selected resolution changes only after server confirmation");
        Require(![delegate validateMenuItem:hd], "Do not overlap requests while resizing");
        [controller setPixelSize:NSMakeSize(1400, 900)]; [controller desktopDidResize:nil];
        Require([controller isChanging], "An unrelated desktop resize cannot confirm the requested resolution");
        ConfirmResolution(controller);
        Require(NSEqualSizes([controller activeDisplayResolution], NSMakeSize(1920, 1080)), "The server-confirmed resolution becomes current");
        Require([delegate validateMenuItem:fullHD] && fullHD.state == NSControlStateValueOn, "The active preset has a checkmark");
        sentCount = 0; [NSApp sendAction:fullHD.action to:fullHD.target from:fullHD];
        Require(!sentCount && ![controller isChanging], "Selecting the current resolution does not send another request");
        for (NSValue *invalid in @[ [NSValue valueWithSize:NSMakeSize(1921, 1080)],
            [NSValue valueWithSize:NSMakeSize(9000, 1080)], [NSValue valueWithSize:NSMakeSize(1920.5, 1080)] ])
        {
            Require(![controller canSetActiveDisplayResolution:invalid.sizeValue], "Invalid dimensions cannot enter the live layout");
            [controller setActiveDisplayResolution:invalid.sizeValue];
        }
        Require(!sentCount && ![controller isChanging], "Invalid dimensions must not disturb the session");
        [controller displayControlCaps:1 area:1];
        Require(![delegate validateMenuItem:hd], "Presets beyond the server area limit are disabled");
        [controller displayControlCaps:2 area:8192ULL * 8192 * 2];
        [controller addVirtualDisplay:nil]; ConfirmResolution(controller);
        NSWindow *primary = [controller primaryWindow], *second = [controller secondWindow];
        resolutionFixtureWindow = second;
        Require([controller activeRemoteDisplayIndex] == 1, "The secondary window is an independent resolution target");
        [delegate menuNeedsUpdate:menu];
        Require([[menu itemAtIndex:0].title isEqualToString:@"Display 2: 1024 × 768"], "The menu follows focus to the second output");
        [NSApp sendAction:hd.action to:hd.target from:hd];
        Require(sentCount == 2 && sentMonitors[0].Width == 1920 && sentMonitors[0].Height == 1080 &&
            sentMonitors[1].Width == 1280 && sentMonitors[1].Height == 720, "Resizing the secondary preserves the primary");
        ConfirmResolution(controller);
        Require([controller secondWindow] == second && [controller primaryWindow] == primary && ![controller isStopped],
            "A live resize reuses both windows and keeps the connection open");
        resolutionFixtureWindow = primary;
        [controller setActiveDisplayResolution:NSMakeSize(1600, 900)];
        Require(sentMonitors[1].Width == 1280 && sentMonitors[1].Height == 720, "Resizing the primary preserves the secondary");
        ConfirmResolution(controller);
        OrbisDisplayLayout layout = [controller currentLayout];
        Require(layout.monitors[1].x == (side == OrbisMonitorRight ? 1600 : side == OrbisMonitorLeft ? -1280 : 120) &&
            layout.monitors[1].y == (side == OrbisMonitorAbove ? -720 : side == OrbisMonitorBelow ? 900 : 120),
            "Resolution changes preserve the arrangement and staggered alignment");
        [controller checkCapturedDrag];
        resolutionFixtureWindow = second;
        [controller setActiveDisplayResolution:NSMakeSize(1280, 800)]; ConfirmResolution(controller);
        Require(![controller isChanging] && [controller activeDisplayResolution].height == 800,
            "A pipeline reset can confirm a monitor resize even with unchanged aggregate bounds");
        [NSApp sendAction:fullHD.action to:fullHD.target from:fullHD];
        [controller displayChangeTimedOut:nil];
        Require([controller activeDisplayResolution].width == 1280 && controller.errorCount == 1 && sentCount == 2,
            "A rejected live resolution restores the previous layout and keeps its selection");
        Require(NSEqualSizes([controller activeScreenResolution], [[second screen] frame].size), "Match Mac Screen uses the selected window's local screen");
        [NSApp sendAction:match.action to:match.target from:match];
        if ([controller isChanging]) ConfirmResolution(controller);
        Require([[NSUserDefaults standardUserDefaults] objectForKey:@"OrbisDisplaySettings.v1"] &&
            [[[NSUserDefaults standardUserDefaults] objectForKey:@"OrbisDisplaySettings.v1"] isEqual:saved],
            "Live resolution changes do not overwrite saved initial display settings");
        resolutionFixtureWindow = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO] autorelease];
        Require(![delegate validateMenuItem:hd], "The library and unrelated windows are not remote resolution targets");
        resolutionFixtureWindow = nil; [controller stop];
        object_setIvar(delegate, class_getInstanceVariable([OrbisAppDelegate class], "_sessionController"), nil);
        [controller release]; [saved release];
    }
}

int main(void)
{
    @autoreleasepool
    {
        [OrbisResolutionApplication sharedApplication];
        pointerEvents = [[NSMutableArray alloc] init];
        id originalSettings = [[[NSUserDefaults standardUserDefaults] objectForKey:@"OrbisDisplaySettings.v1"] retain];
        OrbisAppDelegate *delegate = [[OrbisAppDelegate alloc] init];
        [delegate buildMainMenu];
        NSMenuItem *displayItem = nil;
        NSMenu *resolutionMenu = nil;
        for (NSMenuItem *root in [NSApp mainMenu].itemArray)
            for (NSMenuItem *item in root.submenu.itemArray)
                {
                    if ([item.title isEqualToString:@"Add Virtual Display"]) displayItem = item;
                    if ([item.title isEqualToString:@"Resolution"]) resolutionMenu = item.submenu;
                }
        Require(displayItem && [displayItem target] == delegate, "Add Virtual Display belongs in the native menu");
        Require(![delegate validateMenuItem:displayItem], "The menu action must be disabled outside a session");
        for (NSInteger arrangement = 0; arrangement < 4; arrangement++)
        {
            OrbisProfile *profile = [[OrbisProfile alloc] init];
            profile.name = @"Fixture";
            profile.secondaryWidth = 1024; profile.secondaryHeight = 768;
            profile.monitorArrangement = (OrbisMonitorArrangement)arrangement;
            OrbisDisplaySettings *settings = [[[OrbisDisplaySettings alloc] init] autorelease];
            settings.secondaryWidth = 1024; settings.secondaryHeight = 768;
            settings.arrangement = (OrbisMonitorArrangement)arrangement;
            settings.offset = (int32_t)(arrangement * 100 - 150);
            [settings saveToDefaults:[NSUserDefaults standardUserDefaults]];
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
            OrbisDisplayLayoutMakeWithOffset(1280, 800, 1024, 768, settings.arrangement, settings.offset, true, &expected);
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
        CheckResolutionMenu(delegate, resolutionMenu);
        [delegate release]; [pointerEvents release];
        if (originalSettings) [[NSUserDefaults standardUserDefaults] setObject:originalSettings forKey:@"OrbisDisplaySettings.v1"];
        else [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"OrbisDisplaySettings.v1"];
        [originalSettings release];
        printf("%s: virtual display session lifecycle\n", failures ? "FAIL" : "PASS");
        return failures ? 1 : 0;
    }
}
