/* SPDX-License-Identifier: MIT */

#import "OrbisConnectionTransport.h"

@implementation OrbisTransportDestination
- (instancetype)initWithHostname:(NSString *)hostname port:(uint16_t)port
{
	NSParameterAssert(hostname.length > 0 && port > 0);
	if ((self = [super init]))
	{
		_hostname = [hostname copy];
		_port = port;
	}
	return self;
}
@end
