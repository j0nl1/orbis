/* SPDX-License-Identifier: MIT */

#import "OrbisCredentialStore.h"

#import <Security/Security.h>

#import "OrbisProfile.h"

static NSString *const OrbisCredentialErrorDomain = @"com.dnexus.orbis.credentials";
static NSString *const OrbisKeychainAccount = @"rdp-password";
static NSString *const OrbisKeychainServicePrefix = @"Orbis RDP profile ";

@implementation OrbisCredentialStore

+ (NSString *)serviceForProfile:(OrbisProfile *)profile
{
	if ([[profile identifier] length] == 0)
		return nil;
	return [OrbisKeychainServicePrefix stringByAppendingString:[profile identifier]];
}

+ (NSMutableDictionary *)queryForProfile:(OrbisProfile *)profile
{
	NSString *service = [self serviceForProfile:profile];
	if (!service)
		return nil;
	return [NSMutableDictionary dictionaryWithObjectsAndKeys:
	                                      (id)kSecClassGenericPassword, (id)kSecClass,
	                                      OrbisKeychainAccount, (id)kSecAttrAccount, service,
	                                      (id)kSecAttrService, nil];
}

+ (NSError *)errorForStatus:(OSStatus)status operation:(NSString *)operation
{
	CFStringRef statusDescription = SecCopyErrorMessageString(status, NULL);
	NSString *detail = statusDescription ? [(NSString *)statusDescription autorelease]
	                                     : [NSString stringWithFormat:@"OSStatus %d", (int)status];
	NSString *message = [NSString stringWithFormat:@"%@ failed: %@", operation, detail];
	return [NSError errorWithDomain:OrbisCredentialErrorDomain
	                         code:status
	                     userInfo:@{ NSLocalizedDescriptionKey : message }];
}

+ (NSString *)passwordForProfile:(OrbisProfile *)profile error:(NSError **)error
{
	if (error)
		*error = nil;
	NSMutableDictionary *query = [self queryForProfile:profile];
	if (!query)
		return nil;
	[query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];
	[query setObject:(id)kSecMatchLimitOne forKey:(id)kSecMatchLimit];

	CFTypeRef result = NULL;
	OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, &result);
	if (status == errSecItemNotFound)
		return nil;
	if (status != errSecSuccess)
	{
		if (error)
			*error = [self errorForStatus:status operation:@"Reading the password"];
		return nil;
	}

	NSData *data = [(NSData *)result autorelease];
	return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}

+ (BOOL)setPassword:(NSString *)password forProfile:(OrbisProfile *)profile error:(NSError **)error
{
	if (error)
		*error = nil;
	if ([password length] == 0)
		return [self deletePasswordForProfile:profile error:error];

	NSMutableDictionary *query = [self queryForProfile:profile];
	if (!query)
		return NO;
	NSData *data = [password dataUsingEncoding:NSUTF8StringEncoding];
	NSDictionary *attributes = @{ (id)kSecValueData : data };
	OSStatus status = SecItemUpdate((CFDictionaryRef)query, (CFDictionaryRef)attributes);
	if (status == errSecItemNotFound)
	{
		[query setObject:data forKey:(id)kSecValueData];
		status = SecItemAdd((CFDictionaryRef)query, NULL);
	}
	if (status == errSecSuccess)
		return YES;
	if (error)
		*error = [self errorForStatus:status operation:@"Saving the password"];
	return NO;
}

+ (BOOL)deletePasswordForProfile:(OrbisProfile *)profile error:(NSError **)error
{
	if (error)
		*error = nil;
	NSMutableDictionary *query = [self queryForProfile:profile];
	if (!query)
		return YES;
	OSStatus status = SecItemDelete((CFDictionaryRef)query);
	if (status == errSecSuccess || status == errSecItemNotFound)
		return YES;
	if (error)
		*error = [self errorForStatus:status operation:@"Deleting the password"];
	return NO;
}

@end
