/* SPDX-License-Identifier: MIT */

#import "OrbisAcknowledgements.h"

NSString *const OrbisProjectNameKey = @"name";
NSString *const OrbisProjectDetailKey = @"detail";
NSString *const OrbisProjectLicenseKey = @"license";
NSString *const OrbisProjectURLKey = @"url";
NSString *const OrbisProductDescription =
    @"Orbis is an RDP client for iPad and Mac, built for Linux desktops. Mac shortcuts such as "
    @"⌘C, ⌘V, ⌘A, ⌘Z, and ⌘⌫ work inside the remote session. It also handles GNOME Remote "
    @"Login. Passwords stay in Keychain, separate from connection profiles.";

@implementation OrbisAcknowledgements

+ (NSArray *)projects
{
	return @[
		@{
			OrbisProjectNameKey : @"FreeRDP and WinPR",
			OrbisProjectDetailKey : @"RDP protocol, transport, graphics, input, and platform runtime",
			OrbisProjectLicenseKey : @"Apache-2.0",
			OrbisProjectURLKey : @"https://github.com/FreeRDP/FreeRDP"
		},
		@{
			OrbisProjectNameKey : @"OpenSSL",
			OrbisProjectDetailKey : @"TLS and cryptographic primitives",
			OrbisProjectLicenseKey : @"Apache-2.0",
			OrbisProjectURLKey : @"https://github.com/openssl/openssl"
		},
		@{
			OrbisProjectNameKey : @"FFmpeg",
			OrbisProjectDetailKey : @"H.264 and HEVC decoding support on iPadOS",
			OrbisProjectLicenseKey : @"LGPL-2.1-or-later",
			OrbisProjectURLKey : @"https://github.com/FFmpeg/FFmpeg"
		},
		@{
			OrbisProjectNameKey : @"OpenH264",
			OrbisProjectDetailKey : @"H.264 codec support on iPadOS",
			OrbisProjectLicenseKey : @"BSD-2-Clause",
			OrbisProjectURLKey : @"https://github.com/cisco/openh264"
		},
		@{
			OrbisProjectNameKey : @"Opus",
			OrbisProjectDetailKey : @"Low-latency audio codec",
			OrbisProjectLicenseKey : @"BSD-3-Clause",
			OrbisProjectURLKey : @"https://github.com/xiph/opus"
		},
		@{
			OrbisProjectNameKey : @"libpng",
			OrbisProjectDetailKey : @"PNG image decoding",
			OrbisProjectLicenseKey : @"libpng-2.0",
			OrbisProjectURLKey : @"https://github.com/pnggroup/libpng"
		},
		@{
			OrbisProjectNameKey : @"libjpeg-turbo",
			OrbisProjectDetailKey : @"JPEG image decoding",
			OrbisProjectLicenseKey : @"BSD-3-Clause and IJG",
			OrbisProjectURLKey : @"https://github.com/libjpeg-turbo/libjpeg-turbo"
		},
		@{
			OrbisProjectNameKey : @"libwebp",
			OrbisProjectDetailKey : @"WebP image decoding",
			OrbisProjectLicenseKey : @"BSD-3-Clause",
			OrbisProjectURLKey : @"https://github.com/webmproject/libwebp"
		},
		@{
			OrbisProjectNameKey : @"cJSON",
			OrbisProjectDetailKey : @"JSON parsing used by FreeRDP",
			OrbisProjectLicenseKey : @"MIT",
			OrbisProjectURLKey : @"https://github.com/DaveGamble/cJSON"
		},
		@{
			OrbisProjectNameKey : @"uriparser",
			OrbisProjectDetailKey : @"URI parsing used by FreeRDP",
			OrbisProjectLicenseKey : @"BSD-3-Clause",
			OrbisProjectURLKey : @"https://github.com/uriparser/uriparser"
		}
	];
}

@end
