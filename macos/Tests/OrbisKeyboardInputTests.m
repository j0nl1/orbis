/* SPDX-License-Identifier: MIT */

#import <AppKit/AppKit.h>
#import "MRDPView.h"

static NSMutableArray *events;
static NSUInteger failures;
static NSUInteger mouseEvents;
static NSUInteger displayPointerEvents;
static NSPoint displayPointerPoint;
BOOL OrbisRecordDisplayPointer(rdpClientContext *context, BOOL relative, UINT16 flags, INT32 x, INT32 y)
{
	(void)context; (void)relative; (void)flags;
	displayPointerEvents++; displayPointerPoint = NSMakePoint(x, y);
	return TRUE;
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
    [view keyDown:Key(NSEventTypeKeyDown, 123, @"", @"", NSEventModifierFlagCommand)];
    // AppKit may omit keyUp for keys used while Command is held.
    [view flagsChanged:Key(NSEventTypeFlagsChanged, 55, @"", @"", 0)];
    NSInteger balance = 0;
    for (NSDictionary *event in events)
    {
        if ([event[@"code"] unsignedIntValue] == 0x4B)
            balance += ([event[@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE) ? -1 : 1;
    }
    Require(balance == 0, @"Releasing Command must not leave an unmapped arrow key held remotely");
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
        Require(events.count == (keyCode.unsignedShortValue == 8 ? 4 : 2),
            @"An atomic Command shortcut must ignore keyUp arriving after Command release");
        [view release];
    }

    for (NSNumber *keyCode in @[ @123, @124, @125, @126, @14 ])
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
    [view keyDown:Key(NSEventTypeKeyDown, 123, @"", @"", NSEventModifierFlagCommand)];
    [view keyUp:Key(NSEventTypeKeyUp, 123, @"", @"", NSEventModifierFlagCommand)];
    [view setCommandKeyDown:NO];
    Require(events.count == 2, @"A Command key released normally must not be released again");
    [view release];

    [events removeAllObjects];
    view = [[OrbisKeyboardTestView alloc] init];
    [view flagsChanged:Key(NSEventTypeFlagsChanged, 55, @"", @"", NSEventModifierFlagCommand)];
    [view keyDown:Key(NSEventTypeKeyDown, 123, @"", @"", NSEventModifierFlagCommand)];
    NSEvent *repeat = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:NSEventModifierFlagCommand timestamp:2 windowNumber:0 context:nil
        characters:@"" charactersIgnoringModifiers:@"" isARepeat:YES keyCode:123];
    [view keyDown:repeat];
    [view setCommandKeyDown:NO];
    Require(events.count == 3 && ([events.lastObject[@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
        @"Repeated Command arrows must end with one remote release");
    [view release];

    [events removeAllObjects];
    view = [[OrbisKeyboardTestView alloc] init];
    [view flagsChanged:Key(NSEventTypeFlagsChanged, 55, @"", @"", NSEventModifierFlagCommand)];
    [view keyDown:Key(NSEventTypeKeyDown, 123, @"", @"", NSEventModifierFlagCommand)];
    [view cancelPendingCommandTap];
    [view setCommandKeyDown:NO];
    Require(events.count == 2 && [events.lastObject[@"code"] unsignedIntValue] == 0x4B &&
        ([events.lastObject[@"flags"] unsignedIntValue] & KBD_FLAGS_RELEASE),
        @"Focus cancellation must release Command keys without creating a Super tap");
    [view release];

    [events removeAllObjects];
    view = [[OrbisKeyboardTestView alloc] init];
    NSEventModifierFlags chord = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [view flagsChanged:Key(NSEventTypeFlagsChanged, 55, @"", @"", chord)];
    [view keyDown:Key(NSEventTypeKeyDown, 123, @"", @"", chord)];
    [view flagsChanged:Key(NSEventTypeFlagsChanged, 55, @"", @"", NSEventModifierFlagShift)];
    Require(events.count == 3 && [events[0][@"code"] unsignedIntValue] == 0x2A &&
        [events.lastObject[@"code"] unsignedIntValue] == 0x4B &&
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

int main(void)
{
	@autoreleasepool
	{
		[NSApplication sharedApplication];
		events = [[NSMutableArray alloc] init];
        CheckCommandEventOrdering();
        CheckCommandReleaseTransitions();
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
