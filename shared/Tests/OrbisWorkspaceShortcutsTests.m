/* SPDX-License-Identifier: MIT */
#import <XCTest/XCTest.h>
#import "OrbisWorkspaceShortcuts.h"

@interface OrbisWorkspaceShortcutsTests : XCTestCase
@end
@implementation OrbisWorkspaceShortcutsTests
- (NSUserDefaults *)defaults
{
    NSString *suite = [@"OrbisShortcutTests." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[[NSUserDefaults alloc] initWithSuiteName:suite] autorelease];
    [self addTeardownBlock:^{ [defaults removePersistentDomainForName:suite]; }];
    return defaults;
}
- (void)testDefaultBindingsRemainEmptyWithLegacyPreferences
{
    NSUserDefaults *defaults = [self defaults];
    [defaults setObject:@{ @"workspaceShortcutsEnabled": @YES } forKey:@"OrbisIPadDisplaySettings.v1"];
    for (NSString *platform in @[@"macos", @"ipados"]) {
        OrbisWorkspaceShortcuts *model = [[[OrbisWorkspaceShortcuts alloc] initWithDefaults:defaults platform:platform] autorelease];
        XCTAssertEqual(model.bindings.count, 0u);
        XCTAssertEqualObjects([model labelForAction:OrbisWorkspaceActivities], @"Not assigned");
    }
}
- (void)testSaveRequiresExactModifiersAndSeparatesPlatforms
{
    NSUserDefaults *defaults = [self defaults];
    OrbisWorkspaceShortcuts *model = [[[OrbisWorkspaceShortcuts alloc] initWithDefaults:defaults platform:@"ipados"] autorelease];
    XCTAssertTrue([model assignKeyCode:82 modifiers:OrbisShortcutOption | OrbisShortcutShift label:@"Option Shift Up" toAction:OrbisWorkspaceActivities error:nil]);
    OrbisWorkspaceShortcuts *unsaved = [[[OrbisWorkspaceShortcuts alloc] initWithDefaults:defaults platform:@"ipados"] autorelease];
    XCTAssertEqual(unsaved.bindings.count, 0u);
    [model save];
    OrbisWorkspaceShortcuts *saved = [[[OrbisWorkspaceShortcuts alloc] initWithDefaults:defaults platform:@"ipados"] autorelease];
    XCTAssertEqual([saved actionForKeyCode:82 modifiers:5], OrbisWorkspaceActivities);
    XCTAssertEqual([saved actionForKeyCode:82 modifiers:7], OrbisWorkspaceNone);
    XCTAssertEqual([saved actionForKeyCode:81 modifiers:5], OrbisWorkspaceNone);
    OrbisWorkspaceShortcuts *mac = [[[OrbisWorkspaceShortcuts alloc] initWithDefaults:defaults platform:@"macos"] autorelease];
    XCTAssertEqual(mac.bindings.count, 0u);
}
- (void)testCollisionsReassignmentAndClearing
{
    OrbisWorkspaceShortcuts *model = [[[OrbisWorkspaceShortcuts alloc] initWithDefaults:[self defaults] platform:@"macos"] autorelease];
    XCTAssertTrue([model assignKeyCode:20 modifiers:9 label:@"Command Shift 3" toAction:OrbisWorkspaceScreenshotScreen error:nil]);
    NSError *error = nil;
    XCTAssertFalse([model assignKeyCode:20 modifiers:9 label:@"Command Shift 3" toAction:OrbisWorkspaceScreenshotWindow error:&error]);
    XCTAssertNotNil(error);
    XCTAssertTrue([model assignKeyCode:21 modifiers:9 label:@"Command Shift 4" toAction:OrbisWorkspaceScreenshotScreen error:nil]);
    XCTAssertEqual([model actionForKeyCode:20 modifiers:9], OrbisWorkspaceNone);
    [model clearAction:OrbisWorkspaceScreenshotScreen];
    XCTAssertEqual(model.bindings.count, 0u);
}
- (void)testMalformedSavedBindingsAreIgnored
{
    NSUserDefaults *defaults = [self defaults];
    [defaults setObject:@{ @"5": @{ @"key": @82.5, @"modifiers": @5, @"label": @"Invalid" },
        @"6": @{ @"key": @53, @"modifiers": @16, @"label": @"Invalid" },
        @"1": @"Invalid", @"8": @{ @"key": @20, @"modifiers": @9, @"label": @"Capture" } }
        forKey:@"OrbisWorkspaceShortcuts.v1.macos"];
    OrbisWorkspaceShortcuts *model = [[[OrbisWorkspaceShortcuts alloc] initWithDefaults:defaults platform:@"macos"] autorelease];
    XCTAssertEqual(model.bindings.count, 1u);
    XCTAssertEqual([model actionForKeyCode:20 modifiers:9], OrbisWorkspaceScreenshotScreen);
}
@end
