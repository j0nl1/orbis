/* SPDX-License-Identifier: MIT */

#import <AppKit/AppKit.h>
#import "MRDPView.h"

static NSMutableArray *events;
static NSUInteger failures;
static NSUInteger mouseEvents;

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

int main(void)
{
	@autoreleasepool
	{
		[NSApplication sharedApplication];
		events = [[NSMutableArray alloc] init];
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
		[events release];
	}
	if (failures)
		return 1;
	puts("PASS: native macOS keyboard input");
	return 0;
}
