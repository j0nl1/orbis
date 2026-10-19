/* SPDX-License-Identifier: MIT */
#import <AppKit/AppKit.h>
#import "MRDPView.h"
#import "Clipboard.h"
#import "OrbisClipboardImage.h"

static NSUInteger failures, requests, lists, successfulResponses;
static NSData *sentData;
static UINT16 sentFlags;
static void Require(BOOL value, const char *message)
{
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); failures++; }
}
static UINT ListResponse(CliprdrClientContext *ctx, const CLIPRDR_FORMAT_LIST_RESPONSE *response)
{ (void)ctx; (void)response; return CHANNEL_RC_OK; }
static UINT Request(CliprdrClientContext *ctx, const CLIPRDR_FORMAT_DATA_REQUEST *request)
{ (void)ctx; (void)request; requests++; return CHANNEL_RC_OK; }
static UINT Response(CliprdrClientContext *ctx, const CLIPRDR_FORMAT_DATA_RESPONSE *response)
{
    (void)ctx; [sentData release];
    sentData = [[NSData alloc] initWithBytes:response->requestedFormatData length:response->common.dataLen];
    sentFlags = response->common.msgFlags;
    if ((sentFlags & CB_RESPONSE_OK) && sentData.length) successfulResponses++;
    return CHANNEL_RC_OK;
}
static UINT List(CliprdrClientContext *ctx, const CLIPRDR_FORMAT_LIST *list)
{ (void)ctx; (void)list; lists++; return CHANNEL_RC_OK; }

@interface OrbisClipboardTestView : MRDPView
{
    mfContext fixture;
    CliprdrClientContext channel;
}
- (mfContext *)fixtureContext;
@end
@implementation OrbisClipboardTestView
- (id)init
{
    if (!(self = [super initWithFrame:NSMakeRect(0, 0, 100, 100)])) return nil;
    mfc = &fixture; fixture.view = self;
    pasteboard_rd = [[NSPasteboard pasteboardWithUniqueName] retain];
    pasteboard_wr = pasteboard_rd;
    pasteboard_changecount = (int)pasteboard_rd.changeCount;
    is_connected = 1;
    OrbisSessionCapabilities *capabilities = [[[OrbisSessionCapabilities alloc] init] autorelease];
    [self setSessionCapabilities:capabilities generation:[capabilities beginSession]];
    mac_cliprdr_init(mfc, &channel);
    channel.ClientFormatListResponse = ListResponse;
    channel.ClientFormatDataRequest = Request;
    channel.ClientFormatDataResponse = Response;
    channel.ClientFormatList = List;
    mfc->clipboardSync = TRUE;
    [self setClipboardChannelReady:YES];
    return self;
}
- (mfContext *)fixtureContext { return mfc; }
- (void)dealloc
{
    for (UINT32 i = 0; i < mfc->numServerFormats; i++) free(mfc->serverFormats[i].formatName);
    free(mfc->serverFormats);
    mac_cliprdr_uninit(mfc, &channel);
    [pasteboard_rd releaseGlobally]; [pasteboard_rd release];
    [super dealloc];
}
@end

static UINT Advertise(mfContext *ctx, UINT32 format)
{
    CLIPRDR_FORMAT item = { .formatId = format };
    CLIPRDR_FORMAT_LIST list = { .numFormats = format ? 1 : 0, .formats = &item };
    return ctx->cliprdr->ServerFormatList(ctx->cliprdr, &list);
}
static UINT Deliver(mfContext *ctx, NSData *data)
{
    CLIPRDR_FORMAT_DATA_RESPONSE response = { .common = { .msgFlags = CB_RESPONSE_OK,
        .dataLen = (UINT32)data.length }, .requestedFormatData = data.bytes };
    return ctx->cliprdr->ServerFormatDataResponse(ctx->cliprdr, &response);
}
static void DrainMainQueue(void)
{
    __block BOOL drained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    while (!drained) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
}

int main(int argc, const char **argv)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        OrbisClipboardTestView *view = [[OrbisClipboardTestView alloc] init];
        mfContext *ctx = view.fixtureContext;
        OrbisSessionCapability *initialImage = [view->sessionCapabilities.snapshot
            capabilityForFeature:OrbisSessionFeatureClipboardImage direction:OrbisCapabilityDirectionFromRemote];
        Require(initialImage.state == OrbisCapabilityStateChecking && initialImage.canAttempt,
            "Clipboard channel readiness permits an image attempt without claiming peer image support");
        if (argc > 1 && strcmp(argv[1], "--stress") == 0) {
            NSString *payload = [@"large text\n" stringByPaddingToLength:1024 * 1024
                withString:@"large text\n" startingAtIndex:0];
            [view->pasteboard_rd clearContents];
            Require([view->pasteboard_rd setString:payload forType:NSPasteboardTypeString],
                "The stress fixture must publish its large input");
            [view onPasteboardTimerFired:nil];
            CLIPRDR_FORMAT_DATA_REQUEST initialRequest = { .requestedFormatId = CF_UNICODETEXT };
            ctx->cliprdr->ServerFormatDataRequest(ctx->cliprdr, &initialRequest);
            Require((sentFlags & CB_RESPONSE_OK) && sentData.length > payload.length,
                "The stress fixture must exercise a real large clipboard conversion");
            dispatch_group_t group = dispatch_group_create();
            dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                @autoreleasepool {
                    CLIPRDR_FORMAT_DATA_REQUEST request = { .requestedFormatId = CF_UNICODETEXT };
                    for (NSUInteger i = 0; i < 1000; i++)
                        ctx->cliprdr->ServerFormatDataRequest(ctx->cliprdr, &request);
                }
            });
            for (NSUInteger i = 0; i < 100; i++) {
                @autoreleasepool {
                    [view->pasteboard_rd clearContents];
                    Require([view->pasteboard_rd setString:payload forType:NSPasteboardTypeString],
                        "Every stress iteration must supply large text to the shared buffer");
                    [view onPasteboardTimerFired:nil];
                }
            }
            Require(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)) == 0,
                "Concurrent large copies must finish without a clipboard lock deadlock");
            Require(successfulResponses == 1001,
                "Every concurrent read must return complete text while the local buffer changes");
            dispatch_release(group);
            [view release]; [sentData release];
            return failures ? 1 : 0;
        }
        NSString *large = [@"Clipboard @ é\n" stringByPaddingToLength:2 * 1024 * 1024
            withString:@"Clipboard @ é\n" startingAtIndex:0];
        NSData *remote = [large dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
        Require(Advertise(ctx, CF_UNICODETEXT) == CHANNEL_RC_OK, "Remote text must request data");
        Require(Deliver(ctx, remote) == CHANNEL_RC_OK, "Large remote text must keep the channel alive");
        DrainMainQueue();
        Require([[view->pasteboard_wr stringForType:NSPasteboardTypeString] isEqualToString:large],
            "Large remote text must reach the isolated Mac pasteboard intact");
        NSUInteger priorLists = lists;
        [view onPasteboardTimerFired:nil];
        Require(lists == priorLists, "Publishing remote text must not echo a new clipboard offer");

        [view->pasteboard_rd clearContents];
        [view->pasteboard_rd setString:large forType:NSPasteboardTypeString];
        [view onPasteboardTimerFired:nil];
        CLIPRDR_FORMAT_DATA_REQUEST request = { .requestedFormatId = CF_UNICODETEXT };
        Require(ctx->cliprdr->ServerFormatDataRequest(ctx->cliprdr, &request) == CHANNEL_RC_OK,
            "Large local text must keep the channel alive");
        NSString *roundTrip = [[[NSString alloc] initWithData:sentData
            encoding:NSUTF16LittleEndianStringEncoding] autorelease];
        Require((sentFlags & CB_RESPONSE_OK) && [[roundTrip stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] hasPrefix:large],
            "Large local text must reach the remote response intact");

        // An image can replace a text offer before its outstanding response arrives.
        Advertise(ctx, CF_UNICODETEXT);
        NSUInteger priorRequests = requests;
        Advertise(ctx, 0xBEEF);
        Require(Deliver(ctx, remote) == CHANNEL_RC_OK,
            "A text response after an image offer must never disconnect RDP");
        DrainMainQueue();
        Require(requests == priorRequests, "Unsupported format data must not be requested");

        // CLIPRDR responses have no request ID, so requests must remain serialized.
        Advertise(ctx, CF_UNICODETEXT);
        priorRequests = requests;
        Advertise(ctx, CF_TEXT);
        Require(requests == priorRequests, "A second text offer must wait for the outstanding response");
        Require(Deliver(ctx, remote) == CHANNEL_RC_OK, "An obsolete text response must remain nonfatal");
        Require(requests == priorRequests + 1, "The latest text offer must be requested after draining the old response");
        const char ascii[] = "latest";
        Deliver(ctx, [NSData dataWithBytes:ascii length:sizeof(ascii)]);
        DrainMainQueue();
        Require([[view->pasteboard_wr stringForType:NSPasteboardTypeString] isEqualToString:@"latest"],
            "The latest response must use its own format");

        [view->pasteboard_rd clearContents];
        [view->pasteboard_rd setData:[NSData dataWithBytes:"image" length:5] forType:NSPasteboardTypePNG];
        [view onPasteboardTimerFired:nil];
        ctx->cliprdr->ServerFormatDataRequest(ctx->cliprdr, &request);
        Require((sentFlags & CB_RESPONSE_FAIL) && !sentData.length,
            "A local image must reject a stale text request without killing the channel");

        // A bounded transparent PNG travels through the real channel callbacks.
        NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
            pixelsWide:3 pixelsHigh:2 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
            colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:12 bitsPerPixel:32] autorelease];
        memset(bitmap.bitmapData, 0, 24);
        unsigned char *pixels = bitmap.bitmapData;
        pixels[0] = 255; pixels[3] = 255; pixels[5] = 255; pixels[7] = 128;
        pixels[14] = 255; pixels[15] = 255;
        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [view->pasteboard_rd clearContents];
        [view->pasteboard_rd setData:png forType:NSPasteboardTypePNG];
        [view onPasteboardTimerFired:nil];
        request.requestedFormatId = ClipboardRegisterFormat(ctx->clipboard, "image/png");
        ctx->cliprdr->ServerFormatDataRequest(ctx->cliprdr, &request);
        Require((sentFlags & CB_RESPONSE_OK) && [OrbisClipboardImageCodec normalizedPNGData:sentData] != nil,
            "Local PNG must be served to the real RDP image request");
        request.requestedFormatId = ClipboardRegisterFormat(ctx->clipboard, "PNG");
        ctx->cliprdr->ServerFormatDataRequest(ctx->cliprdr, &request);
        Require((sentFlags & CB_RESPONSE_OK) && sentData.length,
            "Windows PNG alias must serve the same image");
        request.requestedFormatId = CF_DIB;
        ctx->cliprdr->ServerFormatDataRequest(ctx->cliprdr, &request);
        Require((sentFlags & CB_RESPONSE_OK) && [OrbisClipboardImageCodec PNGDataFromDIBData:sentData] != nil,
            "Classic DIB fallback must be decodable");
        NSData *dib = [[sentData copy] autorelease];
        CLIPRDR_FORMAT imageFormat = { .formatId=0xC012, .formatName="PNG" };
        CLIPRDR_FORMAT_LIST imageList = { .numFormats=1, .formats=&imageFormat };
        ctx->cliprdr->ServerFormatList(ctx->cliprdr, &imageList);
        Deliver(ctx, png); DrainMainQueue();
        Require([view->pasteboard_wr dataForType:NSPasteboardTypePNG].length > 0,
            "Remote PNG must reach the isolated Mac pasteboard");
        priorLists = lists; [view onPasteboardTimerFired:nil];
        Require(lists == priorLists, "Remote image publication must not echo to the server");
        Advertise(ctx, CF_DIB); Deliver(ctx, dib); DrainMainQueue();
        Require([view->pasteboard_wr dataForType:NSPasteboardTypePNG].length > 0,
            "Remote DIB must reach the isolated Mac pasteboard as PNG");
        NSData *beforeInvalid = [view->pasteboard_wr dataForType:NSPasteboardTypePNG];
        ctx->cliprdr->ServerFormatList(ctx->cliprdr, &imageList);
        Deliver(ctx, [NSData dataWithBytes:"broken" length:6]); DrainMainQueue();
        Require([[view->pasteboard_wr dataForType:NSPasteboardTypePNG] isEqual:beforeInvalid],
            "Malformed image must preserve existing clipboard without closing RDP");
        Advertise(ctx, CF_UNICODETEXT);
        ctx->cliprdr->ServerFormatList(ctx->cliprdr, &imageList);
        priorRequests = requests;
        Deliver(ctx, remote);
        Require(requests == priorRequests + 1, "Latest image waits for stale text response");
        Deliver(ctx, png); DrainMainQueue();
        Require([view->pasteboard_wr dataForType:NSPasteboardTypePNG].length > 0,
            "Text-to-image ownership transition must publish the latest format");
        NSBitmapImageRep *largeBitmap = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
            pixelsWide:1024 pixelsHigh:1024 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
            colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:4096 bitsPerPixel:32] autorelease];
        uint32_t seed = 12345;
        for (NSUInteger i = 0; i < 1024 * 1024; i++) {
            seed = seed * 1664525u + 1013904223u;
            largeBitmap.bitmapData[i * 4] = seed >> 24;
            largeBitmap.bitmapData[i * 4 + 1] = seed >> 16;
            largeBitmap.bitmapData[i * 4 + 2] = seed >> 8;
            largeBitmap.bitmapData[i * 4 + 3] = 255;
        }
        NSData *largePNG = [largeBitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        Require(largePNG.length > 1024 * 1024, "Large PNG fixture must exceed a megabyte");
        [view->pasteboard_rd clearContents];
        [view->pasteboard_rd setData:largePNG forType:NSPasteboardTypePNG];
        [view onPasteboardTimerFired:nil];
        request.requestedFormatId = ClipboardRegisterFormat(ctx->clipboard, "PNG");
        ctx->cliprdr->ServerFormatDataRequest(ctx->cliprdr, &request);
        Require((sentFlags & CB_RESPONSE_OK) && sentData.length > 1024 * 1024,
            "A real outgoing image request must return the complete multi-megabyte PNG");
        ctx->cliprdr->ServerFormatList(ctx->cliprdr, &imageList);
        Deliver(ctx, largePNG); DrainMainQueue();
        NSBitmapImageRep *receivedLarge = [NSBitmapImageRep imageRepWithData:
            [view->pasteboard_wr dataForType:NSPasteboardTypePNG]];
        Require(receivedLarge.pixelsWide == 1024 && receivedLarge.pixelsHigh == 1024,
            "A multi-megabyte remote PNG must reach AppKit at full resolution");

        OrbisSessionCapability *receivedImage = [view->sessionCapabilities.snapshot
            capabilityForFeature:OrbisSessionFeatureClipboardImage direction:OrbisCapabilityDirectionFromRemote];
        Require(receivedImage.state == OrbisCapabilityStateAvailable,
            "A decoded remote image refines only its transfer direction");
        OrbisSessionCapabilityFacts restricted = receivedImage.facts;
        restricted.explicitlyRestricted = YES;
        [view->sessionCapabilities updateFeature:OrbisSessionFeatureClipboardImage
            direction:OrbisCapabilityDirectionFromRemote facts:restricted limits:receivedImage.limits
            forGeneration:view->sessionCapabilityGeneration];
        priorRequests = requests;
        ctx->cliprdr->ServerFormatList(ctx->cliprdr, &imageList);
        Require(requests == priorRequests, "Explicitly restricted image reception must not request data");
        OrbisSessionCapability *outgoing = [view->sessionCapabilities.snapshot
            capabilityForFeature:OrbisSessionFeatureClipboardImage direction:OrbisCapabilityDirectionToRemote];
        restricted = outgoing.facts; restricted.enabled = NO;
        [view->sessionCapabilities updateFeature:OrbisSessionFeatureClipboardImage
            direction:OrbisCapabilityDirectionToRemote facts:restricted limits:outgoing.limits
            forGeneration:view->sessionCapabilityGeneration];
        request.requestedFormatId = ClipboardRegisterFormat(ctx->clipboard, "PNG");
        ctx->cliprdr->ServerFormatDataRequest(ctx->cliprdr, &request);
        Require((sentFlags & CB_RESPONSE_FAIL) && !sentData.length,
            "A disabled outgoing image capability rejects even an existing image request");
        [view release]; [sentData release];
        fprintf(stderr, "Clipboard boundary failures: %lu\n", (unsigned long)failures);
    }
    return failures ? 1 : 0;
}
