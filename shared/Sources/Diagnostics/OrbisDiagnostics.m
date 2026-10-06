/* SPDX-License-Identifier: MIT */
#import "OrbisDiagnostics.h"
#import <MetricKit/MetricKit.h>
#import <CommonCrypto/CommonDigest.h>
#import <TargetConditionals.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <math.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>

static const NSUInteger OrbisEventFileLimit = 1024 * 1024;
static const NSUInteger OrbisSystemReportLimit = 2 * 1024 * 1024;
static const NSUInteger OrbisSystemReportCount = 10;

@interface OrbisDiagnostics () <MXMetricManagerSubscriber>
@end

@implementation OrbisDiagnostics
{
	NSURL *_directory;
	NSString *_launchID;
	NSString *_binaryUUID;
	BOOL _started;
	NSUInteger _activeSessionState;
	NSUInteger _applicationState;
	NSString *_previousLaunchID;
}

+ (instancetype)sharedDiagnostics
{
	static OrbisDiagnostics *diagnostics;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSURL *support = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
		    inDomains:NSUserDomainMask].firstObject;
		diagnostics = [[self alloc] initWithDirectoryURL:[[support URLByAppendingPathComponent:@"Orbis"]
		    URLByAppendingPathComponent:@"Diagnostics"]];
	});
	return diagnostics;
}

- (instancetype)initWithDirectoryURL:(NSURL *)directory
{
	if (!(self = [super init])) return nil;
	_directory = directory;
	_launchID = NSUUID.UUID.UUIDString;
	const struct mach_header_64 *image = (const struct mach_header_64 *)_dyld_get_image_header(0);
	if (image && image->magic == MH_MAGIC_64)
	{
		const uint8_t *cursor = (const uint8_t *)(image + 1);
		for (uint32_t i = 0; i < image->ncmds; i++)
		{
			const struct load_command *command = (const struct load_command *)cursor;
			if (command->cmd == LC_UUID)
			{
				_binaryUUID = [[NSUUID alloc] initWithUUIDBytes:((const struct uuid_command *)command)->uuid].UUIDString;
				break;
			}
			cursor += command->cmdsize;
		}
	}
	return self;
}

- (BOOL)prepareDirectory:(NSError **)error
{
	NSFileManager *files = NSFileManager.defaultManager;
	if (![files createDirectoryAtURL:_directory withIntermediateDirectories:YES
	    attributes:@{ NSFilePosixPermissions : @0700 } error:error]) return NO;
	[_directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
	return YES;
}

- (void)start
{
	@synchronized(self)
	{
		if (_started) return;
		_started = YES;
	}
	[self recoverPreviousSession];
	[self recordEvent:@"app.launch" values:nil];
	MXMetricManager *manager = MXMetricManager.sharedManager;
	[manager addSubscriber:self];
	[self didReceiveDiagnosticPayloads:manager.pastDiagnosticPayloads];
}

- (void)dealloc
{
	if (_started) [MXMetricManager.sharedManager removeSubscriber:self];
}

- (NSDictionary *)metadata
{
	NSDictionary *bundle = NSBundle.mainBundle.infoDictionary;
#if TARGET_OS_IPHONE
	NSString *platform = @"ipados";
#else
	NSString *platform = @"macos";
#endif
#if defined(__arm64__)
	NSString *architecture = @"arm64";
#else
	NSString *architecture = @"x86_64";
#endif
	return @{ @"version" : bundle[@"CFBundleShortVersionString"] ?: @"unknown",
	    @"build" : bundle[@"CFBundleVersion"] ?: @"unknown", @"platform" : platform,
	    @"binary_uuid" : _binaryUUID ?: @"unknown",
	    @"architecture" : architecture, @"os" : NSProcessInfo.processInfo.operatingSystemVersionString };
}

- (NSURL *)sessionMarkerURL
{
	return [_directory URLByAppendingPathComponent:@"active-session.plist"];
}

- (void)writeSessionMarker
{
	NSFileManager *files = NSFileManager.defaultManager;
	if (!_activeSessionState)
	{
		[files removeItemAtURL:[self sessionMarkerURL] error:nil];
		return;
	}
	if (![self prepareDirectory:nil]) return;
	NSDictionary *marker = @{ @"launch_id" : _launchID, @"session_state" : @(_activeSessionState),
	    @"app_state" : @(_applicationState), @"timestamp" : @(NSDate.date.timeIntervalSince1970) };
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:marker
	    format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
	NSURL *url = [self sessionMarkerURL];
	if (![data writeToURL:url options:NSDataWritingAtomic error:nil]) return;
	NSMutableDictionary *attributes = [@{ NSFilePosixPermissions : @0600 } mutableCopy];
#if TARGET_OS_IPHONE
	attributes[NSFileProtectionKey] = NSFileProtectionCompleteUntilFirstUserAuthentication;
#endif
	[files setAttributes:attributes ofItemAtPath:url.path error:nil];
}

- (void)setActiveSessionState:(NSUInteger)state
{
	if (state > 2) return;
	@synchronized(self)
	{
		_activeSessionState = state;
		[self writeSessionMarker];
	}
}

- (void)recoverPreviousSession
{
	@synchronized(self)
	{
		NSData *data = [NSData dataWithContentsOfURL:[self sessionMarkerURL]];
		id marker = data ? [NSPropertyListSerialization propertyListWithData:data
		    options:NSPropertyListImmutable format:nil error:nil] : nil;
		if ([marker isKindOfClass:NSDictionary.class])
		{
			id launch = marker[@"launch_id"], state = marker[@"session_state"], time = marker[@"timestamp"];
			if ([launch isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:launch] &&
			    ![launch isEqual:_launchID] && [state isKindOfClass:NSNumber.class] &&
			    ([state doubleValue] == 1 || [state doubleValue] == 2) &&
			    [time isKindOfClass:NSNumber.class] && isfinite([time doubleValue]))
			{
				_previousLaunchID = launch;
				id app = marker[@"app_state"];
				NSNumber *appState = [app isKindOfClass:NSNumber.class] && [app doubleValue] >= 0 && [app doubleValue] <= 3 && [app doubleValue] == floor([app doubleValue]) ? app : @0;
				[self recordEvent:@"app.previous_session_interrupted" values:@{
				    @"session_state" : state, @"app_state" : appState, @"previous_timestamp" : time }];
				_previousLaunchID = nil;
			}
		}
		_activeSessionState = 0;
		[self writeSessionMarker];
	}
}

- (void)recordEvent:(NSString *)event values:(NSDictionary<NSString *, NSNumber *> *)values
{
	// Restrict the schema to fixed numeric context, rather than arbitrary descriptions.
	NSSet *allowed = [NSSet setWithArray:@[ @"code", @"rdp_error", @"width", @"height",
	    @"display_count", @"action", @"enabled", @"transport", @"error_kind",
	    @"intentional", @"loop_exit", @"rdp_error_info", @"connection_state", @"session_state",
	    @"app_state", @"previous_timestamp" ]];
	NSMutableDictionary *context = [NSMutableDictionary dictionary];
	for (NSString *key in values)
	{
		id value = values[key];
		if ([allowed containsObject:key] && [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]))
			context[key] = value;
	}
	NSMutableDictionary *record = [[self metadata] mutableCopy];
	record[@"timestamp"] = @(NSDate.date.timeIntervalSince1970);
	record[@"launch_id"] = _launchID;
	record[@"event"] = event;
	record[@"values"] = context;
	if ([event isEqual:@"app.previous_session_interrupted"] && _previousLaunchID)
		record[@"previous_launch_id"] = _previousLaunchID;
	NSData *json = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:nil];
	if (!json || json.length > 4096) return;
	NSMutableData *line = [json mutableCopy];
	[line appendBytes:"\n" length:1];
	@synchronized(self)
	{
		if (![self prepareDirectory:nil]) return;
		NSFileManager *files = NSFileManager.defaultManager;
		NSURL *current = [_directory URLByAppendingPathComponent:@"events.jsonl"];
		NSURL *previous = [_directory URLByAppendingPathComponent:@"events.previous.jsonl"];
		NSDictionary *attrs = [files attributesOfItemAtPath:current.path error:nil];
		if ([attrs fileSize] + line.length > OrbisEventFileLimit)
		{
			[files removeItemAtURL:previous error:nil];
			if (![files moveItemAtURL:current toURL:previous error:nil]) return;
		}
		int fd = open(current.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0600);
		if (fd < 0) return;
		const uint8_t *bytes = line.bytes;
		size_t remaining = line.length;
		while (remaining)
		{
			ssize_t written = write(fd, bytes, remaining);
			if (written < 0 && errno == EINTR) continue;
			if (written <= 0) break;
			bytes += written; remaining -= (size_t)written;
		}
		close(fd);
#if TARGET_OS_IPHONE
		[files setAttributes:@{ NSFileProtectionKey : NSFileProtectionCompleteUntilFirstUserAuthentication }
		    ofItemAtPath:current.path error:nil];
#endif
		if ([event isEqual:@"scene.active"]) _applicationState = 1;
		else if ([event isEqual:@"scene.inactive"] || [event isEqual:@"scene.disconnected"]) _applicationState = 2;
		else if ([event isEqual:@"scene.background"]) _applicationState = 3;
		else if ([event isEqual:@"app.terminating"]) _activeSessionState = 0;
		if ([event hasPrefix:@"scene."] || [event isEqual:@"app.terminating"])
			[self writeSessionMarker];
	}
}

- (void)recordError:(NSError *)error event:(NSString *)event
{
	if (!error) return;
	// Error descriptions and userInfo may contain URLs, account names, or secrets.
	NSArray *domains = @[ NSCocoaErrorDomain, NSPOSIXErrorDomain, NSURLErrorDomain,
	    @"com.dnexus.orbis.session", @"com.dnexus.orbis.transport", @"com.dnexus.orbis.tunnel",
	    @"com.dnexus.orbis.keychain", @"com.dnexus.orbis.display" ];
	NSUInteger kind = [domains indexOfObject:error.domain];
	[self recordEvent:event values:@{ @"code" : @(error.code),
	    @"error_kind" : @(kind == NSNotFound ? domains.count : kind) }];
}

- (NSDictionary *)stackForDiagnostic:(id)diagnostic
{
	NSData *data = [[diagnostic callStackTree] JSONRepresentation];
	if (!data || data.length > OrbisSystemReportLimit) return @{ @"omitted" : @YES };
	id tree = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	return [tree isKindOfClass:NSDictionary.class] ? tree : @{};
}

- (void)didReceiveDiagnosticPayloads:(NSArray<MXDiagnosticPayload *> *)payloads
{
	for (MXDiagnosticPayload *payload in payloads)
	{
		NSMutableArray *crashes = [NSMutableArray array], *hangs = [NSMutableArray array];
		for (MXCrashDiagnostic *crash in payload.crashDiagnostics)
		{
			// Keep stacks, binary UUIDs, version and numeric causes, omitting free-form exception text.
			[crashes addObject:@{ @"version" : crash.applicationVersion ?: @"unknown",
			    @"signal" : crash.signal ?: NSNull.null, @"exception_type" : crash.exceptionType ?: NSNull.null,
			    @"exception_code" : crash.exceptionCode ?: NSNull.null, @"call_stack_tree" : [self stackForDiagnostic:crash] }];
		}
		for (MXHangDiagnostic *hang in payload.hangDiagnostics)
			[hangs addObject:@{ @"version" : hang.applicationVersion ?: @"unknown",
			    @"duration_seconds" : @([hang.hangDuration measurementByConvertingToUnit:NSUnitDuration.seconds].doubleValue),
			    @"call_stack_tree" : [self stackForDiagnostic:hang] }];
		if (!crashes.count && !hangs.count) continue;
		NSDictionary *report = @{ @"source" : @"metrickit", @"crashes" : crashes, @"hangs" : hangs,
		    @"timestamp_begin" : @(payload.timeStampBegin.timeIntervalSince1970),
		    @"timestamp_end" : @(payload.timeStampEnd.timeIntervalSince1970) };
		NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingSortedKeys error:nil];
		if (!data || data.length > OrbisSystemReportLimit) continue;
		unsigned char digest[CC_SHA256_DIGEST_LENGTH];
		CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
		NSMutableString *name = [NSMutableString stringWithString:@"system-"];
		for (NSUInteger i = 0; i < sizeof(digest); i++) [name appendFormat:@"%02x", digest[i]];
		[name appendString:@".json"];
		@synchronized(self)
		{
			if (![self prepareDirectory:nil]) continue;
			NSURL *url = [_directory URLByAppendingPathComponent:name];
			if (![NSFileManager.defaultManager fileExistsAtPath:url.path])
			{
				if (![data writeToURL:url options:NSDataWritingAtomic error:nil]) continue;
				[NSFileManager.defaultManager setAttributes:@{ NSFilePosixPermissions : @0600 }
				    ofItemAtPath:url.path error:nil];
				[url setResourceValue:payload.timeStampEnd forKey:NSURLContentModificationDateKey error:nil];
#if TARGET_OS_IPHONE
				[NSFileManager.defaultManager setAttributes:@{ NSFileProtectionKey : NSFileProtectionCompleteUntilFirstUserAuthentication }
				    ofItemAtPath:url.path error:nil];
#endif
			}
			NSArray *reports = [self systemReportURLs];
			for (NSUInteger i = OrbisSystemReportCount; i < reports.count; i++)
				[NSFileManager.defaultManager removeItemAtURL:reports[i] error:nil];
		}
	}
}

- (NSArray<NSURL *> *)systemReportURLs
{
	NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:_directory
	    includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:0 error:nil];
	NSMutableArray *reports = [NSMutableArray array];
	for (NSURL *url in files)
		if ([url.lastPathComponent hasPrefix:@"system-"] && [url.pathExtension isEqualToString:@"json"])
			[reports addObject:url];
	return [reports sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
		NSDate *first, *second;
		[a getResourceValue:&first forKey:NSURLContentModificationDateKey error:nil];
		[b getResourceValue:&second forKey:NSURLContentModificationDateKey error:nil];
		return [(second ?: NSDate.distantPast) compare:(first ?: NSDate.distantPast)];
	}];
}

- (NSURL *)exportToDirectory:(NSURL *)directory error:(NSError **)error
{
	@synchronized(self)
	{
		if (![self prepareDirectory:error]) return nil;
		NSMutableArray *events = [NSMutableArray array], *reports = [NSMutableArray array];
		for (NSString *name in @[ @"events.previous.jsonl", @"events.jsonl" ])
		{
			NSURL *url = [_directory URLByAppendingPathComponent:name];
			if (![[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil] fileSize] ||
			    [[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil] fileSize] > OrbisEventFileLimit) continue;
			NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
			for (NSString *line in [text componentsSeparatedByString:@"\n"])
			{
				if (!line.length) continue;
				id record = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
				if ([record isKindOfClass:NSDictionary.class]) [events addObject:record];
			}
		}
		NSArray *urls = [self systemReportURLs];
		for (NSURL *url in [urls subarrayWithRange:NSMakeRange(0, MIN(urls.count, OrbisSystemReportCount))])
		{
			if ([[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil] fileSize] > OrbisSystemReportLimit) continue;
			NSData *data = [NSData dataWithContentsOfURL:url];
			id report = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
			if ([report isKindOfClass:NSDictionary.class]) [reports addObject:report];
		}
		NSDictionary *snapshot = @{ @"schema_version" : @1, @"metadata" : [self metadata],
		    @"exported_at" : @(NSDate.date.timeIntervalSince1970), @"events" : events,
		    @"system_reports" : reports };
		NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot
		    options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:error];
		if (!data || ![NSFileManager.defaultManager createDirectoryAtURL:directory
		    withIntermediateDirectories:YES attributes:@{ NSFilePosixPermissions : @0700 } error:error]) return nil;
		NSURL *url = [directory URLByAppendingPathComponent:[NSString stringWithFormat:@"orbis-diagnostics-%@.json", NSUUID.UUID.UUIDString]];
		if (![data writeToURL:url options:NSDataWritingAtomic error:error]) return nil;
		[NSFileManager.defaultManager setAttributes:@{ NSFilePosixPermissions : @0600 } ofItemAtPath:url.path error:nil];
		return url;
	}
}
@end
