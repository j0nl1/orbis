/* SPDX-License-Identifier: MIT */

#import <AppKit/AppKit.h>

@class OrbisProfile;
@class OrbisProfileEditorController;

@protocol OrbisProfileEditorControllerDelegate <NSObject>

- (void)profileEditorController:(OrbisProfileEditorController *)controller
                  savedProfile:(OrbisProfile *)profile
                       password:(NSString *)password;

@end

@interface OrbisProfileEditorController : NSWindowController
{
	id<OrbisProfileEditorControllerDelegate> _delegate;
	OrbisProfile *_profile;
	BOOL _hasStoredPassword;
	NSTextField *_nameField;
	NSTextField *_hostField;
	NSTextField *_portField;
	NSTextField *_usernameField;
	NSSecureTextField *_passwordField;
	NSButton *_certificateCheckbox;
	NSButton *_automaticCheckbox;
	NSTextField *_validationLabel;
}

@property(nonatomic, assign) id<OrbisProfileEditorControllerDelegate> delegate;

- (id)initWithProfile:(OrbisProfile *)profile hasStoredPassword:(BOOL)hasStoredPassword;
- (void)beginSheetForWindow:(NSWindow *)parentWindow;

@end
