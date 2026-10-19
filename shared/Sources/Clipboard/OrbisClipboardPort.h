/* SPDX-License-Identifier: MIT */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT __attribute__((visibility("default"))) const NSUInteger OrbisClipboardMaximumTextBytes;
FOUNDATION_EXPORT __attribute__((visibility("default"))) const NSUInteger OrbisClipboardMaximumPNGBytes;
FOUNDATION_EXPORT __attribute__((visibility("default"))) const NSUInteger OrbisClipboardMaximumImagePixels;
FOUNDATION_EXPORT __attribute__((visibility("default"))) const NSUInteger OrbisClipboardMaximumImageDimension;

// Immutable local clipboard value. PNG is the normalized image representation;
// DIB and protocol-specific formats remain inside the RDP adapter. Text and PNG
// can coexist. Invalid/oversized data is rejected rather than silently truncated.
// This value checks encoded size and PNG signature; adapters must validate image
// encoding, dimensions and decoded pixel count before use/publication.
__attribute__((visibility("default")))
@interface OrbisClipboardContent : NSObject
@property(nonatomic, readonly, copy, nullable) NSString *text;
@property(nonatomic, readonly, copy, nullable) NSData *pngData;
- (nullable instancetype)initWithText:(nullable NSString *)text
	                         pngData:(nullable NSData *)pngData NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

// Local clipboard port. All calls run on the main thread. Reading may trigger an
// OS privacy prompt: callers must follow platform policy (user action on iPadOS).
// Nil means empty, unavailable or rejected content, never permission denial proof.
// Publication returns NO if rejected; implementations must not replace existing
// local clipboard contents when validation fails.
@protocol OrbisClipboardPort <NSObject>
- (nullable OrbisClipboardContent *)readContent;
- (BOOL)publishContent:(OrbisClipboardContent *)content;
@end

NS_ASSUME_NONNULL_END
