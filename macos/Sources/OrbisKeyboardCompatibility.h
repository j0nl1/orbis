/* SPDX-License-Identifier: MIT */
#import <AppKit/AppKit.h>
#include <stdint.h>

typedef struct {
    uint32_t scancode;
    NSEventModifierFlags modifiers;
} OrbisKeyboardChord;

typedef struct {
    OrbisKeyboardChord chords[4];
    NSUInteger count;
    BOOL repeatable;
} OrbisKeyboardEditingPlan;

// An empty plan leaves the event to the physical keyboard or text-layout adapter.
// Right Option can remain remote AltGr by disabling native Option editing.
OrbisKeyboardEditingPlan OrbisKeyboardPlanForEvent(NSEvent *event, BOOL nativeOptionEditing);

// Cocoa already translates windowed typing. Captured input uses this adapter to
// preserve the same active Mac layout and compose dead keys before sending text.
__attribute__((visibility("default")))
@interface OrbisKeyboardTextTranslator : NSObject
{
    NSData *_keyboardLayout;
    UInt32 _deadKeyState;
}
// nil means physical input; an empty string consumes a pending dead key.
- (NSString *)textForEvent:(CGEventRef)event;
- (void)reset;
// The native input-source seam also permits deterministic layout tests.
- (NSData *)keyboardLayoutData;
@end
