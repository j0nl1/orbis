/* SPDX-License-Identifier: MIT */

#import <XCTest/XCTest.h>

#import <arpa/inet.h>
#import <sys/socket.h>
#import <unistd.h>

#import "OrbisTunnelBridge.h"
#import "OrbisDiagnostics.h"

@interface OrbisTunnelBridgeTests : XCTestCase
@property(nonatomic) NSTask *fixture;
@property(nonatomic) uint16_t fixturePort;
@property(nonatomic) OrbisTunnelBridge *bridge;
@property(nonatomic) NSURL *diagnosticsRoot;
@property(nonatomic) OrbisDiagnostics *diagnostics;
@end

@implementation OrbisTunnelBridgeTests

- (void)setUp
{
	[super setUp];
	self.diagnosticsRoot = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
	    URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
	self.diagnostics = [[OrbisDiagnostics alloc] initWithDirectoryURL:self.diagnosticsRoot];
	NSDictionary *environment = NSProcessInfo.processInfo.environment;
	self.fixture = [NSTask new];
	self.fixture.executableURL = [NSURL fileURLWithPath:environment[@"ORBIS_TUNNEL_FIXTURE_PYTHON"]];
	self.fixture.arguments = @[ environment[@"ORBIS_TUNNEL_FIXTURE_SCRIPT"] ];
	NSPipe *output = [NSPipe pipe];
	self.fixture.standardOutput = output;
	NSError *error = nil;
	XCTAssertTrue([self.fixture launchAndReturnError:&error], @"%@", error);
	// Read only the startup port; the fixture never prints request headers or payloads.
	NSMutableData *line = [NSMutableData new];
	while (line.length < 8)
	{
		NSData *byte = [output.fileHandleForReading readDataOfLength:1];
		if (byte.length == 0 || ((const uint8_t *)byte.bytes)[0] == '\n')
			break;
		[line appendData:byte];
	}
	self.fixturePort = (uint16_t)[[[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding] intValue];
	XCTAssertGreaterThan(self.fixturePort, 0);
}

- (void)tearDown
{
	[self.bridge stop];
	self.bridge = nil;
	if (self.fixture.running)
		[self.fixture terminate];
	[self.fixture waitUntilExit];
	self.fixture = nil;
	[NSFileManager.defaultManager removeItemAtURL:self.diagnosticsRoot error:nil];
	[super tearDown];
}

- (int)connectToPath:(NSString *)path failure:(void (^)(NSError *))failure
{
	NSString *endpoint = [NSString stringWithFormat:@"ws://127.0.0.1:%u%@", self.fixturePort, path];
	NSError *error = nil;
	self.bridge = [[OrbisTunnelBridge alloc] initWithEndpoint:[NSURL URLWithString:endpoint]
	                                              clientID:@"fixture-client"
	                                          clientSecret:@"fixture-secret"
	                                           diagnostics:self.diagnostics error:&error];
	XCTAssertNotNil(self.bridge, @"%@", error);
	XCTestExpectation *ready = [self expectationWithDescription:@"Loopback listener ready"];
	__block uint16_t port = 0;
	[self.bridge startOnPort:0 ready:^(uint16_t listeningPort, NSError *readyError) {
		XCTAssertNil(readyError);
		port = listeningPort;
		[ready fulfill];
	} streamFailure:failure ?: ^(NSError *streamError) {
		XCTFail(@"Unexpected stream failure: %@", streamError);
	}];
	[self waitForExpectations:@[ ready ] timeout:5];
	int socketFD = socket(AF_INET, SOCK_STREAM, 0);
	XCTAssertGreaterThanOrEqual(socketFD, 0);
	struct timeval timeout = { .tv_sec = 5 };
	setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
	setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
	int noSignal = 1;
	setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
	struct sockaddr_in address = { .sin_len = sizeof(address), .sin_family = AF_INET,
	                              .sin_port = htons(port), .sin_addr.s_addr = htonl(INADDR_LOOPBACK) };
	XCTAssertEqual(connect(socketFD, (struct sockaddr *)&address, sizeof(address)), 0);
	return socketFD;
}

- (NSData *)readBytes:(size_t)length fromSocket:(int)socketFD
{
	NSMutableData *received = [NSMutableData dataWithLength:length];
	size_t offset = 0;
	while (offset < length)
	{
		ssize_t count = recv(socketFD, (uint8_t *)received.mutableBytes + offset, length - offset, 0);
		if (count <= 0)
			break;
		offset += (size_t)count;
	}
	[received setLength:offset];
	return received;
}

- (void)testServiceAuthAndBinaryByteOrderAcrossDifferentFrameBoundaries
{
	int socketFD = [self connectToPath:@"/echo" failure:nil];
	NSMutableData *payload = [NSMutableData dataWithLength:2 * 1024 * 1024 + 37];
	for (NSUInteger index = 0; index < payload.length; index++)
		((uint8_t *)payload.mutableBytes)[index] = (uint8_t)((index * 73) % 251);
	XCTestExpectation *sent = [self expectationWithDescription:@"TCP payload sent"];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		size_t offset = 0;
		while (offset < payload.length)
		{
			ssize_t count = send(socketFD, (const uint8_t *)payload.bytes + offset,
			                     MIN((size_t)7919, payload.length - offset), 0);
			if (count <= 0)
				break;
			offset += (size_t)count;
		}
		XCTAssertEqual(offset, payload.length);
		[sent fulfill];
	});
	XCTAssertEqualObjects([self readBytes:payload.length fromSocket:socketFD], payload);
	[self waitForExpectations:@[ sent ] timeout:10];
	close(socketFD);
}

- (void)testServerCanSendFirstAndFragmentMessages
{
	int socketFD = [self connectToPath:@"/push" failure:nil];
	NSData *data = [self readBytes:1024 * 1024 fromSocket:socketFD];
	XCTAssertEqual(data.length, (NSUInteger)1024 * 1024);
	BOOL matches = YES;
	for (NSUInteger index = 0; index < data.length; index++)
		matches &= ((const uint8_t *)data.bytes)[index] == (uint8_t)index;
	XCTAssertTrue(matches);
	close(socketFD);
}

- (void)assertFailureAtPath:(NSString *)path contains:(NSString *)description
{
	XCTestExpectation *failed = [self expectationWithDescription:@"Stream failure delivered once"];
	failed.assertForOverFulfill = YES;
	int socketFD = [self connectToPath:path failure:^(NSError *error) {
		XCTAssertTrue([error.localizedDescription containsString:description], @"%@", error);
		XCTAssertFalse([error.description containsString:@"fixture-secret"]);
		[failed fulfill];
	}];
	[self waitForExpectations:@[ failed ] timeout:5];
	XCTAssertEqual([self readBytes:1 fromSocket:socketFD].length, (NSUInteger)0);
	close(socketFD);
}

- (void)testAccessDenialIsReportedAndClosesTCP
{
	[self assertFailureAtPath:@"/deny" contains:@"Access denied"];
}

- (void)testAccessRedirectIsNeverFollowed
{
	[self assertFailureAtPath:@"/redirect" contains:@"redirected"];
}

- (void)testTextFramesAreRejected
{
	[self assertFailureAtPath:@"/text" contains:@"non-binary"];
}

- (void)testRemoteClosureClosesTCP
{
	[self assertFailureAtPath:@"/close" contains:@"closed"];
}

- (void)testStopClosesAnActiveConnectionWithoutReportingFailure
{
	int socketFD = [self connectToPath:@"/echo" failure:nil];
	const uint8_t bytes[] = { 0, 1, 2, 255 };
	XCTAssertEqual(send(socketFD, bytes, sizeof(bytes), 0), (ssize_t)sizeof(bytes));
	XCTAssertEqualObjects([self readBytes:sizeof(bytes) fromSocket:socketFD],
	                      [NSData dataWithBytes:bytes length:sizeof(bytes)]);
	[self.bridge stop];
	XCTAssertEqual([self readBytes:1 fromSocket:socketFD].length, (NSUInteger)0);
	NSArray *closed = [[self diagnosticEvents] filteredArrayUsingPredicate:
	    [NSPredicate predicateWithFormat:@"event == 'tunnel.closed'"]];
	XCTAssertEqual(closed.count, 1u);
	XCTAssertEqualObjects(closed.firstObject[@"values"][@"intentional"], @1);
	XCTAssertEqualObjects(closed.firstObject[@"values"][@"sent_bytes"], @4);
	XCTAssertEqualObjects(closed.firstObject[@"values"][@"received_bytes"], @4);
	close(socketFD);
}

- (void)testInvalidEndpointsAndHeaderInjectionAreRejected
{
	for (NSString *url in @[ @"ws://remote.example.test", @"http://remote.example.test",
	                        @"wss://user:password@remote.example.test", @"wss://remote.example.test/#fragment" ])
	{
		NSError *error = nil;
		XCTAssertNil([[OrbisTunnelBridge alloc] initWithEndpoint:[NSURL URLWithString:url]
		                                             clientID:@"fixture-client" clientSecret:@"fixture-secret" error:&error]);
		XCTAssertNotNil(error);
	}
	NSError *error = nil;
	XCTAssertNil([[OrbisTunnelBridge alloc] initWithEndpoint:[NSURL URLWithString:@"wss://remote.example.test"]
	                                             clientID:@"fixture-client\r\nInjected: value"
	                                         clientSecret:@"fixture-secret" error:&error]);
	XCTAssertNotNil(error);
}

- (void)testProfileHostnamesProduceSecureEndpointsAndRejectURLComponents
{
	NSError *error = nil;
	XCTAssertEqualObjects([[OrbisTunnelBridge endpointForHostname:@"RDP.EXAMPLE.TEST" error:&error] absoluteString],
	                      @"wss://rdp.example.test/");
	XCTAssertNil(error);
	for (NSString *host in @[ @"", @"https://rdp.example.test", @"rdp.example.test:3389",
	                         @"rdp.example.test/path", @"user@rdp.example.test", @"rdp..example.test",
	                         @"-rdp.example.test", @"rdp.example.test?query" ])
	{
		XCTAssertNil([OrbisTunnelBridge endpointForHostname:host error:&error]);
		XCTAssertNotNil(error);
	}
}

- (void)testHandshakeErrorsRemainAvailableToTheRDPSession
{
	XCTestExpectation *failed = [self expectationWithDescription:@"Handshake rejected"];
	int socketFD = [self connectToPath:@"/deny" failure:^(NSError *error) {
		[failed fulfill];
	}];
	[self waitForExpectations:@[ failed ] timeout:5];
	XCTAssertEqual([self.bridge lastHandshakeError].code, (NSInteger)403);
	XCTAssertEqual([self readBytes:1 fromSocket:socketFD].length, (NSUInteger)0);
	close(socketFD);
}

- (NSArray *)diagnosticEvents
{
	NSURL *url = [self.diagnostics exportToDirectory:self.diagnosticsRoot error:nil];
	return [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url]
	    options:0 error:nil][@"events"];
}

- (void)testEstablishedTCPResetRetainsRayIDAndNativeErrorBeforeClosingLoopback
{
	XCTestExpectation *failed = [self expectationWithDescription:@"Established stream reset"];
	failed.assertForOverFulfill = YES;
	int socketFD = [self connectToPath:@"/reset" failure:^(NSError *error) { [failed fulfill]; }];
	[self waitForExpectations:@[ failed ] timeout:5];
	NSArray *events = [self diagnosticEvents];
	NSDictionary *opened = [[events filteredArrayUsingPredicate:
	    [NSPredicate predicateWithFormat:@"event == 'tunnel.opened'"]] firstObject];
	NSDictionary *ended = [[events filteredArrayUsingPredicate:
	    [NSPredicate predicateWithFormat:@"event == 'tunnel.closed'"]] firstObject];
	XCTAssertNotNil(opened);
	XCTAssertNotNil(ended);
	XCTAssertEqualObjects(opened[@"cf_ray_id"], @"a4af05b09864f778-LIS");
	XCTAssertEqualObjects(ended[@"cf_ray_id"], opened[@"cf_ray_id"]);
	XCTAssertEqualObjects(ended[@"values"][@"stream_id"], opened[@"values"][@"stream_id"]);
	XCTAssertGreaterThan([opened[@"values"][@"stream_id"] unsignedLongLongValue], 0u);
	XCTAssertGreaterThan([opened[@"values"][@"transport_id"] unsignedLongLongValue], 0u);
	XCTAssertEqualObjects(ended[@"values"][@"transport_id"], opened[@"values"][@"transport_id"]);
	XCTAssertEqualObjects(ended[@"values"][@"intentional"], @0);
	XCTAssertNotEqual([ended[@"values"][@"native_code"] integerValue], 0);
	XCTAssertGreaterThan([ended[@"values"][@"duration_ms"] doubleValue], 0);
	XCTAssertEqual([self readBytes:1 fromSocket:socketFD].length, (NSUInteger)0);
	NSString *json = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:events
	    options:0 error:nil] encoding:NSUTF8StringEncoding];
	for (NSString *secret in @[ @"fixture-secret", @"fixture-client", @"X-Secret", @"127.0.0.1", @"/reset" ])
		XCTAssertFalse([json containsString:secret]);
	close(socketFD);
}

- (void)testRejectedUpgradeRecordsHTTPStatusAndRayID
{
	[self assertFailureAtPath:@"/deny" contains:@"Access denied"];
	NSArray *events = [self diagnosticEvents];
	NSDictionary *ended = [[events filteredArrayUsingPredicate:
	    [NSPredicate predicateWithFormat:@"event == 'tunnel.closed'"]] firstObject];
	XCTAssertEqualObjects(ended[@"cf_ray_id"], @"a4af05b09864f778-LIS");
	XCTAssertEqualObjects(ended[@"values"][@"http_status"], @403);
}

- (void)testRemoteCloseRecordsTheWebSocketCodeWithoutItsReason
{
	[self assertFailureAtPath:@"/close" contains:@"closed"];
	NSArray *events;
	NSDictionary *closed;
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
	do
	{
		events = [self diagnosticEvents];
		closed = [[events filteredArrayUsingPredicate:
		    [NSPredicate predicateWithFormat:@"event == 'tunnel.websocket_closed'"]] firstObject];
		if (!closed) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
	} while (!closed && deadline.timeIntervalSinceNow > 0);
	XCTAssertEqualObjects(closed[@"values"][@"close_code"], @1000);
	NSArray *ended = [events filteredArrayUsingPredicate:
	    [NSPredicate predicateWithFormat:@"event == 'tunnel.closed'"]];
	XCTAssertEqual(ended.count, 1u);
	XCTAssertEqualObjects(ended.firstObject[@"values"][@"intentional"], @0);
}

@end
