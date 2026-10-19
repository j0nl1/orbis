/* SPDX-License-Identifier: MIT */

#import <XCTest/XCTest.h>
#import <string.h>

#import "OrbisSessionCapabilities.h"
#import "OrbisClipboardPort.h"

static OrbisSessionCapabilityFacts ReadyFacts(void)
{
	return (OrbisSessionCapabilityFacts){
		.implemented = YES, .enabled = YES, .permission = OrbisCapabilityPermissionGranted,
		.channel = OrbisCapabilityChannelReady, .peerSupport = OrbisCapabilityPeerSupportSupported
	};
}

@interface OrbisSessionCapabilitiesTests : XCTestCase
@end

@implementation OrbisSessionCapabilitiesTests

- (void)testUnknownPeerAllowsInitialOfferWithoutClaimingSupport
{
	OrbisSessionCapabilities *store = [OrbisSessionCapabilities new];
	uint64_t generation = [store beginSession];
	OrbisSessionCapabilityFacts facts = ReadyFacts();
	facts.peerSupport = OrbisCapabilityPeerSupportUnknown;
	XCTAssertTrue([store updateFeature:OrbisSessionFeatureClipboardImage
	                       direction:OrbisCapabilityDirectionToRemote facts:facts limits:nil
	                   forGeneration:generation]);
	OrbisSessionCapability *result = [store.snapshot capabilityForFeature:OrbisSessionFeatureClipboardImage
	                                                         direction:OrbisCapabilityDirectionToRemote];
	XCTAssertEqual(result.state, OrbisCapabilityStateChecking);
	XCTAssertEqual(result.reason, OrbisCapabilityReasonPeerUnknown);
	XCTAssertTrue(result.canAttempt);
}

- (void)testEachAuthoritativeBlockPreventsAttempts
{
	OrbisSessionCapabilities *store = [OrbisSessionCapabilities new];
	uint64_t generation = [store beginSession];
	OrbisSessionCapabilityFacts cases[6];
	for (NSUInteger index = 0; index < 6; index++)
		cases[index] = ReadyFacts();
	cases[0].implemented = NO;
	cases[1].enabled = NO;
	cases[2].permission = OrbisCapabilityPermissionDenied;
	cases[3].channel = OrbisCapabilityChannelUnavailable;
	cases[4].peerSupport = OrbisCapabilityPeerSupportUnsupported;
	cases[5].explicitlyRestricted = YES;
	OrbisCapabilityReason reasons[] = {
		OrbisCapabilityReasonNotImplemented, OrbisCapabilityReasonDisabled,
		OrbisCapabilityReasonPermissionDenied, OrbisCapabilityReasonChannelUnavailable,
		OrbisCapabilityReasonPeerUnsupported, OrbisCapabilityReasonExplicitRestriction
	};
	for (NSUInteger index = 0; index < 6; index++)
	{
		[store updateFeature:OrbisSessionFeatureClipboardImage direction:OrbisCapabilityDirectionToRemote
		               facts:cases[index] limits:nil forGeneration:generation];
		OrbisSessionCapability *result = [store.snapshot capabilityForFeature:OrbisSessionFeatureClipboardImage
		                                                         direction:OrbisCapabilityDirectionToRemote];
		XCTAssertEqual(result.state, OrbisCapabilityStateUnavailable);
		XCTAssertEqual(result.reason, reasons[index]);
		XCTAssertFalse(result.canAttempt);
	}
}

- (void)testPendingPermissionOrChannelDoesNotPermitAttempt
{
	OrbisSessionCapabilities *store = [OrbisSessionCapabilities new];
	uint64_t generation = [store beginSession];
	OrbisSessionCapabilityFacts facts = ReadyFacts();
	facts.permission = OrbisCapabilityPermissionUnknown;
	[store updateFeature:OrbisSessionFeatureMicrophone direction:OrbisCapabilityDirectionToRemote
	               facts:facts limits:nil forGeneration:generation];
	OrbisSessionCapability *permission = [store.snapshot capabilityForFeature:OrbisSessionFeatureMicrophone
	                                                              direction:OrbisCapabilityDirectionToRemote];
	XCTAssertEqual(permission.reason, OrbisCapabilityReasonPermissionUnknown);
	XCTAssertEqual(permission.state, OrbisCapabilityStateChecking);
	XCTAssertFalse(permission.canAttempt);
	facts.permission = OrbisCapabilityPermissionGranted;
	facts.channel = OrbisCapabilityChannelPending;
	[store updateFeature:OrbisSessionFeatureMicrophone direction:OrbisCapabilityDirectionToRemote
	               facts:facts limits:nil forGeneration:generation];
	OrbisSessionCapability *channel = [store.snapshot capabilityForFeature:OrbisSessionFeatureMicrophone
	                                                          direction:OrbisCapabilityDirectionToRemote];
	XCTAssertEqual(channel.reason, OrbisCapabilityReasonChannelPending);
	XCTAssertFalse(channel.canAttempt);
}

- (void)testDirectionsFeaturesAndRetainedSnapshotsRemainIndependent
{
	OrbisSessionCapabilities *store = [OrbisSessionCapabilities new];
	uint64_t generation = [store beginSession];
	OrbisSessionCapabilityFacts facts = ReadyFacts();
	[store updateFeature:OrbisSessionFeatureClipboardText direction:OrbisCapabilityDirectionToRemote
	               facts:facts limits:nil forGeneration:generation];
	OrbisSessionCapabilitiesSnapshot *before = store.snapshot;
	facts.enabled = NO;
	[store updateFeature:OrbisSessionFeatureClipboardText direction:OrbisCapabilityDirectionFromRemote
	               facts:facts limits:nil forGeneration:generation];
	XCTAssertTrue([store.snapshot capabilityForFeature:OrbisSessionFeatureClipboardText
	                                       direction:OrbisCapabilityDirectionToRemote].canAttempt);
	XCTAssertEqual([store.snapshot capabilityForFeature:OrbisSessionFeatureClipboardText
	                                        direction:OrbisCapabilityDirectionFromRemote].reason,
	               OrbisCapabilityReasonDisabled);
	XCTAssertEqual([before capabilityForFeature:OrbisSessionFeatureClipboardText
	                                direction:OrbisCapabilityDirectionFromRemote].reason,
	               OrbisCapabilityReasonNotImplemented);
	XCTAssertEqual([store.snapshot capabilityForFeature:OrbisSessionFeatureClipboardImage
	                                        direction:OrbisCapabilityDirectionToRemote].reason,
	               OrbisCapabilityReasonNotImplemented);
}

- (void)testReconnectAndEndRejectStaleCallbacks
{
	OrbisSessionCapabilities *store = [OrbisSessionCapabilities new];
	uint64_t first = [store beginSession];
	[store updateFeature:OrbisSessionFeatureDisplayResize direction:OrbisCapabilityDirectionToRemote
	               facts:ReadyFacts() limits:nil forGeneration:first];
	OrbisSessionCapabilitiesSnapshot *before = store.snapshot;
	uint64_t second = [store beginSession];
	XCTAssertNotEqual(first, second);
	XCTAssertFalse([store updateFeature:OrbisSessionFeatureDisplayResize
	                        direction:OrbisCapabilityDirectionToRemote facts:ReadyFacts() limits:nil
	                    forGeneration:first]);
	XCTAssertFalse([store endSessionForGeneration:first]);
	XCTAssertTrue(store.snapshot.active);
	XCTAssertEqual([store.snapshot capabilityForFeature:OrbisSessionFeatureDisplayResize
	                                        direction:OrbisCapabilityDirectionToRemote].reason,
	               OrbisCapabilityReasonNotImplemented);
	XCTAssertTrue([before capabilityForFeature:OrbisSessionFeatureDisplayResize
	                                direction:OrbisCapabilityDirectionToRemote].canAttempt);
	[store updateFeature:OrbisSessionFeatureDisplayResize direction:OrbisCapabilityDirectionToRemote
	               facts:ReadyFacts() limits:nil forGeneration:second];
	XCTAssertTrue([store endSessionForGeneration:second]);
	XCTAssertEqual([store.snapshot capabilityForFeature:OrbisSessionFeatureDisplayResize
	                                        direction:OrbisCapabilityDirectionToRemote].reason,
	               OrbisCapabilityReasonSessionInactive);
	XCTAssertFalse([store updateFeature:OrbisSessionFeatureDisplayResize
	                        direction:OrbisCapabilityDirectionToRemote facts:ReadyFacts() limits:nil
	                    forGeneration:second]);
}

- (void)testLimitsCopyMutableInputAndInvalidKeysFailClosed
{
	NSMutableString *encoding = [NSMutableString stringWithString:@"image/png"];
	NSMutableArray *formats = [NSMutableArray arrayWithObject:encoding];
	OrbisSessionCapabilityLimits *limits = [[OrbisSessionCapabilityLimits alloc]
	    initWithFormats:formats maximumBytes:123 maximumMonitors:2 maximumWidth:4096 maximumHeight:2160];
	[encoding setString:@"changed"];
	[formats removeAllObjects];
	XCTAssertEqualObjects(limits.formats, (@[ @"image/png" ]));
	OrbisSessionCapabilities *store = [OrbisSessionCapabilities new];
	uint64_t generation = [store beginSession];
	[store updateFeature:OrbisSessionFeatureClipboardImage direction:OrbisCapabilityDirectionToRemote
	               facts:ReadyFacts() limits:limits forGeneration:generation];
	XCTAssertEqual([store.snapshot capabilityForFeature:OrbisSessionFeatureClipboardImage
	                                        direction:OrbisCapabilityDirectionToRemote].limits.maximumBytes,
	               (NSUInteger)123);
	XCTAssertFalse([store updateFeature:(OrbisSessionFeature)NSUIntegerMax
	                        direction:OrbisCapabilityDirectionToRemote facts:ReadyFacts() limits:nil
	                    forGeneration:generation]);
	OrbisSessionCapability *invalid = [store.snapshot capabilityForFeature:OrbisSessionFeatureClipboardImage
	                                                          direction:(OrbisCapabilityDirection)42];
	XCTAssertEqual(invalid.reason, OrbisCapabilityReasonInvalidFeature);
	XCTAssertFalse(invalid.canAttempt);
}

- (void)testWorkerUpdatesPublishLatestGenerationOnMainQueue
{
	OrbisSessionCapabilities *store = [OrbisSessionCapabilities new];
	XCTestExpectation *published = [self expectationWithDescription:@"Latest capabilities observed on main"];
	__block uint64_t latest = 0;
	id observer = [NSNotificationCenter.defaultCenter
	    addObserverForName:OrbisSessionCapabilitiesDidChangeNotification object:store queue:nil
	    usingBlock:^(NSNotification *notification) {
		XCTAssertTrue(NSThread.isMainThread);
		XCTAssertEqual(notification.object, store);
		OrbisSessionCapabilitiesSnapshot *snapshot = store.snapshot;
		XCTAssertEqual(snapshot.generation, latest);
		XCTAssertTrue([snapshot capabilityForFeature:OrbisSessionFeatureClipboardImage
		                                   direction:OrbisCapabilityDirectionToRemote].canAttempt);
		[published fulfill];
	}];
	// All mutations finish before the main queue can drain its notification.
	dispatch_sync(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		uint64_t first = [store beginSession];
		latest = [store beginSession];
		XCTAssertFalse([store updateFeature:OrbisSessionFeatureClipboardImage
		                        direction:OrbisCapabilityDirectionToRemote facts:ReadyFacts() limits:nil
		                    forGeneration:first]);
		[store updateFeature:OrbisSessionFeatureClipboardImage direction:OrbisCapabilityDirectionToRemote
		               facts:ReadyFacts() limits:nil forGeneration:latest];
	});
	[self waitForExpectations:@[ published ] timeout:2];
	[NSNotificationCenter.defaultCenter removeObserver:observer];
}

- (void)testClipboardContentCopiesInputsAndRejectsInvalidPayloads
{
	NSMutableString *text = [NSMutableString stringWithString:@"Example"];
	const unsigned char signature[] = { 137, 80, 78, 71, 13, 10, 26, 10 };
	NSMutableData *png = [NSMutableData dataWithBytes:signature length:sizeof(signature)];
	OrbisClipboardContent *content = [[OrbisClipboardContent alloc] initWithText:text pngData:png];
	[text setString:@"Changed"];
	[png setLength:0];
	XCTAssertEqualObjects(content.text, @"Example");
	XCTAssertEqual(content.pngData.length, sizeof(signature));
	XCTAssertNil([[OrbisClipboardContent alloc] initWithText:nil pngData:nil]);
	XCTAssertNil([[OrbisClipboardContent alloc] initWithText:nil pngData:[NSData data]]);
	XCTAssertNil([[OrbisClipboardContent alloc] initWithText:nil pngData:[@"not PNG" dataUsingEncoding:NSUTF8StringEncoding]]);
	NSMutableData *oversized = [NSMutableData dataWithLength:OrbisClipboardMaximumPNGBytes + 1];
	memcpy(oversized.mutableBytes, signature, sizeof(signature));
	XCTAssertNil([[OrbisClipboardContent alloc] initWithText:nil pngData:oversized]);
	NSString *largeText = [@"x" stringByPaddingToLength:OrbisClipboardMaximumTextBytes + 1
	                                      withString:@"x" startingAtIndex:0];
	XCTAssertNil([[OrbisClipboardContent alloc] initWithText:largeText pngData:nil]);
	XCTAssertNotNil([[OrbisClipboardContent alloc] initWithText:@"" pngData:nil]);
}

@end
