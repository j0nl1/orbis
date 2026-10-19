/* SPDX-License-Identifier: MIT */
#import <UIKit/UIKit.h>
#import "OrbisClipboardPort.h"

// Injectable system boundary. No observations or polling of another app's data.
@protocol OrbisIPadPasteboard <NSObject>
- (NSData *)dataForPasteboardType:(NSString *)type;
@property(nonatomic, copy) NSString *string;
@property(nonatomic, retain) UIImage *image;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *items;
@end

@interface OrbisIPadClipboard : NSObject <OrbisClipboardPort>
- (instancetype)initWithPasteboard:(id<OrbisIPadPasteboard>)pasteboard;
@end
