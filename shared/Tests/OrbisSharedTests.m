/* SPDX-License-Identifier: MIT */

#import <XCTest/XCTest.h>
#import <Security/Security.h>

#import "OrbisAcknowledgements.h"
#import "OrbisProfile.h"
#import "OrbisCredentialStore.h"

@interface OrbisProfileTests : XCTestCase
@end

@implementation OrbisProfileTests

- (void)testNewProfileUsesSafeDefaults
{
	OrbisProfile *profile = [[OrbisProfile alloc] init];

	XCTAssertGreaterThan([[profile identifier] length], (NSUInteger)0);
	XCTAssertEqualObjects([profile name], @"");
	XCTAssertEqualObjects([profile host], @"");
	XCTAssertEqualObjects([profile username], @"");
	XCTAssertEqual([profile port], (NSUInteger)3389);
	XCTAssertFalse([profile acceptAllCertificates]);
	XCTAssertFalse([profile connectAutomatically]);
	XCTAssertEqualObjects([profile transportType], OrbisTransportTypeDirect);
	XCTAssertEqualObjects([profile transportOptions], @{});

	[profile release];
}

- (void)testDictionaryRoundTripPreservesConnectionSettings
{
	NSDictionary *values = @{
		@"id" : @"workstation",
		@"name" : @"Workstation",
		@"host" : @"desktop.example.test",
		@"username" : @"operator",
		@"port" : @3390,
		@"acceptAllCertificates" : @YES,
		@"connectAutomatically" : @YES
	};
	OrbisProfile *profile = [[OrbisProfile alloc] initWithDictionary:values];

	XCTAssertEqualObjects([profile dictionaryRepresentation], values);

	[profile release];
}

- (void)testInvalidPortsFallBackToRDPDefault
{
	for (NSNumber *port in @[ @0, @65536 ])
	{
		OrbisProfile *profile = [[OrbisProfile alloc]
		    initWithDictionary:@{ @"host" : @"desktop.example.test", @"port" : port }];
		XCTAssertEqual([profile port], (NSUInteger)3389);
		[profile release];
	}
}

- (void)testTunnelProfilesRoundTripAndCopyWithoutPersistingCredentials
{
	OrbisProfile *profile = [[OrbisProfile alloc] init];
	[profile setHost:@"rdp.example.test"];
	[profile setTransportType:OrbisTransportTypeCloudflare];
	[profile setTransportOptions:@{ @"hostname" : @"gateway.example.test" }];
	OrbisProfile *decoded = [[OrbisProfile alloc] initWithDictionary:[profile dictionaryRepresentation]];
	OrbisProfile *copy = [profile copy];
	XCTAssertEqualObjects([decoded transportType], OrbisTransportTypeCloudflare);
	XCTAssertEqualObjects([copy transportOptions], [profile transportOptions]);
	XCTAssertEqualObjects([decoded transportHostname], @"gateway.example.test");
	XCTAssertEqualObjects([decoded host], @"rdp.example.test");
	XCTAssertNil([profile dictionaryRepresentation][@"usesCloudflareTunnel"]);
	XCTAssertNil([[profile dictionaryRepresentation] objectForKey:@"clientID"]);
	XCTAssertNil([[profile dictionaryRepresentation] objectForKey:@"secret"]);
	[copy release];
	[decoded release];
	[profile release];
}

- (void)testLegacyTunnelProfilesMigrateToTransportConfiguration
{
	OrbisProfile *profile = [[OrbisProfile alloc] initWithDictionary:@{
	    @"host" : @"gateway.example.test", @"usesCloudflareTunnel" : @YES }];
	XCTAssertEqualObjects([profile transportType], OrbisTransportTypeCloudflare);
	XCTAssertEqualObjects([profile transportHostname], @"gateway.example.test");
	XCTAssertNil([profile dictionaryRepresentation][@"usesCloudflareTunnel"]);
	XCTAssertEqualObjects([profile dictionaryRepresentation][@"transport"], (@{
	    @"type" : @"cloudflare", @"options" : @{ @"hostname" : @"gateway.example.test" } }));
	[profile release];
}

- (void)testUnknownTransportIsPreservedInsteadOfDowngradedToDirect
{
	NSDictionary *transport = @{ @"type" : @"future-gateway", @"options" : @{ @"hostname" : @"future.example.test" } };
	OrbisProfile *profile = [[OrbisProfile alloc] initWithDictionary:@{
	    @"host" : @"rdp.example.test", @"transport" : transport, @"usesCloudflareTunnel" : @YES }];
	XCTAssertEqualObjects([profile transportType], @"future-gateway");
	XCTAssertEqualObjects([profile dictionaryRepresentation][@"transport"], transport);
	[profile release];
}

- (void)testCopyCanChangeWithoutMutatingOriginal
{
	OrbisProfile *profile = [[OrbisProfile alloc] init];
	[profile setName:@"Original"];
	[profile setHost:@"original.example.test"];
	OrbisProfile *copy = [profile copy];

	[copy setName:@"Copy"];
	[copy setHost:@"copy.example.test"];

	XCTAssertEqualObjects([profile name], @"Original");
	XCTAssertEqualObjects([profile host], @"original.example.test");
	XCTAssertEqualObjects([copy identifier], [profile identifier]);

	[copy release];
	[profile release];
}

@end

// Limit credential tests to a disposable keychain, never the user's login keychain.
@interface OrbisCredentialStore (TestKeychainQuery)
+ (NSMutableDictionary *)queryForProfile:(OrbisProfile *)profile account:(NSString *)account;
@end

static SecKeychainRef OrbisFixtureKeychain = NULL;

@interface OrbisFixtureCredentialStore : OrbisCredentialStore
@end

@implementation OrbisFixtureCredentialStore
+ (NSMutableDictionary *)queryForProfile:(OrbisProfile *)profile account:(NSString *)account
{
	NSMutableDictionary *query = [super queryForProfile:profile account:account];
	NSAssert(OrbisFixtureKeychain != NULL, @"The fixture keychain must exist");
	[query setObject:(id)OrbisFixtureKeychain forKey:(id)kSecUseKeychain];
	[query setObject:@[ (id)OrbisFixtureKeychain ] forKey:(id)kSecMatchSearchList];
	return query;
}
@end

@interface OrbisCredentialStoreTests : XCTestCase
@end

@implementation OrbisCredentialStoreTests

- (void)setUp
{
	[super setUp];
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
	    [NSString stringWithFormat:@"orbis-test-%@.keychain", [[NSUUID UUID] UUIDString]]];
	const char password[] = "isolated-fixture-password";
	OSStatus status = SecKeychainCreate([path fileSystemRepresentation], sizeof(password) - 1,
	    password, false, NULL, &OrbisFixtureKeychain);
	XCTAssertEqual(status, errSecSuccess);
}

- (void)tearDown
{
	if (OrbisFixtureKeychain)
	{
		XCTAssertEqual(SecKeychainDelete(OrbisFixtureKeychain), errSecSuccess);
		CFRelease(OrbisFixtureKeychain);
		OrbisFixtureKeychain = NULL;
	}
	[super tearDown];
}

- (void)testServiceTokenIsIndependentFromPasswordAndBoundToHostname
{
	OrbisProfile *profile = [[OrbisProfile alloc] init];
	[profile setHost:@"rdp.example.test"];
	@try
	{
		NSError *error = nil;
		XCTAssertTrue([OrbisFixtureCredentialStore setPassword:@"fixture-password" forProfile:profile error:&error], @"%@", error);
		XCTAssertTrue([OrbisFixtureCredentialStore setCloudflareClientID:@"fixture-client" secret:@"fixture-secret"
		    forProfile:profile error:&error], @"%@", error);
		NSDictionary *token = [OrbisFixtureCredentialStore cloudflareTokenForProfile:profile error:&error];
		XCTAssertNil(error);
		XCTAssertEqualObjects(token[@"clientID"], @"fixture-client");
		XCTAssertEqualObjects(token[@"secret"], @"fixture-secret");
		XCTAssertEqualObjects([OrbisFixtureCredentialStore passwordForProfile:profile error:&error], @"fixture-password");
		[profile setHost:@"another.example.test"];
		XCTAssertNil([OrbisFixtureCredentialStore cloudflareTokenForProfile:profile error:&error]);
		XCTAssertNil(error);
		[profile setHost:@"RDP.EXAMPLE.TEST"];
		XCTAssertNotNil([OrbisFixtureCredentialStore cloudflareTokenForProfile:profile error:&error]);
		XCTAssertTrue([OrbisFixtureCredentialStore deleteCredentialsForProfile:profile error:&error]);
		XCTAssertNil([OrbisFixtureCredentialStore passwordForProfile:profile error:&error]);
		XCTAssertNil([OrbisFixtureCredentialStore cloudflareTokenForProfile:profile error:&error]);
	}
	@finally
	{
		[OrbisFixtureCredentialStore deleteCredentialsForProfile:profile error:nil];
		[profile release];
	}
}

- (void)testTokenIsBoundToGatewayRatherThanLogicalRDPTarget
{
	OrbisProfile *profile = [[OrbisProfile alloc] init];
	[profile setHost:@"logical-server.example.test"];
	[profile setTransportType:OrbisTransportTypeCloudflare];
	[profile setTransportOptions:@{ @"hostname" : @"gateway.example.test" }];
	@try
	{
		NSError *error = nil;
		XCTAssertTrue([OrbisFixtureCredentialStore setCloudflareClientID:@"fixture-client" secret:@"fixture-secret"
		    forProfile:profile error:&error]);
		[profile setHost:@"redirected.internal"];
		XCTAssertNotNil([OrbisFixtureCredentialStore cloudflareTokenForProfile:profile error:&error]);
		[profile setTransportOptions:@{ @"hostname" : @"another-gateway.example.test" }];
		XCTAssertNil([OrbisFixtureCredentialStore cloudflareTokenForProfile:profile error:&error]);
		XCTAssertNil(error);
	}
	@finally
	{
		[OrbisFixtureCredentialStore deleteCredentialsForProfile:profile error:nil];
		[profile release];
	}
}

- (void)testInvalidTokenDoesNotOverwriteAnExistingToken
{
	OrbisProfile *profile = [[OrbisProfile alloc] init];
	[profile setHost:@"rdp.example.test"];
	@try
	{
		NSError *error = nil;
		XCTAssertTrue([OrbisFixtureCredentialStore setCloudflareClientID:@"fixture-client" secret:@"fixture-secret"
		    forProfile:profile error:&error]);
		XCTAssertFalse([OrbisFixtureCredentialStore setCloudflareClientID:@"injected\r\nHeader: value" secret:@"new-secret"
		    forProfile:profile error:&error]);
		XCTAssertNotNil(error);
		XCTAssertEqualObjects([OrbisFixtureCredentialStore cloudflareTokenForProfile:profile error:&error][@"secret"], @"fixture-secret");
	}
	@finally
	{
		[OrbisFixtureCredentialStore deleteCredentialsForProfile:profile error:nil];
		[profile release];
	}
}

@end

@interface OrbisProfileStoreTests : XCTestCase
@end

@implementation OrbisProfileStoreTests

- (void)setUp
{
	[super setUp];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults removeObjectForKey:@"OrbisProfiles.v1"];
	[defaults removeObjectForKey:@"OrbisSelectedProfile.v1"];
}

- (void)tearDown
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults removeObjectForKey:@"OrbisProfiles.v1"];
	[defaults removeObjectForKey:@"OrbisSelectedProfile.v1"];
	[super tearDown];
}

- (void)testSavingProfileStoresACopyAndSelectsIt
{
	OrbisProfileStore *store = [[OrbisProfileStore alloc] init];
	OrbisProfile *profile = [[OrbisProfile alloc] init];
	[profile setName:@"Desktop"];
	[profile setHost:@"desktop.example.test"];

	[store saveProfile:profile];
	[profile setName:@"Changed after saving"];

	XCTAssertEqual([[store profiles] count], (NSUInteger)1);
	XCTAssertEqualObjects([[store selectedProfile] name], @"Desktop");
	XCTAssertNotEqual([store selectedProfile], profile);

	[profile release];
	[store release];
}

- (void)testOnlyOneProfileCanConnectAutomatically
{
	OrbisProfileStore *store = [[OrbisProfileStore alloc] init];
	OrbisProfile *first = [[OrbisProfile alloc] init];
	[first setHost:@"first.example.test"];
	[first setConnectAutomatically:YES];
	[store saveProfile:first];

	OrbisProfile *second = [[OrbisProfile alloc] init];
	[second setHost:@"second.example.test"];
	[second setConnectAutomatically:YES];
	[store saveProfile:second];

	XCTAssertEqualObjects([[store automaticProfile] identifier], [second identifier]);
	XCTAssertFalse([[store profileWithIdentifier:[first identifier]] connectAutomatically]);

	[second release];
	[first release];
	[store release];
}

- (void)testDeletingSelectedProfileSelectsTheNextAvailableProfile
{
	OrbisProfileStore *store = [[OrbisProfileStore alloc] init];
	OrbisProfile *first = [[OrbisProfile alloc] init];
	[first setHost:@"first.example.test"];
	[store saveProfile:first];
	OrbisProfile *second = [[OrbisProfile alloc] init];
	[second setHost:@"second.example.test"];
	[store saveProfile:second];

	[store deleteProfileWithIdentifier:[second identifier]];

	XCTAssertEqualObjects([[store selectedProfile] identifier], [first identifier]);
	XCTAssertNil([store profileWithIdentifier:[second identifier]]);

	[second release];
	[first release];
	[store release];
}

@end

@interface OrbisAcknowledgementsTests : XCTestCase
@end

@implementation OrbisAcknowledgementsTests

- (void)testAcknowledgementsAreCompleteAndLinkToSecureSources
{
	NSArray *projects = [OrbisAcknowledgements projects];
	NSMutableSet *names = [NSMutableSet set];

	XCTAssertGreaterThan([projects count], (NSUInteger)0);
	for (NSDictionary *project in projects)
	{
		NSString *name = [project objectForKey:OrbisProjectNameKey];
		NSString *detail = [project objectForKey:OrbisProjectDetailKey];
		NSString *license = [project objectForKey:OrbisProjectLicenseKey];
		NSURL *url = [NSURL URLWithString:[project objectForKey:OrbisProjectURLKey]];

		XCTAssertGreaterThan([name length], (NSUInteger)0);
		XCTAssertGreaterThan([detail length], (NSUInteger)0);
		XCTAssertGreaterThan([license length], (NSUInteger)0);
		XCTAssertEqualObjects([url scheme], @"https");
		XCTAssertGreaterThan([[url host] length], (NSUInteger)0);
		XCTAssertFalse([names containsObject:name], @"Duplicate acknowledgement: %@", name);
		[names addObject:name];
	}
}

@end
