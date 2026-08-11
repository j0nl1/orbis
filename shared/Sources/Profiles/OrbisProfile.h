/* SPDX-License-Identifier: MIT */

#import <Foundation/Foundation.h>

@interface OrbisProfile : NSObject <NSCopying>
{
	NSString *_identifier;
	NSString *_name;
	NSString *_host;
	NSString *_username;
	NSUInteger _port;
	BOOL _acceptAllCertificates;
	BOOL _connectAutomatically;
}

@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *host;
@property(nonatomic, copy) NSString *username;
@property(nonatomic, assign) NSUInteger port;
@property(nonatomic, assign) BOOL acceptAllCertificates;
@property(nonatomic, assign) BOOL connectAutomatically;

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
