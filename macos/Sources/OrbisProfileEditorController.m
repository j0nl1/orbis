/* SPDX-License-Identifier: MIT */

#import "OrbisProfileEditorController.h"

#import "OrbisProfile.h"
#import "OrbisCredentialStore.h"
#import "OrbisTunnelBridge.h"

static NSRect OrbisCenteredTextRect(NSRect rect, NSFont *font)
{
	CGFloat height = ceil([font ascender] - [font descender] + [font leading]);
	if (NSHeight(rect) > height)
	{
		rect.origin.y += floor((NSHeight(rect) - height) / 2.0);
		rect.size.height = height;
	}
	return rect;
}

@interface OrbisCenteredTextFieldCell : NSTextFieldCell
@end
@implementation OrbisCenteredTextFieldCell
- (NSRect)drawingRectForBounds:(NSRect)bounds
{
	return OrbisCenteredTextRect([super drawingRectForBounds:bounds], [self font]);
}
@end

@interface OrbisCenteredSecureTextFieldCell : NSSecureTextFieldCell
@end
@implementation OrbisCenteredSecureTextFieldCell
- (NSRect)drawingRectForBounds:(NSRect)bounds
{
	return OrbisCenteredTextRect([super drawingRectForBounds:bounds], [self font]);
}
@end

static NSTextField *OrbisEditorLabel(NSString *title)
{
	NSTextField *label = [NSTextField labelWithString:title];
	[label setFont:[NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium]];
	[label setTextColor:[NSColor secondaryLabelColor]];
	return label;
}

static void OrbisConfigureEditorField(NSTextField *field, NSString *identifier)
{
	Class cellClass = [field isKindOfClass:[NSSecureTextField class]]
	    ? [OrbisCenteredSecureTextFieldCell class] : [OrbisCenteredTextFieldCell class];
	NSTextFieldCell *cell = [[[cellClass alloc] initTextCell:[field stringValue]] autorelease];
	NSTextFieldCell *originalCell = [field cell];
	[cell setPlaceholderString:[originalCell placeholderString]];
	[cell setEditable:[originalCell isEditable]];
	[cell setSelectable:[originalCell isSelectable]];
	[cell setScrollable:[originalCell isScrollable]];
	[cell setUsesSingleLineMode:[originalCell usesSingleLineMode]];
	[cell setDrawsBackground:[originalCell drawsBackground]];
	[cell setBackgroundColor:[originalCell backgroundColor]];
	[cell setTextColor:[originalCell textColor]];
	[field setCell:cell];
	[field setBezeled:YES];
	[field setBezelStyle:NSTextFieldRoundedBezel];
	[field setControlSize:NSControlSizeLarge];
	[field setFont:[NSFont systemFontOfSize:13.0]];
	[field setFocusRingType:NSFocusRingTypeExterior];
	[field setAccessibilityIdentifier:identifier];
}

static NSStackView *OrbisEditorFieldGroup(NSString *title, NSView *field)
{
	[field setAccessibilityLabel:title];
	NSStackView *group = [NSStackView stackViewWithViews:@[ OrbisEditorLabel(title), field ]];
	[group setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[group setAlignment:NSLayoutAttributeLeading];
	[group setSpacing:6.0];
	[[field widthAnchor] constraintEqualToAnchor:[group widthAnchor]].active = YES;
	return group;
}

static NSStackView *OrbisEditorSection(NSString *title, NSArray *views)
{
	NSTextField *heading = [NSTextField labelWithString:title];
	[heading setFont:[NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold]];
	NSStackView *section = [NSStackView stackViewWithViews:[@[ heading ] arrayByAddingObjectsFromArray:views]];
	[section setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[section setAlignment:NSLayoutAttributeLeading];
	[section setSpacing:10.0];
	for (NSView *view in views)
		[[view widthAnchor] constraintEqualToAnchor:[section widthAnchor]].active = YES;
	return section;
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
	    initWithContentRect:NSMakeRect(0.0, 0.0, 620.0, 640.0)
	              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
	                backing:NSBackingStoreBuffered
	                  defer:NO] autorelease];
	if (!(self = [super initWithWindow:window]))
		return nil;

	_profile = [profile copy];
	_hasStoredPassword = hasStoredPassword;
	[window setTitle:[[_profile host] length] > 0 ? @"Edit connection" : @"New connection"];
	[window setDelegate:self];
	[self buildContent];
	return self;
}

- (void)buildContent
{
	NSView *content = [[self window] contentView];
	[content setWantsLayer:YES];
	_scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	[_scrollView setTranslatesAutoresizingMaskIntoConstraints:NO];
	[_scrollView setHasVerticalScroller:YES];
	[_scrollView setAutohidesScrollers:YES];
	[_scrollView setBorderType:NSNoBorder];
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
	[_transportField addItemsWithTitles:@[ @"Native RDP", @"Cloudflare Tunnel" ]];
	[_transportField setControlSize:NSControlSizeLarge];
	[_transportField selectItemAtIndex:[[_profile transportType] isEqualToString:OrbisTransportTypeCloudflare] ? 1 : 0];
	[_transportField setAccessibilityIdentifier:@"profile-transport-field"];
	[_transportField setTarget:self];
	[_transportField setAction:@selector(transportChanged:)];
	_gatewayHostnameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[_gatewayHostnameField setPlaceholderString:@"https://rdp.example.com"];
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

	_validationLabel = [[NSTextField wrappingLabelWithString:@""] retain];
	[_validationLabel setTextColor:[NSColor systemRedColor]];
	[_validationLabel setFont:[NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium]];
	[_validationLabel setHidden:YES];

	NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
	[cancel setBezelStyle:NSBezelStyleRounded];
	[cancel setControlSize:NSControlSizeLarge];
	[cancel setKeyEquivalent:@"\033"];
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
	[[save widthAnchor] constraintGreaterThanOrEqualToConstant:160.0].active = YES;

	NSStackView *header = [NSStackView stackViewWithViews:@[ title, subtitle ]];
	[header setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[header setAlignment:NSLayoutAttributeLeading];
	[header setSpacing:3.0];

	NSStackView *nameGroup = OrbisEditorFieldGroup(@"Name", _nameField);
	_hostGroup = [OrbisEditorFieldGroup(@"IP address or hostname", _hostField) retain];
	_portGroup = [OrbisEditorFieldGroup(@"Port", _portField) retain];
	NSStackView *usernameGroup = OrbisEditorFieldGroup(@"Username", _usernameField);
	NSStackView *passwordGroup = OrbisEditorFieldGroup(@"Password", _passwordField);
	NSStackView *transportGroup = OrbisEditorFieldGroup(@"Connection type", _transportField);
	_gatewayHostnameGroup = [OrbisEditorFieldGroup(@"Tunnel URL", _gatewayHostnameField) retain];
	_clientIDGroup = [OrbisEditorFieldGroup(@"CF-Access-Client-Id", _clientIDField) retain];
	_clientSecretGroup = [OrbisEditorFieldGroup(@"CF-Access-Client-Secret", _clientSecretField) retain];
	_endpointGroup = [[NSStackView stackViewWithViews:@[ _hostGroup, _portGroup ]] retain];
	[_endpointGroup setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
	[_endpointGroup setAlignment:NSLayoutAttributeTop];
	[_endpointGroup setSpacing:14.0];
	[[_portGroup widthAnchor] constraintEqualToConstant:100.0].active = YES;
	[_hostGroup setContentHuggingPriority:NSLayoutPriorityDefaultLow
	                     forOrientation:NSLayoutConstraintOrientationHorizontal];
	_accessGroup = [OrbisEditorSection(@"Cloudflare Access", @[ _clientIDGroup, _clientSecretGroup ]) retain];
	NSStackView *accountFields = [NSStackView stackViewWithViews:@[ usernameGroup, passwordGroup ]];
	[accountFields setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
	[accountFields setAlignment:NSLayoutAttributeTop];
	[accountFields setDistribution:NSStackViewDistributionFillEqually];
	[accountFields setSpacing:14.0];
	NSStackView *account = OrbisEditorSection(@"Remote Desktop account", @[ accountFields ]);

	NSStackView *options = [NSStackView stackViewWithViews:@[
		_certificateCheckbox, _automaticCheckbox
	]];
	[options setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[options setAlignment:NSLayoutAttributeLeading];
	[options setSpacing:8.0];
	NSView *primaryResolution = [self resolutionGroupWithTitle:@"Primary display resolution"
	    width:[_profile primaryWidth] height:[_profile primaryHeight]
	    mode:&_primaryResolutionMode widthField:&_primaryWidthField heightField:&_primaryHeightField];
	NSView *secondaryResolution = [self resolutionGroupWithTitle:@"Second display resolution"
	    width:[_profile secondaryWidth] height:[_profile secondaryHeight]
	    mode:&_secondaryResolutionMode widthField:&_secondaryWidthField heightField:&_secondaryHeightField];
	_monitorArrangementField = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
	[_monitorArrangementField addItemsWithTitles:@[ @"Right of primary", @"Left of primary", @"Above primary", @"Below primary" ]];
	[_monitorArrangementField selectItemAtIndex:[_profile monitorArrangement]];
	[_monitorArrangementField setAccessibilityIdentifier:@"profile-monitor-arrangement"];
	NSView *arrangement = OrbisEditorFieldGroup(@"Monitor arrangement", _monitorArrangementField);
	NSTextField *displayHint = [NSTextField wrappingLabelWithString:
	    @"Start with one display. Add a virtual second display from Session → Add Virtual Display. Manual resolutions use pixels; resizing a window scales its display."];
	[displayHint setFont:[NSFont systemFontOfSize:12.0]];
	[displayHint setTextColor:[NSColor secondaryLabelColor]];
	NSStackView *preferences = OrbisEditorSection(@"Options", @[ options, primaryResolution, secondaryResolution, arrangement, displayHint ]);

	NSStackView *stack = [NSStackView stackViewWithViews:@[
		header, nameGroup, transportGroup, _endpointGroup, _gatewayHostnameGroup, _accessGroup,
		account, preferences, _validationLabel
	]];
	_formStack = [stack retain];
	[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[stack setAlignment:NSLayoutAttributeLeading];
	[stack setSpacing:18.0];
	[stack setCustomSpacing:24.0 afterView:header];
	[stack setTranslatesAutoresizingMaskIntoConstraints:NO];
	[_formView addSubview:stack];

	for (NSView *view in @[ header, nameGroup, transportGroup, _endpointGroup, _gatewayHostnameGroup,
	                          _accessGroup, account, preferences, _validationLabel ])
		[[view widthAnchor] constraintEqualToAnchor:[stack widthAnchor]].active = YES;
	for (NSView *field in @[ _nameField, _hostField, _portField, _usernameField, _passwordField,
	                         _transportField, _gatewayHostnameField, _clientIDField, _clientSecretField ])
		[[field heightAnchor] constraintEqualToConstant:36.0].active = YES;
	[[buttons heightAnchor] constraintEqualToConstant:38.0].active = YES;
	[buttons setTranslatesAutoresizingMaskIntoConstraints:NO];
	[content addSubview:buttons];
	NSBox *divider = [[[NSBox alloc] initWithFrame:NSZeroRect] autorelease];
	[divider setBoxType:NSBoxSeparator];
	[divider setTranslatesAutoresizingMaskIntoConstraints:NO];
	[content addSubview:divider];
	[NSLayoutConstraint activateConstraints:@[
		[[_scrollView leadingAnchor] constraintEqualToAnchor:[content leadingAnchor]],
		[[_scrollView trailingAnchor] constraintEqualToAnchor:[content trailingAnchor]],
		[[_scrollView topAnchor] constraintEqualToAnchor:[content topAnchor]],
		[[_scrollView bottomAnchor] constraintEqualToAnchor:[divider topAnchor] constant:-12.0],
		[[divider leadingAnchor] constraintEqualToAnchor:[content leadingAnchor]],
		[[divider trailingAnchor] constraintEqualToAnchor:[content trailingAnchor]],
		[[divider bottomAnchor] constraintEqualToAnchor:[buttons topAnchor] constant:-14.0],
		[[buttons leadingAnchor] constraintEqualToAnchor:[content leadingAnchor] constant:36.0],
		[[buttons trailingAnchor] constraintEqualToAnchor:[content trailingAnchor] constant:-36.0],
		[[buttons bottomAnchor] constraintEqualToAnchor:[content bottomAnchor] constant:-20.0],
		[[stack leadingAnchor] constraintEqualToAnchor:[_formView leadingAnchor] constant:36.0],
		[[stack trailingAnchor] constraintEqualToAnchor:[_formView trailingAnchor] constant:-36.0],
		[[stack topAnchor] constraintEqualToAnchor:[_formView topAnchor] constant:30.0]
	]];
	[self transportChanged:nil];
}

- (NSView *)resolutionGroupWithTitle:(NSString *)title width:(NSUInteger)width height:(NSUInteger)height
                               mode:(NSPopUpButton **)mode widthField:(NSTextField **)widthField
                        heightField:(NSTextField **)heightField
{
	*mode = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
	[*mode addItemsWithTitles:@[ @"Automatic", @"Manual" ]];
	[*mode selectItemAtIndex:width ? 1 : 0];
	[*mode setTarget:self]; [*mode setAction:@selector(resolutionModeChanged:)];
	NSString *prefix = [title hasPrefix:@"Primary"] ? @"primary" : @"secondary";
	[*mode setAccessibilityIdentifier:[NSString stringWithFormat:@"profile-%@-resolution-mode", prefix]];
	*widthField = [[NSTextField alloc] initWithFrame:NSZeroRect];
	*heightField = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[*widthField setStringValue:[NSString stringWithFormat:@"%lu", (unsigned long)(width ?: 1920)]];
	[*heightField setStringValue:[NSString stringWithFormat:@"%lu", (unsigned long)(height ?: 1080)]];
	OrbisConfigureEditorField(*widthField, [NSString stringWithFormat:@"profile-%@-width", prefix]);
	OrbisConfigureEditorField(*heightField, [NSString stringWithFormat:@"profile-%@-height", prefix]);
	[*widthField setAccessibilityLabel:@"Width in pixels"];
	[*heightField setAccessibilityLabel:@"Height in pixels"];
	[*widthField setEnabled:width != 0]; [*heightField setEnabled:width != 0];
	NSStackView *row = [NSStackView stackViewWithViews:@[ *mode, *widthField, [NSTextField labelWithString:@"×"], *heightField ]];
	[row setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
	[row setAlignment:NSLayoutAttributeCenterY]; [row setSpacing:8.0];
	[[*mode widthAnchor] constraintEqualToConstant:160.0].active = YES;
	for (NSView *field in @[ *widthField, *heightField ])
	{
		[[field widthAnchor] constraintEqualToConstant:110.0].active = YES;
		[[field heightAnchor] constraintEqualToConstant:36.0].active = YES;
	}
	return OrbisEditorFieldGroup(title, row);
}

- (void)resolutionModeChanged:(id)sender
{
	(void)sender;
	[_primaryWidthField setEnabled:[_primaryResolutionMode indexOfSelectedItem] == 1];
	[_primaryHeightField setEnabled:[_primaryResolutionMode indexOfSelectedItem] == 1];
	[_secondaryWidthField setEnabled:[_secondaryResolutionMode indexOfSelectedItem] == 1];
	[_secondaryHeightField setEnabled:[_secondaryResolutionMode indexOfSelectedItem] == 1];
}

- (BOOL)readResolutionMode:(NSPopUpButton *)mode widthField:(NSTextField *)widthField
               heightField:(NSTextField *)heightField width:(NSUInteger *)width height:(NSUInteger *)height
{
	*width = *height = 0;
	if ([mode indexOfSelectedItem] == 0) return YES;
	NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
	NSString *w = [widthField stringValue], *h = [heightField stringValue];
	if (!w.length || !h.length || [w rangeOfCharacterFromSet:invalid].location != NSNotFound ||
	    [h rangeOfCharacterFromSet:invalid].location != NSNotFound || w.length > 4 || h.length > 4)
		return NO;
	*width = w.integerValue; *height = h.integerValue;
	return OrbisDisplayResolutionIsValid((uint32_t)*width, (uint32_t)*height);
}

- (void)transportChanged:(id)sender
{
	(void)sender;
	BOOL tunnel = [_transportField indexOfSelectedItem] == 1;
	[[self window] setContentSize:NSMakeSize(620.0, tunnel ? 780.0 : 640.0)];
	[_endpointGroup setHidden:tunnel];
	[_accessGroup setHidden:!tunnel];
	[_hostGroup setHidden:tunnel];
	[_gatewayHostnameGroup setHidden:!tunnel];
	[_clientIDGroup setHidden:!tunnel];
	[_clientSecretGroup setHidden:!tunnel];
	[_portGroup setHidden:tunnel];
	[_hostField setPlaceholderString:@"IP address or hostname"];
	[_validationLabel setHidden:YES];
	[self updateFormLayout];
}

- (void)updateFormLayout
{
	[[[self window] contentView] layoutSubtreeIfNeeded];
	[_formView layoutSubtreeIfNeeded];
	CGFloat height = MAX(NSHeight([_scrollView contentView].bounds), [_formStack fittingSize].height + 60.0);
	[_formView setFrameSize:NSMakeSize(NSWidth([_scrollView contentView].bounds), height)];
	[[_scrollView contentView] scrollToPoint:NSMakePoint(0, height - NSHeight([_scrollView contentView].bounds))];
	[_scrollView reflectScrolledClipView:[_scrollView contentView]];
}

- (void)showValidationError:(NSString *)message
{
	[_validationLabel setStringValue:message];
	[_validationLabel setHidden:NO];
	[self updateFormLayout];
	[_validationLabel scrollRectToVisible:[_validationLabel bounds]];
}

- (void)beginSheetForWindow:(NSWindow *)parentWindow
{
	[parentWindow beginSheet:[self window] completionHandler:^(NSModalResponse response) {
		(void)response;
		[[self window] orderOut:nil];
		[_delegate profileEditorControllerDidFinish:self];
	}];
	[[self window] makeFirstResponder:_nameField];
}

- (void)cancel:(id)sender
{
	(void)sender;
	[[[self window] sheetParent] endSheet:[self window]];
}

- (BOOL)windowShouldClose:(NSWindow *)sender
{
	(void)sender;
	[self cancel:nil];
	return NO;
}

- (void)cancelOperation:(id)sender
{
	[self cancel:sender];
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
	if ([name length] == 0 || (!tunnel && [host length] == 0) || port < 1 || port > 65535)
	{
		[self showValidationError:tunnel ? @"Give this connection a name."
		                                  : @"Name, host, and a valid port are required."];
		return;
	}
	NSString *gatewayHostname = [[_gatewayHostnameField stringValue] stringByTrimmingCharactersInSet:
	    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSDictionary *cloudflareToken = nil;
	if (tunnel)
	{
		NSError *endpointError = nil;
		if ([gatewayHostname containsString:@"://"])
		{
			NSURLComponents *url = [NSURLComponents componentsWithString:gatewayHostname];
			if (![[[url scheme] lowercaseString] isEqualToString:@"https"] ||
			    [url user] || [url password] || [url port] || [url query] || [url fragment] ||
			    ([[url path] length] > 0 && ![[url path] isEqualToString:@"/"]))
			{
				[self showValidationError:@"Enter the tunnel’s HTTPS URL without a port, path, query, or credentials."];
				return;
			}
			gatewayHostname = [url host];
		}
		if (![OrbisTunnelBridge endpointForHostname:gatewayHostname error:&endpointError])
		{
			[self showValidationError:[endpointError localizedDescription]];
			return;
		}
		NSString *clientID = [[_clientIDField stringValue] stringByTrimmingCharactersInSet:
		    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
		NSString *secret = [_clientSecretField stringValue];
		BOOL preserved = [_savedTokenHost isEqualToString:[gatewayHostname lowercaseString]] &&
		                 [_savedTokenClientID isEqualToString:clientID];
		if (![clientID length] || (![secret length] && !preserved))
		{
			[self showValidationError:@"Enter CF-Access-Client-Id and CF-Access-Client-Secret for this tunnel hostname."];
			return;
		}
		if ([secret length])
			cloudflareToken = @{ @"clientID" : clientID, @"secret" : secret };
		// Keep existing RDP identity separate from the public tunnel address.
		host = [[_profile host] length] > 0 ? [_profile host] : gatewayHostname;
	}
	else if ([host containsString:@"://"] || [host containsString:@"/"] ||
	         [host rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound)
	{
		[self showValidationError:@"Enter an IP address or hostname without a URL or spaces."];
		return;
	}

	NSUInteger pw, ph, sw, sh;
	if (![self readResolutionMode:_primaryResolutionMode widthField:_primaryWidthField
	    heightField:_primaryHeightField width:&pw height:&ph] ||
	    ![self readResolutionMode:_secondaryResolutionMode widthField:_secondaryWidthField
	    heightField:_secondaryHeightField width:&sw height:&sh])
	{
		[self showValidationError:@"Use resolutions from 200 to 8192 pixels, with an even width."];
		return;
	}
	[_profile setPrimaryWidth:pw]; [_profile setPrimaryHeight:ph];
	[_profile setSecondaryWidth:sw]; [_profile setSecondaryHeight:sh];
	[_profile setMonitorArrangement:(OrbisMonitorArrangement)[_monitorArrangementField indexOfSelectedItem]];
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
	[[self window] setDelegate:nil];
	[_profile release];
	[_nameField release];
	[_hostField release];
	[_hostGroup release];
	[_transportField release];
	[_gatewayHostnameField release];
	[_gatewayHostnameGroup release];
	[_clientIDField release];
	[_clientSecretField release];
	[_clientIDGroup release];
	[_clientSecretGroup release];
	[_portGroup release];
	[_endpointGroup release];
	[_accessGroup release];
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
	[_primaryResolutionMode release]; [_secondaryResolutionMode release]; [_monitorArrangementField release];
	[_primaryWidthField release]; [_primaryHeightField release];
	[_secondaryWidthField release]; [_secondaryHeightField release];
	[_validationLabel release];
	[super dealloc];
}

@end
