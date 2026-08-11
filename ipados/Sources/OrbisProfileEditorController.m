/* SPDX-License-Identifier: MIT */

#import "OrbisProfileEditorController.h"

#import "OrbisProfile.h"

@interface OrbisProfileEditorController ()
- (UITableViewCell *)fieldCellWithTitle:(NSString *)title textField:(UITextField *)textField;
- (UITableViewCell *)optionCellWithTitle:(NSString *)title control:(UISwitch *)control;
- (void)replacePasswordPressed:(id)sender;
- (void)cancelPressed:(id)sender;
- (void)savePressed:(id)sender;
- (void)showValidationError:(NSString *)message;
@end

@implementation OrbisProfileEditorController

@synthesize delegate = _delegate;

- (id)initWithProfile:(OrbisProfile *)profile
{
	return [self initWithProfile:profile hasSavedPassword:NO];
}

- (id)initWithProfile:(OrbisProfile *)profile hasSavedPassword:(BOOL)hasSavedPassword
{
	if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped]))
		return nil;
	_profile = profile ? [profile copy] : [[OrbisProfile alloc] init];
	_hasSavedPassword = hasSavedPassword;
	_shouldFocusNameField = [[_profile host] length] == 0;
	return self;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	[self setTitle:[[_profile host] length] > 0 ? @"Edit Connection" : @"New Connection"];
	[[self navigationItem] setLargeTitleDisplayMode:UINavigationItemLargeTitleDisplayModeNever];
	[[self navigationItem]
	    setLeftBarButtonItem:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:
	                                                        UIBarButtonSystemItemCancel
	                                                                         target:self
	                                                                         action:@selector(cancelPressed:)]
	                             autorelease]];
	[[self navigationItem]
	    setRightBarButtonItem:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:
	                                                         UIBarButtonSystemItemSave
	                                                                          target:self
	                                                                          action:@selector(savePressed:)]
	                              autorelease]];

	_nameField = [[UITextField alloc] init];
	[_nameField setText:[_profile name]];
	[_nameField setPlaceholder:@"New Connection"];
	[_nameField setTextContentType:UITextContentTypeName];
	[_nameField setReturnKeyType:UIReturnKeyNext];
	[_nameField setDelegate:self];

	_hostField = [[UITextField alloc] init];
	[_hostField setText:[_profile host]];
	[_hostField setPlaceholder:@"192.168.1.20 or rdp.example.com"];
	[_hostField setTextContentType:UITextContentTypeURL];
	[_hostField setAutocapitalizationType:UITextAutocapitalizationTypeNone];
	[_hostField setAutocorrectionType:UITextAutocorrectionTypeNo];
	[_hostField setKeyboardType:UIKeyboardTypeURL];
	[_hostField setReturnKeyType:UIReturnKeyNext];
	[_hostField setDelegate:self];

	_portField = [[UITextField alloc] init];
	[_portField setText:[NSString stringWithFormat:@"%lu", (unsigned long)[_profile port]]];
	[_portField setPlaceholder:@"3389"];
	[_portField setKeyboardType:UIKeyboardTypeNumberPad];
	[_portField setDelegate:self];

	_usernameField = [[UITextField alloc] init];
	[_usernameField setText:[_profile username]];
	[_usernameField setPlaceholder:@"username"];
	[_usernameField setTextContentType:UITextContentTypeUsername];
	[_usernameField setAutocapitalizationType:UITextAutocapitalizationTypeNone];
	[_usernameField setAutocorrectionType:UITextAutocorrectionTypeNo];
	[_usernameField setReturnKeyType:UIReturnKeyNext];
	[_usernameField setDelegate:self];

	_passwordField = [[UITextField alloc] init];
	[_passwordField setPlaceholder:_hasSavedPassword ? @"********" : @"Password"];
	if (_hasSavedPassword)
		[_passwordField setAccessibilityValue:@"Saved in Keychain"];
	[_passwordField setSecureTextEntry:YES];
	[_passwordField setTextContentType:UITextContentTypePassword];
	[_passwordField setAutocapitalizationType:UITextAutocapitalizationTypeNone];
	[_passwordField setAutocorrectionType:UITextAutocorrectionTypeNo];
	[_passwordField setReturnKeyType:UIReturnKeyDone];
	[_passwordField setDelegate:self];
	if (_hasSavedPassword)
	{
		UIButton *replacePasswordButton = [UIButton buttonWithType:UIButtonTypeSystem];
		[replacePasswordButton setImage:[UIImage systemImageNamed:@"pencil"]
		                       forState:UIControlStateNormal];
		[replacePasswordButton setTintColor:[UIColor blackColor]];
		[replacePasswordButton addTarget:self
		                          action:@selector(replacePasswordPressed:)
		                forControlEvents:UIControlEventTouchUpInside];
		[replacePasswordButton setAccessibilityLabel:@"Replace saved password"];
		[replacePasswordButton setFrame:CGRectMake(0.0, 0.0, 44.0, 44.0)];
		[_passwordField setRightView:replacePasswordButton];
		[_passwordField setRightViewMode:UITextFieldViewModeAlways];
	}

	_fieldCells = [[NSArray alloc] initWithObjects:
	                                  [self fieldCellWithTitle:@"Name" textField:_nameField],
	                                  [self fieldCellWithTitle:@"Host" textField:_hostField],
		                                  [self fieldCellWithTitle:@"Port" textField:_portField],
		                                  [self fieldCellWithTitle:@"Username" textField:_usernameField],
		                                  [self fieldCellWithTitle:@"Password" textField:_passwordField],
		                                  nil];

	_certificateSwitch = [[UISwitch alloc] init];
	[_certificateSwitch setOn:[_profile acceptAllCertificates]];
	_automaticSwitch = [[UISwitch alloc] init];
	[_automaticSwitch setOn:[_profile connectAutomatically]];
	_optionCells = [[NSArray alloc]
	    initWithObjects:[self optionCellWithTitle:@"Accept all certificates"
	                                    control:_certificateSwitch],
	                    [self optionCellWithTitle:@"Connect automatically"
	                                    control:_automaticSwitch],
	                    nil];
}

- (UITableViewCell *)fieldCellWithTitle:(NSString *)title textField:(UITextField *)textField
{
	UITableViewCell *cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
	                                               reuseIdentifier:nil] autorelease];
	UILabel *label = [[[UILabel alloc] init] autorelease];
	[label setText:title];
	[label setFont:[UIFont preferredFontForTextStyle:UIFontTextStyleBody]];
	[label setAdjustsFontForContentSizeCategory:YES];
	[[label widthAnchor] constraintEqualToConstant:104.0].active = YES;
	[textField setFont:[UIFont preferredFontForTextStyle:UIFontTextStyleBody]];
	[textField setTextAlignment:NSTextAlignmentRight];
	[textField setClearButtonMode:UITextFieldViewModeWhileEditing];

	UIStackView *stack = [[[UIStackView alloc] initWithArrangedSubviews:@[ label, textField ]]
	    autorelease];
	[stack setAxis:UILayoutConstraintAxisHorizontal];
	[stack setAlignment:UIStackViewAlignmentCenter];
	[stack setSpacing:12.0];
	[stack setTranslatesAutoresizingMaskIntoConstraints:NO];
	[[cell contentView] addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[[stack leadingAnchor] constraintEqualToAnchor:[[cell contentView] leadingAnchor]
		                                          constant:20.0],
		[[stack trailingAnchor] constraintEqualToAnchor:[[cell contentView] trailingAnchor]
		                                           constant:-16.0],
		[[stack topAnchor] constraintEqualToAnchor:[[cell contentView] topAnchor] constant:9.0],
		[[stack bottomAnchor] constraintEqualToAnchor:[[cell contentView] bottomAnchor]
		                                         constant:-9.0],
		[[textField heightAnchor] constraintGreaterThanOrEqualToConstant:32.0],
	]];
	return cell;
}

- (UITableViewCell *)optionCellWithTitle:(NSString *)title control:(UISwitch *)control
{
	UITableViewCell *cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
	                                               reuseIdentifier:nil] autorelease];
	[[cell textLabel] setText:title];
	[[cell textLabel] setNumberOfLines:0];
	[cell setAccessoryView:control];
	[cell setSelectionStyle:UITableViewCellSelectionStyleNone];
	return cell;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	(void)tableView;
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	(void)tableView;
	return section == 0 ? [_fieldCells count] : [_optionCells count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
	         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	(void)tableView;
	return [indexPath section] == 0 ? [_fieldCells objectAtIndex:[indexPath row]]
	                                : [_optionCells objectAtIndex:[indexPath row]];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	(void)tableView;
	return section == 0 ? @"Remote computer" : @"Connection";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
	(void)tableView;
	if (section == 0)
		return @"Host accepts an IPv4 address, a local hostname, or a domain. Use a private "
			       @"hostname when the iPad is connected through Cloudflare One/WARP.";
	return @"Accept all certificates removes the warning for this connection, but also disables "
	       @"identity verification. At most one connection can open automatically.";
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	if (_shouldFocusNameField)
	{
		_shouldFocusNameField = NO;
		[_nameField becomeFirstResponder];
	}
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
	if (textField == _nameField)
		[_hostField becomeFirstResponder];
	else if (textField == _hostField)
		[_portField becomeFirstResponder];
	else if (textField == _usernameField)
		[_passwordField becomeFirstResponder];
	else if (textField == _passwordField)
		[textField resignFirstResponder];
	return YES;
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
	if (textField == _passwordField && _hasSavedPassword && !_isReplacingPassword)
		[self replacePasswordPressed:nil];
	return YES;
}

- (void)replacePasswordPressed:(id)sender
{
	(void)sender;
	if (_isReplacingPassword)
		return;
	_isReplacingPassword = YES;
	[_passwordField setPlaceholder:@"New password"];
	[_passwordField setRightViewMode:UITextFieldViewModeNever];
	[_passwordField becomeFirstResponder];
}

- (void)cancelPressed:(id)sender
{
	(void)sender;
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)savePressed:(id)sender
{
	(void)sender;
	NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	NSString *name = [[_nameField text] stringByTrimmingCharactersInSet:whitespace];
	NSString *host = [[_hostField text] stringByTrimmingCharactersInSet:whitespace];
	NSString *username = [[_usernameField text] stringByTrimmingCharactersInSet:whitespace];
	NSInteger port = [[_portField text] integerValue];

	if ([name length] == 0)
		return [self showValidationError:@"Give this connection a name."];
	if ([host length] == 0)
		return [self showValidationError:@"Enter an IP address or hostname."];
	if ([host rangeOfString:@"://"].location != NSNotFound ||
	    [host rangeOfCharacterFromSet:whitespace].location != NSNotFound)
		return [self showValidationError:@"Enter only the host or IP address, without a URL scheme, "
		                                  @"path, or spaces."];
	if (port < 1 || port > 65535)
		return [self showValidationError:@"Port must be between 1 and 65535."];
	if ([username length] == 0)
		return [self showValidationError:@"Enter the Remote Desktop username."];

	[_profile setName:name];
	[_profile setHost:host];
	[_profile setPort:(NSUInteger)port];
	[_profile setUsername:username];
	[_profile setAcceptAllCertificates:[_certificateSwitch isOn]];
	[_profile setConnectAutomatically:[_automaticSwitch isOn]];
	if (![_delegate profileEditor:self didSaveProfile:_profile password:[_passwordField text]])
		return;
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showValidationError:(NSString *)message
{
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Check Connection"
	                                                               message:message
	                                                        preferredStyle:
	                                                            UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
	                                       handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)dealloc
{
	[_profile release];
	[_nameField release];
	[_hostField release];
	[_portField release];
	[_usernameField release];
	[_passwordField release];
	[_certificateSwitch release];
	[_automaticSwitch release];
	[_fieldCells release];
	[_optionCells release];
	[super dealloc];
}

@end
