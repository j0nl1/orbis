/* SPDX-License-Identifier: MIT */

#import <AppKit/AppKit.h>
#import "MRDPView.h"
#import "Clipboard.h"
#include <pthread.h>

// Replace the OS pasteboard only; the RDP callbacks, view observer, and WinPR
// storage/conversion are production code. Never overwrite the user's clipboard.
@interface OrbisClipboardPasteboard : NSObject
@property(nonatomic, retain) NSData *localData;
@property(nonatomic, copy) NSString *remoteText;
@property(nonatomic) NSInteger generation;
@property(nonatomic) BOOL wroteOffMainThread;
@end
@implementation OrbisClipboardPasteboard
@synthesize localData, remoteText, generation, wroteOffMainThread;
- (NSInteger)changeCount { return generation; }
- (NSArray *)pasteboardItems { return @[self]; }
- (NSArray *)types { return @[NSPasteboardTypeString]; }
- (NSData *)dataForType:(NSString *)type { (void)type; return localData; }
- (NSInteger)declareTypes:(NSArray *)types owner:(id)owner
{ (void)types; (void)owner; return ++generation; }
- (BOOL)setString:(NSString *)text forType:(NSString *)type
{
    (void)type;
    if (![NSThread isMainThread]) wroteOffMainThread = YES;
    self.remoteText = text;
    generation++;
    return YES;
}
- (void)dealloc { [localData release]; [remoteText release]; [super dealloc]; }
@end

@interface OrbisClipboardView : MRDPView
- (instancetype)initWithContext:(mfContext *)fixture;
@end
@implementation OrbisClipboardView
- (instancetype)initWithContext:(mfContext *)fixture
{
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 800, 600)])) {
        mfc = fixture;
        fixture->view = self;
        self.is_connected = YES;
    }
    return self;
}
@end

static void Require(BOOL condition, const char *message)
{
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static UINT Acknowledge(CliprdrClientContext *c, const CLIPRDR_FORMAT_LIST_RESPONSE *r)
{ (void)c; (void)r; return CHANNEL_RC_OK; }
static UINT Request(CliprdrClientContext *c, const CLIPRDR_FORMAT_DATA_REQUEST *r)
{ (void)c; (void)r; return CHANNEL_RC_OK; }
static UINT Advertise(CliprdrClientContext *c, const CLIPRDR_FORMAT_LIST *r)
{ (void)c; (void)r; return CHANNEL_RC_OK; }

typedef struct {
    CliprdrClientContext *channel;
    CLIPRDR_FORMAT_DATA_RESPONSE response;
} ClipboardWorker;

static void *ReceiveLargeText(void *opaque)
{
    ClipboardWorker *worker = opaque;
    @autoreleasepool {
        for (int n = 0; n < 32; n++)
            Require(worker->channel->ServerFormatDataResponse(worker->channel, &worker->response)
                == CHANNEL_RC_OK, "large clipboard response ended the channel");
    }
    return NULL;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        mfContext context = {0};
        CliprdrClientContext channel = {0};
        OrbisClipboardView *view = [[OrbisClipboardView alloc] initWithContext:&context];
        OrbisClipboardPasteboard *pasteboard = [OrbisClipboardPasteboard new];
        view->pasteboard_rd = view->pasteboard_wr = (NSPasteboard *)pasteboard;
        mac_cliprdr_init(&context, &channel);
        channel.ClientFormatListResponse = Acknowledge;
        channel.ClientFormatDataRequest = Request;
        channel.ClientFormatList = Advertise;
        context.clipboardSync = TRUE;
        CLIPRDR_FORMAT format = { .formatId = CF_UNICODETEXT };
        CLIPRDR_FORMAT_LIST list = { .numFormats = 1, .formats = &format };
        Require(channel.ServerFormatList(&channel, &list) == CHANNEL_RC_OK, "format negotiation failed");

        const NSUInteger characters = 2 * 1024 * 1024;
        NSMutableData *remote = [NSMutableData dataWithLength:(characters + 1) * sizeof(WCHAR)];
        WCHAR *utf16 = remote.mutableBytes;
        for (NSUInteger n = 0; n < characters; n++) utf16[n] = 'a';
        NSMutableData *local = [NSMutableData dataWithLength:characters];
        memset(local.mutableBytes, 'b', characters);
        pasteboard.localData = local;
        ClipboardWorker worker = { .channel = &channel };
        worker.response.common.msgFlags = CB_RESPONSE_OK;
        worker.response.common.dataLen = (UINT32)remote.length;
        worker.response.requestedFormatData = remote.bytes;
        pthread_t thread;
        Require(pthread_create(&thread, NULL, ReceiveLargeText, &worker) == 0, "worker creation failed");
        // The main-thread observer races with the actual RDP channel callback.
        for (NSUInteger n = 0; n < 64; n++) {
            pasteboard.generation++;
            [view onPasteboardTimerFired:nil];
        }
        pthread_join(thread, NULL);
        // Deliver queued remote clipboard publication on the main run loop.
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (pasteboard.remoteText.length != characters && [deadline timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        Require(!pasteboard.wroteOffMainThread, "remote pasteboard was written off the main thread");
        Require(pasteboard.remoteText.length == characters, "large remote text was lost or truncated");
        Require([pasteboard.remoteText characterAtIndex:0] == 'a' &&
            [pasteboard.remoteText characterAtIndex:characters - 1] == 'a', "remote text was replaced by local text");
        Require(view->pasteboard_changecount == pasteboard.generation, "remote copy would echo back to the server");

        CLIPRDR_FORMAT_DATA_RESPONSE rejected = {0};
        rejected.common.msgFlags = CB_RESPONSE_FAIL;
        Require(channel.ServerFormatDataResponse(&channel, &rejected) == CHANNEL_RC_OK,
            "clipboard rejection ended the session");
        Require(WaitForSingleObject(context.clipboardRequestEvent, 0) == WAIT_OBJECT_0,
            "clipboard rejection did not wake the requester");
        view.is_connected = NO;
        mac_cliprdr_uninit(&context, &channel);
        [view release];
        [pasteboard release];
        puts("PASS: concurrent multi-megabyte clipboard transfer and main-thread publication");
    }
    return 0;
}

// Shared MRDPView source properties record pointer output in the keyboard target.
void OrbisRecordMouseButton(void *context, int button, int x, int y, BOOL down)
{ (void)context; (void)button; (void)x; (void)y; (void)down; }
BOOL OrbisRecordDisplayPointer(rdpClientContext *context, BOOL relative, UINT16 flags, INT32 x, INT32 y)
{ (void)context; (void)relative; (void)flags; (void)x; (void)y; return TRUE; }
BOOL OrbisRecordExtendedDisplayPointer(rdpClientContext *context, BOOL relative, UINT16 flags, INT32 x, INT32 y)
{ return OrbisRecordDisplayPointer(context, relative, flags, x, y); }
