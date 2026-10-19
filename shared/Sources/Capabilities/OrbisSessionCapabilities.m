/* SPDX-License-Identifier: MIT */

#import "OrbisSessionCapabilities.h"

NSNotificationName const OrbisSessionCapabilitiesDidChangeNotification =
	@"OrbisSessionCapabilitiesDidChange";

#if __has_feature(objc_arc)
#define ORBIS_AUTORELEASE(value) (value)
#define ORBIS_RETAIN(value) (value)
#define ORBIS_RELEASE(value) do { } while (0)
#else
#define ORBIS_AUTORELEASE(value) [(value) autorelease]
#define ORBIS_RETAIN(value) [(value) retain]
#define ORBIS_RELEASE(value) [(value) release]
#endif

@implementation OrbisSessionCapabilityLimits

- (instancetype)init
{
	return [self initWithFormats:@[] maximumBytes:0 maximumMonitors:0 maximumWidth:0 maximumHeight:0];
}

- (instancetype)initWithFormats:(NSArray<NSString *> *)formats maximumBytes:(NSUInteger)maximumBytes
	            maximumMonitors:(NSUInteger)maximumMonitors maximumWidth:(NSUInteger)maximumWidth
	              maximumHeight:(NSUInteger)maximumHeight
{
	if ((self = [super init]))
	{
		// Copy strings too: callers may supply mutable encodings or a mutable list.
		_formats = [[NSArray alloc] initWithArray:formats copyItems:YES];
		_maximumBytes = maximumBytes;
		_maximumMonitors = maximumMonitors;
		_maximumWidth = maximumWidth;
		_maximumHeight = maximumHeight;
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	return ORBIS_RETAIN(self);
}

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_formats release];
	[super dealloc];
}
#endif
@end

@interface OrbisSessionCapability ()
- (instancetype)initWithFacts:(OrbisSessionCapabilityFacts)facts
	                     limits:(OrbisSessionCapabilityLimits *)limits active:(BOOL)active
	                      valid:(BOOL)valid;
@end

@implementation OrbisSessionCapability
- (instancetype)initWithFacts:(OrbisSessionCapabilityFacts)facts
	                     limits:(OrbisSessionCapabilityLimits *)limits active:(BOOL)active
	                      valid:(BOOL)valid
{
	if ((self = [super init]))
	{
		_facts = facts;
		_limits = ORBIS_RETAIN(limits);
		_state = OrbisCapabilityStateUnavailable;
		if (!valid)
			_reason = OrbisCapabilityReasonInvalidFeature;
		else if (!facts.implemented)
			_reason = OrbisCapabilityReasonNotImplemented;
		else if (!facts.enabled)
			_reason = OrbisCapabilityReasonDisabled;
		else if (facts.permission == OrbisCapabilityPermissionDenied)
			_reason = OrbisCapabilityReasonPermissionDenied;
		else if (facts.explicitlyRestricted)
			_reason = OrbisCapabilityReasonExplicitRestriction;
		else if (facts.peerSupport == OrbisCapabilityPeerSupportUnsupported)
			_reason = OrbisCapabilityReasonPeerUnsupported;
		else if (!active)
			_reason = OrbisCapabilityReasonSessionInactive;
		else if (facts.channel == OrbisCapabilityChannelUnavailable)
			_reason = OrbisCapabilityReasonChannelUnavailable;
		else if (facts.permission != OrbisCapabilityPermissionGranted)
		{
			_state = OrbisCapabilityStateChecking;
			_reason = OrbisCapabilityReasonPermissionUnknown;
		}
		else if (facts.channel != OrbisCapabilityChannelReady)
		{
			_state = OrbisCapabilityStateChecking;
			_reason = OrbisCapabilityReasonChannelPending;
		}
		else if (facts.peerSupport != OrbisCapabilityPeerSupportSupported)
		{
			_state = OrbisCapabilityStateChecking;
			_reason = OrbisCapabilityReasonPeerUnknown;
			_canAttempt = YES;
		}
		else
		{
			_state = OrbisCapabilityStateAvailable;
			_reason = OrbisCapabilityReasonNone;
			_canAttempt = YES;
		}
	}
	return self;
}

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_limits release];
	[super dealloc];
}
#endif
@end

static BOOL OrbisValidCapability(OrbisSessionFeature feature, OrbisCapabilityDirection direction)
{
	return feature < OrbisSessionFeatureCount && direction <= OrbisCapabilityDirectionFromRemote;
}

static NSUInteger OrbisCapabilityIndex(OrbisSessionFeature feature, OrbisCapabilityDirection direction)
{
	return feature * 2 + direction;
}

@interface OrbisSessionCapabilitiesSnapshot ()
@property(nonatomic, readonly, copy) NSArray<OrbisSessionCapability *> *entries;
- (instancetype)initWithGeneration:(uint64_t)generation active:(BOOL)active
	                         entries:(nullable NSArray<OrbisSessionCapability *> *)entries;
@end

@implementation OrbisSessionCapabilitiesSnapshot
- (instancetype)initWithGeneration:(uint64_t)generation active:(BOOL)active
	                         entries:(NSArray<OrbisSessionCapability *> *)entries
{
	if ((self = [super init]))
	{
		_generation = generation;
		_active = active;
		NSMutableArray *resolved = [NSMutableArray arrayWithCapacity:OrbisSessionFeatureCount * 2];
		for (NSUInteger index = 0; index < OrbisSessionFeatureCount * 2; index++)
		{
			OrbisSessionCapabilityFacts facts = { 0 };
			OrbisSessionCapabilityLimits *limits = nil;
			if (entries)
			{
				facts = entries[index].facts;
				limits = entries[index].limits;
			}
			else
				limits = ORBIS_AUTORELEASE([OrbisSessionCapabilityLimits new]);
			[resolved addObject:ORBIS_AUTORELEASE([[OrbisSessionCapability alloc]
			    initWithFacts:facts limits:limits active:active valid:YES])];
		}
		_entries = [resolved copy];
	}
	return self;
}

- (OrbisSessionCapability *)capabilityForFeature:(OrbisSessionFeature)feature
	                                  direction:(OrbisCapabilityDirection)direction
{
	if (OrbisValidCapability(feature, direction))
		return _entries[OrbisCapabilityIndex(feature, direction)];
	OrbisSessionCapabilityFacts facts = { 0 };
	OrbisSessionCapabilityLimits *limits = ORBIS_AUTORELEASE([OrbisSessionCapabilityLimits new]);
	return ORBIS_AUTORELEASE([[OrbisSessionCapability alloc] initWithFacts:facts limits:limits
	                                                               active:NO valid:NO]);
}

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_entries release];
	[super dealloc];
}
#endif
@end

@implementation OrbisSessionCapabilities {
	OrbisSessionCapabilitiesSnapshot *_snapshot;
	BOOL _notificationPending;
}

- (instancetype)init
{
	if ((self = [super init]))
		_snapshot = [[OrbisSessionCapabilitiesSnapshot alloc] initWithGeneration:0 active:NO entries:nil];
	return self;
}

- (OrbisSessionCapabilitiesSnapshot *)snapshot
{
	@synchronized(self)
	{
		return ORBIS_AUTORELEASE(ORBIS_RETAIN(_snapshot));
	}
}

// Called only under the store lock. Coalescing prevents a worker thread from
// filling the UI queue with obsolete intermediate states during negotiation.
- (void)scheduleNotification
{
	if (_notificationPending)
		return;
	_notificationPending = YES;
	dispatch_async(dispatch_get_main_queue(), ^{
		@synchronized(self)
		{
			_notificationPending = NO;
		}
		[NSNotificationCenter.defaultCenter postNotificationName:OrbisSessionCapabilitiesDidChangeNotification
		                                                 object:self];
	});
}

- (void)replaceSnapshot:(OrbisSessionCapabilitiesSnapshot *)snapshot
{
	ORBIS_RELEASE(_snapshot);
	_snapshot = ORBIS_RETAIN(snapshot);
	[self scheduleNotification];
}

- (uint64_t)beginSession
{
	@synchronized(self)
	{
		uint64_t generation = _snapshot.generation + 1;
		if (!generation)
			generation = 1;
		[self replaceSnapshot:ORBIS_AUTORELEASE([[OrbisSessionCapabilitiesSnapshot alloc]
		    initWithGeneration:generation active:YES entries:nil])];
		return generation;
	}
}

- (BOOL)updateFeature:(OrbisSessionFeature)feature direction:(OrbisCapabilityDirection)direction
	            facts:(OrbisSessionCapabilityFacts)facts limits:(OrbisSessionCapabilityLimits *)limits
	    forGeneration:(uint64_t)generation
{
	@synchronized(self)
	{
		if (!_snapshot.active || generation != _snapshot.generation ||
		    !OrbisValidCapability(feature, direction))
			return NO;
		NSMutableArray *entries = [_snapshot.entries mutableCopy];
		if (!limits)
			limits = ORBIS_AUTORELEASE([OrbisSessionCapabilityLimits new]);
		entries[OrbisCapabilityIndex(feature, direction)] = ORBIS_AUTORELEASE(
		    [[OrbisSessionCapability alloc] initWithFacts:facts limits:limits active:YES valid:YES]);
		[self replaceSnapshot:ORBIS_AUTORELEASE([[OrbisSessionCapabilitiesSnapshot alloc]
		    initWithGeneration:generation active:YES entries:entries])];
		ORBIS_RELEASE(entries);
		return YES;
	}
}

- (BOOL)endSessionForGeneration:(uint64_t)generation
{
	@synchronized(self)
	{
		if (!_snapshot.active || generation != _snapshot.generation)
			return NO;
		[self replaceSnapshot:ORBIS_AUTORELEASE([[OrbisSessionCapabilitiesSnapshot alloc]
		    initWithGeneration:generation active:NO entries:_snapshot.entries])];
		return YES;
	}
}

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_snapshot release];
	[super dealloc];
}
#endif
@end
