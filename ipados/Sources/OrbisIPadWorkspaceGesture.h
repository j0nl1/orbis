/* SPDX-License-Identifier: MIT */
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, OrbisIPadWorkspaceAction) {
	OrbisIPadWorkspaceScroll = -1,
	OrbisIPadWorkspacePending = 0,
	OrbisIPadWorkspacePrevious,
	OrbisIPadWorkspaceNext,
	OrbisIPadWorkspaceMovePrevious,
	OrbisIPadWorkspaceMoveNext,
	OrbisIPadWorkspaceActivities,
};

// Routes continuous trackpad scrolling; discrete mouse wheels bypass this classifier.
@interface OrbisIPadWorkspaceGesture : NSObject
- (OrbisIPadWorkspaceAction)updateWithTranslation:(CGPoint)translation
	state:(UIGestureRecognizerState)state modifiers:(UIKeyModifierFlags)modifiers enabled:(BOOL)enabled;
@end
