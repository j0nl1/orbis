/* SPDX-License-Identifier: MIT */

#import <AppKit/AppKit.h>

@class OrbisProfile;
@class OrbisProfileEditorController;

@protocol OrbisProfileEditorControllerDelegate <NSObject>

- (BOOL)profileEditorController:(OrbisProfileEditorController *)controller
                  savedProfile:(OrbisProfile *)profile
                       password:(NSString *)password
                cloudflareToken:(NSDictionary *)cloudflareToken;

- (void)profileEditorControllerDidFinish:(OrbisProfileEditorController *)controller;

@end

@interface OrbisProfileEditorController : NSWindowController <NSWindowDelegate>
{
	id<OrbisProfileEditorControllerDelegate> _delegate;
	OrbisProfile *_profile;
	BOOL _hasStoredPassword;
	NSTextField *_nameField;
	NSTextField *_hostField;
	NSStackView *_hostGroup;
	NSTextField *_portField;
	NSTextField *_usernameField;
	NSSecureTextField *_passwordField;
	NSButton *_certificateCheckbox;
	NSButton *_automaticCheckbox;
	NSTextField *_validationLabel;
	NSPopUpButton *_transportField;
	NSTextField *_gatewayHostnameField;
	NSStackView *_gatewayHostnameGroup;
	NSTextField *_clientIDField;
	NSSecureTextField *_clientSecretField;
	NSStackView *_clientIDGroup;
	NSStackView *_clientSecretGroup;
	NSStackView *_portGroup;
	NSStackView *_formStack;
	NSScrollView *_scrollView;
	NSView *_formView;
	NSString *_savedTokenHost;
	NSString *_savedTokenClientID;
}

@property(nonatomic, assign) id<OrbisProfileEditorControllerDelegate> delegate;

- (id)initWithProfile:(OrbisProfile *)profile hasStoredPassword:(BOOL)hasStoredPassword;
- (void)beginSheetForWindow:(NSWindow *)parentWindow;

@end
