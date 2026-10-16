/* SPDX-License-Identifier: MIT */
#import <AppKit/AppKit.h>
#import <freerdp/client.h>
#import <freerdp/freerdp.h>
#import "mf_client.h"
#import "mfreerdp.h"
#import "OrbisSessionController.h"
#import "OrbisRemoteView.h"
#import "OrbisDiagnostics.h"
#import "OrbisProfile.h"
#import "OrbisDirectTransport.h"

@interface OrbisSessionController (DiagnosticsTests)
- (OrbisDiagnostics *)diagnostics;
- (void)handleSessionEnded;
- (BOOL)beginConnection;
@end

@interface OrbisDiagnosticSessionFixture : OrbisSessionController
@property(nonatomic, retain) OrbisDiagnostics *recorder;
- (BOOL)prepareContext;
- (BOOL)prepareKeyboardConnection;
@end
@implementation OrbisDiagnosticSessionFixture
@synthesize recorder;
- (OrbisDiagnostics *)diagnostics { return recorder; }
- (BOOL)prepareContext
{
    RDP_CLIENT_ENTRY_POINTS entry = { 0 };
    entry.Size = sizeof(entry); entry.Version = RDP_CLIENT_INTERFACE_VERSION;
    RdpClientEntry(&entry);
    _context = freerdp_client_context_new(&entry);
    if (!_context) return NO;
    ((mfContext *)_context)->view_ownership = FALSE;
    _wasConnected = YES;
    _transportDiagnosticID = 42;
    freerdp_set_last_error((rdpContext *)_context, FREERDP_ERROR_CONNECT_TRANSPORT_FAILED);
    return YES;
}
- (BOOL)prepareKeyboardConnection
{
    _transportPrepared = YES;
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [_window setReleasedWhenClosed:NO];
    _remoteView = [[OrbisRemoteView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    [_window.contentView addSubview:_remoteView];
    return [self beginConnection];
}
- (void)dealloc
{
    // Stop while the injected recorder is still alive.
    [self stop]; [recorder release]; recorder = nil;
    [super dealloc];
}
@end

static NSUInteger clientStartCalls;
static BOOL clientStartUnicodeInput;
// Keep production context creation and argument parsing; stop at the network boundary.
int OrbisTestClientStart(rdpContext *context)
{
    clientStartCalls++;
    clientStartUnicodeInput = freerdp_settings_get_bool(context->settings, FreeRDP_UnicodeInput);
    return 0;
}
static NSUInteger failures;
static void Check(BOOL condition, const char *message)
{
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); failures++; }
}
static NSArray *Events(OrbisDiagnostics *diagnostics, NSURL *root)
{
    NSURL *url = [diagnostics exportToDirectory:root error:nil];
    return [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url]
        options:0 error:nil][@"events"];
}
static NSDictionary *Find(NSArray *events, NSString *name)
{
    for (NSDictionary *event in events) if ([event[@"event"] isEqualToString:name]) return event;
    return nil;
}

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        NSURL *keyboardRoot = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
            URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
        OrbisDiagnostics *keyboardRecorder = [[OrbisDiagnostics alloc] initWithDirectoryURL:keyboardRoot];
        OrbisProfile *keyboardProfile = [[OrbisProfile alloc] init];
        keyboardProfile.host = @"127.0.0.1"; keyboardProfile.port = 3389;
        OrbisDiagnosticSessionFixture *keyboard = [[OrbisDiagnosticSessionFixture alloc]
            initWithProfile:keyboardProfile password:nil transport:[[[OrbisDirectTransport alloc] init] autorelease]];
        keyboard.recorder = keyboardRecorder;
        Check([keyboard prepareKeyboardConnection],
            "The production session arguments must parse successfully");
        Check(clientStartCalls == 1,
            "Keyboard regression must reach the network boundary exactly once");
        Check(clientStartUnicodeInput,
            "The production command-line parser must retain Unicode input for Option symbols");
        [keyboard stop]; [keyboard release]; [keyboardProfile release]; [keyboardRecorder release];
        [NSFileManager.defaultManager removeItemAtURL:keyboardRoot error:nil];
        for (NSUInteger mode = 0; mode < 3; mode++)
        {
            NSURL *root = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
            OrbisDiagnostics *recorder = [[OrbisDiagnostics alloc] initWithDirectoryURL:root];
            OrbisProfile *profile = [[OrbisProfile alloc] init];
            OrbisDirectTransport *transport = [[OrbisDirectTransport alloc] init];
            OrbisDiagnosticSessionFixture *controller = [[OrbisDiagnosticSessionFixture alloc]
                initWithProfile:profile password:nil transport:transport];
            controller.recorder = recorder;
            Check([controller prepareContext], "The fixture must create a real native RDP context");
            if (mode == 0) [controller stop];
            if (mode == 1) [controller handleSessionEnded];
            if (mode == 2)
            {
                [controller observeValueForKeyPath:@"is_connected" ofObject:nil
                    change:@{ NSKeyValueChangeNewKey : @NO } context:NULL];
                NSArray *before = Events(recorder, root);
                NSDictionary *snapshot = Find(before, @"session.rdp_stopped");
                Check([snapshot[@"values"][@"rdp_error"] unsignedIntValue] == FREERDP_ERROR_CONNECT_TRANSPORT_FAILED,
                    "The worker notification must preserve the native error before teardown");
                Check(Find(before, @"session.stopping") == nil,
                    "The snapshot must precede asynchronous main-queue teardown");
                NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
                while (!Find(Events(recorder, root), @"session.disconnected") && deadline.timeIntervalSinceNow > 0)
                    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            }
            [controller stop];
            NSArray *events = Events(recorder, root);
            NSDictionary *stopping = Find(events, @"session.stopping");
            NSDictionary *ended = Find(events, @"session.disconnected");
            Check(stopping && ended, "Every completed stop must retain both lifecycle events");
            Check([stopping[@"values"][@"rdp_error"] unsignedIntValue] == FREERDP_ERROR_CONNECT_TRANSPORT_FAILED,
                "Stop must preserve errors before disposing the native context");
            Check([ended[@"values"][@"intentional"] boolValue] == (mode == 0),
                "Only an explicit local stop may be labelled intentional");
            Check([ended[@"values"][@"transport_id"] unsignedIntValue] == 42,
                "The RDP lifecycle must retain its tunnel correlation identifier");
            NSUInteger stops = 0;
            for (NSDictionary *event in events) if ([event[@"event"] isEqualToString:@"session.stopping"]) stops++;
            Check(stops == 1, "Repeated stop calls must not duplicate the final diagnosis");
            [controller release]; [transport release]; [profile release]; [recorder release];
            [NSFileManager.defaultManager removeItemAtURL:root error:nil];
        }
    }
    if (!failures) puts("PASS: native RDP error preservation, correlation, and stop attribution");
    return failures ? 1 : 0;
}
