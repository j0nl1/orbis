/* SPDX-License-Identifier: MIT */

#import <XCTest/XCTest.h>

#import "OrbisAcknowledgements.h"
#import "OrbisProfile.h"

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
