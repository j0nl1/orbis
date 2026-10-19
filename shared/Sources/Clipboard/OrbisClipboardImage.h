/* SPDX-License-Identifier: MIT */
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Apple image adapter shared by AppKit and UIKit clipboard adapters. Decodes only
// bounded raster images and normalizes them to PNG; DIB fallback is opaque RGB.
__attribute__((visibility("default")))
@interface OrbisClipboardImageCodec : NSObject
+ (nullable NSData *)normalizedPNGData:(NSData *)data;
+ (nullable NSData *)DIBDataFromPNGData:(NSData *)data;
+ (nullable NSData *)PNGDataFromDIBData:(NSData *)data;
@end
NS_ASSUME_NONNULL_END
