/* SPDX-License-Identifier: MIT */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, OrbisSessionFeature) {
	OrbisSessionFeatureClipboardText,
	OrbisSessionFeatureClipboardImage,
	OrbisSessionFeatureDisplayResize,
	OrbisSessionFeatureMultipleMonitors,
	OrbisSessionFeatureAudioOutput,
	OrbisSessionFeatureMicrophone,
	OrbisSessionFeatureCount
};

typedef NS_ENUM(NSUInteger, OrbisCapabilityDirection) {
	OrbisCapabilityDirectionToRemote,
	OrbisCapabilityDirectionFromRemote
};

typedef NS_ENUM(NSUInteger, OrbisCapabilityPermission) {
	OrbisCapabilityPermissionUnknown,
	OrbisCapabilityPermissionGranted,
	OrbisCapabilityPermissionDenied
};

typedef NS_ENUM(NSUInteger, OrbisCapabilityChannel) {
	OrbisCapabilityChannelPending,
	OrbisCapabilityChannelReady,
	OrbisCapabilityChannelUnavailable
};

typedef NS_ENUM(NSUInteger, OrbisCapabilityPeerSupport) {
	OrbisCapabilityPeerSupportUnknown,
	OrbisCapabilityPeerSupportSupported,
	OrbisCapabilityPeerSupportUnsupported
};

// A complete evidence replacement, supplied by a platform/protocol adapter.
// Granted also means permission is not required. Peer support is independent
// of the formats currently present in the clipboard. Transfer errors are not facts.
typedef struct {
	BOOL implemented;
	BOOL enabled;
	OrbisCapabilityPermission permission;
	OrbisCapabilityChannel channel;
	OrbisCapabilityPeerSupport peerSupport;
	BOOL explicitlyRestricted;
} OrbisSessionCapabilityFacts;

typedef NS_ENUM(NSUInteger, OrbisCapabilityState) {
	OrbisCapabilityStateChecking,
	OrbisCapabilityStateAvailable,
	OrbisCapabilityStateUnavailable
};

typedef NS_ENUM(NSUInteger, OrbisCapabilityReason) {
	OrbisCapabilityReasonNone,
	OrbisCapabilityReasonNotImplemented,
	OrbisCapabilityReasonDisabled,
	OrbisCapabilityReasonPermissionUnknown,
	OrbisCapabilityReasonPermissionDenied,
	OrbisCapabilityReasonSessionInactive,
	OrbisCapabilityReasonChannelPending,
	OrbisCapabilityReasonChannelUnavailable,
	OrbisCapabilityReasonPeerUnknown,
	OrbisCapabilityReasonPeerUnsupported,
	OrbisCapabilityReasonExplicitRestriction,
	OrbisCapabilityReasonInvalidFeature
};

// Immutable feature-specific limits. Zero means no known limit, not zero support.
// Formats describe supported encodings, never the current clipboard contents.
__attribute__((visibility("default")))
@interface OrbisSessionCapabilityLimits : NSObject <NSCopying>
@property(nonatomic, readonly, copy) NSArray<NSString *> *formats;
@property(nonatomic, readonly) NSUInteger maximumBytes;
@property(nonatomic, readonly) NSUInteger maximumMonitors;
@property(nonatomic, readonly) NSUInteger maximumWidth;
@property(nonatomic, readonly) NSUInteger maximumHeight;
- (instancetype)initWithFormats:(NSArray<NSString *> *)formats
	               maximumBytes:(NSUInteger)maximumBytes
	            maximumMonitors:(NSUInteger)maximumMonitors
	               maximumWidth:(NSUInteger)maximumWidth
	              maximumHeight:(NSUInteger)maximumHeight NS_DESIGNATED_INITIALIZER;
- (instancetype)init;
@end

__attribute__((visibility("default")))
@interface OrbisSessionCapability : NSObject
@property(nonatomic, readonly) OrbisSessionCapabilityFacts facts;
@property(nonatomic, readonly) OrbisCapabilityState state;
@property(nonatomic, readonly) OrbisCapabilityReason reason;
// Unknown peer support permits an attempt once all local/channel gates pass.
// Successful or explicitly rejected negotiation can subsequently refine facts.
@property(nonatomic, readonly) BOOL canAttempt;
@property(nonatomic, readonly, strong) OrbisSessionCapabilityLimits *limits;
- (instancetype)init NS_UNAVAILABLE;
@end

__attribute__((visibility("default")))
@interface OrbisSessionCapabilitiesSnapshot : NSObject
@property(nonatomic, readonly) uint64_t generation;
@property(nonatomic, readonly, getter=isActive) BOOL active;
- (instancetype)init NS_UNAVAILABLE;
- (OrbisSessionCapability *)capabilityForFeature:(OrbisSessionFeature)feature
	                                  direction:(OrbisCapabilityDirection)direction;
@end

// Input port implemented by the shared policy module. Updates may arrive on any
// thread. Keep the returned generation with each connection's callbacks; an old
// callback cannot change a later connection's evidence.
@protocol OrbisSessionCapabilitySink <NSObject>
- (uint64_t)beginSession;
- (BOOL)updateFeature:(OrbisSessionFeature)feature
	        direction:(OrbisCapabilityDirection)direction
	            facts:(OrbisSessionCapabilityFacts)facts
	           limits:(nullable OrbisSessionCapabilityLimits *)limits
	    forGeneration:(uint64_t)generation;
- (BOOL)endSessionForGeneration:(uint64_t)generation;
@end

// Delivered asynchronously on the main queue with this store as object.
// Read the latest snapshot inside the observer; notifications carry no stale
// snapshot payload. No observer callback runs while the store is locked.
FOUNDATION_EXPORT __attribute__((visibility("default")))
NSNotificationName const OrbisSessionCapabilitiesDidChangeNotification;

__attribute__((visibility("default")))
@interface OrbisSessionCapabilities : NSObject <OrbisSessionCapabilitySink>
// Immutable and safe to retain/read on any thread, including across updates.
@property(nonatomic, readonly, strong) OrbisSessionCapabilitiesSnapshot *snapshot;
@end

NS_ASSUME_NONNULL_END
