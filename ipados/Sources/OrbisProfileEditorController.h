/* SPDX-License-Identifier: MIT */

#import <UIKit/UIKit.h>

@class OrbisProfile;
@class OrbisProfileEditorController;

@protocol OrbisProfileEditorDelegate <NSObject>
- (BOOL)profileEditor:(OrbisProfileEditorController *)editor
       didSaveProfile:(OrbisProfile *)profile
             password:(NSString *)password;
@end

@interface OrbisProfileEditorController : UITableViewController <UITextFieldDelegate>
{
	OrbisProfile *_profile;
	id<OrbisProfileEditorDelegate> _delegate;
	UITextField *_nameField;
	UITextField *_hostField;
	UITextField *_portField;
	UITextField *_usernameField;
	UITextField *_passwordField;
	UISwitch *_certificateSwitch;
	UISwitch *_automaticSwitch;
	NSArray *_fieldCells;
	NSArray *_optionCells;
	BOOL _hasSavedPassword;
	BOOL _isReplacingPassword;
	BOOL _shouldFocusNameField;
}

@property(nonatomic, assign) id<OrbisProfileEditorDelegate> delegate;

- (id)initWithProfile:(OrbisProfile *)profile;
- (id)initWithProfile:(OrbisProfile *)profile hasSavedPassword:(BOOL)hasSavedPassword;

@end
