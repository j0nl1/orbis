/* SPDX-License-Identifier: MIT */

#import <XCTest/XCTest.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <unistd.h>

#import "OrbisConnectionTransport.h"
#import "OrbisDirectTransport.h"
#import "OrbisCloudflareTransport.h"
#import "OrbisTransportFactory.h"
#import "OrbisProfile.h"

@interface OrbisConnectionTransportTests : XCTestCase
@property(nonatomic, strong) NSTask *fixture;
@property(nonatomic) uint16_t fixturePort;
@property(nonatomic, strong) NSMutableArray<id<OrbisTransportSession>> *sessions;
@end

@implementation OrbisConnectionTransportTests
- (void)setUp
{
	[super setUp];
	self.sessions = [NSMutableArray new];
}
- (void)tearDown
{
	for (id<OrbisTransportSession> session in self.sessions)
		[session close];
	[self.sessions removeAllObjects];
	if (self.fixture.running)
		[self.fixture terminate];
	[self.fixture waitUntilExit];
	self.fixture = nil;
	[super tearDown];
}
- (id<OrbisConnectionTransport>)cloudflareTransportForPath:(NSString *)path
{
	if (!self.fixture)
	{
		NSDictionary *environment = NSProcessInfo.processInfo.environment;
		self.fixture = [NSTask new];
		self.fixture.executableURL = [NSURL fileURLWithPath:environment[@"ORBIS_TUNNEL_FIXTURE_PYTHON"]];
		self.fixture.arguments = @[ environment[@"ORBIS_TUNNEL_FIXTURE_SCRIPT"] ];
		NSPipe *output = [NSPipe pipe];
		self.fixture.standardOutput = output;
		NSError *error = nil;
		XCTAssertTrue([self.fixture launchAndReturnError:&error], @"%@", error);
		NSMutableData *line = [NSMutableData new];
		while (line.length < 8)
		{
			NSData *byte = [output.fileHandleForReading readDataOfLength:1];
			if (!byte.length || ((const uint8_t *)byte.bytes)[0] == '\n')
				break;
			[line appendData:byte];
		}
		self.fixturePort = (uint16_t)[[[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding] intValue];
		XCTAssertGreaterThan(self.fixturePort, 0);
	}
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"ws://127.0.0.1:%u%@", self.fixturePort, path]];
	NSError *error = nil;
	id<OrbisConnectionTransport> transport = [[OrbisCloudflareTransport alloc] initWithEndpoint:url
	    clientID:@"fixture-client" clientSecret:@"fixture-secret" error:&error];
	XCTAssertNotNil(transport, @"%@", error);
	return transport;
}
- (int)socketForDestination:(OrbisTransportDestination *)destination
{
	int fd = socket(AF_INET, SOCK_STREAM, 0);
	XCTAssertGreaterThanOrEqual(fd, 0);
	struct timeval timeout = { .tv_sec = 5 };
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
	setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
	int noSignal = 1;
	setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
	struct sockaddr_in address = { .sin_len = sizeof(address), .sin_family = AF_INET,
	    .sin_port = htons(destination.port), .sin_addr.s_addr = htonl(INADDR_LOOPBACK) };
	XCTAssertEqual(connect(fd, (struct sockaddr *)&address, sizeof(address)), 0);
	return fd;
}
- (void)testDirectTransportKeepsRDPRoutingAndCompletesAsynchronously
{
	OrbisProfile *profile = [OrbisProfile new];
	profile.host = @"logical-server.example.test";
	NSError *error = nil;
	id<OrbisConnectionTransport> transport = [OrbisTransportFactory transportForProfile:profile error:&error];
	XCTAssertNotNil(transport);
	XCTAssertNil(error);
	XCTestExpectation *ready = [self expectationWithDescription:@"Direct transport ready"];
	__block BOOL called = NO;
	id<OrbisTransportSession> session = [transport prepareWithCompletion:^(OrbisTransportDestination *destination, NSError *readyError) {
		called = YES;
		XCTAssertTrue(NSThread.isMainThread);
		XCTAssertNil(destination);
		XCTAssertNil(readyError);
		[ready fulfill];
	}];
	[self.sessions addObject:session];
	XCTAssertFalse(called);
	[self waitForExpectations:@[ ready ] timeout:5];
	XCTAssertNil(session.connectionError);
	XCTAssertEqualObjects(profile.host, @"logical-server.example.test");
	[session close];
	[session close];
}
- (void)testUnknownTransportFailsWithoutFallingBackToDirect
{
	OrbisProfile *profile = [OrbisProfile new];
	profile.transportType = @"future-gateway";
	NSError *error = nil;
	XCTAssertNil([OrbisTransportFactory transportForProfile:profile error:&error]);
	XCTAssertNotNil(error);
}
- (void)testBothAdaptersCompleteCancellationExactlyOnce
{
	for (id<OrbisConnectionTransport> transport in @[ [OrbisDirectTransport new], [self cloudflareTransportForPath:@"/echo"] ])
	{
		XCTestExpectation *cancelled = [self expectationWithDescription:@"Preparation cancelled"];
		cancelled.assertForOverFulfill = YES;
		id<OrbisTransportSession> session = [transport prepareWithCompletion:^(OrbisTransportDestination *destination, NSError *error) {
			XCTAssertTrue(NSThread.isMainThread);
			XCTAssertNil(destination);
			XCTAssertEqual(error.code, NSUserCancelledError);
			[cancelled fulfill];
		}];
		[self.sessions addObject:session];
		[session close];
		[session close];
		[self waitForExpectations:@[ cancelled ] timeout:5];
	}
}
- (void)testCloudflareAttemptsOwnIndependentStreamsAndCanRetryAfterClose
{
	id<OrbisConnectionTransport> transport = [self cloudflareTransportForPath:@"/echo"];
	NSMutableArray<OrbisTransportDestination *> *destinations = [NSMutableArray new];
	for (NSUInteger attempt = 0; attempt < 2; attempt++)
	{
		XCTestExpectation *ready = [self expectationWithDescription:@"Tunnel attempt ready"];
		id<OrbisTransportSession> session = [transport prepareWithCompletion:^(OrbisTransportDestination *destination, NSError *error) {
			XCTAssertNil(error);
			XCTAssertEqualObjects(destination.hostname, @"127.0.0.1");
			XCTAssertGreaterThan(destination.port, 0);
			[destinations addObject:destination];
			[ready fulfill];
		}];
		[self.sessions addObject:session];
		[self waitForExpectations:@[ ready ] timeout:5];
		int fd = [self socketForDestination:destinations.lastObject];
		const char payload[] = "RDP bytes through the common transport interface";
		XCTAssertEqual(send(fd, payload, sizeof(payload), 0), (ssize_t)sizeof(payload));
		char received[sizeof(payload)];
		XCTAssertEqual(recv(fd, received, sizeof(received), MSG_WAITALL), (ssize_t)sizeof(received));
		XCTAssertEqual(memcmp(payload, received, sizeof(payload)), 0);
		[session close];
		char byte;
		XCTAssertLessThanOrEqual(recv(fd, &byte, 1, 0), (ssize_t)0);
		close(fd);
	}
}
- (void)testClosingOnePreparedSessionDoesNotCloseAnother
{
	id<OrbisConnectionTransport> transport = [self cloudflareTransportForPath:@"/echo"];
	NSMutableArray<OrbisTransportDestination *> *destinations = [NSMutableArray new];
	for (NSUInteger attempt = 0; attempt < 2; attempt++)
	{
		XCTestExpectation *ready = [self expectationWithDescription:@"Independent session ready"];
		id<OrbisTransportSession> session = [transport prepareWithCompletion:^(OrbisTransportDestination *destination, NSError *error) {
			XCTAssertNil(error);
			[destinations addObject:destination];
			[ready fulfill];
		}];
		[self.sessions addObject:session];
		[self waitForExpectations:@[ ready ] timeout:5];
	}
	XCTAssertNotEqual(destinations[0].port, destinations[1].port);
	int sockets[2] = { [self socketForDestination:destinations[0]], [self socketForDestination:destinations[1]] };
	for (NSUInteger index = 0; index < 2; index++)
	{
		char sent = 'a', received = 0;
		XCTAssertEqual(send(sockets[index], &sent, 1, 0), (ssize_t)1);
		XCTAssertEqual(recv(sockets[index], &received, 1, 0), (ssize_t)1);
		XCTAssertEqual(sent, received);
	}
	[self.sessions[0] close];
	char byte;
	XCTAssertLessThanOrEqual(recv(sockets[0], &byte, 1, 0), (ssize_t)0);
	char sent = 'b';
	XCTAssertEqual(send(sockets[1], &sent, 1, 0), (ssize_t)1);
	XCTAssertEqual(recv(sockets[1], &byte, 1, 0), (ssize_t)1);
	XCTAssertEqual(sent, byte);
	close(sockets[0]);
	close(sockets[1]);
}

- (void)testCloudflareHandshakeFailureIsAvailableThroughTheCommonInterface
{
	id<OrbisConnectionTransport> transport = [self cloudflareTransportForPath:@"/deny"];
	XCTestExpectation *ready = [self expectationWithDescription:@"Listener ready"];
	__block OrbisTransportDestination *destination = nil;
	id<OrbisTransportSession> session = [transport prepareWithCompletion:^(OrbisTransportDestination *value, NSError *error) {
		destination = value;
		XCTAssertNil(error);
		[ready fulfill];
	}];
	[self.sessions addObject:session];
	[self waitForExpectations:@[ ready ] timeout:5];
	int fd = [self socketForDestination:destination];
	char byte;
	XCTAssertLessThanOrEqual(recv(fd, &byte, 1, 0), (ssize_t)0);
	XCTAssertEqual(session.connectionError.code, 403);
	XCTAssertFalse([session.connectionError.description containsString:@"fixture-secret"]);
	close(fd);
}
@end
