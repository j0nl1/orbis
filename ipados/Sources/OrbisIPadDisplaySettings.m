/* SPDX-License-Identifier: MIT */
#import "OrbisIPadDisplaySettings.h"
#import "ConnectionParams.h"
#include "OrbisDisplayLayout.h"

static NSString *const OrbisIPadDisplaySettingsKey = @"OrbisIPadDisplaySettings.v1";

@implementation OrbisIPadDisplaySettings
{
	NSUserDefaults *_defaults;
}

+ (NSArray<NSNumber *> *)supportedScales
{
	return @[ @100, @125, @150, @175, @200 ];
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
{
	if (!(self = [super init])) return nil;
	_defaults = [defaults retain];
	_desktopScale = 100;
	id saved = [defaults objectForKey:OrbisIPadDisplaySettingsKey];
	if (![saved isKindOfClass:[NSDictionary class]]) return self;
	id width = saved[@"width"], height = saved[@"height"], scale = saved[@"desktopScale"];
	if ([width isKindOfClass:[NSNumber class]] && [height isKindOfClass:[NSNumber class]] &&
	    [width doubleValue] == [width unsignedIntegerValue] &&
	    [height doubleValue] == [height unsignedIntegerValue] &&
	    [width unsignedIntegerValue] <= 8192 && [height unsignedIntegerValue] <= 8192 &&
	    OrbisDisplayResolutionIsValid([width unsignedIntValue], [height unsignedIntValue]))
	{
		_width = [width unsignedIntegerValue];
		_height = [height unsignedIntegerValue];
	}
	if ([[self.class supportedScales] containsObject:scale]) _desktopScale = [scale unsignedIntegerValue];
	return self;
}

- (BOOL)automaticResolution { return _width == 0 && _height == 0; }

- (BOOL)saveWithError:(NSError **)error
{
	NSString *message = nil;
	if (!self.automaticResolution && (_width > 8192 || _height > 8192 ||
	    !OrbisDisplayResolutionIsValid((uint32_t)_width, (uint32_t)_height)))
		message = @"Enter a width and height between 200 and 8192 pixels. Width must be even.";
	else if (![[self.class supportedScales] containsObject:@(_desktopScale)])
		message = @"Choose one of the supported desktop scales.";
	if (message)
	{
		if (error) *error = [NSError errorWithDomain:@"com.dnexus.orbis.display" code:1
		    userInfo:@{ NSLocalizedDescriptionKey : message }];
		return NO;
	}
	[_defaults setObject:@{ @"width" : @(_width), @"height" : @(_height),
	    @"desktopScale" : @(_desktopScale) } forKey:OrbisIPadDisplaySettingsKey];
	return YES;
}

- (void)applyToConnectionParameters:(ConnectionParams *)parameters
{
	[parameters setInt:(int)_width forKey:@"width"];
	[parameters setInt:(int)_height forKey:@"height"];
	[parameters setInt:(int)_desktopScale forKey:@"desktop_scale_factor"];
	[parameters setBool:self.automaticResolution forKey:@"match_window_resolution"];
}

- (void)dealloc { [_defaults release]; [super dealloc]; }
@end
