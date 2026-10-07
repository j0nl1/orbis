/* SPDX-License-Identifier: MIT */
#import "OrbisKeyboardCompatibility.h"
#import <Carbon/Carbon.h>
#include <winpr/input.h>
#include <freerdp/scancode.h>

static OrbisKeyboardEditingPlan OrbisPlanForSelector(SEL command)
{
    OrbisKeyboardEditingPlan plan = {0};
    NSString *selector = NSStringFromSelector(command);
    if (!selector) return plan;
    BOOL selecting = [selector hasSuffix:@"AndModifySelection:"];
    NSString *action = selecting ? [[selector substringToIndex:selector.length - @"AndModifySelection:".length]
        stringByAppendingString:@":"] : selector;
    struct Binding { NSString *action; uint32_t scancode; NSEventModifierFlags modifiers; BOOL deleting; };
    const struct Binding bindings[] = {
        { @"moveToLeftEndOfLine:", RDP_SCANCODE_HOME, 0, NO },
        { @"moveToBeginningOfLine:", RDP_SCANCODE_HOME, 0, NO },
        { @"moveToRightEndOfLine:", RDP_SCANCODE_END, 0, NO },
        { @"moveToEndOfLine:", RDP_SCANCODE_END, 0, NO },
        { @"moveToBeginningOfDocument:", RDP_SCANCODE_HOME, NSEventModifierFlagControl, NO },
        { @"moveToEndOfDocument:", RDP_SCANCODE_END, NSEventModifierFlagControl, NO },
        { @"moveWordLeft:", RDP_SCANCODE_LEFT, NSEventModifierFlagControl, NO },
        { @"moveWordBackward:", RDP_SCANCODE_LEFT, NSEventModifierFlagControl, NO },
        { @"moveWordRight:", RDP_SCANCODE_RIGHT, NSEventModifierFlagControl, NO },
        { @"moveWordForward:", RDP_SCANCODE_RIGHT, NSEventModifierFlagControl, NO },
        { @"moveBackward:", RDP_SCANCODE_LEFT, 0, NO },
        { @"moveForward:", RDP_SCANCODE_RIGHT, 0, NO },
        { @"moveToBeginningOfParagraph:", RDP_SCANCODE_UP, NSEventModifierFlagControl, NO },
        { @"moveToEndOfParagraph:", RDP_SCANCODE_DOWN, NSEventModifierFlagControl, NO },
        { @"moveParagraphBackward:", RDP_SCANCODE_UP, NSEventModifierFlagControl, NO },
        { @"moveParagraphForward:", RDP_SCANCODE_DOWN, NSEventModifierFlagControl, NO },
        { @"deleteWordBackward:", RDP_SCANCODE_BACKSPACE, NSEventModifierFlagControl, NO },
        { @"deleteWordForward:", RDP_SCANCODE_DELETE, NSEventModifierFlagControl, NO },
        { @"deleteToBeginningOfLine:", RDP_SCANCODE_HOME, NSEventModifierFlagShift, YES },
        { @"deleteToEndOfLine:", RDP_SCANCODE_END, NSEventModifierFlagShift, YES },
        { @"deleteToBeginningOfParagraph:", RDP_SCANCODE_UP, NSEventModifierFlagControl | NSEventModifierFlagShift, YES },
        { @"deleteToEndOfParagraph:", RDP_SCANCODE_DOWN, NSEventModifierFlagControl | NSEventModifierFlagShift, YES }
    };
    for (NSUInteger i = 0; i < sizeof(bindings) / sizeof(bindings[0]); i++)
    {
        const struct Binding *binding = &bindings[i];
        if (![action isEqualToString:binding->action]) continue;
        plan.chords[0] = (OrbisKeyboardChord){ binding->scancode,
            binding->modifiers | (selecting ? NSEventModifierFlagShift : 0) };
        plan.count = 1;
        if (binding->deleting)
        {
            plan.chords[1] = (OrbisKeyboardChord){ RDP_SCANCODE_BACKSPACE, 0 };
            plan.count = 2;
        }
        plan.repeatable = YES;
        break;
    }
    return plan;
}

// AppKit may resolve one binding into several editing actions. Preserve the
// entire sequence, and fall back without partial edits if any action is unsupported.
@interface OrbisKeyboardInterpreter : NSView
{
    OrbisKeyboardEditingPlan _plan;
    BOOL _unsupported;
}
@property(nonatomic, readonly) OrbisKeyboardEditingPlan plan;
@end
@implementation OrbisKeyboardInterpreter
- (OrbisKeyboardEditingPlan)plan { return _unsupported ? (OrbisKeyboardEditingPlan){0} : _plan; }
- (void)doCommandBySelector:(SEL)selector
{
    OrbisKeyboardEditingPlan action = OrbisPlanForSelector(selector);
    if (!action.count || _plan.count + action.count > sizeof(_plan.chords) / sizeof(_plan.chords[0]))
    { _unsupported = YES; return; }
    for (NSUInteger i = 0; i < action.count; i++) _plan.chords[_plan.count++] = action.chords[i];
    _plan.repeatable = YES;
}
- (void)insertText:(id)text { (void)text; _unsupported = YES; }
- (void)insertText:(id)text replacementRange:(NSRange)range { (void)range; [self insertText:text]; }
@end

OrbisKeyboardEditingPlan OrbisKeyboardPlanForEvent(NSEvent *event, BOOL nativeOptionEditing)
{
    OrbisKeyboardEditingPlan plan = {0};
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    BOOL command = (flags & NSEventModifierFlagCommand) != 0;
    BOOL option = (flags & NSEventModifierFlagOption) != 0;
    if (!command && (!option || !nativeOptionEditing || (flags & NSEventModifierFlagControl))) return plan;

    NSString *base = event.charactersIgnoringModifiers.lowercaseString;
    if (command && base.length == 1 && [@"acfvxzswtnlrp" rangeOfString:base].location != NSNotFound)
    {
        DWORD vk = GetVirtualKeyCodeFromKeycode(event.keyCode, WINPR_KEYCODE_TYPE_APPLE);
        plan.chords[0] = (OrbisKeyboardChord){ GetVirtualScanCodeFromVirtualKeyCode(vk, 4),
            (flags & ~NSEventModifierFlagCommand) | NSEventModifierFlagControl };
        plan.count = 1;
        return plan;
    }
    if (option && !nativeOptionEditing) return plan;
    OrbisKeyboardInterpreter *interpreter = [[OrbisKeyboardInterpreter alloc] init];
    [interpreter interpretKeyEvents:@[event]];
    plan = interpreter.plan;
    [interpreter release];
    return plan;
}

@implementation OrbisKeyboardTextTranslator
- (NSData *)keyboardLayoutData
{
    TISInputSourceRef source = TISCopyCurrentKeyboardLayoutInputSource();
    if (!source) return nil;
    NSData *data = [[(NSData *)TISGetInputSourceProperty(source,
        kTISPropertyUnicodeKeyLayoutData) retain] autorelease];
    CFRelease(source);
    return data;
}
- (void)reset
{
    _deadKeyState = 0;
    [_keyboardLayout release]; _keyboardLayout = nil;
}
- (NSString *)textForEvent:(CGEventRef)event
{
    CGEventFlags flags = CGEventGetFlags(event);
    if (flags & (kCGEventFlagMaskCommand | kCGEventFlagMaskControl))
    { [self reset]; return nil; }
    unsigned short code = (unsigned short)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    NSData *layout = [self keyboardLayoutData];
    if (!layout) return nil;
    if (![_keyboardLayout isEqualToData:layout])
    {
        [_keyboardLayout release]; _keyboardLayout = [layout retain]; _deadKeyState = 0;
    }
    UInt32 modifiers = ((flags & kCGEventFlagMaskShift) ? shiftKey : 0) |
        ((flags & kCGEventFlagMaskAlternate) ? optionKey : 0) |
        ((flags & kCGEventFlagMaskAlphaShift) ? alphaLock : 0);
    UniChar characters[16]; UniCharCount length = 0;
    UInt32 deadState = _deadKeyState;
    UInt32 keyboardType = (UInt32)CGEventGetIntegerValueField(event, kCGKeyboardEventKeyboardType);
    OSStatus status = UCKeyTranslate((const UCKeyboardLayout *)layout.bytes, code,
        kUCKeyActionDown, modifiers >> 8, keyboardType ?: LMGetKbdType(), 0,
        &deadState, sizeof(characters) / sizeof(characters[0]), &length, characters);
    if (status != noErr) { _deadKeyState = 0; return nil; }
    NSString *text = [NSString stringWithCharacters:characters length:length];
    for (NSUInteger index = 0; index < length; index++)
        if ([[NSCharacterSet controlCharacterSet] characterIsMember:characters[index]] ||
            (characters[index] >= 0xF700 && characters[index] <= 0xF8FF))
        {
            _deadKeyState = 0;
            return nil;
        }
    if (!length && !deadState) return nil;
    _deadKeyState = deadState;
    return text;
}
- (void)dealloc { [self reset]; [super dealloc]; }
@end
