/* SPDX-License-Identifier: MIT */
#import "OrbisIPadDisplaySettings.h"
#import "ConnectionParams.h"
#include "OrbisDisplayLayout.h"
#include <math.h>

static NSString *const OrbisIPadDisplaySettingsKey = @"OrbisIPadDisplaySettings.v1";

@implementation OrbisIPadDisplaySettings
{
	NSUserDefaults *_defaults;
}

+ (NSArray<NSArray<NSNumber *> *> *)resolutionsForPixelWidth:(NSUInteger)width height:(NSUInteger)height
{
	if (!width || !height) return @[];
	// Keep the window aspect ratio; round to even pixels for the RDP display protocol.
	double limit = MIN(1.0, 8192.0 / MAX(width, height));
	NSMutableArray *resolutions = [NSMutableArray array];
	for (NSNumber *fraction in @[ @1.0, @0.85, @0.75, @0.60, @0.50 ])
	{
		double factor = limit * fraction.doubleValue;
		NSUInteger w = (NSUInteger)(round(width * factor / 2.0) * 2.0);
		NSUInteger h = (NSUInteger)(round(height * factor / 2.0) * 2.0);
		NSArray *size = @[ @(w), @(h) ];
		if (OrbisDisplayResolutionIsValid((uint32_t)w, (uint32_t)h) && ![resolutions containsObject:size])
			[resolutions addObject:size];
	}
	return resolutions;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
{
	if (!(self = [super init])) return nil;
	_defaults = [defaults retain];
	id saved = [defaults objectForKey:OrbisIPadDisplaySettingsKey];
	if (![saved isKindOfClass:[NSDictionary class]]) return self;
	id width = saved[@"width"], height = saved[@"height"];
	if ([width isKindOfClass:[NSNumber class]] && [height isKindOfClass:[NSNumber class]] &&
	    [width doubleValue] == [width unsignedIntegerValue] &&
	    [height doubleValue] == [height unsignedIntegerValue] &&
	    [width unsignedIntegerValue] <= 8192 && [height unsignedIntegerValue] <= 8192 &&
	    OrbisDisplayResolutionIsValid([width unsignedIntValue], [height unsignedIntValue]))
	{
		_width = [width unsignedIntegerValue];
		_height = [height unsignedIntegerValue];
	}
	return self;
}

- (BOOL)automaticResolution { return _width == 0 && _height == 0; }

- (BOOL)saveWithError:(NSError **)error
{
	NSString *message = nil;
	if (!self.automaticResolution && (_width > 8192 || _height > 8192 ||
	    !OrbisDisplayResolutionIsValid((uint32_t)_width, (uint32_t)_height)))
		message = @"Enter a width and height between 200 and 8192 pixels. Width must be even.";
	if (message)
	{
		if (error) *error = [NSError errorWithDomain:@"com.dnexus.orbis.display" code:1
		    userInfo:@{ NSLocalizedDescriptionKey : message }];
		return NO;
	}
	[_defaults setObject:@{ @"width" : @(_width), @"height" : @(_height) }
	    forKey:OrbisIPadDisplaySettingsKey];
	return YES;
}

- (void)applyToConnectionParameters:(ConnectionParams *)parameters
{
	[parameters setInt:(int)_width forKey:@"width"];
	[parameters setInt:(int)_height forKey:@"height"];
	[parameters setBool:self.automaticResolution forKey:@"match_window_resolution"];
}

- (void)dealloc { [_defaults release]; [super dealloc]; }
@end
