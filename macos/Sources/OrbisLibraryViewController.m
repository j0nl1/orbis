/* SPDX-License-Identifier: MIT */

#import "OrbisLibraryViewController.h"

#import <QuartzCore/QuartzCore.h>

#import "OrbisCredentialStore.h"
#import "OrbisAboutController.h"
#import "OrbisProfile.h"
#import "OrbisProfileEditorController.h"

static NSButton *OrbisSymbolButton(NSString *symbol, NSString *toolTip, id target, SEL action)
{
	NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:toolTip];
	NSButton *button = [NSButton buttonWithImage:image target:target action:action];
	[button setBezelStyle:NSBezelStyleCircular];
	[button setToolTip:toolTip];
	[button setImagePosition:NSImageOnly];
	return button;
}

static NSView *OrbisFlexibleSpacer(void)
{
	NSView *spacer = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
	[spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow
	                        forOrientation:NSLayoutConstraintOrientationHorizontal];
	[spacer setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
	                                      forOrientation:NSLayoutConstraintOrientationHorizontal];
	return spacer;
}

static void OrbisConfigureWarningAlert(NSAlert *alert)
{
	[alert setAlertStyle:NSAlertStyleWarning];
	NSImage *warning = [NSImage imageNamed:NSImageNameCaution];
	if (warning)
		[alert setIcon:warning];
}

@interface OrbisLibraryViewController () <OrbisProfileEditorControllerDelegate>
@end

@implementation OrbisLibraryViewController

@synthesize delegate = _delegate;
@synthesize profileStore = _profileStore;

- (id)init
{
	if (!(self = [super init]))
		return nil;
	_profileStore = [[OrbisProfileStore alloc] init];
	return self;
}

- (void)loadView
{
	NSView *root = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 980.0, 680.0)] autorelease];
	[root setWantsLayer:YES];
	[root.layer setBackgroundColor:[[NSColor windowBackgroundColor] CGColor]];
	[self setView:root];

	NSTextField *title = [NSTextField labelWithString:@"Orbis"];
	[title setFont:[NSFont systemFontOfSize:32.0 weight:NSFontWeightSemibold]];
	NSTextField *subtitle = [NSTextField labelWithString:@"Your computers, one tap away"];
	[subtitle setFont:[NSFont systemFontOfSize:13.0]];
	[subtitle setTextColor:[NSColor secondaryLabelColor]];

	NSStackView *titles = [NSStackView stackViewWithViews:@[ title, subtitle ]];
	[titles setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[titles setAlignment:NSLayoutAttributeLeading];
	[titles setSpacing:1.0];

	NSButton *refresh = OrbisSymbolButton(@"arrow.clockwise", @"Refresh connections", self,
	                                      @selector(refreshPressed:));
	NSButton *add = OrbisSymbolButton(@"plus", @"New connection", self, @selector(addConnection:));
	NSButton *info = OrbisSymbolButton(@"info.circle", @"About Orbis", self,
	                                  @selector(showAbout:));
	[refresh setContentTintColor:[NSColor secondaryLabelColor]];
	[add setContentTintColor:[NSColor systemTealColor]];
	[info setContentTintColor:[NSColor systemBlueColor]];
	NSStackView *headerActions = [NSStackView stackViewWithViews:@[ refresh, add, info ]];
	[headerActions setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
	[headerActions setAlignment:NSLayoutAttributeCenterY];
	[headerActions setSpacing:10.0];
	[headerActions setContentHuggingPriority:NSLayoutPriorityRequired
	                           forOrientation:NSLayoutConstraintOrientationHorizontal];
	[headerActions setContentCompressionResistancePriority:NSLayoutPriorityRequired
	                                         forOrientation:NSLayoutConstraintOrientationHorizontal];

	NSView *headerSpacer = OrbisFlexibleSpacer();
	NSStackView *header = [NSStackView stackViewWithViews:@[ titles, headerSpacer, headerActions ]];
	[header setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
	[header setAlignment:NSLayoutAttributeCenterY];
	[header setDistribution:NSStackViewDistributionFill];
	[header setTranslatesAutoresizingMaskIntoConstraints:NO];
	[root addSubview:header];

	NSTextField *section = [NSTextField labelWithString:@"Connections"];
	[section setFont:[NSFont systemFontOfSize:15.0 weight:NSFontWeightSemibold]];
	[section setTranslatesAutoresizingMaskIntoConstraints:NO];
	[root addSubview:section];

	NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSZeroRect] autorelease];
	[scroll setDrawsBackground:NO];
	[scroll setBorderType:NSNoBorder];
	[scroll setHasVerticalScroller:YES];
	[scroll setAutohidesScrollers:YES];
	[scroll setTranslatesAutoresizingMaskIntoConstraints:NO];

	NSView *document = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
	[document setTranslatesAutoresizingMaskIntoConstraints:NO];
	_cardsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
	[_cardsStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[_cardsStack setAlignment:NSLayoutAttributeLeading];
	[_cardsStack setSpacing:12.0];
	[_cardsStack setTranslatesAutoresizingMaskIntoConstraints:NO];
	[document addSubview:_cardsStack];
	[scroll setDocumentView:document];
	[root addSubview:scroll];

	[NSLayoutConstraint activateConstraints:@[
		[[header leadingAnchor] constraintEqualToAnchor:[root leadingAnchor] constant:32.0],
		[[header trailingAnchor] constraintEqualToAnchor:[root trailingAnchor] constant:-32.0],
		[[header topAnchor] constraintEqualToAnchor:[[root safeAreaLayoutGuide] topAnchor] constant:24.0],
		[[section leadingAnchor] constraintEqualToAnchor:[header leadingAnchor]],
		[[section topAnchor] constraintEqualToAnchor:[header bottomAnchor] constant:24.0],
		[[scroll leadingAnchor] constraintEqualToAnchor:[root leadingAnchor] constant:24.0],
		[[scroll trailingAnchor] constraintEqualToAnchor:[root trailingAnchor] constant:-24.0],
		[[scroll topAnchor] constraintEqualToAnchor:[section bottomAnchor] constant:10.0],
		[[scroll bottomAnchor] constraintEqualToAnchor:[root bottomAnchor] constant:-24.0],
		[[document widthAnchor] constraintEqualToAnchor:[[scroll contentView] widthAnchor]],
		[[document heightAnchor] constraintGreaterThanOrEqualToAnchor:[[scroll contentView] heightAnchor]],
		[[_cardsStack leadingAnchor] constraintEqualToAnchor:[document leadingAnchor]],
		[[_cardsStack trailingAnchor] constraintEqualToAnchor:[document trailingAnchor]],
		[[_cardsStack topAnchor] constraintEqualToAnchor:[document topAnchor]],
		[[_cardsStack bottomAnchor] constraintLessThanOrEqualToAnchor:[document bottomAnchor]]
	]];

	[self reloadProfiles];
}

- (void)reloadProfiles
{
	if (!_cardsStack)
		return;
	NSArray *existingViews = [[_cardsStack arrangedSubviews] copy];
	for (NSView *view in existingViews)
	{
		[_cardsStack removeArrangedSubview:view];
		[view removeFromSuperview];
	}
	[existingViews release];

	NSArray *profiles = [_profileStore profiles];
	if ([profiles count] == 0)
	{
		NSView *emptyState = [self emptyStateView];
		[_cardsStack addArrangedSubview:emptyState];
		[[emptyState widthAnchor] constraintEqualToAnchor:[_cardsStack widthAnchor]].active = YES;
		return;
	}

	NSUInteger index = 0;
	for (OrbisProfile *profile in profiles)
	{
		NSView *card = [self cardForProfile:profile index:index++];
		[_cardsStack addArrangedSubview:card];
		[[card widthAnchor] constraintEqualToAnchor:[_cardsStack widthAnchor]].active = YES;
	}
}

- (NSView *)emptyStateView
{
	NSBox *box = [[[NSBox alloc] initWithFrame:NSZeroRect] autorelease];
	[box setBoxType:NSBoxCustom];
	[box setFillColor:[NSColor controlBackgroundColor]];
	[box setBorderColor:[NSColor separatorColor]];
	[box setBorderWidth:1.0];
	[box setCornerRadius:20.0];

	NSImageView *icon = [[[NSImageView alloc] initWithFrame:NSZeroRect] autorelease];
	[icon setImage:[NSImage imageWithSystemSymbolName:@"display" accessibilityDescription:nil]];
	[icon setSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:31.0
	                                                                           weight:NSFontWeightMedium]];
	NSTextField *title = [NSTextField labelWithString:@"No connections yet"];
	[title setFont:[NSFont systemFontOfSize:18.0 weight:NSFontWeightSemibold]];
	NSTextField *subtitle = [NSTextField labelWithString:@"Add a computer to start a private Remote Desktop session."];
	[subtitle setTextColor:[NSColor secondaryLabelColor]];
	NSButton *button = [NSButton buttonWithTitle:@"Add connection"
	                                      target:self
	                                      action:@selector(addConnection:)];
	[button setBezelStyle:NSBezelStyleRounded];

	NSStackView *stack = [NSStackView stackViewWithViews:@[ icon, title, subtitle, button ]];
	[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[stack setAlignment:NSLayoutAttributeCenterX];
	[stack setSpacing:10.0];
	[stack setTranslatesAutoresizingMaskIntoConstraints:NO];
	[box addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[[box heightAnchor] constraintEqualToConstant:230.0],
		[[stack centerXAnchor] constraintEqualToAnchor:[box centerXAnchor]],
		[[stack centerYAnchor] constraintEqualToAnchor:[box centerYAnchor]]
	]];
	return box;
}

- (NSView *)cardForProfile:(OrbisProfile *)profile index:(NSUInteger)index
{
	NSBox *card = [[[NSBox alloc] initWithFrame:NSZeroRect] autorelease];
	[card setBoxType:NSBoxCustom];
	[card setFillColor:[NSColor controlBackgroundColor]];
	[card setBorderColor:[NSColor separatorColor]];
	[card setBorderWidth:1.0];
	[card setCornerRadius:18.0];

	NSImageView *icon = [[[NSImageView alloc] initWithFrame:NSZeroRect] autorelease];
	[icon setImage:[NSImage imageWithSystemSymbolName:@"bolt.fill" accessibilityDescription:nil]];
	[icon setContentTintColor:[NSColor systemTealColor]];

	NSTextField *name = [NSTextField labelWithString:[profile name]];
	[name setFont:[NSFont systemFontOfSize:16.0 weight:NSFontWeightSemibold]];
	NSString *endpoint = [NSString stringWithFormat:@"%@:%lu  ·  %@", [profile host],
	                                                   (unsigned long)[profile port],
	                                                   [[profile username] length] > 0
	                                                       ? [profile username]
	                                                       : @"Account on connect"];
	NSTextField *detail = [NSTextField labelWithString:endpoint];
	[detail setFont:[NSFont systemFontOfSize:12.0]];
	[detail setTextColor:[NSColor secondaryLabelColor]];
	NSStackView *labels = [NSStackView stackViewWithViews:@[ name, detail ]];
	[labels setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[labels setAlignment:NSLayoutAttributeLeading];
	[labels setSpacing:2.0];

	NSImageView *statusIcon = [[[NSImageView alloc] initWithFrame:NSZeroRect] autorelease];
	[statusIcon setImage:[NSImage imageWithSystemSymbolName:@"checkmark.circle.fill"
	                             accessibilityDescription:@"Ready"]];
	[statusIcon setSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:12.0
	                                                                                  weight:NSFontWeightSemibold]];
	[statusIcon setContentTintColor:[NSColor systemGreenColor]];
	[statusIcon setImageScaling:NSImageScaleProportionallyDown];
	[statusIcon setAccessibilityIdentifier:@"connection-status-icon"];

	NSTextField *statusLabel = [NSTextField labelWithString:@"Ready to connect"];
	[statusLabel setFont:[NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium]];
	[statusLabel setTextColor:[NSColor secondaryLabelColor]];
	[statusLabel setAlignment:NSTextAlignmentCenter];
	[statusLabel setAccessibilityIdentifier:@"connection-status-label"];

	NSStackView *status = [NSStackView stackViewWithViews:@[ statusIcon, statusLabel ]];
	[status setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
	[status setAlignment:NSLayoutAttributeCenterY];
	[status setSpacing:5.0];
	[status setEdgeInsets:NSEdgeInsetsMake(5.0, 8.0, 5.0, 8.0)];
	[status setWantsLayer:YES];
	[status.layer setCornerRadius:13.0];
	[status.layer setBackgroundColor:[[NSColor tertiarySystemFillColor] CGColor]];
	[status setContentHuggingPriority:NSLayoutPriorityRequired
	                    forOrientation:NSLayoutConstraintOrientationHorizontal];
	[status setContentCompressionResistancePriority:NSLayoutPriorityRequired
	                                  forOrientation:NSLayoutConstraintOrientationHorizontal];

	NSButton *connect = OrbisSymbolButton(@"play.fill", @"Connect", self, @selector(connectPressed:));
	NSButton *edit = OrbisSymbolButton(@"pencil", @"Edit", self, @selector(editPressed:));
	NSButton *delete = OrbisSymbolButton(@"trash", @"Delete", self, @selector(deletePressed:));
	[connect setContentTintColor:[NSColor systemTealColor]];
	[edit setContentTintColor:[NSColor systemBlueColor]];
	for (NSButton *button in @[ connect, edit, delete ])
		[button setTag:(NSInteger)index];
	[delete setContentTintColor:[NSColor systemRedColor]];
	NSStackView *actions = [NSStackView stackViewWithViews:@[ connect, edit, delete ]];
	[actions setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
	[actions setAlignment:NSLayoutAttributeCenterY];
	[actions setSpacing:8.0];
	[actions setContentHuggingPriority:NSLayoutPriorityRequired
	                      forOrientation:NSLayoutConstraintOrientationHorizontal];
	[actions setContentCompressionResistancePriority:NSLayoutPriorityRequired
	                                    forOrientation:NSLayoutConstraintOrientationHorizontal];

	NSView *statusSpacer = OrbisFlexibleSpacer();
	NSStackView *row = [NSStackView stackViewWithViews:@[ icon, labels, statusSpacer, status, actions ]];
	[row setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
	[row setAlignment:NSLayoutAttributeCenterY];
	[row setSpacing:14.0];
	[row setEdgeInsets:NSEdgeInsetsMake(18.0, 18.0, 18.0, 18.0)];
	[row setTranslatesAutoresizingMaskIntoConstraints:NO];
	[card addSubview:row];
	[[labels widthAnchor] constraintGreaterThanOrEqualToConstant:260.0].active = YES;
	[[statusIcon widthAnchor] constraintEqualToConstant:16.0].active = YES;
	[[statusIcon heightAnchor] constraintEqualToConstant:16.0].active = YES;
	[[status heightAnchor] constraintEqualToConstant:26.0].active = YES;
	[NSLayoutConstraint activateConstraints:@[
		[[card heightAnchor] constraintEqualToConstant:82.0],
		[[row leadingAnchor] constraintEqualToAnchor:[card leadingAnchor]],
		[[row trailingAnchor] constraintEqualToAnchor:[card trailingAnchor]],
		[[row topAnchor] constraintEqualToAnchor:[card topAnchor]],
		[[row bottomAnchor] constraintEqualToAnchor:[card bottomAnchor]]
	]];
	return card;
}

- (OrbisProfile *)profileForSender:(NSControl *)sender
{
	NSArray *profiles = [_profileStore profiles];
	NSInteger index = [sender tag];
	if (index < 0 || (NSUInteger)index >= [profiles count])
		return nil;
	return [profiles objectAtIndex:(NSUInteger)index];
}

- (void)addConnection:(id)sender
{
	(void)sender;
	[self presentEditorForProfile:[[[OrbisProfile alloc] init] autorelease]];
}

- (void)showAbout:(id)sender
{
	(void)sender;
	if (!_aboutController)
		_aboutController = [[OrbisAboutController alloc] init];
	[_aboutController beginSheetForWindow:[[self view] window]];
}

- (void)editPressed:(NSButton *)sender
{
	OrbisProfile *profile = [self profileForSender:sender];
	if (profile)
		[self presentEditorForProfile:profile];
}

- (void)presentEditorForProfile:(OrbisProfile *)profile
{
	if (_profileEditor || ![[self view] window])
		return;
	BOOL hasPassword = [[OrbisCredentialStore passwordForProfile:profile error:nil] length] > 0;
	_profileEditor = [[OrbisProfileEditorController alloc] initWithProfile:profile
	                                                  hasStoredPassword:hasPassword];
	[_profileEditor setDelegate:self];
	[_profileEditor beginSheetForWindow:[[self view] window]];
}

- (void)profileEditorController:(OrbisProfileEditorController *)controller
                  savedProfile:(OrbisProfile *)profile
                       password:(NSString *)password
{
	NSError *error = nil;
	if (password && ![OrbisCredentialStore setPassword:password forProfile:profile error:&error])
	{
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		OrbisConfigureWarningAlert(alert);
		[alert setMessageText:@"Password couldn’t be saved"];
		[alert setInformativeText:[error localizedDescription]];
		[alert runModal];
		return;
	}
	[_profileStore saveProfile:profile];
	[self reloadProfiles];
	[controller setDelegate:nil];
	[_profileEditor autorelease];
	_profileEditor = nil;
}

- (void)connectPressed:(NSButton *)sender
{
	OrbisProfile *profile = [self profileForSender:sender];
	if (!profile)
		return;
	[_profileStore selectProfileWithIdentifier:[profile identifier]];
	[_delegate libraryViewController:self connectToProfile:profile];
}

- (void)connectSelectedProfile:(id)sender
{
	(void)sender;
	OrbisProfile *profile = [_profileStore selectedProfile];
	if (profile)
		[_delegate libraryViewController:self connectToProfile:profile];
}

- (void)deletePressed:(NSButton *)sender
{
	OrbisProfile *profile = [self profileForSender:sender];
	if (!profile)
		return;
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	OrbisConfigureWarningAlert(alert);
	[alert setMessageText:@"Delete this connection?"];
	[alert setInformativeText:[NSString stringWithFormat:@"%@ and its saved password will be removed from this Mac.", [profile name]]];
	[alert addButtonWithTitle:@"Delete"];
	[alert addButtonWithTitle:@"Cancel"];
	[alert beginSheetModalForWindow:[[self view] window]
	                 completionHandler:^(NSModalResponse response) {
		                 if (response != NSAlertFirstButtonReturn)
			                 return;
		                 [OrbisCredentialStore deletePasswordForProfile:profile error:nil];
		                 [_profileStore deleteProfileWithIdentifier:[profile identifier]];
		                 [self reloadProfiles];
	                 }];
}

- (void)refreshPressed:(id)sender
{
	(void)sender;
	[self reloadProfiles];
}

- (void)dealloc
{
	_delegate = nil;
	[_profileEditor setDelegate:nil];
	[_profileEditor release];
	[_aboutController release];
	[_cardsStack release];
	[_profileStore release];
	[super dealloc];
}

@end
