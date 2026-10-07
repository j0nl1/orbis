/* SPDX-License-Identifier: MIT */
#import "OrbisInputEventTap.h"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <unistd.h>

static CGEventRef OrbisEventTapCallback(CGEventTapProxy proxy, CGEventType type,
                                       CGEventRef event, void *context)
{
    (void)proxy;
    @autoreleasepool
    {
        return [(id<OrbisInputEventSink>)context consumeEvent:event type:type] ? NULL : event;
    }
}

// Read the OS's effective masks rather than assuming a created filter includes
// every requested event. Filter identities isolate ours from other app filters.
static NSData *OrbisEventTapInformationSnapshot(void)
{
    uint32_t count = 0;
    if (CGGetEventTapList(0, NULL, &count) != kCGErrorSuccess) return nil;
    uint32_t capacity = MAX(count, 1);
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)capacity * sizeof(CGEventTapInformation)];
    if (CGGetEventTapList(capacity, data.mutableBytes, &count) != kCGErrorSuccess || count > capacity)
        return nil;
    [data setLength:(NSUInteger)count * sizeof(CGEventTapInformation)];
    return data;
}

static NSSet *OrbisEventTapIdentities(NSData *snapshot)
{
    NSMutableSet *identities = [NSMutableSet set];
    const CGEventTapInformation *taps = snapshot.bytes;
    for (NSUInteger i = 0; i < snapshot.length / sizeof(*taps); i++)
        [identities addObject:@(taps[i].eventTapID)];
    return identities;
}

static BOOL OrbisNewEventTapHasMask(NSSet *previous, CGEventMask requested)
{
    NSData *snapshot = OrbisEventTapInformationSnapshot();
    if (!snapshot) return NO;
    const CGEventTapInformation *taps = snapshot.bytes;
    for (NSUInteger i = 0; i < snapshot.length / sizeof(*taps); i++)
    {
        const CGEventTapInformation *tap = &taps[i];
        if (tap->tappingProcess == getpid() && tap->tapPoint == kCGSessionEventTap &&
            tap->options == kCGEventTapOptionDefault && tap->enabled &&
            ![previous containsObject:@(tap->eventTapID)])
            return (tap->eventsOfInterest & requested) == requested;
    }
    return NO;
}

@implementation OrbisInputEventTap
+ (BOOL)keyboardAccessAllowed { return CGPreflightListenEventAccess(); }
+ (BOOL)permissionsGranted { return AXIsProcessTrusted() && [self keyboardAccessAllowed]; }
+ (void)requestPermissions
{
    BOOL accessibility = AXIsProcessTrustedWithOptions((CFDictionaryRef)@{ (id)kAXTrustedCheckOptionPrompt: @YES });
    if (![self keyboardAccessAllowed])
    {
        CGRequestListenEventAccess();
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:
            @"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"]];
    }
    else if (!accessibility)
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:
            @"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}
- (BOOL)startWithSink:(id<OrbisInputEventSink>)sink
{
    [self stop];
    if (!sink || ![self.class permissionsGranted]) return NO;
    NSData *previous = OrbisEventTapInformationSnapshot();
    if (!previous) return NO;
    NSSet *identities = OrbisEventTapIdentities(previous);
    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp) |
        CGEventMaskBit(kCGEventFlagsChanged) | CGEventMaskBit(kCGEventLeftMouseDown) |
        CGEventMaskBit(kCGEventLeftMouseUp) | CGEventMaskBit(kCGEventRightMouseDown) |
        CGEventMaskBit(kCGEventRightMouseUp) | CGEventMaskBit(kCGEventOtherMouseDown) |
        CGEventMaskBit(kCGEventOtherMouseUp) | CGEventMaskBit(kCGEventMouseMoved) |
        CGEventMaskBit(kCGEventLeftMouseDragged) | CGEventMaskBit(kCGEventRightMouseDragged) |
        CGEventMaskBit(kCGEventOtherMouseDragged) | CGEventMaskBit(kCGEventScrollWheel);
    _tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
        kCGEventTapOptionDefault, mask, OrbisEventTapCallback, sink);
    if (!_tap || !OrbisNewEventTapHasMask(identities, mask))
    { [self stop]; return NO; }
    _source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _tap, 0);
    if (!_source) { [self stop]; return NO; }
    CFRunLoopAddSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
    CGEventTapEnable(_tap, true);
    return YES;
}
- (void)stop
{
    if (_tap) CGEventTapEnable(_tap, false);
    if (_source)
    {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
        CFRelease(_source); _source = NULL;
    }
    if (_tap) { CFMachPortInvalidate(_tap); CFRelease(_tap); _tap = NULL; }
}
- (void)dealloc { [self stop]; [super dealloc]; }
@end
