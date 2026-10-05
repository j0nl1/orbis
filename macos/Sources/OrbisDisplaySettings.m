/* SPDX-License-Identifier: MIT */
#import "OrbisDisplaySettings.h"
#import "OrbisProfile.h"
#import "OrbisFormControls.h"
#import "OrbisInputCapture.h"
#import <ApplicationServices/ApplicationServices.h>
#include <float.h>

static NSString *const OrbisDisplaySettingsKey = @"OrbisDisplaySettings.v1";

@implementation OrbisDisplaySettings
@synthesize primaryWidth = _primaryWidth, primaryHeight = _primaryHeight;
@synthesize secondaryWidth = _secondaryWidth, secondaryHeight = _secondaryHeight;
@synthesize arrangement = _arrangement, offset = _offset;
+ (instancetype)loadMigratingProfile:(OrbisProfile *)profile
{
    return [[[self alloc] initWithDefaults:[NSUserDefaults standardUserDefaults] legacyProfile:profile] autorelease];
}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults legacyProfile:(OrbisProfile *)profile
{
    if (!(self = [super init])) return nil;
    id stored = [defaults objectForKey:OrbisDisplaySettingsKey];
    if ([stored isKindOfClass:[NSDictionary class]])
    {
        for (NSUInteger i = 0; i < 2; i++)
        {
            NSString *prefix = i ? @"secondary" : @"primary";
            id w = stored[[prefix stringByAppendingString:@"Width"]];
            id h = stored[[prefix stringByAppendingString:@"Height"]];
            if ([w isKindOfClass:[NSNumber class]] && [h isKindOfClass:[NSNumber class]] &&
                [w doubleValue] == [w unsignedIntValue] && [h doubleValue] == [h unsignedIntValue] &&
                OrbisDisplayResolutionIsValid([w unsignedIntValue], [h unsignedIntValue]))
            {
                if (i) { _secondaryWidth = [w unsignedIntValue]; _secondaryHeight = [h unsignedIntValue]; }
                else { _primaryWidth = [w unsignedIntValue]; _primaryHeight = [h unsignedIntValue]; }
            }
        }
        id side = stored[@"arrangement"], offset = stored[@"offset"];
        if ([side isKindOfClass:[NSNumber class]] && [side integerValue] >= 0 &&
            [side integerValue] <= OrbisMonitorBelow && [side doubleValue] == [side integerValue])
            _arrangement = (OrbisMonitorArrangement)[side integerValue];
        if ([offset isKindOfClass:[NSNumber class]] && [offset doubleValue] == [offset intValue] &&
            [offset doubleValue] >= -8191 && [offset doubleValue] <= 8191)
            _offset = [offset intValue];
    }
    else if (!stored && profile)
    {
        _primaryWidth = profile.primaryWidth; _primaryHeight = profile.primaryHeight;
        _secondaryWidth = profile.secondaryWidth; _secondaryHeight = profile.secondaryHeight;
        _arrangement = profile.monitorArrangement;
        [self saveToDefaults:defaults];
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone
{
    OrbisDisplaySettings *copy = [[[self class] allocWithZone:zone] init];
    copy.primaryWidth = _primaryWidth; copy.primaryHeight = _primaryHeight;
    copy.secondaryWidth = _secondaryWidth; copy.secondaryHeight = _secondaryHeight;
    copy.arrangement = _arrangement; copy.offset = _offset;
    return copy;
}
- (void)saveToDefaults:(NSUserDefaults *)defaults
{
    [defaults setObject:@{ @"primaryWidth": @(_primaryWidth), @"primaryHeight": @(_primaryHeight),
        @"secondaryWidth": @(_secondaryWidth), @"secondaryHeight": @(_secondaryHeight),
        @"arrangement": @(_arrangement), @"offset": @(_offset) } forKey:OrbisDisplaySettingsKey];
}
- (OrbisDisplayLayout)previewLayout
{
    NSArray *screens = [NSScreen screens];
    NSSize primary = [[screens firstObject] frame].size;
    NSSize secondary = [(screens.count > 1 ? screens[1] : [screens firstObject]) frame].size;
    uint32_t pw = (uint32_t)(_primaryWidth ?: MIN(8192, MAX(800, primary.width)));
    uint32_t ph = (uint32_t)(_primaryHeight ?: MIN(8192, MAX(600, primary.height)));
    uint32_t sw = (uint32_t)(_secondaryWidth ?: MIN(8192, MAX(800, secondary.width)));
    uint32_t sh = (uint32_t)(_secondaryHeight ?: MIN(8192, MAX(600, secondary.height)));
    pw -= pw % 2; sw -= sw % 2;
    OrbisDisplayLayout layout;
    OrbisDisplayLayoutMakeWithOffset(pw, ph, sw, sh, _arrangement, _offset, true, &layout);
    return layout;
}
- (void)placeSecondaryAtPoint:(NSPoint)point
{
    OrbisDisplayLayout layout = [self previewLayout];
    CGFloat pw = layout.monitors[0].width, ph = layout.monitors[0].height;
    CGFloat sw = layout.monitors[1].width, sh = layout.monitors[1].height;
    NSPoint candidates[] = { NSMakePoint(pw, MIN(ph - 1, MAX(1 - sh, point.y))),
        NSMakePoint(-sw, MIN(ph - 1, MAX(1 - sh, point.y))),
        NSMakePoint(MIN(pw - 1, MAX(1 - sw, point.x)), -sh),
        NSMakePoint(MIN(pw - 1, MAX(1 - sw, point.x)), ph) };
    CGFloat distance = CGFLOAT_MAX;
    for (NSUInteger i = 0; i < 4; i++)
    {
        CGFloat dx = point.x - candidates[i].x, dy = point.y - candidates[i].y;
        CGFloat next = dx * dx + dy * dy;
        if (next < distance)
        {
            distance = next; _arrangement = (OrbisMonitorArrangement)i;
            _offset = (int32_t)llround(i < 2 ? candidates[i].y : candidates[i].x);
        }
    }
    OrbisDisplayLayout normalized = [self previewLayout];
    _offset = _arrangement < OrbisMonitorAbove ? normalized.monitors[1].y : normalized.monitors[1].x;
}
@end

@implementation OrbisDisplayArrangementView
@synthesize settings = _settings;
- (instancetype)initWithFrame:(NSRect)frame
{
    if (!(self = [super initWithFrame:frame])) return nil;
    _dragMonitor = -1; _selectedMonitor = 1;
    [self setAccessibilityElement:YES];
    [self setAccessibilityRole:NSAccessibilityGroupRole];
    [self setAccessibilityLabel:@"Monitor arrangement"];
    [self setAccessibilityIdentifier:@"display-arrangement"];
    [self setAccessibilityHelp:@"Drag either display to arrange it. Use arrow keys to place the second display beside the primary; hold Shift to adjust alignment."];
    return self;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)becomeFirstResponder { [self setNeedsDisplay:YES]; return YES; }
- (BOOL)resignFirstResponder { [self setNeedsDisplay:YES]; return YES; }
- (NSString *)accessibilityValue
{
    NSArray *sides = @[ @"right", @"left", @"above", @"below" ];
    return [NSString stringWithFormat:@"Display 2 %@ of display 1, offset %d pixels", sides[_settings.arrangement], _settings.offset];
}
- (void)updateMonitorRects
{
    OrbisDisplayLayout layout = [_settings previewLayout];
    _scale = MIN((self.bounds.size.width - 100) / layout.width, (self.bounds.size.height - 60) / layout.height);
    NSPoint origin = NSMakePoint((self.bounds.size.width - layout.width * _scale) / 2,
        (self.bounds.size.height - layout.height * _scale) / 2);
    for (NSUInteger i = 0; i < 2; i++)
    {
        OrbisDisplayRect r = layout.pixels[i];
        _monitorRects[i] = NSMakeRect(origin.x + r.x * _scale, origin.y + r.y * _scale, r.width * _scale, r.height * _scale);
    }
}
- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    [[NSColor controlBackgroundColor] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:8 yRadius:8] fill];
    [self updateMonitorRects];
    for (NSUInteger i = 0; i < 2; i++)
    {
        NSRect rect = _monitorRects[i];
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 2, 2) xRadius:5 yRadius:5];
        [[NSColor systemTealColor] setFill]; [path fill];
        BOOL focused = self.window.firstResponder == self && _selectedMonitor == (NSInteger)i;
        [(focused ? [NSColor keyboardFocusIndicatorColor] : [NSColor separatorColor]) setStroke];
        [path setLineWidth:focused ? 3 : 1]; [path stroke];
        if (!i)
        {
            [[NSColor whiteColor] setFill];
            NSRectFill(NSMakeRect(rect.origin.x + 7, rect.origin.y + 7, rect.size.width - 14, 5));
        }
        NSString *text = [NSString stringWithFormat:@"%lu", (unsigned long)i + 1];
        NSDictionary *attributes = @{ NSFontAttributeName:[NSFont systemFontOfSize:24 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName:[NSColor whiteColor] };
        NSSize size = [text sizeWithAttributes:attributes];
        [text drawAtPoint:NSMakePoint(NSMidX(rect) - size.width / 2, NSMidY(rect) - size.height / 2) withAttributes:attributes];
    }
}
- (void)mouseDown:(NSEvent *)event
{
    [self updateMonitorRects];
    [self.window makeFirstResponder:self];
    _dragStart = [self convertPoint:event.locationInWindow fromView:nil];
    _dragMonitor = -1;
    for (NSInteger i = 1; i >= 0; i--)
        if (NSPointInRect(_dragStart, _monitorRects[i])) { _dragMonitor = i; _selectedMonitor = i; break; }
    OrbisDisplayLayout layout = [_settings previewLayout];
    _originalPosition = NSMakePoint(layout.monitors[1].x, layout.monitors[1].y);
    _dragScale = MAX(_scale, 0.001);
    [self setNeedsDisplay:YES];
}
- (void)mouseDragged:(NSEvent *)event
{
    if (_dragMonitor < 0) return;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat direction = _dragMonitor ? 1 : -1;
    [_settings placeSecondaryAtPoint:NSMakePoint(_originalPosition.x + direction * (point.x - _dragStart.x) / _dragScale,
        _originalPosition.y + direction * (point.y - _dragStart.y) / _dragScale)];
    [self setNeedsDisplay:YES];
}
- (void)mouseUp:(NSEvent *)event
{
    (void)event; _dragMonitor = -1;
    NSAccessibilityPostNotification(self, NSAccessibilityValueChangedNotification);
}
- (void)keyDown:(NSEvent *)event
{
    unsigned short code = event.keyCode;
    if (code < 123 || code > 126) { [super keyDown:event]; return; }
    if (event.modifierFlags & NSEventModifierFlagShift)
    {
        OrbisDisplayLayout layout = [_settings previewLayout];
        NSPoint position = NSMakePoint(layout.monitors[1].x + (code == 123 ? -40 : code == 124 ? 40 : 0),
            layout.monitors[1].y + (code == 126 ? -40 : code == 125 ? 40 : 0));
        [_settings placeSecondaryAtPoint:position];
    }
    else
    {
        _settings.arrangement = code == 123 ? OrbisMonitorLeft : code == 124 ? OrbisMonitorRight :
            code == 126 ? OrbisMonitorAbove : OrbisMonitorBelow;
        _settings.offset = 0;
    }
    [self setNeedsDisplay:YES];
    NSAccessibilityPostNotification(self, NSAccessibilityValueChangedNotification);
}
- (void)dealloc { [_settings release]; [super dealloc]; }
@end

@implementation OrbisDisplaySettingsController
- (instancetype)initWithSettings:(OrbisDisplaySettings *)settings
{
    NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 620, 780)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO] autorelease];
    if (!(self = [super initWithWindow:window])) return nil;
    _settings = [settings copy];
    [window setTitle:@"Settings"];
    [window setReleasedWhenClosed:NO];
    NSView *content = window.contentView;
    NSTextField *title = [NSTextField labelWithString:@"Displays"];
    [title setFont:[NSFont systemFontOfSize:22 weight:NSFontWeightSemibold]];
    NSTextField *hint = [NSTextField wrappingLabelWithString:
        @"Drag the displays to match your Mac screens. The white bar marks the primary display. Arrow keys change sides; Shift + arrows adjust alignment."];
    [hint setTextColor:[NSColor secondaryLabelColor]];
    _arrangementView = [[OrbisDisplayArrangementView alloc] initWithFrame:NSMakeRect(0, 0, 556, 210)];
    _arrangementView.settings = _settings;
    NSMutableArray *rows = [NSMutableArray arrayWithObjects:title, hint, _arrangementView, nil];
    for (NSUInteger i = 0; i < 2; i++)
    {
        NSUInteger width = i ? _settings.secondaryWidth : _settings.primaryWidth;
        NSUInteger height = i ? _settings.secondaryHeight : _settings.primaryHeight;
        NSString *prefix = i ? @"secondary" : @"primary";
        _modes[i] = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [_modes[i] addItemsWithTitles:@[ @"Automatic", @"Manual" ]];
        [_modes[i] selectItemAtIndex:width ? 1 : 0];
        [_modes[i] setTarget:self]; [_modes[i] setAction:@selector(resolutionChanged:)];
        [_modes[i] setAccessibilityIdentifier:[@"settings-" stringByAppendingFormat:@"%@-resolution-mode", prefix]];
        _widths[i] = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _heights[i] = [[NSTextField alloc] initWithFrame:NSZeroRect];
        [_widths[i] setStringValue:[NSString stringWithFormat:@"%lu", (unsigned long)(width ?: 1920)]];
        [_heights[i] setStringValue:[NSString stringWithFormat:@"%lu", (unsigned long)(height ?: 1080)]];
        for (NSTextField *field in @[ _widths[i], _heights[i] ])
        {
            OrbisConfigureFormField(field, nil);
            [field setDelegate:self];
            [[field widthAnchor] constraintEqualToConstant:90].active = YES;
            [[field heightAnchor] constraintEqualToConstant:36].active = YES;
        }
        [_widths[i] setAccessibilityLabel:[NSString stringWithFormat:@"Display %lu width in pixels", (unsigned long)i + 1]];
        [_heights[i] setAccessibilityLabel:[NSString stringWithFormat:@"Display %lu height in pixels", (unsigned long)i + 1]];
        [_widths[i] setAccessibilityIdentifier:[@"settings-" stringByAppendingFormat:@"%@-width", prefix]];
        [_heights[i] setAccessibilityIdentifier:[@"settings-" stringByAppendingFormat:@"%@-height", prefix]];
        NSTextField *label = [NSTextField labelWithString:i ? @"Display 2" : @"Display 1"];
        [[label widthAnchor] constraintEqualToConstant:80].active = YES;
        NSStackView *row = [NSStackView stackViewWithViews:@[ label, _modes[i], _widths[i],
            [NSTextField labelWithString:@"×"], _heights[i] ]];
        [row setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
        [row setAlignment:NSLayoutAttributeCenterY]; [row setSpacing:10];
        [[_modes[i] widthAnchor] constraintEqualToConstant:130].active = YES;
        [rows addObject:row];
    }
    NSTextField *note = [NSTextField wrappingLabelWithString:
        @"Resolutions use pixels. These settings apply to all connections when a session starts. Open the second display with Session → Add Virtual Display."];
    [note setTextColor:[NSColor secondaryLabelColor]];
    _validationLabel = [[NSTextField wrappingLabelWithString:@""] retain];
    [_validationLabel setTextColor:[NSColor systemRedColor]];
    [_validationLabel setHidden:YES];
    [rows addObjectsFromArray:@[ note, _validationLabel ]];
    NSTextField *inputTitle = [NSTextField labelWithString:@"Input"];
    [inputTitle setFont:[NSFont systemFontOfSize:18 weight:NSFontWeightSemibold]];
    _captureInput = [[NSButton checkboxWithTitle:@"Capture Mac input in full screen" target:nil action:nil] retain];
    [_captureInput setState:[[NSUserDefaults standardUserDefaults] boolForKey:OrbisFullscreenInputCaptureKey]
        ? NSControlStateValueOn : NSControlStateValueOff];
    [_captureInput setAccessibilityIdentifier:@"settings-fullscreen-input-capture"];
    NSTextField *inputHint = [NSTextField wrappingLabelWithString:
        @"Forward physical keys, shortcuts, mouse buttons and macros that generate input to the active remote desktop. Command becomes Super and Option becomes Alt. Control + Option + Command + Esc releases capture until you leave full screen or switch apps. Windowed sessions keep their usual Mac shortcuts."];
    [inputHint setTextColor:[NSColor secondaryLabelColor]];
    NSButton *permission = [NSButton buttonWithTitle:@"Allow input capture…" target:self action:@selector(requestInputPermission:)];
    [permission setBezelStyle:NSBezelStyleRounded];
    [permission setToolTip:@"Allow Orbis to control input in macOS Privacy & Security settings. Required for full screen capture."];
    [rows addObjectsFromArray:@[ inputTitle, _captureInput, inputHint, permission ]];
    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
    NSButton *save = [NSButton buttonWithTitle:@"Save settings" target:self action:@selector(save:)];
    [cancel setKeyEquivalent:@"\033"]; [save setKeyEquivalent:@"\r"];
    for (NSButton *button in @[ cancel, save ])
    {
        [button setBezelStyle:NSBezelStyleRounded];
        [button setControlSize:NSControlSizeLarge];
        [[button widthAnchor] constraintGreaterThanOrEqualToConstant:110].active = YES;
        [[button heightAnchor] constraintEqualToConstant:34].active = YES;
    }
    [save setContentTintColor:[NSColor systemTealColor]];
    NSStackView *buttons = [NSStackView stackViewWithViews:@[ cancel, save ]];
    [buttons setOrientation:NSUserInterfaceLayoutOrientationHorizontal]; [buttons setSpacing:10];
    [buttons setTranslatesAutoresizingMaskIntoConstraints:NO]; [content addSubview:buttons];
    NSStackView *stack = [NSStackView stackViewWithViews:rows];
    [stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [stack setAlignment:NSLayoutAttributeLeading]; [stack setSpacing:16];
    [stack setTranslatesAutoresizingMaskIntoConstraints:NO]; [content addSubview:stack];
    for (NSView *row in rows)
        if (row != permission) [[row widthAnchor] constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:32],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-32],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:26],
        [_arrangementView.heightAnchor constraintEqualToConstant:210],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:buttons.topAnchor constant:-16],
        [buttons.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor],
        [buttons.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-24] ]];
    [self resolutionChanged:nil];
    return self;
}
- (void)beginSheetForWindow:(NSWindow *)window
{
    [window beginSheet:self.window completionHandler:^(NSModalResponse response) { (void)response; [self close]; }];
}
- (BOOL)readResolution:(NSUInteger)i width:(NSUInteger *)width height:(NSUInteger *)height
{
    *width = *height = 0;
    if (_modes[i].indexOfSelectedItem == 0) return YES;
    NSString *w = _widths[i].stringValue, *h = _heights[i].stringValue;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
    if (!w.length || !h.length || w.length > 4 || h.length > 4 ||
        [w rangeOfCharacterFromSet:invalid].location != NSNotFound || [h rangeOfCharacterFromSet:invalid].location != NSNotFound)
        return NO;
    *width = w.integerValue; *height = h.integerValue;
    return OrbisDisplayResolutionIsValid((uint32_t)*width, (uint32_t)*height);
}
- (void)resolutionChanged:(id)sender
{
    (void)sender;
    NSUInteger sizes[4];
    for (NSUInteger i = 0; i < 2; i++)
    {
        BOOL manual = _modes[i].indexOfSelectedItem == 1;
        [_widths[i] setEnabled:manual]; [_heights[i] setEnabled:manual];
    }
    if ([self readResolution:0 width:&sizes[0] height:&sizes[1]] &&
        [self readResolution:1 width:&sizes[2] height:&sizes[3]])
    {
        _settings.primaryWidth = sizes[0]; _settings.primaryHeight = sizes[1];
        _settings.secondaryWidth = sizes[2]; _settings.secondaryHeight = sizes[3];
        OrbisDisplayLayout normalized = [_settings previewLayout];
        _settings.offset = _settings.arrangement < OrbisMonitorAbove ? normalized.monitors[1].y : normalized.monitors[1].x;
        [_validationLabel setHidden:YES];
        [_arrangementView setNeedsDisplay:YES];
    }
}
- (void)controlTextDidChange:(NSNotification *)notification { (void)notification; [self resolutionChanged:nil]; }
- (void)save:(id)sender
{
    (void)sender;
    NSUInteger w, h;
    for (NSUInteger i = 0; i < 2; i++)
        if (![self readResolution:i width:&w height:&h])
        {
            [_validationLabel setStringValue:@"Use resolutions from 200 to 8192 pixels, with an even width."];
            [_validationLabel setHidden:NO]; return;
        }
    [self resolutionChanged:nil];
    [_settings saveToDefaults:[NSUserDefaults standardUserDefaults]];
    BOOL enabled = _captureInput.state == NSControlStateValueOn;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:OrbisFullscreenInputCaptureKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:OrbisInputCaptureSettingsDidChangeNotification object:nil];
    if (enabled && !AXIsProcessTrusted()) [self requestInputPermission:nil];
    [self.window.sheetParent endSheet:self.window];
}
- (void)requestInputPermission:(id)sender
{
    (void)sender;
    AXIsProcessTrustedWithOptions((CFDictionaryRef)@{ (id)kAXTrustedCheckOptionPrompt: @YES });
}
- (void)cancel:(id)sender { (void)sender; [self.window.sheetParent endSheet:self.window]; }
- (void)dealloc
{
    [_settings release]; [_arrangementView release]; [_validationLabel release];
    [_captureInput release];
    for (NSUInteger i = 0; i < 2; i++) { [_modes[i] release]; [_widths[i] release]; [_heights[i] release]; }
    [super dealloc];
}
@end
