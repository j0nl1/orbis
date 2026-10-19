/* SPDX-License-Identifier: MIT */
#import "OrbisClipboardImage.h"
#import "OrbisClipboardPort.h"
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>

static BOOL DimensionsAllowed(uint64_t width, uint64_t height)
{
    return width && height && width <= OrbisClipboardMaximumImageDimension &&
        height <= OrbisClipboardMaximumImageDimension &&
        width * height <= OrbisClipboardMaximumImagePixels;
}
static CGImageRef ReadBoundedImage(NSData *data)
{
    if (!data.length || data.length > OrbisClipboardMaximumPNGBytes) return NULL;
    CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)data,
        (CFDictionaryRef)@{(id)kCGImageSourceShouldCache:@NO});
    if (!source) return NULL;
    NSDictionary *properties = (NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
    uint64_t width = [properties[(id)kCGImagePropertyPixelWidth] unsignedLongLongValue];
    uint64_t height = [properties[(id)kCGImagePropertyPixelHeight] unsignedLongLongValue];
    NSUInteger orientation = [properties[(id)kCGImagePropertyOrientation] unsignedIntegerValue];
    [properties release];
    CGImageRef image = NULL;
    if (CGImageSourceGetCount(source) == 1 && DimensionsAllowed(width, height)) {
        if (orientation >= 2 && orientation <= 8)
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, (CFDictionaryRef)@{
                (id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
                (id)kCGImageSourceCreateThumbnailWithTransform:@YES,
                (id)kCGImageSourceThumbnailMaxPixelSize:@(MAX(width, height)) });
        else image = CGImageSourceCreateImageAtIndex(source, 0,
            (CFDictionaryRef)@{(id)kCGImageSourceShouldCacheImmediately:@YES});
    }
    CFRelease(source);
    if (image && !DimensionsAllowed(CGImageGetWidth(image), CGImageGetHeight(image))) {
        CGImageRelease(image); image = NULL;
    }
    return image;
}
static NSData *EncodePNG(CGImageRef image)
{
    if (!image) return nil;
    NSMutableData *result = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((CFMutableDataRef)result,
        CFSTR("public.png"), 1, NULL);
    if (!destination) return nil;
    CGImageDestinationAddImage(destination, image, NULL);
    BOOL success = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    return success && result.length <= OrbisClipboardMaximumPNGBytes ? result : nil;
}
static uint16_t Read16(const uint8_t *p) { return p[0] | ((uint16_t)p[1] << 8); }
static uint32_t Read32(const uint8_t *p)
{ return p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }
static void Write16(uint8_t *p, uint16_t n) { p[0] = n; p[1] = n >> 8; }
static void Write32(uint8_t *p, uint32_t n)
{ p[0] = n; p[1] = n >> 8; p[2] = n >> 16; p[3] = n >> 24; }

@implementation OrbisClipboardImageCodec
+ (NSData *)normalizedPNGData:(NSData *)data
{
    CGImageRef image = ReadBoundedImage(data);
    NSData *result = EncodePNG(image);
    if (image) CGImageRelease(image);
    return result;
}
+ (NSData *)DIBDataFromPNGData:(NSData *)data
{
    CGImageRef image = ReadBoundedImage(data);
    if (!image) return nil;
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    size_t stride = (width * 3 + 3) & ~(size_t)3;
    size_t size = 40 + stride * height;
    if (size > OrbisClipboardMaximumPNGBytes) { CGImageRelease(image); return nil; }
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8, width * 4,
        space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) { CGImageRelease(image); return nil; }
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context); CGImageRelease(image);
    NSMutableData *result = [NSMutableData dataWithLength:size];
    uint8_t *out = result.mutableBytes;
    Write32(out, 40); Write32(out + 4, (uint32_t)width); Write32(out + 8, (uint32_t)height);
    Write16(out + 12, 1); Write16(out + 14, 24); Write32(out + 20, (uint32_t)(stride * height));
    const uint8_t *rgb = pixels.bytes;
    for (size_t y = 0; y < height; y++) for (size_t x = 0; x < width; x++) {
        const uint8_t *src = rgb + (y * width + x) * 4;
        uint8_t *dst = out + 40 + (height - 1 - y) * stride + x * 3;
        dst[0] = src[2]; dst[1] = src[1]; dst[2] = src[0];
    }
    return result;
}
+ (NSData *)PNGDataFromDIBData:(NSData *)data
{
    if (data.length < 40 || data.length > OrbisClipboardMaximumPNGBytes - 14) return nil;
    const uint8_t *p = data.bytes;
    uint32_t header = Read32(p);
    if (header != 40 && header != 52 && header != 56 && header != 108 && header != 124) return nil;
    if (header > data.length) return nil;
    int32_t signedWidth = (int32_t)Read32(p + 4), signedHeight = (int32_t)Read32(p + 8);
    uint64_t height = signedHeight < 0 ? -(int64_t)signedHeight : signedHeight;
    if (signedWidth <= 0 || !DimensionsAllowed((uint32_t)signedWidth, height) || Read16(p + 12) != 1)
        return nil;
    uint16_t bits = Read16(p + 14);
    uint32_t compression = Read32(p + 16), colors = Read32(p + 32);
    if (!(bits == 1 || bits == 4 || bits == 8 || bits == 16 || bits == 24 || bits == 32) ||
        !(compression == 0 || compression == 3 || compression == 6) ||
        ((compression == 3 || compression == 6) && bits != 16 && bits != 32)) return nil;
    uint64_t palette = bits <= 8 ? (colors ?: (1u << bits)) : colors;
    if (palette > 256) return nil;
    uint64_t offset = header + palette * 4;
    if (header == 40 && compression) offset += compression == 6 ? 16 : 12;
    uint64_t stride = (((uint64_t)signedWidth * bits + 31) / 32) * 4;
    if (offset > data.length || stride * height > data.length - offset) return nil;
    // Embedded profiles/linked files are unnecessary clipboard inputs.
    if (header == 124 && (Read32(p + 112) || Read32(p + 116))) return nil;
    NSMutableData *bmp = [NSMutableData dataWithLength:data.length + 14];
    uint8_t *out = bmp.mutableBytes;
    out[0] = 'B'; out[1] = 'M'; Write32(out + 2, (uint32_t)bmp.length);
    Write32(out + 10, (uint32_t)(offset + 14));
    memcpy(out + 14, data.bytes, data.length);
    return [self normalizedPNGData:bmp];
}
@end
