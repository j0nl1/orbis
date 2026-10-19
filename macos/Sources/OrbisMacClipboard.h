/* SPDX-License-Identifier: MIT */
#import <AppKit/AppKit.h>
#import "OrbisClipboardPort.h"

// AppKit adapter. A named pasteboard may be injected for isolated integration tests.
__attribute__((visibility("default")))
@interface OrbisMacClipboard : NSObject <OrbisClipboardPort>
- (instancetype)initWithPasteboard:(NSPasteboard *)pasteboard;
@end
