/* SPDX-License-Identifier: MIT */

#import <Foundation/Foundation.h>
#import "OrbisDisplayLayout.h"

FOUNDATION_EXPORT NSString *const OrbisTransportTypeDirect;
FOUNDATION_EXPORT NSString *const OrbisTransportTypeCloudflare;

@interface OrbisProfile : NSObject <NSCopying>
{
	NSString *_identifier;
	NSString *_name;
	NSString *_host;
	NSString *_username;
	NSUInteger _port;
	BOOL _acceptAllCertificates;
	BOOL _connectAutomatically;
	NSString *_transportType;
	NSDictionary *_transportOptions;
	NSUInteger _primaryWidth, _primaryHeight, _secondaryWidth, _secondaryHeight;
	OrbisMonitorArrangement _monitorArrangement;
}

@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *host;
@property(nonatomic, copy) NSString *username;
@property(nonatomic, assign) NSUInteger port;
@property(nonatomic, assign) BOOL acceptAllCertificates;
@property(nonatomic, assign) BOOL connectAutomatically;
// Transport options contain non-secret configuration; credentials belong in Keychain.
@property(nonatomic, copy) NSString *transportType;
@property(nonatomic, copy) NSDictionary *transportOptions;
@property(nonatomic, readonly) NSString *transportHostname;
// Zero dimensions select automatic resolution; a manual resolution is a complete pair.
@property(nonatomic, assign) NSUInteger primaryWidth;
@property(nonatomic, assign) NSUInteger primaryHeight;
@property(nonatomic, assign) NSUInteger secondaryWidth;
@property(nonatomic, assign) NSUInteger secondaryHeight;
@property(nonatomic, assign) OrbisMonitorArrangement monitorArrangement;

- (id)initWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)dictionaryRepresentation;

@end

@interface OrbisProfileStore : NSObject
{
	NSMutableArray *_profiles;
	NSString *_selectedProfileIdentifier;
}

@property(nonatomic, readonly) NSArray *profiles;
@property(nonatomic, readonly) OrbisProfile *selectedProfile;
@property(nonatomic, readonly) OrbisProfile *automaticProfile;

- (OrbisProfile *)profileWithIdentifier:(NSString *)identifier;
- (void)selectProfileWithIdentifier:(NSString *)identifier;
- (void)saveProfile:(OrbisProfile *)profile;
- (void)deleteProfileWithIdentifier:(NSString *)identifier;

@end
