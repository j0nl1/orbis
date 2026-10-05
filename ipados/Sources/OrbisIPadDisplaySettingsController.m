/* SPDX-License-Identifier: MIT */
#import "OrbisIPadDisplaySettingsController.h"
#import "OrbisIPadDisplaySettings.h"
#import "OrbisDiagnostics.h"
#include <math.h>

@implementation OrbisIPadDisplaySettingsController
{
	OrbisIPadDisplaySettings *_settings;
	UISwitch *_automaticSwitch;
	UITextField *_widthField;
	UITextField *_heightField;
	UIButton *_presetButton;
	NSArray *_resolutionCells;
	CGSize _presetPixelSize;
	UISwitch *_workspaceSwitch;
	UITableViewCell *_workspaceCell;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
{
	if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
	_settings = [[OrbisIPadDisplaySettings alloc] initWithDefaults:defaults];
	return self;
}

- (UITableViewCell *)cellWithTitle:(NSString *)title control:(UIView *)control
{
	UITableViewCell *cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
	    reuseIdentifier:nil] autorelease];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.textLabel.text = title;
	cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	cell.textLabel.adjustsFontForContentSizeCategory = YES;
	cell.accessoryView = control;
	return cell;
}

- (UITextField *)dimensionField:(NSUInteger)value identifier:(NSString *)identifier
{
	UITextField *field = [[[UITextField alloc] initWithFrame:CGRectMake(0, 0, 110, 44)] autorelease];
	field.text = [NSString stringWithFormat:@"%lu", (unsigned long)value];
	field.textAlignment = NSTextAlignmentRight;
	field.keyboardType = UIKeyboardTypeNumberPad;
	field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	field.adjustsFontForContentSizeCategory = YES;
	field.accessibilityIdentifier = identifier;
	field.accessibilityLabel = [identifier isEqualToString:@"display-width"] ? @"Width in pixels" : @"Height in pixels";
	return field;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.title = @"Settings";
	self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc]
	    initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelPressed:)] autorelease];
	self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc]
	    initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(savePressed:)] autorelease];
	_automaticSwitch = [[UISwitch alloc] init];
	_automaticSwitch.on = _settings.automaticResolution;
	_automaticSwitch.accessibilityIdentifier = @"display-automatic-resolution";
	[_automaticSwitch addTarget:self action:@selector(automaticChanged:) forControlEvents:UIControlEventValueChanged];
	_widthField = [[self dimensionField:_settings.width identifier:@"display-width"] retain];
	_heightField = [[self dimensionField:_settings.height identifier:@"display-height"] retain];
	_presetButton = [[UIButton buttonWithType:UIButtonTypeSystem] retain];
	_presetButton.frame = CGRectMake(0, 0, 160, 44);
	[_presetButton setTitle:@"Choose resolution" forState:UIControlStateNormal];
	_presetButton.showsMenuAsPrimaryAction = YES;
	_resolutionCells = [[NSArray alloc] initWithObjects:
	    [self cellWithTitle:@"Automatically match window" control:_automaticSwitch],
	    [self cellWithTitle:@"Suggested" control:_presetButton],
	    [self cellWithTitle:@"Width" control:_widthField],
	    [self cellWithTitle:@"Height" control:_heightField], nil];
	[self updateResolutionPresets];
	[self automaticChanged:nil];
	_workspaceSwitch = [[UISwitch alloc] init];
	_workspaceSwitch.on = _settings.workspaceShortcutsEnabled;
	_workspaceSwitch.accessibilityIdentifier = @"keyboard-workspace-shortcuts";
	_workspaceCell = [[self cellWithTitle:@"Workspace shortcuts" control:_workspaceSwitch] retain];
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	[self updateResolutionPresets];
}

- (void)updateResolutionPresets
{
	UIWindow *window = self.view.window;
	UIScreen *screen = window ? window.screen : [UIScreen mainScreen];
	CGSize bounds = window ? window.bounds.size : screen.bounds.size;
	CGFloat scale = screen.nativeScale;
	CGSize pixels = CGSizeMake(round(bounds.width * scale), round(bounds.height * scale));
	if (CGSizeEqualToSize(pixels, _presetPixelSize)) return;
	_presetPixelSize = pixels;
	NSArray *sizes = [OrbisIPadDisplaySettings resolutionsForPixelWidth:(NSUInteger)pixels.width
	    height:(NSUInteger)pixels.height];
	if (_automaticSwitch.on && sizes.count)
	{
		_widthField.text = [sizes[0][0] stringValue];
		_heightField.text = [sizes[0][1] stringValue];
	}
	__block OrbisIPadDisplaySettingsController *controller = self;
	NSMutableArray *actions = [NSMutableArray array];
	for (NSArray *size in sizes)
	{
		NSString *title = [NSString stringWithFormat:@"%@ × %@", size[0], size[1]];
		[actions addObject:[UIAction actionWithTitle:title image:nil identifier:nil handler:^(UIAction *action) {
			(void)action;
			controller->_widthField.text = [size[0] stringValue];
			controller->_heightField.text = [size[1] stringValue];
		}]];
	}
	_presetButton.menu = [UIMenu menuWithChildren:actions];
}

- (void)automaticChanged:(id)sender
{
	(void)sender;
	_widthField.enabled = _heightField.enabled = _presetButton.enabled = !_automaticSwitch.on;
	_widthField.textColor = _heightField.textColor = _automaticSwitch.on ?
	    [UIColor tertiaryLabelColor] : [UIColor labelColor];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	(void)tableView; return section == 0 ? _resolutionCells.count : 1;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path
{
	(void)tableView;
	if (path.section == 0) return _resolutionCells[path.row];
	if (path.section == 1) return _workspaceCell;
	UITableViewCell *cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease];
	cell.textLabel.text = @"Export Diagnostics";
	cell.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.up"];
	cell.accessibilityIdentifier = @"export-diagnostics";
	return cell;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	(void)tableView; return section == 0 ? @"Remote resolution" : (section == 1 ? @"Keyboard" : @"Diagnostics");
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
	(void)tableView;
	if (section == 2)
		return @"Export recent session events, error codes, and available crash or hang reports. Diagnostics stay on this device until you share them.";
	if (section == 1)
		return @"Alt (Option) + Shift + Left or Right switches workspaces. Alt + Shift + Up toggles Activities. Alt + the key left of 1 also toggles Activities. Uses GNOME keyboard shortcuts. Trackpad swipes scroll normally. Applies to new connections.";
	return @"Applies to new connections to any computer. Suggested resolutions match this iPad window’s proportions. Automatic follows rotation and resizing. A manual resolution stays fixed.";
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path
{
	[tableView deselectRowAtIndexPath:path animated:YES];
	if (path.section != 2) return;
	tableView.userInteractionEnabled = NO;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		@autoreleasepool
		{
			NSError *error = nil;
			NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"OrbisExports"]];
			NSURL *url = [[OrbisDiagnostics sharedDiagnostics] exportToDirectory:directory error:&error];
			dispatch_async(dispatch_get_main_queue(), ^{
				tableView.userInteractionEnabled = YES;
				if (!self.view.window || self.presentedViewController)
				{
					if (url) [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
					return;
				}
				if (!url)
				{
					UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Could not export diagnostics"
					    message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
					[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
					[self presentViewController:alert animated:YES completion:nil];
					return;
				}
				UIActivityViewController *share = [[[UIActivityViewController alloc]
				    initWithActivityItems:@[url] applicationActivities:nil] autorelease];
				UIView *anchor = [tableView cellForRowAtIndexPath:path] ?: tableView;
				share.popoverPresentationController.sourceView = anchor;
				share.popoverPresentationController.sourceRect = anchor.bounds;
				share.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *shareError) {
					(void)type; (void)completed; (void)items; (void)shareError;
					[[NSFileManager defaultManager] removeItemAtURL:url error:nil];
				};
				[self presentViewController:share animated:YES completion:nil];
			});
		}
	});
}

- (NSUInteger)dimensionFromField:(UITextField *)field
{
	NSString *text = [field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!text.length || text.length > 4 || [text rangeOfCharacterFromSet:
	    [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location != NSNotFound)
		return NSUIntegerMax;
	return (NSUInteger)text.integerValue;
}

- (void)savePressed:(id)sender
{
	(void)sender;
	[self.view endEditing:YES];
	_settings.width = _automaticSwitch.on ? 0 : [self dimensionFromField:_widthField];
	_settings.height = _automaticSwitch.on ? 0 : [self dimensionFromField:_heightField];
	_settings.workspaceShortcutsEnabled = _workspaceSwitch.on;
	NSError *error = nil;
	if ([_settings saveWithError:&error])
		return [self dismissViewControllerAnimated:YES completion:nil];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Display Settings"
	    message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)cancelPressed:(id)sender
{
	(void)sender; [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)dealloc
{
	[_presetButton release]; [_resolutionCells release];
	[_workspaceSwitch release]; [_workspaceCell release];
	[_settings release]; [_automaticSwitch release]; [_widthField release]; [_heightField release];
	[super dealloc];
}
@end
