/* SPDX-License-Identifier: MIT */
#import <AppKit/AppKit.h>
#import "OrbisMacClipboard.h"
#import "OrbisClipboardImage.h"
#import <ImageIO/ImageIO.h>

static unsigned failures;
static void Require(BOOL value, const char *message)
{ if (!value) { fprintf(stderr, "FAIL: %s\n", message); failures++; } }
static NSData *PNG(NSUInteger width, NSUInteger height)
{
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
        isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:width * 4 bitsPerPixel:32] autorelease];
    for (NSUInteger y=0; y<height; y++) for (NSUInteger x=0; x<width; x++) {
        unsigned char *p = bitmap.bitmapData + (y * width + x) * 4;
        p[0]=(x * 31 + y * 17) & 255; p[1]=(x * 13 + y * 67) & 255;
        p[2]=(x * 71 + y * 19) & 255; p[3]=255;
    }
    return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}
static BOOL SamePixels(NSData *a, NSData *b)
{
    NSBitmapImageRep *left = [NSBitmapImageRep imageRepWithData:a], *right = [NSBitmapImageRep imageRepWithData:b];
    if (!left || !right || left.pixelsWide != right.pixelsWide || left.pixelsHigh != right.pixelsHigh) return NO;
    for (NSInteger y=0; y<left.pixelsHigh; y++) for (NSInteger x=0; x<left.pixelsWide; x++) {
        NSColor *l = [[left colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
        NSColor *r = [[right colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
        if (fabs(l.redComponent-r.redComponent)>0.02 || fabs(l.greenComponent-r.greenComponent)>0.02 ||
            fabs(l.blueComponent-r.blueComponent)>0.02 || fabs(l.alphaComponent-r.alphaComponent)>0.02) return NO;
    }
    return YES;
}
int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSData *small = PNG(7, 3);
        NSData *normalized = [OrbisClipboardImageCodec normalizedPNGData:small];
        Require(SamePixels(small, normalized), "PNG normalization preserves every asymmetric pixel");
        NSData *dib = [OrbisClipboardImageCodec DIBDataFromPNGData:small];
        Require(SamePixels(small, [OrbisClipboardImageCodec PNGDataFromDIBData:dib]),
            "Opaque DIB roundtrip preserves row orientation and color channels");
        NSMutableData *truncated = [[dib mutableCopy] autorelease];
        [truncated setLength:truncated.length - 1];
        Require(![OrbisClipboardImageCodec PNGDataFromDIBData:truncated], "Truncated DIB is rejected");
        NSMutableData *badDimensions = [[dib mutableCopy] autorelease];
        memset((uint8_t *)badDimensions.mutableBytes + 4, 0x7f, 4);
        Require(![OrbisClipboardImageCodec PNGDataFromDIBData:badDimensions], "DIB dimensions are bounded before decode");
        NSMutableData *palette = [NSMutableData dataWithLength:40];
        uint8_t *header = palette.mutableBytes;
        header[0]=40; header[4]=1; header[8]=1; header[12]=1; header[14]=8;
        Require(![OrbisClipboardImageCodec PNGDataFromDIBData:palette], "Missing DIB palette and pixel rows are rejected");
        Require(![OrbisClipboardImageCodec normalizedPNGData:PNG(16385, 1)],
            "A valid image beyond the dimension limit is rejected");
        CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)small, NULL);
        CGImageRef original = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        NSMutableData *orientedTIFF = [NSMutableData data];
        CGImageDestinationRef destination = CGImageDestinationCreateWithData((CFMutableDataRef)orientedTIFF,
            CFSTR("public.tiff"), 1, NULL);
        CGImageDestinationAddImage(destination, original, (CFDictionaryRef)@{(id)kCGImagePropertyOrientation:@6});
        Require(CGImageDestinationFinalize(destination), "Oriented TIFF fixture must encode");
        CFRelease(destination); CGImageRelease(original); CFRelease(source);
        NSBitmapImageRep *oriented = [NSBitmapImageRep imageRepWithData:
            [OrbisClipboardImageCodec normalizedPNGData:orientedTIFF]];
        Require(oriented.pixelsWide == 3 && oriented.pixelsHigh == 7,
            "Image orientation is applied before source metadata is removed");
        NSData *large = PNG(2048, 1024);
        Require([OrbisClipboardImageCodec normalizedPNGData:large] != nil,
            "Large screenshot-sized images remain supported");
        NSBitmapImageRep *alpha = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
            pixelsWide:2 pixelsHigh:1 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
            colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:8 bitsPerPixel:32] autorelease];
        unsigned char transparent[] = {255, 0, 0, 128, 0, 0, 0, 0};
        memcpy(alpha.bitmapData, transparent, 8);
        NSData *transparentPNG = [alpha representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        Require(SamePixels(transparentPNG, [OrbisClipboardImageCodec normalizedPNGData:transparentPNG]),
            "PNG transparency survives normalization");
        NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
        OrbisMacClipboard *adapter = [[[OrbisMacClipboard alloc] initWithPasteboard:pasteboard] autorelease];
        OrbisClipboardContent *image = [[[OrbisClipboardContent alloc] initWithText:nil pngData:transparentPNG] autorelease];
        Require([adapter publishContent:image] && SamePixels(adapter.readContent.pngData, transparentPNG),
            "Real AppKit adapter publishes and reads transparent PNG");
        uint8_t signature[] = {137,80,78,71,13,10,26,10,0};
        OrbisClipboardContent *invalid = [[[OrbisClipboardContent alloc] initWithText:nil
            pngData:[NSData dataWithBytes:signature length:sizeof(signature)]] autorelease];
        Require(![adapter publishContent:invalid] && SamePixels(adapter.readContent.pngData, transparentPNG),
            "Malformed PNG publication preserves current pasteboard");
        NSData *tiff = [alpha representationUsingType:NSBitmapImageFileTypeTIFF properties:@{}];
        [pasteboard clearContents]; [pasteboard setData:tiff forType:NSPasteboardTypeTIFF];
        Require(SamePixels(adapter.readContent.pngData, transparentPNG), "Native TIFF clipboard becomes interoperable PNG");
        [pasteboard releaseGlobally];
        fprintf(stderr, "Image clipboard failures: %u\n", failures);
    }
    return failures ? 1 : 0;
}
