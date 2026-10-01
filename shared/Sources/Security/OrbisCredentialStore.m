/* SPDX-License-Identifier: MIT */

#import "OrbisCredentialStore.h"

#import <Security/Security.h>

#import "OrbisProfile.h"

static NSString *const OrbisCredentialErrorDomain = @"com.dnexus.orbis.credentials";
static NSString *const OrbisKeychainAccount = @"rdp-password";
static NSString *const OrbisCloudflareAccount = @"cloudflare-service-token";
static NSString *const OrbisKeychainServicePrefix = @"Orbis RDP profile ";

@implementation OrbisCredentialStore

+ (NSString *)serviceForProfile:(OrbisProfile *)profile
{
	if ([[profile identifier] length] == 0)
		return nil;
	return [OrbisKeychainServicePrefix stringByAppendingString:[profile identifier]];
}

+ (NSMutableDictionary *)queryForProfile:(OrbisProfile *)profile account:(NSString *)account
{
	NSString *service = [self serviceForProfile:profile];
	if (!service)
		return nil;
	return [NSMutableDictionary dictionaryWithObjectsAndKeys:
	                                      (id)kSecClassGenericPassword, (id)kSecClass,
	                                      account, (id)kSecAttrAccount, service,
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
	NSData *data = [self dataForProfile:profile account:OrbisKeychainAccount error:error];
	return data ? [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] : nil;
}

+ (NSData *)dataForProfile:(OrbisProfile *)profile account:(NSString *)account error:(NSError **)error
{
	if (error)
		*error = nil;
	NSMutableDictionary *query = [self queryForProfile:profile account:account];
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
			*error = [self errorForStatus:status operation:@"Reading credentials"];
		return nil;
	}

	return [(NSData *)result autorelease];
}

+ (BOOL)setPassword:(NSString *)password forProfile:(OrbisProfile *)profile error:(NSError **)error
{
	if (error)
		*error = nil;
	if ([password length] == 0)
		return [self deletePasswordForProfile:profile error:error];
	return [self setData:[password dataUsingEncoding:NSUTF8StringEncoding]
	         forProfile:profile account:OrbisKeychainAccount error:error];
}

+ (BOOL)setData:(NSData *)data forProfile:(OrbisProfile *)profile account:(NSString *)account error:(NSError **)error
{
	if (error)
		*error = nil;
	NSMutableDictionary *query = [self queryForProfile:profile account:account];
	if (!query)
	{
		if (error)
			*error = [self errorForStatus:errSecParam operation:@"Saving credentials"];
		return NO;
	}
	NSDictionary *attributes = @{ (id)kSecValueData : data };
	OSStatus status = SecItemUpdate((CFDictionaryRef)query, (CFDictionaryRef)attributes);
	if (status == errSecItemNotFound)
	{
		[query setObject:data forKey:(id)kSecValueData];
		[query setObject:(id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly forKey:(id)kSecAttrAccessible];
		status = SecItemAdd((CFDictionaryRef)query, NULL);
	}
	if (status == errSecSuccess)
		return YES;
	if (error)
		*error = [self errorForStatus:status operation:@"Saving credentials"];
	return NO;
}

+ (BOOL)deletePasswordForProfile:(OrbisProfile *)profile error:(NSError **)error
{
	return [self deleteDataForProfile:profile account:OrbisKeychainAccount error:error];
}

+ (BOOL)deleteDataForProfile:(OrbisProfile *)profile account:(NSString *)account error:(NSError **)error
{
	if (error)
		*error = nil;
	NSMutableDictionary *query = [self queryForProfile:profile account:account];
	if (!query)
		return YES;
	OSStatus status = SecItemDelete((CFDictionaryRef)query);
	if (status == errSecSuccess || status == errSecItemNotFound)
		return YES;
	if (error)
		*error = [self errorForStatus:status operation:@"Deleting credentials"];
	return NO;
}

+ (NSDictionary *)cloudflareTokenForProfile:(OrbisProfile *)profile error:(NSError **)error
{
	NSData *data = [self dataForProfile:profile account:OrbisCloudflareAccount error:error];
	if (!data)
		return nil;
	id token = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
	if (![token isKindOfClass:[NSDictionary class]] ||
	    ![token[@"host"] isKindOfClass:[NSString class]] ||
	    ![token[@"clientID"] isKindOfClass:[NSString class]] ||
	    ![token[@"secret"] isKindOfClass:[NSString class]])
	{
		if (error)
			*error = [self errorForStatus:errSecDecode operation:@"Reading the service token"];
		return nil;
	}
	// Editing the hostname must not send the saved token to a different application.
	if (![token[@"host"] isEqualToString:[[profile transportHostname] lowercaseString]])
		return nil;
	return token;
}

+ (BOOL)setCloudflareClientID:(NSString *)clientID secret:(NSString *)secret
                  forProfile:(OrbisProfile *)profile error:(NSError **)error
{
	if (error)
		*error = nil;
	NSCharacterSet *newlines = [NSCharacterSet newlineCharacterSet];
	if (![clientID length] || ![secret length] || ![[profile transportHostname] length] ||
	    [clientID rangeOfCharacterFromSet:newlines].location != NSNotFound ||
	    [secret rangeOfCharacterFromSet:newlines].location != NSNotFound)
	{
		if (error)
			*error = [self errorForStatus:errSecParam operation:@"Saving the service token"];
		return NO;
	}
	NSDictionary *token = @{ @"host" : [[profile transportHostname] lowercaseString], @"clientID" : clientID, @"secret" : secret };
	NSData *data = [NSJSONSerialization dataWithJSONObject:token options:0 error:error];
	return data && [self setData:data forProfile:profile account:OrbisCloudflareAccount error:error];
}

+ (BOOL)deleteCloudflareTokenForProfile:(OrbisProfile *)profile error:(NSError **)error
{
	return [self deleteDataForProfile:profile account:OrbisCloudflareAccount error:error];
}

+ (BOOL)deleteCredentialsForProfile:(OrbisProfile *)profile error:(NSError **)error
{
	return [self deletePasswordForProfile:profile error:error] &&
	       [self deleteCloudflareTokenForProfile:profile error:error];
}

@end
