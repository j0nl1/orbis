/* SPDX-License-Identifier: MIT */
#import "OrbisIPadShortcutsController.h"
#import "OrbisWorkspaceShortcuts.h"

static OrbisShortcutModifiers OrbisIPadShortcutModifiers(UIKeyModifierFlags flags)
{
    return ((flags & UIKeyModifierShift) ? OrbisShortcutShift : 0) |
        ((flags & UIKeyModifierControl) ? OrbisShortcutControl : 0) |
        ((flags & UIKeyModifierAlternate) ? OrbisShortcutOption : 0) |
        ((flags & UIKeyModifierCommand) ? OrbisShortcutCommand : 0);
}
@interface OrbisIPadShortcutRecorder : UIViewController
@property(nonatomic, copy) BOOL (^record)(UIKey *key);
@property(nonatomic, copy) void (^clear)(void);
@property(nonatomic, copy) BOOL (^suggested)(void);
@property(nonatomic, copy) NSString *suggestedTitle;
@end
@implementation OrbisIPadShortcutRecorder
- (BOOL)canBecomeFirstResponder { return YES; }
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.text = @"Press a key combination on your keyboard.\n\nSome system shortcuts cannot be captured by Orbis.";
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    label.adjustsFontForContentSizeCategory = YES; label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:24],
        [label.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-24],
        [label.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor] ]];
    if (_suggested) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:_suggestedTitle forState:UIControlStateNormal];
        [button addTarget:self action:@selector(useSuggested:) forControlEvents:UIControlEventTouchUpInside];
        button.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:button];
        [NSLayoutConstraint activateConstraints:@[
            [button.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [button.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:24] ]];
    }
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
        target:self action:@selector(cancel:)] autorelease];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStylePlain
        target:self action:@selector(clearPressed:)] autorelease];
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [self becomeFirstResponder]; }
- (void)cancel:(id)sender { (void)sender; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)useSuggested:(id)sender { (void)sender; if (_suggested && _suggested()) [self cancel:nil]; }
- (void)clearPressed:(id)sender { (void)sender; if (_clear) _clear(); [self cancel:nil]; }
- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event
{
    (void)event;
    for (UIPress *press in presses) {
        UIKey *key = press.key;
        if (!key || key.keyCode < 4 || key.keyCode >= 224) continue;
        if (_record && _record(key)) { [self cancel:nil]; break; }
    }
}
- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event { (void)presses; (void)event; }
- (void)dealloc { [_record release]; [_clear release]; [_suggested release]; [_suggestedTitle release]; [super dealloc]; }
@end

@implementation OrbisIPadShortcutsController
{
    OrbisWorkspaceShortcuts *_shortcuts;
}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
{
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _shortcuts = [[OrbisWorkspaceShortcuts alloc] initWithDefaults:defaults platform:@"ipados"];
    return self;
}
- (void)viewDidLoad
{
    [super viewDidLoad]; self.title = @"Keyboard Shortcuts";
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
        target:self action:@selector(cancelPressed:)] autorelease];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
        target:self action:@selector(savePressed:)] autorelease];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{ (void)tableView; (void)section; return OrbisWorkspaceShortcuts.actions.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path
{
    (void)tableView;
    OrbisWorkspaceAction action = [OrbisWorkspaceShortcuts.actions[path.row] integerValue];
    UITableViewCell *cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil] autorelease];
    cell.textLabel.text = [OrbisWorkspaceShortcuts titleForAction:action];
    cell.detailTextLabel.text = [_shortcuts labelForAction:action];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.accessibilityIdentifier = [NSString stringWithFormat:@"workspace-shortcut-%ld", (long)action];
    for (UILabel *label in @[cell.textLabel, cell.detailTextLabel]) {
        label.adjustsFontForContentSizeCategory = YES; label.numberOfLines = 0;
    }
    return cell;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{ (void)tableView; (void)section; return OrbisWorkspaceShortcuts.warning; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path
{
    [tableView deselectRowAtIndexPath:path animated:YES];
    OrbisWorkspaceAction action = [OrbisWorkspaceShortcuts.actions[path.row] integerValue];
    OrbisIPadShortcutRecorder *recorder = [[[OrbisIPadShortcutRecorder alloc] init] autorelease];
    recorder.title = [OrbisWorkspaceShortcuts titleForAction:action];
    __block OrbisIPadShortcutRecorder *recording = recorder;
    recorder.record = ^BOOL(UIKey *key) {
        OrbisShortcutModifiers modifiers = OrbisIPadShortcutModifiers(key.modifierFlags);
        NSString *symbol = @{ @79:@"→", @80:@"←", @81:@"↓", @82:@"↑", @40:@"Return", @41:@"Esc", @42:@"Delete", @43:@"Tab", @44:@"Space" }[@(key.keyCode)]
            ?: key.charactersIgnoringModifiers.uppercaseString;
        if (!symbol.length) symbol = [NSString stringWithFormat:@"Key %lu", (unsigned long)key.keyCode];
        NSString *label = [NSString stringWithFormat:@"%@%@%@%@%@", modifiers & OrbisShortcutControl ? @"⌃" : @"",
            modifiers & OrbisShortcutOption ? @"⌥" : @"", modifiers & OrbisShortcutShift ? @"⇧" : @"",
            modifiers & OrbisShortcutCommand ? @"⌘" : @"", symbol];
        NSError *error = nil;
        if (![_shortcuts assignKeyCode:key.keyCode modifiers:modifiers label:label toAction:action error:&error]) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Shortcut unavailable"
                message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [recording presentViewController:alert animated:YES completion:nil]; return NO;
        }
        [self.tableView reloadData]; return YES;
    };
    if (action == OrbisWorkspaceScreenshotScreen || action == OrbisWorkspaceScreenshotWindow) {
        recorder.suggestedTitle = action == OrbisWorkspaceScreenshotScreen ? @"Use ⌘⇧3" : @"Use ⌘⇧4";
        recorder.suggested = ^BOOL {
            NSString *label = action == OrbisWorkspaceScreenshotScreen ? @"⇧⌘3" : @"⇧⌘4";
            NSError *error = nil;
            if ([_shortcuts assignKeyCode:action == OrbisWorkspaceScreenshotScreen ? 32 : 33
                modifiers:OrbisShortcutCommand | OrbisShortcutShift label:label toAction:action error:&error]) {
                [self.tableView reloadData]; return YES;
            }
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Shortcut unavailable"
                message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [recording presentViewController:alert animated:YES completion:nil]; return NO;
        };
    }
    recorder.clear = ^{ [_shortcuts clearAction:action]; [self.tableView reloadData]; };
    UINavigationController *navigation = [[[UINavigationController alloc] initWithRootViewController:recorder] autorelease];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:navigation animated:YES completion:nil];
}
- (void)savePressed:(id)sender { (void)sender; [_shortcuts save]; [self.navigationController popViewControllerAnimated:YES]; }
- (void)cancelPressed:(id)sender { (void)sender; [self.navigationController popViewControllerAnimated:YES]; }
- (void)dealloc { [_shortcuts release]; [super dealloc]; }
@end
