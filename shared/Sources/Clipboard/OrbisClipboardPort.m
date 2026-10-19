/* SPDX-License-Identifier: MIT */

#import "OrbisClipboardPort.h"

#import <string.h>

const NSUInteger OrbisClipboardMaximumTextBytes = 8 * 1024 * 1024;
const NSUInteger OrbisClipboardMaximumPNGBytes = 32 * 1024 * 1024;
const NSUInteger OrbisClipboardMaximumImagePixels = 16 * 1024 * 1024;
const NSUInteger OrbisClipboardMaximumImageDimension = 16384;

@implementation OrbisClipboardContent

- (instancetype)initWithText:(NSString *)text pngData:(NSData *)pngData
{
	if ((self = [super init]))
	{
		static const unsigned char signature[] = { 137, 80, 78, 71, 13, 10, 26, 10 };
		BOOL validText = !text || ([text canBeConvertedToEncoding:NSUTF8StringEncoding] &&
		                          [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <=
		                              OrbisClipboardMaximumTextBytes);
		BOOL validPNG = !pngData || (pngData.length >= sizeof(signature) &&
		                            pngData.length <= OrbisClipboardMaximumPNGBytes &&
		                            memcmp(pngData.bytes, signature, sizeof(signature)) == 0);
		if (!validText || !validPNG || (!text && !pngData))
		{
#if !__has_feature(objc_arc)
			[self release];
#endif
			return nil;
		}
		_text = [text copy];
		_pngData = [pngData copy];
	}
	return self;
}

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_text release];
	[_pngData release];
	[super dealloc];
}
#endif

@end
