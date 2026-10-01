/* SPDX-License-Identifier: MIT */

#import "OrbisProfileEditorController.h"

#import "OrbisProfile.h"
#import "OrbisCredentialStore.h"
#import "OrbisTunnelBridge.h"

static NSTextField *OrbisEditorLabel(NSString *title)
{
	NSTextField *label = [NSTextField labelWithString:title];
	[label setFont:[NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium]];
	[label setTextColor:[NSColor secondaryLabelColor]];
	return label;
}

static void OrbisConfigureEditorField(NSTextField *field, NSString *identifier)
{
	[field setBezeled:YES];
	[field setBezelStyle:NSTextFieldRoundedBezel];
	[field setControlSize:NSControlSizeLarge];
	[field setFont:[NSFont systemFontOfSize:13.0]];
	[field setFocusRingType:NSFocusRingTypeExterior];
	[field setAccessibilityIdentifier:identifier];
}

static NSStackView *OrbisEditorFieldGroup(NSString *title, NSView *field)
{
	NSStackView *group = [NSStackView stackViewWithViews:@[ OrbisEditorLabel(title), field ]];
	[group setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[group setAlignment:NSLayoutAttributeLeading];
	[group setSpacing:6.0];
	[[field widthAnchor] constraintEqualToAnchor:[group widthAnchor]].active = YES;
	return group;
}

static NSView *OrbisEditorFlexibleSpacer(void)
{
	NSView *spacer = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
	[spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow
	                        forOrientation:NSLayoutConstraintOrientationHorizontal];
	[spacer setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
	                                      forOrientation:NSLayoutConstraintOrientationHorizontal];
	return spacer;
}

@implementation OrbisProfileEditorController

@synthesize delegate = _delegate;

- (id)initWithProfile:(OrbisProfile *)profile hasStoredPassword:(BOOL)hasStoredPassword
{
	NSWindow *window = [[[NSWindow alloc]
	    initWithContentRect:NSMakeRect(0.0, 0.0, 560.0, 610.0)
	              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
	                backing:NSBackingStoreBuffered
	                  defer:NO] autorelease];
	if (!(self = [super initWithWindow:window]))
		return nil;

	_profile = [profile copy];
	_hasStoredPassword = hasStoredPassword;
	[self buildContent];
	return self;
}

- (void)buildContent
{
	NSView *content = [[self window] contentView];
	[content setWantsLayer:YES];
	_scrollView = [[NSScrollView alloc] initWithFrame:[content bounds]];
	[_scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[_scrollView setHasVerticalScroller:YES];
	[_scrollView setDrawsBackground:NO];
	_formView = [[NSView alloc] initWithFrame:[content bounds]];
	[_scrollView setDocumentView:_formView];
	[content addSubview:_scrollView];

	NSTextField *title = [NSTextField labelWithString:
	    ([[_profile host] length] > 0 ? @"Edit connection" : @"New connection")];
	[title setFont:[NSFont systemFontOfSize:26.0 weight:NSFontWeightSemibold]];

	NSTextField *subtitle = [NSTextField labelWithString:@"A reusable Remote Desktop profile"];
	[subtitle setFont:[NSFont systemFontOfSize:13.0]];
	[subtitle setTextColor:[NSColor secondaryLabelColor]];

	_nameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[_nameField setPlaceholderString:@"e.g. Workstation"];
	[_nameField setStringValue:[_profile name] ?: @""];
	OrbisConfigureEditorField(_nameField, @"profile-name-field");

	_hostField = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[_hostField setPlaceholderString:@"IP address or hostname"];
	[_hostField setStringValue:[_profile host] ?: @""];
	OrbisConfigureEditorField(_hostField, @"profile-host-field");

	_portField = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[_portField setPlaceholderString:@"3389"];
	[_portField setStringValue:[NSString stringWithFormat:@"%lu", (unsigned long)[_profile port]]];
	OrbisConfigureEditorField(_portField, @"profile-port-field");

	_usernameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[_usernameField setPlaceholderString:@"Remote account"];
	[_usernameField setStringValue:[_profile username] ?: @""];
	OrbisConfigureEditorField(_usernameField, @"profile-username-field");

	_passwordField = [[NSSecureTextField alloc] initWithFrame:NSZeroRect];
	[_passwordField setPlaceholderString:(_hasStoredPassword ? @"••••••••" : @"Optional")];
	OrbisConfigureEditorField(_passwordField, @"profile-password-field");

	_transportField = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
	[_transportField addItemsWithTitles:@[ @"Direct RDP", @"Cloudflare Tunnel" ]];
	[_transportField selectItemAtIndex:[[_profile transportType] isEqualToString:OrbisTransportTypeCloudflare] ? 1 : 0];
	[_transportField setAccessibilityIdentifier:@"profile-transport-field"];
	[_transportField setTarget:self];
	[_transportField setAction:@selector(transportChanged:)];
	_gatewayHostnameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[_gatewayHostnameField setPlaceholderString:@"Defaults to the RDP host"];
	if ([[_profile transportType] isEqualToString:OrbisTransportTypeCloudflare])
		[_gatewayHostnameField setStringValue:[_profile transportHostname]];
	OrbisConfigureEditorField(_gatewayHostnameField, @"profile-gateway-hostname-field");
	_clientIDField = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[_clientIDField setPlaceholderString:@"Service Token Client ID"];
	OrbisConfigureEditorField(_clientIDField, @"profile-client-id-field");
	_clientSecretField = [[NSSecureTextField alloc] initWithFrame:NSZeroRect];
	OrbisConfigureEditorField(_clientSecretField, @"profile-client-secret-field");
	NSDictionary *token = [OrbisCredentialStore cloudflareTokenForProfile:_profile error:nil];
	_savedTokenHost = token ? [[[_profile transportHostname] lowercaseString] copy] : nil;
	_savedTokenClientID = [token[@"clientID"] copy];
	[_clientIDField setStringValue:_savedTokenClientID ?: @""];
	[_clientSecretField setPlaceholderString:token ? @"Saved in Keychain" : @"Service Token Client Secret"];

	_certificateCheckbox = [[NSButton alloc] initWithFrame:NSZeroRect];
	[_certificateCheckbox setButtonType:NSButtonTypeSwitch];
	[_certificateCheckbox setTitle:@"Accept this server’s certificate automatically"];
	[_certificateCheckbox setState:[_profile acceptAllCertificates] ? NSControlStateValueOn
	                                                                   : NSControlStateValueOff];

	_automaticCheckbox = [[NSButton alloc] initWithFrame:NSZeroRect];
	[_automaticCheckbox setButtonType:NSButtonTypeSwitch];
	[_automaticCheckbox setTitle:@"Connect automatically when Orbis opens"];
	[_automaticCheckbox setState:[_profile connectAutomatically] ? NSControlStateValueOn
	                                                                  : NSControlStateValueOff];

	_validationLabel = [[NSTextField labelWithString:@""] retain];
	[_validationLabel setTextColor:[NSColor systemRedColor]];
	[_validationLabel setFont:[NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium]];
	[_validationLabel setHidden:YES];

	NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
	[cancel setBezelStyle:NSBezelStyleRounded];
	[cancel setControlSize:NSControlSizeLarge];
	NSButton *save = [NSButton buttonWithTitle:@"Save connection" target:self action:@selector(save:)];
	[save setBezelStyle:NSBezelStyleRounded];
	[save setControlSize:NSControlSizeLarge];
	[save setContentTintColor:[NSColor systemTealColor]];
	[save setKeyEquivalent:@"\r"];

	NSStackView *buttons = [NSStackView stackViewWithViews:@[
		OrbisEditorFlexibleSpacer(), cancel, save
	]];
	[buttons setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
	[buttons setAlignment:NSLayoutAttributeCenterY];
	[buttons setSpacing:10.0];
	[[cancel widthAnchor] constraintGreaterThanOrEqualToConstant:100.0].active = YES;
	[[save widthAnchor] constraintGreaterThanOrEqualToConstant:150.0].active = YES;

	NSStackView *header = [NSStackView stackViewWithViews:@[ title, subtitle ]];
	[header setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[header setAlignment:NSLayoutAttributeLeading];
	[header setSpacing:3.0];

	NSStackView *nameGroup = OrbisEditorFieldGroup(@"Name", _nameField);
	NSStackView *hostGroup = OrbisEditorFieldGroup(@"Host", _hostField);
	_portGroup = [OrbisEditorFieldGroup(@"Port", _portField) retain];
	NSStackView *usernameGroup = OrbisEditorFieldGroup(@"Username", _usernameField);
	NSStackView *passwordGroup = OrbisEditorFieldGroup(@"Password", _passwordField);
	NSStackView *transportGroup = OrbisEditorFieldGroup(@"Connection", _transportField);
	_gatewayHostnameGroup = [OrbisEditorFieldGroup(@"Tunnel hostname", _gatewayHostnameField) retain];
	_clientIDGroup = [OrbisEditorFieldGroup(@"CF-Access-Client-Id", _clientIDField) retain];
	_clientSecretGroup = [OrbisEditorFieldGroup(@"CF-Access-Client-Secret", _clientSecretField) retain];

	NSStackView *options = [NSStackView stackViewWithViews:@[
		_certificateCheckbox, _automaticCheckbox
	]];
	[options setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[options setAlignment:NSLayoutAttributeLeading];
	[options setSpacing:8.0];
	[options setEdgeInsets:NSEdgeInsetsMake(12.0, 14.0, 12.0, 14.0)];
	[options setWantsLayer:YES];
	[options.layer setCornerRadius:12.0];
	[options.layer setBackgroundColor:[[NSColor tertiarySystemFillColor] CGColor]];

	NSStackView *stack = [NSStackView stackViewWithViews:@[
		header, nameGroup, transportGroup, hostGroup, _portGroup, _gatewayHostnameGroup, _clientIDGroup, _clientSecretGroup,
		usernameGroup, passwordGroup, options,
		_validationLabel, buttons
	]];
	_formStack = [stack retain];
	[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[stack setAlignment:NSLayoutAttributeLeading];
	[stack setSpacing:14.0];
	[stack setTranslatesAutoresizingMaskIntoConstraints:NO];
	[_formView addSubview:stack];

	for (NSView *view in @[ header, nameGroup, transportGroup, hostGroup, _portGroup, _gatewayHostnameGroup, _clientIDGroup,
	                          _clientSecretGroup, usernameGroup, passwordGroup,
	                          options, _validationLabel, buttons ])
		[[view widthAnchor] constraintEqualToAnchor:[stack widthAnchor]].active = YES;
	for (NSView *field in @[ _nameField, _hostField, _portField, _usernameField, _passwordField,
	                         _transportField, _gatewayHostnameField, _clientIDField, _clientSecretField ])
		[[field heightAnchor] constraintEqualToConstant:36.0].active = YES;
	[[buttons heightAnchor] constraintEqualToConstant:38.0].active = YES;
	[NSLayoutConstraint activateConstraints:@[
		[[stack leadingAnchor] constraintEqualToAnchor:[_formView leadingAnchor] constant:36.0],
		[[stack trailingAnchor] constraintEqualToAnchor:[_formView trailingAnchor] constant:-36.0],
		[[stack topAnchor] constraintEqualToAnchor:[_formView topAnchor] constant:30.0]
	]];
	[self transportChanged:nil];
}

- (void)transportChanged:(id)sender
{
	(void)sender;
	BOOL tunnel = [_transportField indexOfSelectedItem] == 1;
	[_gatewayHostnameGroup setHidden:!tunnel];
	[_clientIDGroup setHidden:!tunnel];
	[_clientSecretGroup setHidden:!tunnel];
	[_portGroup setHidden:tunnel];
	[_hostField setPlaceholderString:@"IP address or hostname"];
	[_formView layoutSubtreeIfNeeded];
	CGFloat height = MAX(NSHeight([_scrollView contentView].bounds), [_formStack fittingSize].height + 60.0);
	[_formView setFrameSize:NSMakeSize(NSWidth([_scrollView contentView].bounds), height)];
	[[_scrollView contentView] scrollToPoint:NSMakePoint(0, height - NSHeight([_scrollView contentView].bounds))];
	[_scrollView reflectScrolledClipView:[_scrollView contentView]];
}

- (void)beginSheetForWindow:(NSWindow *)parentWindow
{
	[parentWindow beginSheet:[self window] completionHandler:nil];
	[[self window] makeFirstResponder:_nameField];
}

- (void)cancel:(id)sender
{
	(void)sender;
	[[[self window] sheetParent] endSheet:[self window]];
}

- (void)save:(id)sender
{
	(void)sender;
	NSString *name = [[_nameField stringValue]
	    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *host = [[_hostField stringValue]
	    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	BOOL tunnel = [_transportField indexOfSelectedItem] == 1;
	NSInteger port = tunnel ? (NSInteger)[_profile port] : [_portField integerValue];
	if ([name length] == 0 || [host length] == 0 || port < 1 || port > 65535)
	{
		[_validationLabel setStringValue:@"Name, host, and a valid port are required."];
		[_validationLabel setHidden:NO];
		return;
	}
	NSString *gatewayHostname = [[_gatewayHostnameField stringValue] stringByTrimmingCharactersInSet:
	    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (![gatewayHostname length])
		gatewayHostname = host;
	NSDictionary *cloudflareToken = nil;
	if (tunnel)
	{
		NSError *endpointError = nil;
		if (![OrbisTunnelBridge endpointForHostname:gatewayHostname error:&endpointError])
		{
			[_validationLabel setStringValue:[endpointError localizedDescription]];
			[_validationLabel setHidden:NO];
			return;
		}
		NSString *clientID = [[_clientIDField stringValue] stringByTrimmingCharactersInSet:
		    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
		NSString *secret = [_clientSecretField stringValue];
		BOOL preserved = [_savedTokenHost isEqualToString:[gatewayHostname lowercaseString]] &&
		                 [_savedTokenClientID isEqualToString:clientID];
		if (![clientID length] || (![secret length] && !preserved))
		{
			[_validationLabel setStringValue:@"Enter CF-Access-Client-Id and CF-Access-Client-Secret for this tunnel hostname."];
			[_validationLabel setHidden:NO];
			return;
		}
		if ([secret length])
			cloudflareToken = @{ @"clientID" : clientID, @"secret" : secret };
	}

	[_profile setName:name];
	[_profile setHost:host];
	[_profile setPort:(NSUInteger)port];
	[_profile setTransportType:tunnel ? OrbisTransportTypeCloudflare : OrbisTransportTypeDirect];
	[_profile setTransportOptions:tunnel ? @{ @"hostname" : gatewayHostname } : @{}];
	[_profile setUsername:[[_usernameField stringValue]
	                          stringByTrimmingCharactersInSet:
	                              [NSCharacterSet whitespaceAndNewlineCharacterSet]]];
	[_profile setAcceptAllCertificates:[_certificateCheckbox state] == NSControlStateValueOn];
	[_profile setConnectAutomatically:[_automaticCheckbox state] == NSControlStateValueOn];

	NSString *password = [_passwordField stringValue];
	if ([password length] == 0)
		password = nil;
	if (![_delegate profileEditorController:self savedProfile:_profile password:password
	                          cloudflareToken:cloudflareToken])
		return;
	[[[self window] sheetParent] endSheet:[self window]];
}

- (void)dealloc
{
	_delegate = nil;
	[_profile release];
	[_nameField release];
	[_hostField release];
	[_transportField release];
	[_gatewayHostnameField release];
	[_gatewayHostnameGroup release];
	[_clientIDField release];
	[_clientSecretField release];
	[_clientIDGroup release];
	[_clientSecretGroup release];
	[_portGroup release];
	[_formStack release];
	[_formView release];
	[_scrollView release];
	[_savedTokenHost release];
	[_savedTokenClientID release];
	[_portField release];
	[_usernameField release];
	[_passwordField release];
	[_certificateCheckbox release];
	[_automaticCheckbox release];
	[_validationLabel release];
	[super dealloc];
}

@end
