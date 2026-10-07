/* SPDX-License-Identifier: MIT */
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, OrbisWorkspaceAction) {
    OrbisWorkspaceNone = 0,
    OrbisWorkspacePrevious = 1,
    OrbisWorkspaceNext = 2,
    OrbisWorkspaceActivities = 5,
    OrbisWorkspaceCloseActivities = 6,
    OrbisWorkspaceScreenshotScreen = 8,
    OrbisWorkspaceScreenshotWindow = 9,
};
typedef NS_OPTIONS(NSUInteger, OrbisShortcutModifiers) {
    OrbisShortcutShift = 1, OrbisShortcutControl = 2,
    OrbisShortcutOption = 4, OrbisShortcutCommand = 8,
};

// Physical key codes are stored separately for UIKit and AppKit.
@interface OrbisWorkspaceShortcuts : NSObject
@property(nonatomic, readonly) NSDictionary *bindings;
+ (NSArray *)actions;
+ (NSString *)titleForAction:(OrbisWorkspaceAction)action;
+ (NSString *)warning;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults platform:(NSString *)platform;
- (OrbisWorkspaceAction)actionForKeyCode:(NSUInteger)code modifiers:(OrbisShortcutModifiers)modifiers;
- (OrbisWorkspaceAction)actionForMouseButton:(NSUInteger)button modifiers:(OrbisShortcutModifiers)modifiers;
- (BOOL)assignKeyCode:(NSUInteger)code modifiers:(OrbisShortcutModifiers)modifiers
               label:(NSString *)label toAction:(OrbisWorkspaceAction)action error:(NSError **)error;
- (BOOL)assignMouseButton:(NSUInteger)button modifiers:(OrbisShortcutModifiers)modifiers
                   label:(NSString *)label toAction:(OrbisWorkspaceAction)action error:(NSError **)error;
- (void)clearAction:(OrbisWorkspaceAction)action;
- (NSString *)labelForAction:(OrbisWorkspaceAction)action;
- (void)save;
@end
