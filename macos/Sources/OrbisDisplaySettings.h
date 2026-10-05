/* SPDX-License-Identifier: MIT */
#import <AppKit/AppKit.h>
#import "OrbisDisplayLayout.h"
@class OrbisProfile;

@interface OrbisDisplaySettings : NSObject <NSCopying>
{
    NSUInteger _primaryWidth, _primaryHeight, _secondaryWidth, _secondaryHeight;
    OrbisMonitorArrangement _arrangement;
    int32_t _offset;
}
@property(nonatomic) NSUInteger primaryWidth, primaryHeight, secondaryWidth, secondaryHeight;
@property(nonatomic) OrbisMonitorArrangement arrangement;
@property(nonatomic) int32_t offset;
+ (instancetype)loadMigratingProfile:(OrbisProfile *)profile;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults legacyProfile:(OrbisProfile *)profile;
- (void)saveToDefaults:(NSUserDefaults *)defaults;
- (OrbisDisplayLayout)previewLayout;
- (void)placeSecondaryAtPoint:(NSPoint)point;
@end

@interface OrbisDisplayArrangementView : NSView
{
    OrbisDisplaySettings *_settings;
    NSRect _monitorRects[2];
    CGFloat _scale, _dragScale;
    NSPoint _dragStart, _originalPosition;
    NSInteger _dragMonitor, _selectedMonitor;
}
@property(nonatomic, retain) OrbisDisplaySettings *settings;
@end

@interface OrbisDisplaySettingsController : NSWindowController <NSTextFieldDelegate>
{
    OrbisDisplaySettings *_settings;
    OrbisDisplayArrangementView *_arrangementView;
    NSPopUpButton *_modes[2];
    NSTextField *_widths[2], *_heights[2], *_validationLabel;
    NSButton *_captureInput;
}
- (instancetype)initWithSettings:(OrbisDisplaySettings *)settings;
- (void)beginSheetForWindow:(NSWindow *)window;
@end
