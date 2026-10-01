/* SPDX-License-Identifier: MIT */

#import "OrbisTransportFactory.h"
#import "OrbisCloudflareTransport.h"
#import "OrbisDirectTransport.h"
#import "OrbisCredentialStore.h"
#import "OrbisProfile.h"
#import "OrbisTunnelBridge.h"

@implementation OrbisTransportFactory
+ (id<OrbisConnectionTransport>)transportForProfile:(OrbisProfile *)profile error:(NSError **)error
{
	if (error)
		*error = nil;
	if ([[profile transportType] isEqualToString:OrbisTransportTypeDirect])
		return [OrbisDirectTransport new];
	if ([[profile transportType] isEqualToString:OrbisTransportTypeCloudflare])
	{
		NSString *hostname = [profile transportHostname];
		NSURL *endpoint = [OrbisTunnelBridge endpointForHostname:hostname error:error];
		if (!endpoint)
			return nil;
		NSDictionary *token = [OrbisCredentialStore cloudflareTokenForProfile:profile error:error];
		if (!token)
		{
			if (error && !*error)
				*error = [NSError errorWithDomain:@"com.dnexus.orbis.transport" code:1 userInfo:@{
				    NSLocalizedDescriptionKey : @"Edit this connection and enter a Client ID and Client Secret for its tunnel hostname." }];
			return nil;
		}
		return [[OrbisCloudflareTransport alloc] initWithEndpoint:endpoint clientID:token[@"clientID"]
		    clientSecret:token[@"secret"] error:error];
	}
	if (error)
		*error = [NSError errorWithDomain:@"com.dnexus.orbis.transport" code:2 userInfo:@{
		    NSLocalizedDescriptionKey : @"This connection uses an unsupported transport. Edit its connection settings." }];
	return nil;
}
@end
