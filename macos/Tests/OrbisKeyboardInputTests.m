/* SPDX-License-Identifier: MIT */

#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <IOKit/hidsystem/IOLLEvent.h>
#import "MRDPView.h"
#import "OrbisInputCapture.h"
#import "OrbisKeyboardCompatibility.h"
#import <ApplicationServices/ApplicationServices.h>
#include <unistd.h>

// Replace only the macOS permission and filter creation boundary. Exercise the
// production event-filter adapter, including an OS-created filter with stripped keys.
static BOOL osAccessibility = YES, osKeyboardAccess = YES, osPartialKeyboard, osTapCreated, osTapListUnavailable;
static CGEventMask osRequestedMask;
static NSUInteger osTapCreations;
Boolean OrbisTestAccessibilityAllowed(void) { return osAccessibility; }
bool OrbisTestKeyboardAllowed(void) { return osKeyboardAccess; }
static void TestMachPortCallback(CFMachPortRef port, void *message, CFIndex size, void *info)
{ (void)port; (void)message; (void)size; (void)info; }
CFMachPortRef OrbisTestCreateEventTap(CGEventTapLocation location, CGEventTapPlacement placement,
    CGEventTapOptions options, CGEventMask mask, CGEventTapCallBack callback, void *context)
{
    (void)location; (void)placement; (void)options; (void)callback; (void)context;
    osRequestedMask = mask; osTapCreated = YES; osTapCreations++;
    CFMachPortContext portContext = {0};
    return CFMachPortCreate(kCFAllocatorDefault, TestMachPortCallback, &portContext, NULL);
}
void OrbisTestEnableEventTap(CFMachPortRef port, bool enable) { (void)port; osTapCreated = enable; }
CGError OrbisTestEventTapList(uint32_t maximum, CGEventTapInformation *list, uint32_t *count)
{
    if (osTapListUnavailable) return kCGErrorFailure;
    *count = osTapCreated ? 2 : 1;
    if (!maximum || !list) return kCGErrorSuccess;
    if (maximum < *count) return kCGErrorRangeCheck;
    // A pre-existing complete filter must not disguise our new partial filter.
    list[0] = (CGEventTapInformation){ .eventTapID = 41, .tapPoint = kCGSessionEventTap,
        .tappingProcess = getpid(), .enabled = true, .eventsOfInterest = UINT64_MAX };
    if (osTapCreated)
        list[1] = (CGEventTapInformation){ .eventTapID = 42, .tapPoint = kCGSessionEventTap,
            .tappingProcess = getpid(), .enabled = true, .eventsOfInterest = osRequestedMask &
                ~(osPartialKeyboard ? (CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp)) : 0) };
    return kCGErrorSuccess;
}

@interface OrbisEventSinkFixture : NSObject <OrbisInputEventSink>
@end
@implementation OrbisEventSinkFixture
- (BOOL)consumeEvent:(CGEventRef)event type:(CGEventType)type { (void)event; (void)type; return NO; }
@end

static NSMutableArray *events;
static NSUInteger failures;
static NSUInteger mouseEvents;
static NSUInteger displayPointerEvents;
static UINT16 displayPointerFlags;
static NSPoint displayPointerPoint;
BOOL OrbisRecordDisplayPointer(rdpClientContext *context, BOOL relative, UINT16 flags, INT32 x, INT32 y)
{
	(void)context; (void)relative;
	displayPointerFlags = flags;
	displayPointerEvents++; displayPointerPoint = NSMakePoint(x, y);
	return TRUE;
}

BOOL OrbisRecordExtendedDisplayPointer(rdpClientContext *context, BOOL relative, UINT16 flags, INT32 x, INT32 y)
{
    return OrbisRecordDisplayPointer(context, relative, flags, x, y);
}

void OrbisRecordMouseButton(void *context, int button, int x, int y, BOOL down)
{
	(void)context;
	(void)button;
	(void)x;
	(void)y;
	(void)down;
	mouseEvents++;
}

BOOL OrbisRecordKeyboardEvent(rdpInput *input, UINT16 flags, UINT8 code)
{
	(void)input;
	[events addObject:@{ @"unicode" : @NO, @"flags" : @(flags), @"code" : @(code) }];
	return TRUE;
}

BOOL OrbisRecordUnicodeKeyboardEvent(rdpInput *input, UINT16 flags, UINT16 code)
{
	(void)input;
	[events addObject:@{ @"unicode" : @YES, @"flags" : @(flags), @"code" : @(code) }];
	return TRUE;
}

@interface OrbisKeyboardTestView : MRDPView
{
	freerdp _instanceFixture;
	mfContext _contextFixture;
	rdpInput _inputFixture;
}
@end

@interface OrbisCaptureTestWindow : NSWindow
@property(nonatomic) BOOL captureFullscreen;
@end
@implementation OrbisCaptureTestWindow
@synthesize captureFullscreen;
- (NSWindowStyleMask)styleMask
{
    return [super styleMask] | (captureFullscreen ? NSWindowStyleMaskFullScreen : 0);
}
@end

@interface OrbisCaptureTestDelegate : NSObject <OrbisInputCaptureDelegate>
@property(nonatomic, assign) MRDPView *view;
@property(nonatomic) BOOL eligible;
@end
@implementation OrbisCaptureTestDelegate
@synthesize view, eligible;
- (MRDPView *)inputCaptureKeyboardTarget { return eligible ? view : nil; }
- (MRDPView *)inputCapturePointerTargetAtScreenPoint:(NSPoint)point { (void)point; return eligible ? view : nil; }
@end

@interface OrbisSpanishTestTextTranslator : OrbisKeyboardTextTranslator
@end
@implementation OrbisSpanishTestTextTranslator
- (NSData *)keyboardLayoutData
{
    CFArrayRef sources = TISCreateInputSourceList((CFDictionaryRef)@{
        (id)kTISPropertyInputSourceID: @"com.apple.keylayout.Spanish-ISO" }, true);
    NSData *data = nil;
    if (CFArrayGetCount(sources))
        data = [[(NSData *)TISGetInputSourceProperty((TISInputSourceRef)CFArrayGetValueAtIndex(sources, 0),
            kTISPropertyUnicodeKeyLayoutData) retain] autorelease];
    CFRelease(sources);
    return data;
}
@end

@interface OrbisTestInputCapture : OrbisInputCapture
@property(nonatomic) BOOL allowTap;
@property(nonatomic) BOOL deniesKeyboard;
@property(nonatomic) NSUInteger tapAttempts;
- (NSData *)keyboardLayoutData;
@end
@implementation OrbisTestInputCapture
@synthesize allowTap, tapAttempts, deniesKeyboard;
- (BOOL)keyboardCaptureAllowed { return !deniesKeyboard; }
- (BOOL)installTap { tapAttempts++; return allowTap; }
- (instancetype)initWithDelegate:(id<OrbisInputCaptureDelegate>)delegate
{
    if (!(self = [super initWithDelegate:delegate])) return nil;
    [_textTranslator release]; _textTranslator = [[OrbisSpanishTestTextTranslator alloc] init];
    return self;
}
- (NSData *)keyboardLayoutData { return [_textTranslator keyboardLayoutData]; }

@end

@implementation OrbisKeyboardTestView
- (id)init
{
	if (!(self = [super initWithFrame:NSMakeRect(0, 0, 800, 600)]))
		return nil;
	mfc = &_contextFixture;
	instance = &_instanceFixture;
	instance->context = (rdpContext *)mfc;
	instance->context->input = &_inputFixture;
	mfc->appleKeyboardType = APPLE_KEYBOARD_TYPE_ANSI;
	[self setIs_connected:1];
	[self setMapsCommandShortcutsToControl:YES];
	return self;
}
- (void)makeDisplayBitmap
{
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	bitmap_context = CGBitmapContextCreate(NULL, 600, 200, 8, 600 * 4,
	    colorSpace, kCGImageAlphaPremultipliedLast);
	CGColorSpaceRelease(colorSpace);
	CGContextSetRGBFillColor(bitmap_context, 1, 0, 0, 1);
	CGContextFillRect(bitmap_context, CGRectMake(0, 0, 400, 200));
	CGContextSetRGBFillColor(bitmap_context, 0, 0, 1, 1);
	CGContextFillRect(bitmap_context, CGRectMake(400, 0, 200, 200));
}
- (void)dealloc
{
	if (bitmap_context) CGContextRelease(bitmap_context);
	[super dealloc];
}
@end

static NSEvent *Key(NSEventType type, unsigned short code, NSString *text, NSString *base,
                    NSEventModifierFlags flags)
{
	return [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:flags
	    timestamp:1 windowNumber:0 context:nil characters:text charactersIgnoringModifiers:base
	    isARepeat:NO keyCode:code];
}

static void Require(BOOL condition, NSString *message)
{
	if (condition)
		return;
	fprintf(stderr, "FAIL: %s; RDP events: %s\n", [message UTF8String], [[events description] UTF8String]);
	failures++;
}

static NSArray *UnicodeEvents(void)
{
	return [events filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:
	    ^BOOL(NSDictionary *event, NSDictionary *bindings) {
		(void)bindings;
		return [event[@"unicode"] boolValue];
	}]];
}

static void CheckOptionText(NSString *text, NSEventModifierFlags extraFlags)
{
	[events removeAllObjects];
	OrbisKeyboardTestView *view = [[OrbisKeyboardTestView alloc] init];
	NSEventModifierFlags flags = NSEventModifierFlagOption | extraFlags;
	[view flagsChanged:Key(NSEventTypeFlagsChanged, 58, @"", @"", flags)];
	[view keyDown:Key(NSEventTypeKeyDown, 19, text, @"2", flags)];
	// Releasing Option before the printable key must not leak its physical key-up.
	[view flagsChanged:Key(NSEventTypeFlagsChanged, 58, @"", @"", 0)];
	[view keyUp:Key(NSEventTypeKeyUp, 19, @"2", @"2", 0)];
	NSArray *unicode = UnicodeEvents();
	Require(unicode.count == text.length * 2, [NSString stringWithFormat:@"Option text must reach RDP: %@", text]);
	for (NSUInteger index = 0; index < text.length && unicode.count == text.length * 2; index++)
	{
		Require([unicode[index * 2][@"code"] unsignedIntValue] == [text characterAtIndex:index] &&
		        !([unicode[index * 2][@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE) &&
		        [unicode[index * 2 + 1][@"code"] unsignedIntValue] == [text characterAtIndex:index] &&
		        ([unicode[index * 2 + 1][@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
		        @"Each symbol needs its own Unicode press and release");
	}
	for (NSDictionary *event in events)
		Require([event[@"unicode"] boolValue] || [event[@"code"] unsignedIntValue] == 0x2A,
		        @"Option text must not send Alt or the physical base key");
	[view release];
}

static void RequireWordDeletion(NSUInteger start)
{
	Require(events.count == start + 4 && UnicodeEvents().count == 0,
	        @"Word deletion must send exactly one complete Control+Backspace chord");
	if (events.count != start + 4)
		return;
	const UINT8 codes[] = { 0x1D, 0x0E, 0x0E, 0x1D };
	for (NSUInteger index = 0; index < 4; index++)
		Require([events[start + index][@"code"] unsignedIntValue] == codes[index] &&
		        (([events[start + index][@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE) != 0) ==
		            (index >= 2),
		        @"Word deletion must press Control, press/release Backspace, then release Control");
}

static void CheckOptionBackspace(BOOL releaseOptionFirst, BOOL repeat)
{
	[events removeAllObjects];
	OrbisKeyboardTestView *view = [[OrbisKeyboardTestView alloc] init];
	[view flagsChanged:Key(NSEventTypeFlagsChanged, 58, @"", @"", NSEventModifierFlagOption)];
	[view keyDown:Key(NSEventTypeKeyDown, 51, @"\177", @"\177", NSEventModifierFlagOption)];
	RequireWordDeletion(0);
	if (repeat)
	{
		NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
		    modifierFlags:NSEventModifierFlagOption timestamp:2 windowNumber:0 context:nil
		    characters:@"\177" charactersIgnoringModifiers:@"\177" isARepeat:YES keyCode:51];
		[view keyDown:event];
		RequireWordDeletion(4);
	}
	if (releaseOptionFirst)
		[view flagsChanged:Key(NSEventTypeFlagsChanged, 58, @"", @"", 0)];
	[view keyUp:Key(NSEventTypeKeyUp, 51, @"\177", @"\177",
	               releaseOptionFirst ? 0 : NSEventModifierFlagOption)];
	if (!releaseOptionFirst)
		[view flagsChanged:Key(NSEventTypeFlagsChanged, 58, @"", @"", 0)];
	Require(events.count == (repeat ? 8 : 4),
	        @"Either release order must avoid stray Backspace releases or remote Alt");
	[events removeAllObjects];
	[view keyDown:Key(NSEventTypeKeyDown, 0, @"a", @"a", 0)];
	[view keyUp:Key(NSEventTypeKeyUp, 0, @"a", @"a", 0)];
	Require(events.count == 2 && [events[0][@"code"] unsignedIntValue] == 0x1E &&
	        [events[1][@"code"] unsignedIntValue] == 0x1E,
	        @"Typing after word deletion must not retain a remote modifier");
	[view release];
}

static void CheckDisplayViewports(void)
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
	    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
	[window setReleasedWhenClosed:NO];
	OrbisKeyboardTestView *source = [[OrbisKeyboardTestView alloc] init];
	MRDPView *second = [[MRDPView alloc] initWithFrame:NSMakeRect(20, 30, 400, 200)];
	[[window contentView] addSubview:second];
	[second attachToDisplaySource:source];
	[second setMapsCommandShortcutsToControl:YES];
	[second setDisplayRegion:NSMakeRect(1024, 0, 1280, 800)];
	NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeMouseMoved location:NSMakePoint(220, 130)
	    modifierFlags:0 timestamp:1 windowNumber:window.windowNumber context:nil eventNumber:1 clickCount:0 pressure:0];
	NSPoint point = [second remotePointForEvent:event];
	Require(NSEqualPoints(point, NSMakePoint(1664, 400)), @"Secondary pointer coordinates must include region offset, scaling, and the view origin");
	displayPointerEvents = 0; [second mouseMoved:event];
	Require(displayPointerEvents == 1 && NSEqualPoints(displayPointerPoint, point),
	    @"Managed pointer events must reach RDP without scaling twice");
	[events removeAllObjects];
	[second keyDown:Key(NSEventTypeKeyDown, 8, @"c", @"c", NSEventModifierFlagCommand)];
	Require(events.count > 0, @"The second display must use the existing session keyboard");

	[source makeDisplayBitmap];
	[second setDisplayRegion:NSMakeRect(400, 0, 200, 200)];
	NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
	    pixelsWide:400 pixelsHigh:200 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
	    isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:1600 bitsPerPixel:32] autorelease];
	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
	[second drawRect:second.bounds];
	[NSGraphicsContext restoreGraphicsState];
	NSColor *color = [[bitmap colorAtX:200 y:100] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
	Require(color.blueComponent > 0.9 && color.redComponent < 0.1,
	    @"The second window must paint only its blue monitor, excluding the red primary monitor");
	[second detachFromDisplaySource];
	Require(!second.is_connected && source.is_connected, @"Detaching the second display must preserve the primary session");
	[second removeFromSuperview]; [second release]; [source release]; [window release];
}

static void CheckCommandEventOrdering(void)
{
    [events removeAllObjects];
    OrbisKeyboardTestView *view = [[OrbisKeyboardTestView alloc] init];
    // A nested client can deliver the shortcut before its modifier transition.
    [view keyDown:Key(NSEventTypeKeyDown, 8, @"c", @"c", NSEventModifierFlagCommand)];
    [view setCommandKeyDown:YES];
    [view setCommandKeyDown:NO];
    Require(events.count == 4,
        @"A shortcut observed before Command state must not produce an extra remote Super tap");
    [view release];

    [events removeAllObjects];
    view = [[OrbisKeyboardTestView alloc] init];
    [view flagsChanged:Key(NSEventTypeFlagsChanged, 55, @"", @"", NSEventModifierFlagCommand)];
    [view keyDown:Key(NSEventTypeKeyDown, 14, @"e", @"e", NSEventModifierFlagCommand)];
    // AppKit may omit keyUp for keys used while Command is held.
    [view flagsChanged:Key(NSEventTypeFlagsChanged, 55, @"", @"", 0)];
    NSInteger balance = 0;
    for (NSDictionary *event in events)
    {
        if ([event[@"code"] unsignedIntValue] == 0x12)
            balance += ([event[@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE) ? -1 : 1;
    }
    Require(balance == 0, @"Releasing Command must not leave an unmapped key held remotely");
    [view release];
}

static void CheckCommandReleaseTransitions(void)
{
    [events removeAllObjects];
    OrbisKeyboardTestView *view = [[OrbisKeyboardTestView alloc] init];
    [view setCommandKeyDown:YES];
    [view setCommandKeyDown:YES];
    [view setCommandKeyDown:NO];
    [view setCommandKeyDown:NO];
    Require(events.count == 2 && [events[0][@"code"] unsignedIntValue] == 0x5B &&
        ([events[1][@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
        @"A standalone Command tap must remain one complete remote Super tap");
    [view release];

    for (NSNumber *keyCode in @[ @8, @51 ])
    {
        [events removeAllObjects];
        view = [[OrbisKeyboardTestView alloc] init];
        NSString *text = keyCode.unsignedShortValue == 8 ? @"c" : @"\177";
        [view flagsChanged:Key(NSEventTypeFlagsChanged, 55, @"", @"", NSEventModifierFlagCommand)];
        [view keyDown:Key(NSEventTypeKeyDown, keyCode.unsignedShortValue, text, text, NSEventModifierFlagCommand)];
        [view flagsChanged:Key(NSEventTypeFlagsChanged, 55, @"", @"", 0)];
        [view keyUp:Key(NSEventTypeKeyUp, keyCode.unsignedShortValue, text, text, 0)];
        Require(events.count == (keyCode.unsignedShortValue == 8 ? 4 : 6),
            @"An atomic Command shortcut must ignore keyUp arriving after Command release");
        [view release];
    }

    for (NSNumber *keyCode in @[ @14 ])
    {
        [events removeAllObjects];
        view = [[OrbisKeyboardTestView alloc] init];
        NSString *text = keyCode.unsignedShortValue == 14 ? @"e" : @"";
        [view flagsChanged:Key(NSEventTypeFlagsChanged, 55, @"", @"", NSEventModifierFlagCommand)];
        [view keyDown:Key(NSEventTypeKeyDown, keyCode.unsignedShortValue, text, text, NSEventModifierFlagCommand)];
        [view setCommandKeyDown:NO];
        Require(events.count == 2 &&
            [events[0][@"code"] unsignedIntValue] == [events[1][@"code"] unsignedIntValue] &&
            ([events[1][@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
            @"Every non-atomic Command key must receive its remote release when keyUp is missing");
        [view keyUp:Key(NSEventTypeKeyUp, keyCode.unsignedShortValue, text, text, 0)];
        Require(events.count == 2, @"A late keyUp must not release an already completed Command key twice");
        [view keyDown:Key(NSEventTypeKeyDown, keyCode.unsignedShortValue, text, text, 0)];
        [view keyUp:Key(NSEventTypeKeyUp, keyCode.unsignedShortValue, text, text, 0)];
        Require(events.count == 4 && ([events.lastObject[@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
            @"The same key must still work normally after recovering a Command chord");
        [view release];
    }

    [events removeAllObjects];
    view = [[OrbisKeyboardTestView alloc] init];
    [view flagsChanged:Key(NSEventTypeFlagsChanged, 55, @"", @"", NSEventModifierFlagCommand)];
    [view keyDown:Key(NSEventTypeKeyDown, 14, @"e", @"e", NSEventModifierFlagCommand)];
    [view keyUp:Key(NSEventTypeKeyUp, 14, @"e", @"e", NSEventModifierFlagCommand)];
    [view setCommandKeyDown:NO];
    Require(events.count == 2, @"A Command key released normally must not be released again");
    [view release];

    [events removeAllObjects];
    view = [[OrbisKeyboardTestView alloc] init];
    [view flagsChanged:Key(NSEventTypeFlagsChanged, 55, @"", @"", NSEventModifierFlagCommand)];
    [view keyDown:Key(NSEventTypeKeyDown, 14, @"e", @"e", NSEventModifierFlagCommand)];
    NSEvent *repeat = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:NSEventModifierFlagCommand timestamp:2 windowNumber:0 context:nil
        characters:@"e" charactersIgnoringModifiers:@"e" isARepeat:YES keyCode:14];
    [view keyDown:repeat];
    [view setCommandKeyDown:NO];
    Require(events.count == 3 && ([events.lastObject[@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
        @"Repeated unmapped Command keys must end with one remote release");
    [view release];

    [events removeAllObjects];
    view = [[OrbisKeyboardTestView alloc] init];
    [view flagsChanged:Key(NSEventTypeFlagsChanged, 55, @"", @"", NSEventModifierFlagCommand)];
    [view keyDown:Key(NSEventTypeKeyDown, 14, @"e", @"e", NSEventModifierFlagCommand)];
    [view cancelPendingCommandTap];
    [view setCommandKeyDown:NO];
    Require(events.count == 2 && [events.lastObject[@"code"] unsignedIntValue] == 0x12 &&
        ([events.lastObject[@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
        @"Focus cancellation must release Command keys without creating a Super tap");
    [view release];

    [events removeAllObjects];
    view = [[OrbisKeyboardTestView alloc] init];
    NSEventModifierFlags chord = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [view flagsChanged:Key(NSEventTypeFlagsChanged, 55, @"", @"", chord)];
    [view keyDown:Key(NSEventTypeKeyDown, 14, @"e", @"e", chord)];
    [view flagsChanged:Key(NSEventTypeFlagsChanged, 55, @"", @"", NSEventModifierFlagShift)];
    Require(events.count == 3 && [events[0][@"code"] unsignedIntValue] == 0x2A &&
        [events.lastObject[@"code"] unsignedIntValue] == 0x12 &&
        ([events.lastObject[@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
        @"Recovering a Command key must preserve Shift while it is physically held");
    [view flagsChanged:Key(NSEventTypeFlagsChanged, 56, @"", @"", 0)];
    Require(events.count == 4 && [events.lastObject[@"code"] unsignedIntValue] == 0x2A &&
        ([events.lastObject[@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
        @"Shift must be released when its own modifier event arrives");
    [view release];

    [events removeAllObjects];
    view = [[OrbisKeyboardTestView alloc] init];
    NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(10, 10)
        modifierFlags:NSEventModifierFlagCommand timestamp:1 windowNumber:0 context:nil
        eventNumber:1 clickCount:1 pressure:1];
    [view mouseDown:click];
    [view mouseUp:click];
    [view setCommandKeyDown:YES];
    [view setCommandKeyDown:NO];
    Require(events.count == 0, @"A Command pointer action must not create a later Super tap");
    [view release];
    mouseEvents = 0;
}

static CGEventRef CaptureKey(CGEventType type, unsigned short code, CGEventFlags flags)
{
    CGEventRef event = CGEventCreateKeyboardEvent(NULL, code, type != kCGEventKeyUp);
    CGEventSetType(event, type); CGEventSetFlags(event, flags);
    return event;
}

// Pointer traffic must not turn a held editing modifier into a physical Super tap.
static void CheckCapturedEditingPointerInterleaving(void)
{
    for (NSNumber *localLayout in @[ @NO, @YES ])
    {
        [events removeAllObjects];
        OrbisKeyboardTestView *view = [[OrbisKeyboardTestView alloc] init];
        view.capturesLocalKeyboardLayout = localLayout.boolValue;
        CGEventRef command = CaptureKey(kCGEventFlagsChanged, 55, kCGEventFlagMaskCommand);
        [view sendCapturedEvent:command windowPoint:NSZeroPoint];
        CFRelease(command);
        for (NSUInteger index = 0; index < 6; index++)
        {
            unsigned short code = index % 2 ? 9 : 8;
            CGEventRef down = CaptureKey(kCGEventKeyDown, code, kCGEventFlagMaskCommand);
            CGEventRef up = CaptureKey(kCGEventKeyUp, code, kCGEventFlagMaskCommand);
            [view sendCapturedEvent:down windowPoint:NSZeroPoint];
            [view sendCapturedEvent:up windowPoint:NSZeroPoint];
            CFRelease(down); CFRelease(up);
            CGEventRef pointer = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, CGPointMake(10, 10), kCGMouseButtonLeft);
            CGEventSetFlags(pointer, kCGEventFlagMaskCommand);
            [view sendCapturedEvent:pointer windowPoint:NSMakePoint(10, 10)];
            CFRelease(pointer);
        }
        CGEventRef released = CaptureKey(kCGEventFlagsChanged, 55, 0);
        [view sendCapturedEvent:released windowPoint:NSZeroPoint];
        CFRelease(released);
        Require(events.count == 24, @"Copy/paste with intervening pointer movement must send only six complete Control chords");
        BOOL sentSuper = NO;
        for (NSDictionary *event in events) sentSuper |= [event[@"code"] unsignedIntValue] == 0x5B;
        Require(!sentSuper, @"Moving the mouse while Command is held after editing must never emit Super");
        [view release];
    }
    [events removeAllObjects];
    OrbisKeyboardTestView *view = [[OrbisKeyboardTestView alloc] init];
    CGEventRef command = CaptureKey(kCGEventFlagsChanged, 55, kCGEventFlagMaskCommand);
    CGEventRef pointer = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, CGPointMake(10, 10), kCGMouseButtonLeft);
    CGEventSetFlags(pointer, kCGEventFlagMaskCommand);
    [view sendCapturedEvent:command windowPoint:NSZeroPoint];
    [view sendCapturedEvent:pointer windowPoint:NSMakePoint(10, 10)];
    CGEventSetFlags(command, 0);
    [view sendCapturedEvent:command windowPoint:NSZeroPoint];
    Require(events.count == 2 && [events[0][@"code"] unsignedIntValue] == 0x5B &&
        ([events[1][@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
        @"Pointer movement alone must preserve a standalone Command tap");
    [events removeAllObjects];
    CGEventSetFlags(command, kCGEventFlagMaskCommand);
    [view sendCapturedEvent:command windowPoint:NSZeroPoint];
    CGEventRef tab = CaptureKey(kCGEventKeyDown, 48, kCGEventFlagMaskCommand);
    [view sendCapturedEvent:tab windowPoint:NSZeroPoint];
    [view sendCapturedEvent:pointer windowPoint:NSMakePoint(10, 10)];
    Require(events.count == 2, @"Pointer movement must preserve Super already held for a physical chord");
    CGEventSetType(tab, kCGEventKeyUp);
    [view sendCapturedEvent:tab windowPoint:NSZeroPoint];
    CGEventSetFlags(command, 0);
    [view sendCapturedEvent:command windowPoint:NSZeroPoint];
    Require(events.count == 4 && [events.lastObject[@"code"] unsignedIntValue] == 0x5B &&
        ([events.lastObject[@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
        @"A physical Command chord must remain balanced with pointer traffic");
    CFRelease(command); CFRelease(pointer); CFRelease(tab); [view release];
}

static void CheckRapidDistinctPastePresses(void)
{
    for (NSNumber *captured in @[ @NO, @YES ])
    {
        [events removeAllObjects];
        OrbisKeyboardTestView *view = [[OrbisKeyboardTestView alloc] init];
        for (NSUInteger index = 0; index < 6; index++)
        {
            if (captured.boolValue)
            {
                CGEventRef down = CaptureKey(kCGEventKeyDown, 9, kCGEventFlagMaskCommand);
                CGEventSetTimestamp(down, (index + 1) * 10000000);
                CGEventRef up = CaptureKey(kCGEventKeyUp, 9, kCGEventFlagMaskCommand);
                [view sendCapturedEvent:down windowPoint:NSZeroPoint];
                [view sendCapturedEvent:up windowPoint:NSZeroPoint];
                CFRelease(down); CFRelease(up);
            }
            else
            {
                NSEvent *down = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
                    modifierFlags:NSEventModifierFlagCommand timestamp:(index + 1) * 0.01 windowNumber:0 context:nil
                    characters:@"v" charactersIgnoringModifiers:@"v" isARepeat:NO keyCode:9];
                [view keyDown:down];
                [view keyDown:down]; // AppKit redispatch of the identical menu event.
                [view keyUp:Key(NSEventTypeKeyUp, 9, @"v", @"v", NSEventModifierFlagCommand)];
            }
        }
        [view setCommandKeyDown:NO];
        Require(events.count == 24, @"Distinct rapid paste presses must each deliver one complete Control+V chord");
        [view release];
    }
}

static void CheckFullscreenInputCapture(void)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id original = [[defaults objectForKey:OrbisFullscreenInputCaptureKey] retain];
    NSString *layoutKey = OrbisCapturedMacKeyboardLayoutKey;
    id originalLayout = [[defaults objectForKey:layoutKey] retain];
    [defaults removeObjectForKey:layoutKey];
    OrbisCaptureTestWindow *window = [[OrbisCaptureTestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO];
    OrbisKeyboardTestView *view = [[OrbisKeyboardTestView alloc] init];
    [view setDisplayRegion:NSMakeRect(0, 0, 800, 600)];
    [window.contentView addSubview:view];
    OrbisCaptureTestDelegate *delegate = [[OrbisCaptureTestDelegate alloc] init];
    delegate.view = view; delegate.eligible = YES;
    OrbisTestInputCapture *capture = [[OrbisTestInputCapture alloc] initWithDelegate:delegate];
    capture.allowTap = YES;
    CGEventRef down = CaptureKey(kCGEventKeyDown, 48, kCGEventFlagMaskCommand);
    CGEventRef up = CaptureKey(kCGEventKeyUp, 48, kCGEventFlagMaskCommand);
    CGEventRef released = CaptureKey(kCGEventFlagsChanged, 55, 0);
    [defaults setBool:NO forKey:OrbisFullscreenInputCaptureKey]; window.captureFullscreen = YES;
    [events removeAllObjects];
    Require(![capture consumeEvent:down type:kCGEventKeyDown] && !capture.active && !capture.tapAttempts && !events.count,
        @"Disabled capture must leave Mac input unchanged and never request a system filter");
    [defaults setBool:YES forKey:OrbisFullscreenInputCaptureKey]; window.captureFullscreen = NO;
    Require(![capture consumeEvent:down type:kCGEventKeyDown] && !capture.tapAttempts,
        @"An enabled setting must still preserve windowed input");
    window.captureFullscreen = YES;
    capture.deniesKeyboard = YES;
    Require(![capture consumeEvent:down type:kCGEventKeyDown] && !capture.active && !capture.tapAttempts && !events.count,
        @"Without Input Monitoring, a modifier-only OS filter must never consume input or report keyboard capture as active");
    [capture stop]; capture.deniesKeyboard = NO; capture.tapAttempts = 0; [events removeAllObjects];
    CGEventRef commandModifier = CaptureKey(kCGEventFlagsChanged, 55, kCGEventFlagMaskCommand);
    Require([capture consumeEvent:commandModifier type:kCGEventFlagsChanged] && !events.count,
        @"Captured Command must wait for a chord before choosing Control editing or Super");
    CFRelease(commandModifier);
    Require([capture consumeEvent:down type:kCGEventKeyDown] && [capture consumeEvent:up type:kCGEventKeyUp] &&
        [capture consumeEvent:released type:kCGEventFlagsChanged] && capture.active,
        @"Fullscreen Command+Tab must be consumed before the Mac app switcher");
    Require(events.count == 4 && [events[0][@"code"] unsignedIntValue] == 0x5B &&
        [events[1][@"code"] unsignedIntValue] == 0x0F &&
        ([events[2][@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE) &&
        ([events[3][@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
        @"Captured Command+Tab must reach RDP as a complete physical Super+Tab sequence");
    for (NSNumber *localLayout in @[ @NO, @YES ])
    for (NSNumber *shift in @[ @NO, @YES ])
    for (NSNumber *key in @[ @8, @9 ])
    {
        [defaults setBool:localLayout.boolValue forKey:layoutKey];
        [events removeAllObjects];
        CGEventFlags editFlags = kCGEventFlagMaskCommand | (shift.boolValue ? kCGEventFlagMaskShift : 0);
        CGEventRef command = CaptureKey(kCGEventFlagsChanged, 55, editFlags);
        CGEventRef editDown = CaptureKey(kCGEventKeyDown, key.unsignedShortValue, editFlags);
        CGEventRef editUp = CaptureKey(kCGEventKeyUp, key.unsignedShortValue, 0);
        [capture consumeEvent:command type:kCGEventFlagsChanged];
        [capture consumeEvent:editDown type:kCGEventKeyDown];
        [capture consumeEvent:released type:kCGEventFlagsChanged];
        [capture consumeEvent:editUp type:kCGEventKeyUp];
        NSUInteger controlIndex = shift.boolValue ? 3 : 0;
        Require(events.count == (shift.boolValue ? 8 : 4) && [events[controlIndex][@"code"] unsignedIntValue] == 0x1D &&
            [events[controlIndex + 1][@"code"] unsignedIntValue] == (key.integerValue == 8 ? 0x2E : 0x2F) &&
            ([events[controlIndex + 2][@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE) &&
            ([events.lastObject[@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
            @"Fullscreen Command+C/V and Shift variants must preserve remote editing in both layouts, including late releases");
        for (NSDictionary *event in events)
            Require([event[@"code"] unsignedIntValue] != 0x5B,
                @"An editing shortcut must never trigger remote Super or Activities");
        CFRelease(command); CFRelease(editDown); CFRelease(editUp);
    }
    [defaults setBool:YES forKey:layoutKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:OrbisInputCaptureSettingsDidChangeNotification object:nil];
    [events removeAllObjects];
    CGEventRef optionDown = CaptureKey(kCGEventKeyDown, 19, kCGEventFlagMaskAlternate);
    CGEventRef optionUp = CaptureKey(kCGEventKeyUp, 19, kCGEventFlagMaskAlternate);
    CGEventRef optionFlags = CaptureKey(kCGEventFlagsChanged, 58, kCGEventFlagMaskAlternate);
    [capture consumeEvent:optionFlags type:kCGEventFlagsChanged];
    Require(!events.count, @"Mac-layout typing must defer Alt until a non-text shortcut needs it");
    Require([capture keyboardLayoutData] != nil, @"The Spanish ISO layout must be available for native translation tests");
    [capture consumeEvent:optionDown type:kCGEventKeyDown];
    [capture consumeEvent:released type:kCGEventFlagsChanged];
    [capture consumeEvent:optionUp type:kCGEventKeyUp];
    Require(events.count == 2 && UnicodeEvents().count == 2 &&
        [events[0][@"code"] unsignedIntValue] == '@' &&
        ([events[1][@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
        @"Mac-layout fullscreen capture must send Spanish Option+2 as @ without Alt or a physical 2");
    [events removeAllObjects];
    CGEventFlags rightFlags = kCGEventFlagMaskAlternate | NX_DEVICERALTKEYMASK;
    CGEventRef rightDown = CaptureKey(kCGEventKeyDown, 19, rightFlags);
    CGEventRef rightUp = CaptureKey(kCGEventKeyUp, 19, rightFlags);
    [capture consumeEvent:rightDown type:kCGEventKeyDown]; [capture consumeEvent:rightUp type:kCGEventKeyUp];
    [capture consumeEvent:released type:kCGEventFlagsChanged];
    Require(events.count == 2 && UnicodeEvents().count == 2 && [events[0][@"code"] unsignedIntValue] == '@',
        @"Mac-layout Spanish typing must also send @ with right Option+2");
    [events removeAllObjects];
    CGEventRef tabDown = CaptureKey(kCGEventKeyDown, 48, kCGEventFlagMaskAlternate);
    CGEventRef tabUp = CaptureKey(kCGEventKeyUp, 48, kCGEventFlagMaskAlternate);
    [capture consumeEvent:tabDown type:kCGEventKeyDown]; [capture consumeEvent:tabUp type:kCGEventKeyUp];
    [capture consumeEvent:released type:kCGEventFlagsChanged];
    Require(events.count == 4 && !UnicodeEvents().count && [events[0][@"code"] unsignedIntValue] == 0x38 &&
        [events[1][@"code"] unsignedIntValue] == 0x0F,
        @"Local typing must preserve physical Alt+Tab while capture stays active");
    [events removeAllObjects];
    for (NSNumber *shift in @[ @NO, @YES ])
    {
        CGEventRef less = CaptureKey(kCGEventKeyDown, 50, shift.boolValue ? kCGEventFlagMaskShift : 0);
        CGEventRef lessUp = CaptureKey(kCGEventKeyUp, 50, 0);
        CGEventSetIntegerValueField(less, kCGKeyboardEventKeyboardType, 41);
        [capture consumeEvent:less type:kCGEventKeyDown]; [capture consumeEvent:lessUp type:kCGEventKeyUp];
        Require(UnicodeEvents().count == 2 && [UnicodeEvents()[0][@"code"] unsignedIntValue] == (shift.boolValue ? '>' : '<'),
            @"The Spanish ISO key next to Shift must type < and >, not ordinal symbols");
        [capture consumeEvent:released type:kCGEventFlagsChanged]; [events removeAllObjects];
        CFRelease(less); CFRelease(lessUp);
    }
    // Caps/Shift and Option effects belong to the local character, not a remote shortcut.
    CGEventRef shifted = CaptureKey(kCGEventKeyDown, 19, kCGEventFlagMaskShift);
    CGEventRef shiftedUp = CaptureKey(kCGEventKeyUp, 19, kCGEventFlagMaskShift);
    [capture consumeEvent:shifted type:kCGEventKeyDown];
    [capture consumeEvent:shiftedUp type:kCGEventKeyUp];
    Require(UnicodeEvents().count == 2 && [UnicodeEvents()[0][@"code"] unsignedIntValue] == '"',
        @"Captured Shift+2 must use Spanish Mac punctuation even if the remote layout differs");
    [capture consumeEvent:released type:kCGEventFlagsChanged];
    [events removeAllObjects];
    // Spanish acute accent is a dead key; it must compose with the next letter locally.
    CGEventRef accent = CaptureKey(kCGEventKeyDown, 39, 0);
    CGEventRef accentUp = CaptureKey(kCGEventKeyUp, 39, 0);
    CGEventRef letter = CaptureKey(kCGEventKeyDown, 14, 0);
    CGEventRef letterUp = CaptureKey(kCGEventKeyUp, 14, 0);
    [capture consumeEvent:accent type:kCGEventKeyDown]; [capture consumeEvent:accentUp type:kCGEventKeyUp];
    Require(!events.count, @"A local dead key must not leak its physical key to the remote desktop");
    [capture consumeEvent:letter type:kCGEventKeyDown]; [capture consumeEvent:letterUp type:kCGEventKeyUp];
    Require(events.count == 2 && UnicodeEvents().count == 2 &&
        [events[0][@"code"] unsignedIntValue] == 0x00E9,
        @"Captured Spanish dead-key composition must send the accented character once");
    CFRelease(shifted); CFRelease(shiftedUp); CFRelease(accent); CFRelease(accentUp); CFRelease(letter); CFRelease(letterUp);
    [defaults removeObjectForKey:layoutKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:OrbisInputCaptureSettingsDidChangeNotification object:nil];
    [events removeAllObjects];
    [capture consumeEvent:optionDown type:kCGEventKeyDown]; [capture consumeEvent:optionUp type:kCGEventKeyUp];
    [capture consumeEvent:released type:kCGEventFlagsChanged];
    Require(events.count == 4 && [events[0][@"code"] unsignedIntValue] == 0x38 &&
        [events[1][@"code"] unsignedIntValue] == 0x03 && !UnicodeEvents().count,
        @"Default capture must retain physical left Alt+2");
    [events removeAllObjects];
    [capture consumeEvent:rightDown type:kCGEventKeyDown]; [capture consumeEvent:rightUp type:kCGEventKeyUp];
    [capture consumeEvent:released type:kCGEventFlagsChanged];
    Require(events.count == 4 && !UnicodeEvents().count &&
        [events[0][@"code"] unsignedIntValue] == 0x38 && ([events[0][@"flags"] unsignedIntValue] & KBD_FLAGS_EXTENDED) &&
        [events[1][@"code"] unsignedIntValue] == 0x03 &&
        ([events[3][@"flags"] unsignedIntValue] & (KBD_FLAGS_EXTENDED | KBD_FLAGS_RELEASE)) == (KBD_FLAGS_EXTENDED | KBD_FLAGS_RELEASE),
        @"Default capture must preserve right Option as AltGr with a matching release");
    [events removeAllObjects];
    CGEventRef rightModifier = CaptureKey(kCGEventFlagsChanged, 61, rightFlags);
    [capture consumeEvent:rightModifier type:kCGEventFlagsChanged];
    // Some event sources preserve the side only on the modifier transition.
    [capture consumeEvent:optionDown type:kCGEventKeyDown];
    [capture consumeEvent:optionUp type:kCGEventKeyUp];
    [capture consumeEvent:released type:kCGEventFlagsChanged];
    Require(events.count == 4 && [events[0][@"code"] unsignedIntValue] == 0x38 &&
        ([events[0][@"flags"] unsignedIntValue] & KBD_FLAGS_EXTENDED) &&
        [events[1][@"code"] unsignedIntValue] == 0x03 &&
        ([events[3][@"flags"] unsignedIntValue] & (KBD_FLAGS_EXTENDED | KBD_FLAGS_RELEASE)) ==
        (KBD_FLAGS_EXTENDED | KBD_FLAGS_RELEASE),
        @"Holding right Option must keep AltGr when subsequent keys omit device-side flags");
    CFRelease(rightModifier);
    [events removeAllObjects];
    rightModifier = CaptureKey(kCGEventFlagsChanged, 61, kCGEventFlagMaskAlternate);
    CGEventRef leftModifier = CaptureKey(kCGEventFlagsChanged, 58, kCGEventFlagMaskAlternate);
    [capture consumeEvent:rightModifier type:kCGEventFlagsChanged];
    [capture consumeEvent:optionDown type:kCGEventKeyDown];
    [capture consumeEvent:optionUp type:kCGEventKeyUp];
    [capture consumeEvent:leftModifier type:kCGEventFlagsChanged];
    [capture consumeEvent:rightModifier type:kCGEventFlagsChanged];
    [capture consumeEvent:optionDown type:kCGEventKeyDown];
    [capture consumeEvent:optionUp type:kCGEventKeyUp];
    [capture consumeEvent:released type:kCGEventFlagsChanged];
    Require(events.count == 8 && ([events[0][@"flags"] unsignedIntValue] & KBD_FLAGS_EXTENDED) &&
        [events[3][@"code"] unsignedIntValue] == 0x38 &&
        ([events[3][@"flags"] unsignedIntValue] & (KBD_FLAGS_EXTENDED | KBD_FLAGS_RELEASE)) ==
        (KBD_FLAGS_EXTENDED | KBD_FLAGS_RELEASE) &&
        [events[4][@"code"] unsignedIntValue] == 0x38 &&
        !([events[4][@"flags"] unsignedIntValue] & KBD_FLAGS_EXTENDED) &&
        [events[7][@"code"] unsignedIntValue] == 0x38 &&
        !([events[7][@"flags"] unsignedIntValue] & KBD_FLAGS_EXTENDED),
        @"Modifier key codes must distinguish AltGr and Alt, including independently held Options without device flags");
    CFRelease(rightModifier); CFRelease(leftModifier);
    [events removeAllObjects];
    CGEventRef iso = CaptureKey(kCGEventKeyDown, 50, 0);
    CGEventRef isoUp = CaptureKey(kCGEventKeyUp, 50, 0);
    CGEventSetIntegerValueField(iso, kCGKeyboardEventKeyboardType, 41);
    [capture consumeEvent:iso type:kCGEventKeyDown]; [capture consumeEvent:isoUp type:kCGEventKeyUp];
    Require(events.count == 2 && [events[0][@"code"] unsignedIntValue] == 0x56 &&
        [events[1][@"code"] unsignedIntValue] == 0x56,
        @"Physical ISO typing must retain the <> position even on a third-party keyboard");
    [events removeAllObjects];
    [capture consumeEvent:rightDown type:kCGEventKeyDown];
    delegate.eligible = NO; [capture refresh];
    Require(events.count == 4 &&
        ([events.lastObject[@"flags"] unsignedIntValue] & (KBD_FLAGS_EXTENDED | KBD_FLAGS_RELEASE)) ==
        (KBD_FLAGS_EXTENDED | KBD_FLAGS_RELEASE),
        @"Losing fullscreen focus must release a held AltGr as well as its physical key");
    delegate.eligible = YES; [capture refresh];
    CFRelease(iso); CFRelease(isoUp); CFRelease(rightDown); CFRelease(rightUp); CFRelease(tabDown); CFRelease(tabUp); CFRelease(optionFlags);
    [events removeAllObjects];
    [capture consumeEvent:down type:kCGEventKeyDown]; delegate.eligible = NO; [capture refresh];
    Require(!capture.active && events.count == 4 &&
        ([events[2][@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE) &&
        ([events[3][@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
        @"Changing apps must release a held key and Super before restoring local input");
    Require(![capture consumeEvent:up type:kCGEventKeyUp], @"Inactive capture must pass subsequent input to macOS");
    delegate.eligible = YES; [capture refresh]; [events removeAllObjects];
    CGEventFlags escapeFlags = kCGEventFlagMaskCommand | kCGEventFlagMaskControl | kCGEventFlagMaskAlternate;
    CGEventRef escapeDown = CaptureKey(kCGEventKeyDown, 53, escapeFlags);
    CGEventRef escapeUp = CaptureKey(kCGEventKeyUp, 53, escapeFlags);
    [capture consumeEvent:down type:kCGEventKeyDown];
    Require([capture consumeEvent:escapeDown type:kCGEventKeyDown] && !capture.active && events.count == 4,
        @"The release chord must finish remote input without sending Escape or reactivating capture");
    Require([capture consumeEvent:escapeUp type:kCGEventKeyUp] &&
        [capture consumeEvent:released type:kCGEventFlagsChanged] && !capture.suppressesLocalModifiers,
        @"Escape and modifier releases must drain locally without a stray remote Super tap");
    Require(![capture consumeEvent:down type:kCGEventKeyDown], @"Capture stays suspended in the same fullscreen focus episode");
    delegate.eligible = NO; [capture refresh]; delegate.eligible = YES; [capture refresh];
    Require(capture.active, @"Returning from another app must rearm opted-in fullscreen capture");
    [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowWillExitFullScreenNotification object:window];
    [capture refresh];
    Require(!capture.active, @"Capture must stop throughout the exit animation even while the fullscreen style bit remains set");
    window.captureFullscreen = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowDidExitFullScreenNotification object:window];
    [capture refresh]; window.captureFullscreen = YES; [capture refresh];
    Require(capture.active, @"A later fullscreen entry must rearm capture after the completed transition");
    [[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidBeginTrackingNotification object:nil];
    Require(![capture consumeEvent:down type:kCGEventKeyDown], @"Mac menus must receive local shortcuts during menu tracking");
    [[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidBeginTrackingNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidEndTrackingNotification object:nil];
    Require(![capture consumeEvent:down type:kCGEventKeyDown], @"Closing a submenu must not recapture input while the main menu is still tracking");
    [[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidEndTrackingNotification object:nil];
    Require(capture.active, @"Closing a native menu must resume the opted-in fullscreen session");
    [events removeAllObjects]; displayPointerEvents = 0;
    CGEventRef click = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, CGPointMake(200, 200), kCGMouseButtonLeft);
    CGEventSetFlags(click, 0);
    Require([capture consumeEvent:click type:kCGEventLeftMouseDown] && displayPointerEvents == 1 &&
        (displayPointerFlags & PTR_FLAGS_DOWN), @"Captured macro clicks must reach the normal remote pointer boundary exactly once");
    window.captureFullscreen = NO; [capture refresh];
    Require(displayPointerEvents == 2 && !(displayPointerFlags & PTR_FLAGS_DOWN) && !capture.active,
        @"Leaving fullscreen while a mouse button is held must release it remotely");
    window.captureFullscreen = YES; [capture refresh];
    CGEventRef back = CGEventCreateMouseEvent(NULL, kCGEventOtherMouseDown, CGPointMake(200, 200), (CGMouseButton)3);
    displayPointerEvents = 0;
    [capture consumeEvent:back type:kCGEventOtherMouseDown];
    Require(displayPointerEvents == 1 && displayPointerFlags == (PTR_XFLAGS_DOWN | PTR_XFLAGS_BUTTON1),
        @"Captured side buttons must use the extended RDP button protocol");
    CGEventSetType(back, kCGEventOtherMouseUp); [capture consumeEvent:back type:kCGEventOtherMouseUp];
    Require(displayPointerEvents == 2 && displayPointerFlags == PTR_XFLAGS_BUTTON1,
        @"A side-button release must use the same extended button without a duplicate local click");
    CFRelease(back);
    [capture consumeEvent:down type:kCGEventKeyDown]; [events removeAllObjects];
    [capture consumeEvent:NULL type:kCGEventTapDisabledByTimeout];
    Require(!capture.active && events.count == 2,
        @"A disabled system tap must release remote state and return local control");
    Require(![capture consumeEvent:down type:kCGEventKeyDown], @"A timed-out tap must stay suspended until focus changes");
    [capture stop]; capture.allowTap = NO; [events removeAllObjects];
    Require(![capture consumeEvent:down type:kCGEventKeyDown] && !events.count,
        @"A missing OS permission must never swallow input or claim capture is active");
    CFRelease(down); CFRelease(up); CFRelease(released); CFRelease(optionDown); CFRelease(optionUp);
    CFRelease(escapeDown); CFRelease(escapeUp); CFRelease(click);
    [capture release]; [delegate release]; [view removeFromSuperview]; [view release]; [window release];
    if (original) [defaults setObject:original forKey:OrbisFullscreenInputCaptureKey];
    else [defaults removeObjectForKey:OrbisFullscreenInputCaptureKey];
    [original release];
    if (originalLayout) [defaults setObject:originalLayout forKey:layoutKey];
    else [defaults removeObjectForKey:layoutKey];
    [originalLayout release];
}

// Exercise both entry points with the same native editing commands.
static void CheckEditingParity(void)
{
    NSArray *cases = @[
        @[@51, @"\177", @(NSEventModifierFlagCommand), @[@0x2A, @0x47, @0x47, @0x2A, @0x0E, @0x0E]],
        @[@123, @"\uF702", @(NSEventModifierFlagCommand), @[@0x47, @0x47]],
        @[@124, @"\uF703", @(NSEventModifierFlagCommand | NSEventModifierFlagShift), @[@0x2A, @0x4F, @0x4F, @0x2A]],
        @[@126, @"\uF700", @(NSEventModifierFlagCommand), @[@0x1D, @0x47, @0x47, @0x1D]],
        @[@123, @"\uF702", @(NSEventModifierFlagOption), @[@0x1D, @0x4B, @0x4B, @0x1D]],
        @[@51, @"\177", @(NSEventModifierFlagOption), @[@0x1D, @0x0E, @0x0E, @0x1D]],
        @[@117, @"\uF728", @(NSEventModifierFlagOption), @[@0x1D, @0x53, @0x53, @0x1D]],
        @[@126, @"\uF700", @(NSEventModifierFlagOption), @[@0x4B, @0x4B, @0x1D, @0x48, @0x48, @0x1D]],
        @[@125, @"\uF701", @(NSEventModifierFlagOption), @[@0x4D, @0x4D, @0x1D, @0x50, @0x50, @0x1D]]
    ];
    for (NSArray *item in cases)
    {
        for (NSUInteger captured = 0; captured < 2; captured++)
        {
            [events removeAllObjects];
            OrbisKeyboardTestView *view = [[OrbisKeyboardTestView alloc] init];
            unsigned short code = [item[0] unsignedShortValue];
            NSString *text = item[1];
            NSEventModifierFlags flags = [item[2] unsignedLongValue];
            NSEvent *down = Key(NSEventTypeKeyDown, code, text, text, flags);
            NSEvent *up = Key(NSEventTypeKeyUp, code, text, text, 0);
            if (captured)
            {
                [view sendCapturedEvent:down.CGEvent windowPoint:NSZeroPoint];
                [view sendCapturedEvent:up.CGEvent windowPoint:NSZeroPoint];
                [view releaseCapturedInput];
            }
            else
            {
                [view keyDown:down]; [view keyUp:up]; [view setCommandKeyDown:NO];
            }
            NSArray *expected = item[3];
            Require(events.count == expected.count, @"Native editing must produce the same complete chord sequence in windowed and captured input");
            for (NSUInteger i = 0; i < MIN(events.count, expected.count); i++)
                Require([events[i][@"code"] unsignedIntValue] == [expected[i] unsignedIntValue],
                    @"Native line, document, word and selection actions must use their remote editing equivalent");
            NSMutableDictionary *balance = [NSMutableDictionary dictionary];
            for (NSDictionary *event in events)
            {
                UINT16 wireFlags = [event[@"flags"] unsignedIntValue];
                UINT8 wireCode = [event[@"code"] unsignedIntValue];
                Require(![event[@"unicode"] boolValue] && wireCode != 0x5B && wireCode != 0x38,
                    @"Mapped editing must not leak native text, Super, or Alt");
                BOOL navigation = wireCode >= 0x47 && wireCode <= 0x53;
                Require(((wireFlags & KBD_FLAGS_EXTENDED) != 0) == navigation,
                    @"Navigation actions must retain their extended RDP scancode");
                NSNumber *identity = @((wireFlags & KBD_FLAGS_EXTENDED) | wireCode);
                NSInteger value = [balance[identity] integerValue] + ((wireFlags & KBD_FLAGS_RELEASE) ? -1 : 1);
                balance[identity] = @(value);
                Require(value >= 0, @"Editing must never release a remote key before pressing it");
            }
            for (NSNumber *value in balance.allValues)
                Require(value.integerValue == 0, @"Mapped editing and cleanup must leave every remote key released");
            // Editing is repeatable even when successive events arrive within the menu coalescing interval.
            [events removeAllObjects];
            if (captured)
            {
                [view sendCapturedEvent:down.CGEvent windowPoint:NSZeroPoint];
                [view sendCapturedEvent:down.CGEvent windowPoint:NSZeroPoint];
                [view releaseCapturedInput];
            }
            else { [view keyDown:down]; [view keyDown:down]; [view setCommandKeyDown:NO]; }
            Require(events.count == expected.count * 2, @"Native editing repeats must not be discarded as duplicate menu commands");
            [view release];
        }
    }
}

static void CheckCapturedWordDeletionMetadata(void)
{
    for (NSNumber *emptyUnicode in @[ @NO, @YES ])
    {
        [events removeAllObjects];
        OrbisKeyboardTestView *view = [[OrbisKeyboardTestView alloc] init];
        CGEventFlags flags = kCGEventFlagMaskAlternate | NX_DEVICELALTKEYMASK;
        CGEventRef modifier = CaptureKey(kCGEventFlagsChanged, 58, flags);
        CGEventRef down = CaptureKey(kCGEventKeyDown, 51, flags);
        CGEventRef up = CaptureKey(kCGEventKeyUp, 51, flags);
        CGEventRef released = CaptureKey(kCGEventFlagsChanged, 58, 0);
        if (emptyUnicode.boolValue) CGEventKeyboardSetUnicodeString(down, 0, NULL);
        [view sendCapturedEvent:modifier windowPoint:NSZeroPoint];
        [view sendCapturedEvent:down windowPoint:NSZeroPoint];
        [view sendCapturedEvent:up windowPoint:NSZeroPoint];
        [view sendCapturedEvent:released windowPoint:NSZeroPoint];
        RequireWordDeletion(0);
        Require(events.count == 4,
            @"Captured native editing must never tap remote Alt and move focus to the menu before deleting text");
        [events removeAllObjects];
        [view sendCapturedEvent:modifier windowPoint:NSZeroPoint];
        Require(!events.count, @"Left Alt must remain pending until its physical chord or standalone release is known");
        [view sendCapturedEvent:released windowPoint:NSZeroPoint];
        Require(events.count == 2 && [events[0][@"code"] unsignedIntValue] == 0x38 &&
            [events[1][@"code"] unsignedIntValue] == 0x38 &&
            ([events[1][@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
            @"A standalone left Option tap must retain normal remote Alt behavior");
        CFRelease(modifier); CFRelease(down); CFRelease(up); CFRelease(released);
        [view release];
    }
}

static void CheckAltGrEditingIsolation(void)
{
    for (NSNumber *localLayout in @[ @NO, @YES ])
    {
        [events removeAllObjects];
        OrbisKeyboardTestView *view = [[OrbisKeyboardTestView alloc] init];
        view.capturesLocalKeyboardLayout = localLayout.boolValue;
        CGEventFlags flags = kCGEventFlagMaskAlternate | NX_DEVICERALTKEYMASK;
        CGEventRef modifier = CaptureKey(kCGEventFlagsChanged, 61, flags);
        CGEventRef down = CaptureKey(kCGEventKeyDown, 51, flags);
        CGEventRef up = CaptureKey(kCGEventKeyUp, 51, flags);
        CGEventRef released = CaptureKey(kCGEventFlagsChanged, 61, 0);
        [view sendCapturedEvent:modifier windowPoint:NSZeroPoint];
        [view sendCapturedEvent:down windowPoint:NSZeroPoint];
        [view sendCapturedEvent:up windowPoint:NSZeroPoint];
        [view sendCapturedEvent:released windowPoint:NSZeroPoint];
        Require(events.count == 4 && [events[0][@"code"] unsignedIntValue] == (localLayout.boolValue ? 0x1D : 0x38) &&
            [events[1][@"code"] unsignedIntValue] == 0x0E &&
            [events[2][@"code"] unsignedIntValue] == 0x0E &&
            ([events.lastObject[@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
            @"Right Option must preserve AltGr in remote-layout mode and use native word deletion only in Mac-layout mode");
        if (!localLayout.boolValue && events.count == 4)
            Require(([events[0][@"flags"] unsignedIntValue] & KBD_FLAGS_EXTENDED) &&
                ([events.lastObject[@"flags"] unsignedIntValue] & KBD_FLAGS_EXTENDED),
                @"An AltGr editing key must retain the right Alt scancode on both modifier transitions");
        CFRelease(modifier); CFRelease(down); CFRelease(up); CFRelease(released);
        [view release];
    }
}

static void CheckSystemCaptureCapabilities(void)
{
    OrbisInputEventTap *tap = [[OrbisInputEventTap alloc] init];
    OrbisEventSinkFixture *sink = [[OrbisEventSinkFixture alloc] init];
    osKeyboardAccess = NO; osTapCreations = 0;
    Require(![tap startWithSink:sink] && !osTapCreations,
        @"Denied keyboard monitoring must not create a partial modifier or mouse filter");
    osKeyboardAccess = YES; osAccessibility = NO;
    Require(![tap startWithSink:sink] && !osTapCreations,
        @"Denied Accessibility must not create a system input filter");
    osAccessibility = YES; osPartialKeyboard = YES;
    Require(![tap startWithSink:sink] && !osTapCreated,
        @"The actual filter mask must contain key presses and releases, even if permission preflight reports access");
    osPartialKeyboard = NO; osTapListUnavailable = YES;
    Require(![tap startWithSink:sink] && !osTapCreated,
        @"An unverified system filter must not be reported as active");
    osTapListUnavailable = NO;
    Require([tap startWithSink:sink] && osTapCreated,
        @"A verified complete system filter must be available to the session input policy");
    [tap stop]; [tap stop];
    Require(!osTapCreated, @"Stopping the filter must be idempotent and restore local input");
    [tap release]; [sink release];
}

int main(void)
{
	@autoreleasepool
	{
		[NSApplication sharedApplication];
		events = [[NSMutableArray alloc] init];
        CheckSystemCaptureCapabilities();
        CheckAltGrEditingIsolation();
        CheckEditingParity();
        CheckFullscreenInputCapture();
        CheckCapturedEditingPointerInterleaving();
        CheckRapidDistinctPastePresses();
        CheckCapturedWordDeletionMetadata();
        CheckCommandEventOrdering();
        CheckCommandReleaseTransitions();
        [events removeAllObjects];
        OrbisKeyboardTestView *isoView = [[OrbisKeyboardTestView alloc] init];
        [isoView keyDown:Key(NSEventTypeKeyDown, 50, @"<", @"<", 0)];
        [isoView keyUp:Key(NSEventTypeKeyUp, 50, @"<", @"<", 0)];
        Require(events.count == 2 && [events[0][@"code"] unsignedIntValue] == 0x56 &&
            [events[1][@"code"] unsignedIntValue] == 0x56,
            @"Windowed ISO typing must map <> correctly even if Apple hardware detection reports ANSI");
        [isoView release];
		CheckDisplayViewports();
		CheckOptionBackspace(NO, NO);
		CheckOptionBackspace(YES, NO);
		CheckOptionBackspace(NO, YES);
		CheckOptionBackspace(YES, YES);

		[events removeAllObjects];
		OrbisKeyboardTestView *transitionView = [[OrbisKeyboardTestView alloc] init];
		[transitionView keyDown:Key(NSEventTypeKeyDown, 51, @"\177", @"\177", NSEventModifierFlagOption)];
		[transitionView flagsChanged:Key(NSEventTypeFlagsChanged, 58, @"", @"", 0)];
		[transitionView keyDown:Key(NSEventTypeKeyDown, 51, @"\177", @"\177", 0)];
		[transitionView keyUp:Key(NSEventTypeKeyUp, 51, @"\177", @"\177", 0)];
		Require(events.count == 6 && [events[4][@"code"] unsignedIntValue] == 0x0E &&
		        [events[5][@"code"] unsignedIntValue] == 0x0E &&
		        ([events[5][@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
		        @"Releasing Option while holding Backspace must still release subsequent plain Backspace");
		[transitionView release];
		[events removeAllObjects];
		OrbisKeyboardTestView *view = [[OrbisKeyboardTestView alloc] init];
		[view flagsChanged:Key(NSEventTypeFlagsChanged, 58, @"", @"", NSEventModifierFlagOption)];
		[view keyDown:Key(NSEventTypeKeyDown, 19, @"@", @"2", NSEventModifierFlagOption)];
		[view keyUp:Key(NSEventTypeKeyUp, 19, @"@", @"2", NSEventModifierFlagOption)];
		[view flagsChanged:Key(NSEventTypeFlagsChanged, 58, @"", @"", 0)];
		Require(events.count == 2 && [events[0][@"unicode"] boolValue] &&
		        [events[0][@"code"] unsignedIntValue] == '@' &&
		        [events[1][@"unicode"] boolValue] && [events[1][@"code"] unsignedIntValue] == '@' &&
		        ([events[1][@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
		        @"Option+2 must send @ down/up without an Alt shortcut or a physical 2");
		[view release];
		for (NSString *text in @[ @"@", @"€", @"#", @"[", @"]", @"{", @"}", @"\\", @"|", @"~", @"€@" ])
		{
			CheckOptionText(text, 0);
			CheckOptionText(text, NSEventModifierFlagShift);
		}

		[events removeAllObjects];
		view = [[OrbisKeyboardTestView alloc] init];
		[view flagsChanged:Key(NSEventTypeFlagsChanged, 58, @"", @"", NSEventModifierFlagOption)];
		[view keyDown:Key(NSEventTypeKeyDown, 19, @"@", @"2", NSEventModifierFlagOption)];
		[view keyDown:Key(NSEventTypeKeyDown, 19, @"@", @"2", NSEventModifierFlagOption)];
		[view keyUp:Key(NSEventTypeKeyUp, 19, @"@", @"2", NSEventModifierFlagOption)];
		[view flagsChanged:Key(NSEventTypeFlagsChanged, 58, @"", @"", 0)];
		Require(events.count == 4 && UnicodeEvents().count == 4,
		        @"Repeated Option text must send each character once without extra key releases");
		[view release];

		[events removeAllObjects];
		view = [[OrbisKeyboardTestView alloc] init];
		[view flagsChanged:Key(NSEventTypeFlagsChanged, 58, @"", @"", NSEventModifierFlagOption)];
		[view keyDown:Key(NSEventTypeKeyDown, 48, @"\t", @"\t", NSEventModifierFlagOption)];
		[view keyUp:Key(NSEventTypeKeyUp, 48, @"\t", @"\t", NSEventModifierFlagOption)];
		[view flagsChanged:Key(NSEventTypeFlagsChanged, 58, @"", @"", 0)];
		Require(events.count == 4 && UnicodeEvents().count == 0 &&
		        [events[0][@"code"] unsignedIntValue] == 0x38 &&
		        [events[1][@"code"] unsignedIntValue] == 0x0F &&
		        ([events[3][@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
		        @"Option+Tab must remain a complete remote Alt+Tab chord");
		[view release];

		[events removeAllObjects];
		view = [[OrbisKeyboardTestView alloc] init];
		[view flagsChanged:Key(NSEventTypeFlagsChanged, 55, @"", @"", NSEventModifierFlagCommand)];
		[view keyDown:Key(NSEventTypeKeyDown, 8, @"c", @"c", NSEventModifierFlagCommand)];
		[view keyUp:Key(NSEventTypeKeyUp, 8, @"c", @"c", NSEventModifierFlagCommand)];
		[view flagsChanged:Key(NSEventTypeFlagsChanged, 55, @"", @"", 0)];
		Require(events.count == 4 && UnicodeEvents().count == 0 &&
		        [events[0][@"code"] unsignedIntValue] == 0x1D &&
		        [events[1][@"code"] unsignedIntValue] == 0x2E &&
		        ([events[3][@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
		        @"Command+C must still send an atomic remote Control+C chord");
		[view release];

		[events removeAllObjects];
		view = [[OrbisKeyboardTestView alloc] init];
		[view flagsChanged:Key(NSEventTypeFlagsChanged, 58, @"", @"", NSEventModifierFlagOption)];
		NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
		    location:NSMakePoint(10, 10) modifierFlags:NSEventModifierFlagOption timestamp:1
		    windowNumber:0 context:nil eventNumber:1 clickCount:1 pressure:1];
		[view mouseDown:click];
		[view mouseUp:click];
		[view flagsChanged:Key(NSEventTypeFlagsChanged, 58, @"", @"", 0)];
		Require(mouseEvents == 2 && events.count == 2 &&
		        [events[0][@"code"] unsignedIntValue] == 0x38 &&
		        ([events[1][@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
		        @"Option+click must retain remote Alt for pointer gestures");
		[view release];

		[events removeAllObjects];
		view = [[OrbisKeyboardTestView alloc] init];
		[view flagsChanged:Key(NSEventTypeFlagsChanged, 58, @"", @"", NSEventModifierFlagOption)];
		[view mouseDown:click];
		[view mouseUp:click];
		[events removeAllObjects];
		[view keyDown:Key(NSEventTypeKeyDown, 51, @"\177", @"\177", NSEventModifierFlagOption)];
		Require(events.count == 5 && [events[0][@"code"] unsignedIntValue] == 0x38 &&
		        ([events[0][@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
		        @"Word deletion after Option+click must release remote Alt before Control");
		if (events.count == 5)
			RequireWordDeletion(1);
		[view keyUp:Key(NSEventTypeKeyUp, 51, @"\177", @"\177", NSEventModifierFlagOption)];
		[view flagsChanged:Key(NSEventTypeFlagsChanged, 58, @"", @"", 0)];
		Require(events.count == 5, @"The pointer-to-deletion transition must leave Alt released");
		[view release];

		for (NSNumber *mapping in @[ @YES, @NO ])
		{
			[events removeAllObjects];
			view = [[OrbisKeyboardTestView alloc] init];
			[view setMapsCommandShortcutsToControl:[mapping boolValue]];
			NSEventModifierFlags flags = [mapping boolValue] ? 0 : NSEventModifierFlagOption;
			[view flagsChanged:Key(NSEventTypeFlagsChanged, 58, @"", @"", flags)];
			[view keyDown:Key(NSEventTypeKeyDown, 51, @"\177", @"\177", flags)];
			[view keyUp:Key(NSEventTypeKeyUp, 51, @"\177", @"\177", flags)];
			[view flagsChanged:Key(NSEventTypeFlagsChanged, 58, @"", @"", 0)];
			Require(events.count == ([mapping boolValue] ? 2 : 4) && UnicodeEvents().count == 0,
			        @"Plain Backspace and disabled shortcut mapping must preserve physical key events");
			for (NSDictionary *event in events)
				Require([event[@"code"] unsignedIntValue] == 0x0E ||
				        (![mapping boolValue] && [event[@"code"] unsignedIntValue] == 0x38),
				        @"Control must only be injected for mapped Option+Backspace");
			[view release];
		}
		[events release];
	}
	if (failures)
		return 1;
	puts("PASS: native macOS keyboard input");
	return 0;
}
