/* SPDX-License-Identifier: MIT */
#import "OrbisIPadDisplaySettingsController.h"
#import "OrbisIPadDisplaySettings.h"

@implementation OrbisIPadDisplaySettingsController
{
	OrbisIPadDisplaySettings *_settings;
	UISwitch *_automaticSwitch;
	UITextField *_widthField;
	UITextField *_heightField;
	UIButton *_presetButton;
	UIButton *_scaleButton;
	NSArray *_resolutionCells;
	UITableViewCell *_scaleCell;
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
	_widthField = [[self dimensionField:_settings.automaticResolution ? 1920 : _settings.width identifier:@"display-width"] retain];
	_heightField = [[self dimensionField:_settings.automaticResolution ? 1080 : _settings.height identifier:@"display-height"] retain];
	_presetButton = [[UIButton buttonWithType:UIButtonTypeSystem] retain];
	_presetButton.frame = CGRectMake(0, 0, 160, 44);
	[_presetButton setTitle:@"Choose resolution" forState:UIControlStateNormal];
	__block OrbisIPadDisplaySettingsController *controller = self;
	NSMutableArray *presets = [NSMutableArray array];
	for (NSArray *size in @[ @[ @1280, @720 ], @[ @1920, @1080 ], @[ @2560, @1440 ],
	    @[ @2732, @2048 ], @[ @3840, @2160 ] ])
	{
		NSString *title = [NSString stringWithFormat:@"%@ × %@", size[0], size[1]];
		[presets addObject:[UIAction actionWithTitle:title image:nil identifier:nil handler:^(UIAction *action) {
			(void)action;
			controller->_widthField.text = [size[0] stringValue];
			controller->_heightField.text = [size[1] stringValue];
		}]];
	}
	_presetButton.menu = [UIMenu menuWithChildren:presets];
	_presetButton.showsMenuAsPrimaryAction = YES;
	_resolutionCells = [[NSArray alloc] initWithObjects:
	    [self cellWithTitle:@"Automatically match window" control:_automaticSwitch],
	    [self cellWithTitle:@"Presets" control:_presetButton],
	    [self cellWithTitle:@"Width" control:_widthField],
	    [self cellWithTitle:@"Height" control:_heightField], nil];
	_scaleButton = [[UIButton buttonWithType:UIButtonTypeSystem] retain];
	_scaleButton.frame = CGRectMake(0, 0, 100, 44);
	_scaleButton.accessibilityIdentifier = @"display-desktop-scale";
	_scaleButton.accessibilityLabel = @"Desktop scale";
	_scaleButton.showsMenuAsPrimaryAction = YES;
	_scaleCell = [[self cellWithTitle:@"Desktop scale" control:_scaleButton] retain];
	[self updateScaleMenu];
	[self automaticChanged:nil];
}

- (void)updateScaleMenu
{
	[_scaleButton setTitle:[NSString stringWithFormat:@"%lu%%", (unsigned long)_settings.desktopScale]
	    forState:UIControlStateNormal];
	__block OrbisIPadDisplaySettingsController *controller = self;
	NSMutableArray *actions = [NSMutableArray array];
	for (NSNumber *scale in [OrbisIPadDisplaySettings supportedScales])
	{
		UIAction *action = [UIAction actionWithTitle:[NSString stringWithFormat:@"%@%%", scale]
		    image:nil identifier:nil handler:^(UIAction *selected) {
			(void)selected;
			controller->_settings.desktopScale = scale.unsignedIntegerValue;
			[controller updateScaleMenu];
		}];
		action.state = scale.unsignedIntegerValue == _settings.desktopScale ? UIMenuElementStateOn : UIMenuElementStateOff;
		[actions addObject:action];
	}
	_scaleButton.menu = [UIMenu menuWithChildren:actions];
}

- (void)automaticChanged:(id)sender
{
	(void)sender;
	_widthField.enabled = _heightField.enabled = _presetButton.enabled = !_automaticSwitch.on;
	_widthField.textColor = _heightField.textColor = _automaticSwitch.on ?
	    [UIColor tertiaryLabelColor] : [UIColor labelColor];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	(void)tableView; return section == 0 ? _resolutionCells.count : 1;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path
{
	(void)tableView; return path.section == 0 ? _resolutionCells[path.row] : _scaleCell;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	(void)tableView; return section == 0 ? @"Remote resolution" : @"Linux display scale";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
	(void)tableView;
	return section == 0 ? @"Applies to new connections to any computer. Automatic follows rotation and window resizing. A manual resolution stays fixed." :
	    @"Requests larger text and apps on the remote desktop. Some Linux servers may ignore this setting. Pinch zoom on the iPad is independent.";
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
	[_presetButton release]; [_scaleButton release]; [_resolutionCells release]; [_scaleCell release];
	[_settings release]; [_automaticSwitch release]; [_widthField release]; [_heightField release];
	[super dealloc];
}
@end
