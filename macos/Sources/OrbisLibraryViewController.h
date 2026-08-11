/* SPDX-License-Identifier: MIT */

#import <AppKit/AppKit.h>

@class OrbisLibraryViewController;
@class OrbisProfile;
@class OrbisProfileStore;

@protocol OrbisLibraryViewControllerDelegate <NSObject>

- (void)libraryViewController:(OrbisLibraryViewController *)controller
             connectToProfile:(OrbisProfile *)profile;

@end

@interface OrbisLibraryViewController : NSViewController
{
	id<OrbisLibraryViewControllerDelegate> _delegate;
	OrbisProfileStore *_profileStore;
	NSStackView *_cardsStack;
	id _profileEditor;
	id _aboutController;
}

@property(nonatomic, assign) id<OrbisLibraryViewControllerDelegate> delegate;
@property(nonatomic, readonly) OrbisProfileStore *profileStore;

- (void)reloadProfiles;
- (void)addConnection:(id)sender;
- (void)connectSelectedProfile:(id)sender;

@end
