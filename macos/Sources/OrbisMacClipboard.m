/* SPDX-License-Identifier: MIT */
#import "OrbisMacClipboard.h"
#import "OrbisClipboardImage.h"

@implementation OrbisMacClipboard {
    NSPasteboard *_pasteboard;
}
- (instancetype)initWithPasteboard:(NSPasteboard *)pasteboard
{
    if ((self = [super init])) _pasteboard = [pasteboard retain];
    return self;
}
- (void)dealloc { [_pasteboard release]; [super dealloc]; }
- (OrbisClipboardContent *)readContent
{
    NSAssert(NSThread.isMainThread, @"Clipboard access requires the main thread");
    NSString *text = [_pasteboard stringForType:NSPasteboardTypeString];
    if ([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > OrbisClipboardMaximumTextBytes) text = nil;
    NSData *image = [_pasteboard dataForType:NSPasteboardTypePNG];
    if (!image) image = [_pasteboard dataForType:NSPasteboardTypeTIFF];
    NSData *png = image ? [OrbisClipboardImageCodec normalizedPNGData:image] : nil;
    // An invalid image does not invalidate an independent text representation.
    return [[[OrbisClipboardContent alloc] initWithText:text pngData:png] autorelease];
}
- (BOOL)publishContent:(OrbisClipboardContent *)content
{
    NSAssert(NSThread.isMainThread, @"Clipboard publication requires the main thread");
    if (!content || (!content.text && !content.pngData)) return NO;
    NSData *png = content.pngData ? [OrbisClipboardImageCodec normalizedPNGData:content.pngData] : nil;
    if (content.pngData && !png) return NO;
    NSPasteboardItem *item = [[[NSPasteboardItem alloc] init] autorelease];
    if (content.text && ![item setString:content.text forType:NSPasteboardTypeString]) return NO;
    if (png && ![item setData:png forType:NSPasteboardTypePNG]) return NO;
    [_pasteboard clearContents];
    return [_pasteboard writeObjects:@[item]];
}
@end
