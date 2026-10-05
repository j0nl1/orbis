/* SPDX-License-Identifier: MIT */

#import "OrbisProfileEditorController.h"

#import "OrbisProfile.h"
#import "OrbisCredentialStore.h"
#import "OrbisTunnelBridge.h"

@interface OrbisProfileEditorController ()
- (UITableViewCell *)fieldCellWithTitle:(NSString *)title textField:(UITextField *)textField;
- (UITableViewCell *)optionCellWithTitle:(NSString *)title control:(UISwitch *)control;
- (void)replacePasswordPressed:(id)sender;
- (void)transportChanged:(id)sender;
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


	_transportControl = [[UISegmentedControl alloc] initWithItems:@[ @"Direct RDP", @"Cloudflare" ]];
	[_transportControl setSelectedSegmentIndex:[[_profile transportType] isEqualToString:OrbisTransportTypeCloudflare] ? 1 : 0];
	[_transportControl addTarget:self action:@selector(transportChanged:) forControlEvents:UIControlEventValueChanged];
	_gatewayHostnameField = [[UITextField alloc] init];
	[_gatewayHostnameField setText:[_profile transportHostname]];
	[_gatewayHostnameField setPlaceholder:@"https://rdp.example.com"];
	[_gatewayHostnameField setKeyboardType:UIKeyboardTypeURL];
	_clientIDField = [[UITextField alloc] init];
	[_clientIDField setPlaceholder:@"CF-Access-Client-Id"];
	_clientSecretField = [[UITextField alloc] init];
	[_clientSecretField setSecureTextEntry:YES];
	[_clientSecretField setPlaceholder:@"CF-Access-Client-Secret"];
	NSDictionary *token = [OrbisCredentialStore cloudflareTokenForProfile:_profile error:nil];
	if (token)
	{
		_savedTokenHost = [[[_profile transportHostname] lowercaseString] copy];
		_savedTokenClientID = [token[@"clientID"] copy];
		[_clientIDField setText:_savedTokenClientID];
		[_clientSecretField setPlaceholder:@"********"];
		[_clientSecretField setAccessibilityValue:@"Saved in Keychain"];
	}
	for (UITextField *field in @[ _gatewayHostnameField, _clientIDField, _clientSecretField ])
	{
		[field setAutocapitalizationType:UITextAutocapitalizationTypeNone];
		[field setAutocorrectionType:UITextAutocorrectionTypeNo];
		[field setSpellCheckingType:UITextSpellCheckingTypeNo];
		[field setDelegate:self];
		[field setReturnKeyType:UIReturnKeyNext];
	}
	[_clientSecretField setReturnKeyType:UIReturnKeyDone];
	_accessCells = [[NSArray alloc] initWithObjects:
		[self fieldCellWithTitle:@"Tunnel URL" textField:_gatewayHostnameField],
		[self fieldCellWithTitle:@"Client ID" textField:_clientIDField],
		[self fieldCellWithTitle:@"Client Secret" textField:_clientSecretField], nil];
	_accountCells = [[_fieldCells subarrayWithRange:NSMakeRange(3, 2)] retain];
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

- (void)transportChanged:(id)sender
{
	(void)sender;
	[[self view] endEditing:YES];
	[[self tableView] reloadData];
}

- (NSArray *)endpointCells
{
	return [_transportControl selectedSegmentIndex] == 1 ? _accessCells
	    : [_fieldCells subarrayWithRange:NSMakeRange(1, 2)];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	(void)tableView;
	return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	(void)tableView;
	if (section == 0) return 2;
	if (section == 1) return [[self endpointCells] count];
	return section == 2 ? [_accountCells count] : [_optionCells count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	(void)tableView;
	NSInteger section = [indexPath section];
	if (section == 0)
	{
		if ([indexPath row] == 0) return [_fieldCells firstObject];
		UITableViewCell *cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease];
		[_transportControl setTranslatesAutoresizingMaskIntoConstraints:NO];
		[[cell contentView] addSubview:_transportControl];
		[NSLayoutConstraint activateConstraints:@[
			[_transportControl.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:20],
			[_transportControl.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-20],
			[_transportControl.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],
			[_transportControl.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10]
		]];
		return cell;
	}
	NSArray *cells = section == 1 ? [self endpointCells] : section == 2 ? _accountCells : _optionCells;
	return [cells objectAtIndex:[indexPath row]];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	(void)tableView;
	return @[ @"Connection", @"Remote computer", @"Remote Desktop account", @"Options" ][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
	(void)tableView;
	if (section == 1)
		return [_transportControl selectedSegmentIndex] == 1
			? @"Use the tunnel hostname or HTTPS URL. Access service tokens are stored separately in Keychain and are bound to this hostname."
			: @"Enter an IP address, a local hostname, or a domain. Private networks such as WARP use Direct RDP.";
	if (section == 2) return @"The Remote Desktop password is stored in Keychain. An empty password field keeps the saved password.";
	if (section == 3) return @"Accept all certificates disables identity verification. At most one connection can open automatically.";
	return nil;
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
	else if (textField == _gatewayHostnameField)
		[_clientIDField becomeFirstResponder];
	else if (textField == _clientIDField)
		[_clientSecretField becomeFirstResponder];
	else if (textField == _clientSecretField)
		[_usernameField becomeFirstResponder];
	else if (textField == _portField)
		[_usernameField becomeFirstResponder];
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
	BOOL tunnel = [_transportControl selectedSegmentIndex] == 1;
	NSString *portText = [[_portField text] stringByTrimmingCharactersInSet:whitespace];
	NSInteger port = tunnel ? (NSInteger)[_profile port] : [portText integerValue];
	if (!tunnel && ([portText length] == 0 || [portText rangeOfCharacterFromSet:
		[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound))
		return [self showValidationError:@"Port must be a number between 1 and 65535."];
	NSDictionary *cloudflareToken = nil;
	NSString *gatewayHostname = [[_gatewayHostnameField text] stringByTrimmingCharactersInSet:whitespace];
	if (tunnel)
	{
		if ([gatewayHostname containsString:@"://"])
		{
			NSURLComponents *url = [NSURLComponents componentsWithString:gatewayHostname];
			if (![[[url scheme] lowercaseString] isEqualToString:@"https"] ||
			    [url user] || [url password] || [url port] || [url query] || [url fragment] ||
			    ([[url path] length] && ![[url path] isEqualToString:@"/"]))
				return [self showValidationError:@"Enter the tunnel HTTPS URL without a port, path, query, or credentials."];
			gatewayHostname = [url host];
		}
		NSError *error = nil;
		if (![OrbisTunnelBridge endpointForHostname:gatewayHostname error:&error])
			return [self showValidationError:[error localizedDescription]];
		NSString *clientID = [[_clientIDField text] stringByTrimmingCharactersInSet:whitespace];
		NSString *secret = [_clientSecretField text];
		BOOL preserved = [_savedTokenHost isEqualToString:[gatewayHostname lowercaseString]] &&
		    [_savedTokenClientID isEqualToString:clientID];
		if (![clientID length] || (![secret length] && !preserved))
			return [self showValidationError:@"Enter a Client ID and Client Secret for this tunnel hostname."];
		if ([secret length]) cloudflareToken = @{ @"clientID" : clientID, @"secret" : secret };
		host = [[_profile host] length] ? [_profile host] : gatewayHostname;
	}

	if ([name length] == 0)
		return [self showValidationError:@"Give this connection a name."];
	if ([host length] == 0)
		return [self showValidationError:@"Enter an IP address or hostname."];
	if ([host rangeOfString:@"://"].location != NSNotFound || [host containsString:@"/"] ||
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
	[_profile setTransportType:tunnel ? OrbisTransportTypeCloudflare : OrbisTransportTypeDirect];
	[_profile setTransportOptions:tunnel ? @{ @"hostname" : gatewayHostname } : @{}];
	[_profile setUsername:username];
	[_profile setAcceptAllCertificates:[_certificateSwitch isOn]];
	[_profile setConnectAutomatically:[_automaticSwitch isOn]];
	if (![_delegate profileEditor:self didSaveProfile:_profile password:[_passwordField text] cloudflareToken:cloudflareToken])
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
	[_accessCells release];
	[_accountCells release];
	[_transportControl release];
	[_gatewayHostnameField release];
	[_clientIDField release];
	[_clientSecretField release];
	[_savedTokenHost release];
	[_savedTokenClientID release];
	[super dealloc];
}

@end
