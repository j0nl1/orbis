/* SPDX-License-Identifier: MIT */

#import "OrbisProfileEditorController.h"

#import "OrbisProfile.h"

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

static NSStackView *OrbisEditorFieldGroup(NSString *title, NSTextField *field)
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
	NSStackView *portGroup = OrbisEditorFieldGroup(@"Port", _portField);
	NSStackView *usernameGroup = OrbisEditorFieldGroup(@"Username", _usernameField);
	NSStackView *passwordGroup = OrbisEditorFieldGroup(@"Password", _passwordField);

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
		header, nameGroup, hostGroup, portGroup, usernameGroup, passwordGroup, options,
		_validationLabel, buttons
	]];
	[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[stack setAlignment:NSLayoutAttributeLeading];
	[stack setSpacing:14.0];
	[stack setTranslatesAutoresizingMaskIntoConstraints:NO];
	[content addSubview:stack];

	for (NSView *view in @[ header, nameGroup, hostGroup, portGroup, usernameGroup, passwordGroup,
	                          options, _validationLabel, buttons ])
		[[view widthAnchor] constraintEqualToAnchor:[stack widthAnchor]].active = YES;
	for (NSTextField *field in @[ _nameField, _hostField, _portField, _usernameField, _passwordField ])
		[[field heightAnchor] constraintEqualToConstant:36.0].active = YES;
	[[buttons heightAnchor] constraintEqualToConstant:38.0].active = YES;
	[NSLayoutConstraint activateConstraints:@[
		[[stack leadingAnchor] constraintEqualToAnchor:[content leadingAnchor] constant:36.0],
		[[stack trailingAnchor] constraintEqualToAnchor:[content trailingAnchor] constant:-36.0],
		[[stack topAnchor] constraintEqualToAnchor:[content topAnchor] constant:30.0],
		[[stack bottomAnchor] constraintLessThanOrEqualToAnchor:[content bottomAnchor] constant:-30.0]
	]];
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
	NSInteger port = [_portField integerValue];
	if ([name length] == 0 || [host length] == 0 || port < 1 || port > 65535)
	{
		[_validationLabel setStringValue:@"Name, host, and a valid port are required."];
		[_validationLabel setHidden:NO];
		return;
	}

	[_profile setName:name];
	[_profile setHost:host];
	[_profile setPort:(NSUInteger)port];
	[_profile setUsername:[[_usernameField stringValue]
	                          stringByTrimmingCharactersInSet:
	                              [NSCharacterSet whitespaceAndNewlineCharacterSet]]];
	[_profile setAcceptAllCertificates:[_certificateCheckbox state] == NSControlStateValueOn];
	[_profile setConnectAutomatically:[_automaticCheckbox state] == NSControlStateValueOn];

	NSString *password = [_passwordField stringValue];
	if ([password length] == 0)
		password = nil;
	[_delegate profileEditorController:self savedProfile:_profile password:password];
	[[[self window] sheetParent] endSheet:[self window]];
}

- (void)dealloc
{
	_delegate = nil;
	[_profile release];
	[_nameField release];
	[_hostField release];
	[_portField release];
	[_usernameField release];
	[_passwordField release];
	[_certificateCheckbox release];
	[_automaticCheckbox release];
	[_validationLabel release];
	[super dealloc];
}

@end
