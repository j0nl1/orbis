/* SPDX-License-Identifier: MIT */
#import <XCTest/XCTest.h>
#import <MetricKit/MetricKit.h>
#import "OrbisDiagnostics.h"

@interface OrbisDiagnostics (Testing)
- (void)recoverPreviousSession;
- (void)didReceiveDiagnosticPayloads:(NSArray *)payloads;
@end

@interface OrbisTestCallStack : NSObject
@end
@implementation OrbisTestCallStack
- (NSData *)JSONRepresentation
{
	return [NSJSONSerialization dataWithJSONObject:@{ @"callStacks" : @[
	    @{ @"binaryUUID" : @"11111111-2222-3333-4444-555555555555", @"offsetIntoBinaryTextSegment" : @1234 }
	] } options:0 error:nil];
}
@end
@interface OrbisTestCrashDiagnostic : NSObject
@end
@implementation OrbisTestCrashDiagnostic
- (NSString *)applicationVersion { return @"1.2.3"; }
- (NSNumber *)signal { return @11; }
- (NSNumber *)exceptionType { return @1; }
- (NSNumber *)exceptionCode { return @42; }
- (OrbisTestCallStack *)callStackTree { return [[OrbisTestCallStack alloc] init]; }
- (NSString *)terminationReason { return @"secret-exception-content"; }
@end
@interface OrbisTestHangDiagnostic : OrbisTestCrashDiagnostic
@end
@implementation OrbisTestHangDiagnostic
- (NSMeasurement *)hangDuration { return [[NSMeasurement alloc] initWithDoubleValue:2.5 unit:NSUnitDuration.seconds]; }
@end
@interface OrbisTestDiagnosticPayload : NSObject
@property(nonatomic) NSDate *timeStampBegin;
@property(nonatomic) NSDate *timeStampEnd;
@property(nonatomic) NSArray *crashDiagnostics;
@property(nonatomic) NSArray *hangDiagnostics;
@end
@implementation OrbisTestDiagnosticPayload
@end

@interface OrbisDiagnosticsTests : XCTestCase
@property(nonatomic) NSURL *root;
@property(nonatomic) OrbisDiagnostics *diagnostics;
@end
@implementation OrbisDiagnosticsTests
- (void)setUp
{
	[super setUp];
	self.root = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
	    URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
	self.diagnostics = [[OrbisDiagnostics alloc] initWithDirectoryURL:[self.root URLByAppendingPathComponent:@"store"]];
}
- (void)tearDown
{
	self.diagnostics = nil;
	[NSFileManager.defaultManager removeItemAtURL:self.root error:nil];
	[super tearDown];
}
- (NSDictionary *)snapshot
{
	NSError *error;
	NSURL *url = [self.diagnostics exportToDirectory:[self.root URLByAppendingPathComponent:@"export"] error:&error];
	XCTAssertNotNil(url); XCTAssertNil(error);
	return [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:nil];
}
- (OrbisTestDiagnosticPayload *)payloadAt:(NSUInteger)time
{
	OrbisTestDiagnosticPayload *payload = [[OrbisTestDiagnosticPayload alloc] init];
	payload.timeStampBegin = [NSDate dateWithTimeIntervalSince1970:time];
	payload.timeStampEnd = [NSDate dateWithTimeIntervalSince1970:time + 100];
	payload.crashDiagnostics = @[ [[OrbisTestCrashDiagnostic alloc] init] ];
	payload.hangDiagnostics = @[ [[OrbisTestHangDiagnostic alloc] init] ];
	return payload;
}
- (void)testEventsPersistAcrossLaunchesWithoutCredentialsOrErrorDescriptions
{
	[self.diagnostics recordEvent:@"session.connecting" values:(id)@{ @"width" : @2732,
	    @"password" : @"secret-password", @"hostname" : @"private.example", @"code" : @7 }];
	NSError *error = [NSError errorWithDomain:@"secret-domain" code:99
	    userInfo:@{ NSLocalizedDescriptionKey : @"secret-password", @"token" : @"secret-token" }];
	[self.diagnostics recordError:error event:@"transport.failed"];
	self.diagnostics = [[OrbisDiagnostics alloc] initWithDirectoryURL:[self.root URLByAppendingPathComponent:@"store"]];
	[self.diagnostics recordEvent:@"app.launch" values:nil];
	NSDictionary *snapshot = [self snapshot];
	NSArray *events = snapshot[@"events"];
	XCTAssertEqual(events.count, 3u);
	XCTAssertEqualObjects(events[0][@"values"], (@{ @"width" : @2732, @"code" : @7 }));
	XCTAssertEqualObjects(events[1][@"values"][@"code"], @99);
	XCTAssertEqual([events[0][@"binary_uuid"] length], 36u);
	XCTAssertNotEqualObjects(events[0][@"launch_id"], events[2][@"launch_id"]);
	NSString *text = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil]
	    encoding:NSUTF8StringEncoding];
	for (NSString *secret in @[ @"secret-password", @"secret-token", @"private.example", @"secret-domain" ])
		XCTAssertFalse([text containsString:secret]);
}
- (void)testConcurrentRecordsProduceCompleteJSONLines
{
	dispatch_apply(80, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^(size_t index) {
		[self.diagnostics recordEvent:@"display.requested" values:@{ @"code" : @(index) }];
	});
	NSArray *events = [self snapshot][@"events"];
	XCTAssertEqual(events.count, 80u);
	NSMutableSet *codes = [NSMutableSet set];
	for (NSDictionary *event in events) [codes addObject:event[@"values"][@"code"]];
	XCTAssertEqual(codes.count, 80u);
}
- (void)testEventRotationBoundsStorageAndPreservesTheNewestRecords
{
	NSString *event = [@"session." stringByPaddingToLength:1500 withString:@"x" startingAtIndex:0];
	for (NSUInteger index = 0; index < 1600; index++)
		[self.diagnostics recordEvent:event values:@{ @"code" : @(index) }];
	NSURL *store = [self.root URLByAppendingPathComponent:@"store"];
	for (NSString *file in @[ @"events.jsonl", @"events.previous.jsonl" ])
	{
		NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:[store URLByAppendingPathComponent:file].path error:nil];
		XCTAssertGreaterThan(attrs.fileSize, 0u);
		XCTAssertLessThanOrEqual(attrs.fileSize, 1024u * 1024u);
	}
	NSArray *events = [self snapshot][@"events"];
	XCTAssertGreaterThan(events.count, 0u); XCTAssertLessThan(events.count, 1600u);
	XCTAssertEqualObjects(events.lastObject[@"values"][@"code"], @1599);
}
- (void)testCrashAndHangReportsRetainStacksAndAreDeduplicated
{
	OrbisTestDiagnosticPayload *payload = [self payloadAt:1000];
	[self.diagnostics didReceiveDiagnosticPayloads:(id)@[payload, payload]];
	NSDictionary *snapshot = [self snapshot];
	NSArray *reports = snapshot[@"system_reports"];
	XCTAssertEqual(reports.count, 1u);
	NSDictionary *report = reports.firstObject;
	XCTAssertEqualObjects(report[@"crashes"][0][@"signal"], @11);
	XCTAssertEqualObjects(report[@"crashes"][0][@"call_stack_tree"][@"callStacks"][0][@"offsetIntoBinaryTextSegment"], @1234);
	XCTAssertEqualObjects(report[@"hangs"][0][@"duration_seconds"], @2.5);
	NSString *text = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil]
	    encoding:NSUTF8StringEncoding];
	XCTAssertFalse([text containsString:@"secret-exception-content"]);
}
- (void)testSystemReportRetentionAndExportRemainBounded
{
	for (NSUInteger index = 0; index < 13; index++)
		[self.diagnostics didReceiveDiagnosticPayloads:(id)@[[self payloadAt:index * 1000]]];
	NSArray *reports = [self snapshot][@"system_reports"];
	XCTAssertEqual(reports.count, 10u);
	XCTAssertEqualObjects(reports.firstObject[@"timestamp_begin"], @12000);
	[self.diagnostics didReceiveDiagnosticPayloads:(id)@[[self payloadAt:0]]];
	reports = [self snapshot][@"system_reports"];
	XCTAssertEqual(reports.count, 10u);
	XCTAssertEqualObjects(reports.firstObject[@"timestamp_begin"], @12000);
	NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:[self.root URLByAppendingPathComponent:@"store"].path error:nil];
	XCTAssertEqual(files.count, 10u);
}
- (void)testExportReportsUnavailableStorageWithoutCrashing
{
	[NSFileManager.defaultManager createDirectoryAtURL:self.root withIntermediateDirectories:YES attributes:nil error:nil];
	NSURL *blocked = [self.root URLByAppendingPathComponent:@"blocked"];
	[[NSData data] writeToURL:blocked atomically:YES];
	self.diagnostics = [[OrbisDiagnostics alloc] initWithDirectoryURL:blocked];
	[self.diagnostics recordEvent:@"session.failed" values:@{ @"code" : @1 }];
	NSError *error;
	XCTAssertNil([self.diagnostics exportToDirectory:[self.root URLByAppendingPathComponent:@"export"] error:&error]);
	XCTAssertNotNil(error);
}
- (void)testInterruptedSessionRetainsPreviousLaunchAndBackgroundStateOnlyOnce
{
	[self.diagnostics recordEvent:@"app.launch" values:nil];
	[self.diagnostics setActiveSessionState:2];
	[self.diagnostics recordEvent:@"scene.background" values:nil];
	NSArray *before = [self snapshot][@"events"];
	NSString *previousLaunch = before[0][@"launch_id"];
	NSURL *store = [self.root URLByAppendingPathComponent:@"store"];
	NSURL *marker = [store URLByAppendingPathComponent:@"active-session.plist"];
	XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:marker.path]);
	self.diagnostics = [[OrbisDiagnostics alloc] initWithDirectoryURL:store];
	[self.diagnostics recoverPreviousSession];
	[self.diagnostics recoverPreviousSession];
	NSArray *events = [self snapshot][@"events"];
	XCTAssertEqual(events.count, 3u);
	NSDictionary *interrupted = events.lastObject;
	XCTAssertEqualObjects(interrupted[@"event"], @"app.previous_session_interrupted");
	XCTAssertEqualObjects(interrupted[@"previous_launch_id"], previousLaunch);
	XCTAssertNotEqualObjects(interrupted[@"launch_id"], previousLaunch);
	XCTAssertEqualObjects(interrupted[@"values"][@"session_state"], @2);
	XCTAssertEqualObjects(interrupted[@"values"][@"app_state"], @3);
	XCTAssertGreaterThan([interrupted[@"values"][@"previous_timestamp"] doubleValue], 0);
	XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:marker.path]);
}
- (void)testNormalSessionEndAndGracefulTerminationDoNotReportInterruption
{
	NSURL *store = [self.root URLByAppendingPathComponent:@"store"];
	for (NSNumber *terminate in @[@NO, @YES])
	{
		[self.diagnostics setActiveSessionState:1];
		if (terminate.boolValue) [self.diagnostics recordEvent:@"app.terminating" values:nil];
		else [self.diagnostics setActiveSessionState:0];
		self.diagnostics = [[OrbisDiagnostics alloc] initWithDirectoryURL:store];
		[self.diagnostics recoverPreviousSession];
	}
	NSArray *events = [self snapshot][@"events"];
	XCTAssertEqual(events.count, 1u);
	XCTAssertEqualObjects(events.firstObject[@"event"], @"app.terminating");
}
- (void)testMalformedSessionMarkersAreIgnoredAndRemoved
{
	NSURL *store = [self.root URLByAppendingPathComponent:@"store"];
	[NSFileManager.defaultManager createDirectoryAtURL:store withIntermediateDirectories:YES attributes:nil error:nil];
	NSURL *marker = [store URLByAppendingPathComponent:@"active-session.plist"];
	for (id malformed in @[@"invalid", @{ @"launch_id" : @"private-host", @"session_state" : @2, @"timestamp" : @100 },
	    @{ @"launch_id" : NSUUID.UUID.UUIDString, @"session_state" : @1.5, @"timestamp" : @100 }])
	{
		NSData *data = [NSPropertyListSerialization dataWithPropertyList:malformed format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
		[data writeToURL:marker atomically:YES];
		[self.diagnostics recoverPreviousSession];
		XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:marker.path]);
	}
	XCTAssertEqual([[self snapshot][@"events"] count], 0u);
}
- (void)testDisconnectContextPersistsWithoutFreeFormTransportDetails
{
	NSDictionary *context = @{ @"intentional" : @0, @"loop_exit" : @3, @"rdp_error" : @123,
	    @"rdp_error_info" : @456, @"connection_state" : @2, @"code" : @0 };
	NSMutableDictionary *values = [context mutableCopy];
	values[@"description"] = @"private transport address";
	[self.diagnostics recordEvent:@"session.rdp_stopped" values:(id)values];
	XCTAssertEqualObjects([self snapshot][@"events"][0][@"values"], context);
}
@end
