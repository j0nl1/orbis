/* SPDX-License-Identifier: MIT */

#import "OrbisProfile.h"

static NSString *const OrbisProfilesDefaultsKey = @"OrbisProfiles.v1";
static NSString *const OrbisSelectedProfileDefaultsKey = @"OrbisSelectedProfile.v1";

@implementation OrbisProfile

@synthesize identifier = _identifier;
@synthesize name = _name;
@synthesize host = _host;
@synthesize username = _username;
@synthesize port = _port;
@synthesize acceptAllCertificates = _acceptAllCertificates;
@synthesize connectAutomatically = _connectAutomatically;

- (id)init
{
	if (!(self = [super init]))
		return nil;

	_identifier = [[[NSUUID UUID] UUIDString] copy];
	_name = [@"" copy];
	_host = [@"" copy];
	_username = [@"" copy];
	_port = 3389;
	_acceptAllCertificates = NO;
	_connectAutomatically = NO;
	return self;
}

- (id)initWithDictionary:(NSDictionary *)dictionary
{
	if (!(self = [self init]))
		return nil;

	NSString *identifier = [dictionary objectForKey:@"id"];
	NSString *name = [dictionary objectForKey:@"name"];
	NSString *host = [dictionary objectForKey:@"host"];
	NSString *username = [dictionary objectForKey:@"username"];
	NSNumber *port = [dictionary objectForKey:@"port"];

	if ([identifier length] > 0)
		[self setIdentifier:identifier];
	if ([name length] > 0)
		[self setName:name];
	if ([host isKindOfClass:[NSString class]])
		[self setHost:host];
	if ([username isKindOfClass:[NSString class]])
		[self setUsername:username];
	if ([port unsignedIntegerValue] > 0 && [port unsignedIntegerValue] <= 65535)
		[self setPort:[port unsignedIntegerValue]];
	[self setAcceptAllCertificates:[[dictionary objectForKey:@"acceptAllCertificates"] boolValue]];
	[self setConnectAutomatically:[[dictionary objectForKey:@"connectAutomatically"] boolValue]];
	return self;
}

- (NSDictionary *)dictionaryRepresentation
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
	                         _identifier, @"id", _name, @"name", _host, @"host", _username,
	                         @"username", [NSNumber numberWithUnsignedInteger:_port], @"port",
	                         [NSNumber numberWithBool:_acceptAllCertificates],
	                         @"acceptAllCertificates",
	                         [NSNumber numberWithBool:_connectAutomatically],
	                         @"connectAutomatically", nil];
}

- (id)copyWithZone:(NSZone *)zone
{
	OrbisProfile *copy = [[[self class] allocWithZone:zone] init];
	[copy setIdentifier:_identifier];
	[copy setName:_name];
	[copy setHost:_host];
	[copy setUsername:_username];
	[copy setPort:_port];
	[copy setAcceptAllCertificates:_acceptAllCertificates];
	[copy setConnectAutomatically:_connectAutomatically];
	return copy;
}

- (void)dealloc
{
	[_identifier release];
	[_name release];
	[_host release];
	[_username release];
	[super dealloc];
}

@end

@implementation OrbisProfileStore

- (id)init
{
	if (!(self = [super init]))
		return nil;

	_profiles = [[NSMutableArray alloc] init];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSArray *storedProfiles = [defaults objectForKey:OrbisProfilesDefaultsKey];
	if (storedProfiles == nil)
	{
		[self persist];
	}
	else
	{
		for (id value in storedProfiles)
		{
			if (![value isKindOfClass:[NSDictionary class]])
				continue;
			OrbisProfile *profile = [[[OrbisProfile alloc] initWithDictionary:value] autorelease];
			if ([[profile host] length] > 0)
				[_profiles addObject:profile];
		}
		_selectedProfileIdentifier = [[defaults stringForKey:OrbisSelectedProfileDefaultsKey] copy];
		if (![self profileWithIdentifier:_selectedProfileIdentifier] && [_profiles count] > 0)
		{
			[_selectedProfileIdentifier release];
			_selectedProfileIdentifier = [[[_profiles objectAtIndex:0] identifier] copy];
			[self persist];
		}
	}
	return self;
}

- (NSArray *)profiles
{
	return _profiles;
}

- (OrbisProfile *)selectedProfile
{
	return [self profileWithIdentifier:_selectedProfileIdentifier];
}

- (OrbisProfile *)automaticProfile
{
	for (OrbisProfile *profile in _profiles)
		if ([profile connectAutomatically])
			return profile;
	return nil;
}

- (OrbisProfile *)profileWithIdentifier:(NSString *)identifier
{
	if ([identifier length] == 0)
		return nil;
	for (OrbisProfile *profile in _profiles)
		if ([[profile identifier] isEqualToString:identifier])
			return profile;
	return nil;
}

- (void)selectProfileWithIdentifier:(NSString *)identifier
{
	if (![self profileWithIdentifier:identifier])
		return;
	[_selectedProfileIdentifier release];
	_selectedProfileIdentifier = [identifier copy];
	[self persist];
}

- (void)saveProfile:(OrbisProfile *)profile
{
	if (!profile || [[profile identifier] length] == 0)
		return;

	if ([profile connectAutomatically])
		for (OrbisProfile *existing in _profiles)
			[existing setConnectAutomatically:NO];

	OrbisProfile *storedProfile = [profile copy];
	NSUInteger index = NSNotFound;
	for (NSUInteger candidate = 0; candidate < [_profiles count]; candidate++)
	{
		if ([[[_profiles objectAtIndex:candidate] identifier]
			        isEqualToString:[profile identifier]])
		{
			index = candidate;
			break;
		}
	}
	if (index == NSNotFound)
		[_profiles addObject:storedProfile];
	else
		[_profiles replaceObjectAtIndex:index withObject:storedProfile];
	[storedProfile release];

	[self selectProfileWithIdentifier:[profile identifier]];
}

- (void)deleteProfileWithIdentifier:(NSString *)identifier
{
	OrbisProfile *profile = [self profileWithIdentifier:identifier];
	if (!profile)
		return;
	[_profiles removeObject:profile];

	if ([_selectedProfileIdentifier isEqualToString:identifier])
	{
		[_selectedProfileIdentifier release];
		_selectedProfileIdentifier = nil;
		if ([_profiles count] > 0)
			_selectedProfileIdentifier = [[[_profiles objectAtIndex:0] identifier] copy];
	}
	[self persist];
}

- (void)persist
{
	NSMutableArray *values = [NSMutableArray arrayWithCapacity:[_profiles count]];
	for (OrbisProfile *profile in _profiles)
		[values addObject:[profile dictionaryRepresentation]];

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:values forKey:OrbisProfilesDefaultsKey];
	if (_selectedProfileIdentifier)
		[defaults setObject:_selectedProfileIdentifier forKey:OrbisSelectedProfileDefaultsKey];
	else
		[defaults removeObjectForKey:OrbisSelectedProfileDefaultsKey];
}

- (void)dealloc
{
	[_profiles release];
	[_selectedProfileIdentifier release];
	[super dealloc];
}

@end
