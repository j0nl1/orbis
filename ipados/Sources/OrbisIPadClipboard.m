/* SPDX-License-Identifier: MIT */
#import "OrbisIPadClipboard.h"
#import "OrbisClipboardImage.h"

@implementation OrbisIPadClipboard
{
	id<OrbisIPadPasteboard> _pasteboard;
}
- (instancetype)init
{
	return [self initWithPasteboard:(id<OrbisIPadPasteboard>)[UIPasteboard generalPasteboard]];
}
- (instancetype)initWithPasteboard:(id<OrbisIPadPasteboard>)pasteboard
{
	if ((self = [super init])) _pasteboard = [pasteboard retain];
	return self;
}
- (void)dealloc { [_pasteboard release]; [super dealloc]; }
- (OrbisClipboardContent *)readContent
{
	NSAssert([NSThread isMainThread], @"Clipboard reads require the main thread");
	NSData *png = [_pasteboard dataForPasteboardType:@"public.png"];
	if (png) png = [OrbisClipboardImageCodec normalizedPNGData:png];
	else
	{
		UIImage *image = _pasteboard.image;
		CGImageRef pixels = image.CGImage;
		if (pixels && CGImageGetWidth(pixels) <= OrbisClipboardMaximumImageDimension &&
		    CGImageGetHeight(pixels) <= OrbisClipboardMaximumImageDimension &&
		    CGImageGetWidth(pixels) > 0 && CGImageGetHeight(pixels) > 0 &&
		    CGImageGetWidth(pixels) <= OrbisClipboardMaximumImagePixels / CGImageGetHeight(pixels))
			png = [OrbisClipboardImageCodec normalizedPNGData:UIImagePNGRepresentation(image)];
	}
	return [[[OrbisClipboardContent alloc] initWithText:_pasteboard.string pngData:png] autorelease];
}
- (BOOL)publishContent:(OrbisClipboardContent *)content
{
	NSAssert([NSThread isMainThread], @"Clipboard publication requires the main thread");
	NSMutableDictionary *item = [NSMutableDictionary dictionary];
	if (content.pngData)
	{
		NSData *png = [OrbisClipboardImageCodec normalizedPNGData:content.pngData];
		if (!png) return NO;
		item[@"public.png"] = png;
	}
	if (content.text) item[@"public.utf8-plain-text"] = content.text;
	if (!item.count) return NO;
	_pasteboard.items = @[item];
	return YES;
}
@end
