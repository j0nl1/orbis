/* SPDX-License-Identifier: MIT */
#import "OrbisWorkspaceShortcuts.h"

@implementation OrbisWorkspaceShortcuts
{
    NSUserDefaults *_defaults;
    NSString *_key;
    NSMutableDictionary *_bindings;
}
+ (NSArray *)actions { return @[ @5, @6, @1, @2, @8, @9 ]; }
+ (NSString *)titleForAction:(OrbisWorkspaceAction)action
{
    switch (action) {
        case OrbisWorkspaceActivities: return @"Open Activities";
        case OrbisWorkspaceCloseActivities: return @"Close Activities";
        case OrbisWorkspacePrevious: return @"Previous workspace";
        case OrbisWorkspaceNext: return @"Next workspace";
        case OrbisWorkspaceScreenshotScreen: return @"Capture remote screen";
        case OrbisWorkspaceScreenshotWindow: return @"Capture remote window";
        default: return @"Unknown action";
    }
}
+ (NSString *)warning
{
    return @"Custom shortcuts can override typing, editing, or system functions. Choose combinations carefully. Some shortcuts are reserved by iPadOS or macOS and cannot reach Orbis. Copy, paste, and text deletion keep their usual behavior unless you explicitly assign the same combination here. Mac screenshot combinations require full screen input capture on macOS. Screenshots are saved on the remote computer.";
}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults platform:(NSString *)platform
{
    if (!(self = [super init])) return nil;
    _defaults = [defaults retain];
    _key = [[@"OrbisWorkspaceShortcuts.v1." stringByAppendingString:platform] copy];
    _bindings = [[NSMutableDictionary alloc] init];
    id saved = [_defaults objectForKey:_key];
    if ([saved isKindOfClass:[NSDictionary class]])
        for (NSNumber *action in self.class.actions) {
            id binding = saved[action.stringValue];
            if (![binding isKindOfClass:[NSDictionary class]]) continue;
            NSString *input = binding[@"button"] ? @"button" : @"key";
            if (binding[@"button"] && binding[@"key"]) continue;
            if (![binding[input] isKindOfClass:[NSNumber class]] ||
                ![binding[@"modifiers"] isKindOfClass:[NSNumber class]] ||
                ![binding[@"label"] isKindOfClass:[NSString class]]) continue;
            if ([binding[input] doubleValue] != [binding[input] unsignedIntegerValue] ||
                [binding[@"modifiers"] doubleValue] != [binding[@"modifiers"] unsignedIntegerValue]) continue;
            [self assignInput:input code:[binding[input] unsignedIntegerValue]
                modifiers:[binding[@"modifiers"] unsignedIntegerValue]
                label:binding[@"label"] toAction:action.integerValue error:nil];
        }
    return self;
}
- (NSDictionary *)bindings { return [[_bindings copy] autorelease]; }
- (OrbisWorkspaceAction)actionForKeyCode:(NSUInteger)code modifiers:(OrbisShortcutModifiers)modifiers
{
    return [self actionForInput:@"key" code:code modifiers:modifiers];
}
- (OrbisWorkspaceAction)actionForMouseButton:(NSUInteger)button modifiers:(OrbisShortcutModifiers)modifiers
{
    return [self actionForInput:@"button" code:button modifiers:modifiers];
}
- (OrbisWorkspaceAction)actionForInput:(NSString *)input code:(NSUInteger)code modifiers:(OrbisShortcutModifiers)modifiers
{
    for (NSNumber *action in self.class.actions) {
        NSDictionary *binding = _bindings[action.stringValue];
        if (binding[input] && [binding[input] unsignedIntegerValue] == code &&
            [binding[@"modifiers"] unsignedIntegerValue] == modifiers) return action.integerValue;
    }
    return OrbisWorkspaceNone;
}
- (BOOL)assignKeyCode:(NSUInteger)code modifiers:(OrbisShortcutModifiers)modifiers
               label:(NSString *)label toAction:(OrbisWorkspaceAction)action error:(NSError **)error
{
    return [self assignInput:@"key" code:code modifiers:modifiers label:label toAction:action error:error];
}
- (BOOL)assignMouseButton:(NSUInteger)button modifiers:(OrbisShortcutModifiers)modifiers
                   label:(NSString *)label toAction:(OrbisWorkspaceAction)action error:(NSError **)error
{
    return [self assignInput:@"button" code:button modifiers:modifiers label:label toAction:action error:error];
}
- (BOOL)assignInput:(NSString *)input code:(NSUInteger)code modifiers:(OrbisShortcutModifiers)modifiers
             label:(NSString *)label toAction:(OrbisWorkspaceAction)action error:(NSError **)error
{
    NSUInteger maximum = [input isEqualToString:@"button"] ? 31 : 255;
    if (![self.class.actions containsObject:@(action)] || code > maximum || modifiers > 15 || !label.length || label.length > 80)
        return NO;
    OrbisWorkspaceAction other = [self actionForInput:input code:code modifiers:modifiers];
    if (other != OrbisWorkspaceNone && other != action) {
        if (error) *error = [NSError errorWithDomain:@"OrbisWorkspaceShortcuts" code:1 userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:@"This combination is already assigned to %@.", [self.class titleForAction:other]] }];
        return NO;
    }
    _bindings[[@(action) stringValue]] = @{ input: @(code), @"modifiers": @(modifiers), @"label": label };
    return YES;
}
- (void)clearAction:(OrbisWorkspaceAction)action { [_bindings removeObjectForKey:[@(action) stringValue]]; }
- (NSString *)labelForAction:(OrbisWorkspaceAction)action { return _bindings[[@(action) stringValue]][@"label"] ?: @"Not assigned"; }
- (void)save { [_defaults setObject:_bindings forKey:_key]; }
- (void)dealloc { [_defaults release]; [_key release]; [_bindings release]; [super dealloc]; }
@end
