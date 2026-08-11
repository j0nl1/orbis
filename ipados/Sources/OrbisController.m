/* SPDX-License-Identifier: MIT */

#import "OrbisController.h"

#import <QuartzCore/QuartzCore.h>
#import <Security/Security.h>

#include <math.h>
#include <stdlib.h>
#include <freerdp/crypto/certificate_data.h>

#import "Bookmark.h"
#import "ConnectionParams.h"
#import "OrbisCredentialStore.h"
#import "OrbisAboutController.h"
#import "OrbisProfile.h"
#import "OrbisProfileEditorController.h"
#import "RDPSession.h"
#import "RDPSessionViewController.h"
static NSString *const OrbisCardViewKey = @"card";
static NSString *const OrbisCardDetailsKey = @"details";
static NSString *const OrbisCardChevronKey = @"chevron";
static NSString *const OrbisCardHeaderKey = @"header";
static NSString *const OrbisCardStatusLabelKey = @"status-label";
static NSString *const OrbisCardStatusIconKey = @"status-icon";
static NSString *const OrbisCardActivityIndicatorKey = @"activity-indicator";
static NSString *const OrbisCardConnectButtonKey = @"connect-button";

@interface OrbisController () <OrbisProfileEditorDelegate>
{
	OrbisProfileStore *_profileStore;
	UIStackView *_connectionsStack;
	UILabel *_statusLabel;
	UIImageView *_statusIconView;
	UIButton *_connectButton;
	UIActivityIndicatorView *_activityIndicator;
	NSMutableDictionary *_profileCardViews;
	UIViewPropertyAnimator *_cardAnimator;
	NSString *_expandedProfileIdentifier;
	NSString *_connectionStatus;
	BOOL _didAttemptAutomaticConnection;
	BOOL _isStartingConnection;
	BOOL _isPresentingPasswordPrompt;
}

- (void)addProfilePressed:(id)sender;
- (void)editProfilePressed:(id)sender;
- (void)deleteProfilePressed:(id)sender;
- (void)profileSelected:(OrbisProfile *)profile;
- (void)connectPressed:(id)sender;
- (void)showConnectionDetails;
- (void)refreshConnectionsPressed:(id)sender;
- (void)showAboutPressed:(id)sender;
- (void)refreshProfileUI;
- (UIView *)connectionCardForProfile:(OrbisProfile *)profile;
- (void)bindSelectedProfileControls;
- (void)prepareStatusForCardViews:(NSDictionary *)cardViews selected:(BOOL)selected;
- (void)applyPresentationToCardViews:(NSDictionary *)cardViews
	                       expanded:(BOOL)expanded
	                       selected:(BOOL)selected;
- (void)toggleProfileCardWithIdentifier:(NSString *)identifier;
- (void)startConnection;
- (void)startConnectionWithPassword:(NSString *)password;
- (void)presentPasswordPrompt;
- (NSString *)savedPasswordForProfile:(OrbisProfile *)profile error:(NSError **)error;
- (BOOL)savePassword:(NSString *)password forProfile:(OrbisProfile *)profile error:(NSError **)error;
- (BOOL)discardStoredCertificateForProfile:(OrbisProfile *)profile error:(NSError **)error;
- (void)setConnectionBusy:(BOOL)busy status:(NSString *)status;
- (void)showErrorWithTitle:(NSString *)title message:(NSString *)message;
- (void)sessionDidEnd:(NSNotification *)notification;

@end

@implementation OrbisController

- (void)viewDidLoad
{
	[super viewDidLoad];
	_profileStore = [[OrbisProfileStore alloc] init];
	_profileCardViews = [[NSMutableDictionary alloc] init];
	_expandedProfileIdentifier = [[[_profileStore selectedProfile] identifier] copy];
	_connectionStatus = [@"Ready to connect" copy];

	[[self view] setBackgroundColor:[UIColor systemGroupedBackgroundColor]];
	[self setTitle:@"Orbis"];

	UILabel *appTitle = [[[UILabel alloc] init] autorelease];
	[appTitle setText:@"Orbis"];
	[appTitle setFont:[UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle]];
	[appTitle setAdjustsFontForContentSizeCategory:YES];

	UILabel *appSubtitle = [[[UILabel alloc] init] autorelease];
	[appSubtitle setText:@"Your computers, one tap away"];
	[appSubtitle setFont:[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]];
	[appSubtitle setAdjustsFontForContentSizeCategory:YES];
	[appSubtitle setTextColor:[UIColor secondaryLabelColor]];

	UIStackView *titleStack = [[[UIStackView alloc]
	    initWithArrangedSubviews:@[ appTitle, appSubtitle ]] autorelease];
	[titleStack setAxis:UILayoutConstraintAxisVertical];
	[titleStack setSpacing:1.0];

	UIButtonConfiguration *headerButtonConfiguration =
	    [UIButtonConfiguration glassButtonConfiguration];
	[headerButtonConfiguration setCornerStyle:UIButtonConfigurationCornerStyleCapsule];
	[headerButtonConfiguration setContentInsets:NSDirectionalEdgeInsetsMake(11.0, 11.0, 11.0, 11.0)];

	UIButton *refreshButton = [UIButton buttonWithType:UIButtonTypeSystem];
	UIButtonConfiguration *refreshConfiguration = [headerButtonConfiguration copy];
	[refreshConfiguration setImage:[UIImage systemImageNamed:@"arrow.clockwise"]];
	[refreshButton setConfiguration:refreshConfiguration];
	[refreshConfiguration release];
	[refreshButton addTarget:self
	                  action:@selector(refreshConnectionsPressed:)
	        forControlEvents:UIControlEventTouchUpInside];
	[refreshButton setAccessibilityLabel:@"Refresh connections"];
	[[refreshButton widthAnchor] constraintEqualToConstant:46.0].active = YES;
	[[refreshButton heightAnchor] constraintEqualToConstant:46.0].active = YES;

	UIButton *addButton = [UIButton buttonWithType:UIButtonTypeSystem];
	UIButtonConfiguration *addConfiguration = [headerButtonConfiguration copy];
	[addConfiguration setImage:[UIImage systemImageNamed:@"plus"]];
	[addButton setConfiguration:addConfiguration];
	[addConfiguration release];
	[addButton addTarget:self
	              action:@selector(addProfilePressed:)
	    forControlEvents:UIControlEventTouchUpInside];
	[addButton setAccessibilityLabel:@"Add connection"];
	[[addButton widthAnchor] constraintEqualToConstant:46.0].active = YES;
	[[addButton heightAnchor] constraintEqualToConstant:46.0].active = YES;

	UIButton *infoButton = [UIButton buttonWithType:UIButtonTypeSystem];
	UIButtonConfiguration *infoConfiguration = [headerButtonConfiguration copy];
	[infoConfiguration setImage:[UIImage systemImageNamed:@"info.circle"]];
	[infoButton setConfiguration:infoConfiguration];
	[infoConfiguration release];
	[infoButton addTarget:self
	               action:@selector(showAboutPressed:)
	     forControlEvents:UIControlEventTouchUpInside];
	[infoButton setAccessibilityLabel:@"About Orbis"];
	[[infoButton widthAnchor] constraintEqualToConstant:46.0].active = YES;
	[[infoButton heightAnchor] constraintEqualToConstant:46.0].active = YES;

	UIStackView *appHeader = [[[UIStackView alloc]
	    initWithArrangedSubviews:@[ titleStack, refreshButton, addButton, infoButton ]] autorelease];
	[appHeader setAxis:UILayoutConstraintAxisHorizontal];
	[appHeader setAlignment:UIStackViewAlignmentCenter];
	[appHeader setSpacing:10.0];

	UIScrollView *scrollView = [[[UIScrollView alloc] init] autorelease];
	[scrollView setAlwaysBounceVertical:YES];
	[scrollView setContentInsetAdjustmentBehavior:UIScrollViewContentInsetAdjustmentAutomatic];
	[scrollView setTranslatesAutoresizingMaskIntoConstraints:NO];
	[[self view] addSubview:scrollView];

	UIView *contentView = [[[UIView alloc] init] autorelease];
	[contentView setTranslatesAutoresizingMaskIntoConstraints:NO];
	[scrollView addSubview:contentView];

	UILabel *sectionTitle = [[[UILabel alloc] init] autorelease];
	[sectionTitle setText:@"Connections"];
	[sectionTitle setFont:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]];
	[sectionTitle setAdjustsFontForContentSizeCategory:YES];

	_connectionsStack = [[UIStackView alloc] init];
	[_connectionsStack setAxis:UILayoutConstraintAxisVertical];
	[_connectionsStack setSpacing:14.0];

	UIImageView *keychainIcon = [[[UIImageView alloc]
	    initWithImage:[UIImage systemImageNamed:@"lock.shield.fill"]] autorelease];
	[keychainIcon setTintColor:[UIColor tertiaryLabelColor]];
	[keychainIcon setContentMode:UIViewContentModeScaleAspectFit];
	[[keychainIcon widthAnchor] constraintEqualToConstant:18.0].active = YES;

	UILabel *keychainLabel = [[[UILabel alloc] init] autorelease];
	[keychainLabel setText:@"Passwords protected separately in iPad Keychain"];
	[keychainLabel setFont:[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]];
	[keychainLabel setAdjustsFontForContentSizeCategory:YES];
	[keychainLabel setTextColor:[UIColor tertiaryLabelColor]];

	UIStackView *keychainStack = [[[UIStackView alloc]
	    initWithArrangedSubviews:@[ keychainIcon, keychainLabel ]] autorelease];
	[keychainStack setAxis:UILayoutConstraintAxisHorizontal];
	[keychainStack setAlignment:UIStackViewAlignmentCenter];
	[keychainStack setSpacing:7.0];

	UIStackView *stack = [[[UIStackView alloc]
	    initWithArrangedSubviews:@[ appHeader, sectionTitle, _connectionsStack, keychainStack ]]
	    autorelease];
	[stack setAxis:UILayoutConstraintAxisVertical];
	[stack setAlignment:UIStackViewAlignmentFill];
	[stack setSpacing:16.0];
	[stack setCustomSpacing:24.0 afterView:appHeader];
	[stack setCustomSpacing:10.0 afterView:sectionTitle];
	[stack setCustomSpacing:24.0 afterView:_connectionsStack];
	[stack setTranslatesAutoresizingMaskIntoConstraints:NO];
	[contentView addSubview:stack];

	UILayoutGuide *safeArea = [[self view] safeAreaLayoutGuide];
	[NSLayoutConstraint activateConstraints:@[
		[[scrollView leadingAnchor] constraintEqualToAnchor:[safeArea leadingAnchor]],
		[[scrollView trailingAnchor] constraintEqualToAnchor:[safeArea trailingAnchor]],
		[[scrollView topAnchor] constraintEqualToAnchor:[safeArea topAnchor]],
		[[scrollView bottomAnchor] constraintEqualToAnchor:[[self view] bottomAnchor]],
		[[contentView leadingAnchor]
		    constraintEqualToAnchor:[[scrollView contentLayoutGuide] leadingAnchor]],
		[[contentView trailingAnchor]
		    constraintEqualToAnchor:[[scrollView contentLayoutGuide] trailingAnchor]],
		[[contentView topAnchor] constraintEqualToAnchor:[[scrollView contentLayoutGuide] topAnchor]],
		[[contentView bottomAnchor]
		    constraintEqualToAnchor:[[scrollView contentLayoutGuide] bottomAnchor]],
		[[contentView widthAnchor] constraintEqualToAnchor:[[scrollView frameLayoutGuide] widthAnchor]],
		[[contentView heightAnchor]
		    constraintGreaterThanOrEqualToAnchor:[[scrollView frameLayoutGuide] heightAnchor]],
		[[stack leadingAnchor] constraintEqualToAnchor:[contentView leadingAnchor] constant:20.0],
		[[stack trailingAnchor] constraintEqualToAnchor:[contentView trailingAnchor] constant:-20.0],
		[[stack topAnchor] constraintEqualToAnchor:[contentView topAnchor] constant:16.0],
		[[stack bottomAnchor]
		    constraintLessThanOrEqualToAnchor:[contentView bottomAnchor] constant:-36.0],
	]];

	[self refreshProfileUI];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(sessionDidEnd:)
	                                             name:TSXSessionDidDisconnectNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(sessionDidEnd:)
	                                             name:TSXSessionDidFailToConnectNotification
	                                           object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[[self navigationController] setNavigationBarHidden:YES animated:animated];
	[self refreshProfileUI];
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	if ([[[[NSProcessInfo processInfo] environment] objectForKey:@"ORBIS_DISABLE_AUTOCONNECT"]
	        boolValue])
	{
		_didAttemptAutomaticConnection = YES;
		return;
	}
	if (!_didAttemptAutomaticConnection && !_isStartingConnection)
	{
		_didAttemptAutomaticConnection = YES;
		OrbisProfile *automatic = [_profileStore automaticProfile];
		if (automatic)
		{
			[_profileStore selectProfileWithIdentifier:[automatic identifier]];
			[_expandedProfileIdentifier release];
			_expandedProfileIdentifier = [[automatic identifier] copy];
			[self refreshProfileUI];
			[self startConnection];
		}
	}
}

- (void)refreshConnectionsPressed:(id)sender
{
	(void)sender;
	OrbisProfileStore *freshStore = [[OrbisProfileStore alloc] init];
	[_profileStore release];
	_profileStore = freshStore;
	if (![_profileStore profileWithIdentifier:_expandedProfileIdentifier])
	{
		[_expandedProfileIdentifier release];
		_expandedProfileIdentifier = nil;
	}
	[self setConnectionBusy:NO status:@"Connections refreshed"];
	[self refreshProfileUI];

	UISelectionFeedbackGenerator *feedback =
	    [[[UISelectionFeedbackGenerator alloc] init] autorelease];
	[feedback selectionChanged];
}

- (void)showAboutPressed:(id)sender
{
	(void)sender;
	OrbisAboutController *about = [[[OrbisAboutController alloc] init] autorelease];
	UINavigationController *navigation = [[[UINavigationController alloc]
	    initWithRootViewController:about] autorelease];
	[navigation setModalPresentationStyle:UIModalPresentationFormSheet];
	[navigation setPreferredContentSize:CGSizeMake(620.0, 760.0)];
	[self presentViewController:navigation animated:YES completion:nil];
}

- (UIView *)connectionCardForProfile:(OrbisProfile *)profile
{
	BOOL expanded = [[profile identifier] isEqualToString:_expandedProfileIdentifier];
	BOOL selected = [[profile identifier]
	    isEqualToString:[[_profileStore selectedProfile] identifier]];

	UIView *card = [[[UIView alloc] init] autorelease];
	[card setBackgroundColor:[UIColor secondarySystemGroupedBackgroundColor]];
	[[card layer] setCornerCurve:kCACornerCurveContinuous];
	[[card layer] setCornerRadius:26.0];
	[[card layer] setBorderWidth:selected ? 2.0 : 0.5];
	[[card layer] setBorderColor:(selected ? [UIColor systemTealColor]
	                                        : [UIColor separatorColor]).CGColor];
	[[card layer] setShadowColor:[[UIColor blackColor] CGColor]];
	[[card layer] setShadowOpacity:expanded ? 0.10f : 0.05f];
	[[card layer] setShadowRadius:expanded ? 20.0 : 10.0];
	[[card layer] setShadowOffset:CGSizeMake(0.0, expanded ? 10.0 : 5.0)];

	NSString *profileIdentifier = [profile identifier];
	__block OrbisController *controller = self;

	UIImageView *connectionIcon = [[[UIImageView alloc]
	    initWithImage:[UIImage systemImageNamed:[profile connectAutomatically] ? @"bolt.fill"
	                                                                    : @"desktopcomputer"]]
	    autorelease];
	[connectionIcon setTintColor:[UIColor labelColor]];
	[connectionIcon setContentMode:UIViewContentModeScaleAspectFit];
	[[connectionIcon widthAnchor] constraintEqualToConstant:28.0].active = YES;
	[[connectionIcon heightAnchor] constraintEqualToConstant:28.0].active = YES;

	UILabel *title = [[[UILabel alloc] init] autorelease];
	[title setText:[profile name]];
	[title setFont:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]];
	[title setAdjustsFontForContentSizeCategory:YES];
	[title setTextColor:[UIColor labelColor]];

	NSString *displayStatus = selected ? _connectionStatus : @"Disconnected";
	UIImageSymbolConfiguration *statusSymbolConfiguration =
	    [UIImageSymbolConfiguration configurationWithPointSize:13.0
	                                                   weight:UIImageSymbolWeightSemibold];
	UIImageView *statusIconView = [[[UIImageView alloc]
	    initWithImage:[UIImage systemImageNamed:@"wifi.slash"
	                             withConfiguration:statusSymbolConfiguration]] autorelease];
	[statusIconView setTintColor:[UIColor systemOrangeColor]];
	[statusIconView setContentMode:UIViewContentModeScaleAspectFit];

	UIActivityIndicatorView *activityIndicator = [[[UIActivityIndicatorView alloc]
	    initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium] autorelease];
	[activityIndicator setHidesWhenStopped:YES];

	UIView *statusGlyph = [[[UIView alloc] init] autorelease];
	[statusGlyph addSubview:statusIconView];
	[statusGlyph addSubview:activityIndicator];
	[statusIconView setTranslatesAutoresizingMaskIntoConstraints:NO];
	[activityIndicator setTranslatesAutoresizingMaskIntoConstraints:NO];
	[NSLayoutConstraint activateConstraints:@[
		[[statusGlyph widthAnchor] constraintEqualToConstant:20.0],
		[[statusGlyph heightAnchor] constraintEqualToConstant:20.0],
		[[statusIconView centerXAnchor] constraintEqualToAnchor:[statusGlyph centerXAnchor]],
		[[statusIconView centerYAnchor] constraintEqualToAnchor:[statusGlyph centerYAnchor]],
		[[activityIndicator centerXAnchor] constraintEqualToAnchor:[statusGlyph centerXAnchor]],
		[[activityIndicator centerYAnchor] constraintEqualToAnchor:[statusGlyph centerYAnchor]],
	]];

	UILabel *statusLabel = [[[UILabel alloc] init] autorelease];
	[statusLabel setText:displayStatus];
	[statusLabel setFont:[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]];
	[statusLabel setAdjustsFontForContentSizeCategory:YES];
	[statusLabel setTextColor:[UIColor secondaryLabelColor]];
	[statusLabel setLineBreakMode:NSLineBreakByTruncatingTail];
	[statusLabel setContentHuggingPriority:UILayoutPriorityRequired
	                              forAxis:UILayoutConstraintAxisHorizontal];
	[statusLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
	                                           forAxis:UILayoutConstraintAxisHorizontal];

	UIStackView *statusStack = [[[UIStackView alloc]
	    initWithArrangedSubviews:@[ statusGlyph, statusLabel ]] autorelease];
	[statusStack setAxis:UILayoutConstraintAxisHorizontal];
	[statusStack setAlignment:UIStackViewAlignmentCenter];
	[statusStack setSpacing:5.0];
	[statusStack setLayoutMargins:UIEdgeInsetsMake(5.0, 8.0, 5.0, 8.0)];
	[statusStack setLayoutMarginsRelativeArrangement:YES];
	[statusStack setBackgroundColor:[UIColor tertiarySystemFillColor]];
	[[statusStack layer] setCornerCurve:kCACornerCurveContinuous];
	[[statusStack layer] setCornerRadius:13.0];
	[statusStack setContentHuggingPriority:UILayoutPriorityRequired
	                              forAxis:UILayoutConstraintAxisHorizontal];
	[statusStack setContentCompressionResistancePriority:UILayoutPriorityRequired
	                                           forAxis:UILayoutConstraintAxisHorizontal];

	UILabel *endpoint = [[[UILabel alloc] init] autorelease];
	[endpoint setText:[NSString stringWithFormat:@"%@:%lu · %@", [profile host],
	                                                  (unsigned long)[profile port],
	                                                  [profile username]]];
	[endpoint setFont:[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]];
	[endpoint setAdjustsFontForContentSizeCategory:YES];
	[endpoint setTextColor:[UIColor secondaryLabelColor]];
	[endpoint setLineBreakMode:NSLineBreakByTruncatingMiddle];

	UIStackView *identity = [[[UIStackView alloc]
	    initWithArrangedSubviews:@[ title, endpoint ]] autorelease];
	[identity setAxis:UILayoutConstraintAxisVertical];
	[identity setAlignment:UIStackViewAlignmentFill];
	[identity setSpacing:2.0];
	[identity setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
	                                             forAxis:UILayoutConstraintAxisHorizontal];
	UIView *statusSpacer = [[[UIView alloc] init] autorelease];
	[statusSpacer setContentHuggingPriority:1.0 forAxis:UILayoutConstraintAxisHorizontal];
	[statusSpacer setContentCompressionResistancePriority:1.0
	                                              forAxis:UILayoutConstraintAxisHorizontal];

	UIStackView *headerContent = [[[UIStackView alloc]
	    initWithArrangedSubviews:@[ connectionIcon, identity, statusSpacer, statusStack ]] autorelease];
	[headerContent setAxis:UILayoutConstraintAxisHorizontal];
	[headerContent setAlignment:UIStackViewAlignmentCenter];
	[headerContent setSpacing:14.0];
	[headerContent setCustomSpacing:0.0 afterView:identity];
	[headerContent setUserInteractionEnabled:NO];

	UIControl *header = [[[UIControl alloc] init] autorelease];
	[header addAction:[UIAction actionWithHandler:^(UIAction *action) {
		        (void)action;
		        [controller toggleProfileCardWithIdentifier:profileIdentifier];
	        }]
	    forControlEvents:UIControlEventTouchUpInside];
	[header addSubview:headerContent];
	[headerContent setTranslatesAutoresizingMaskIntoConstraints:NO];
	[NSLayoutConstraint activateConstraints:@[
		[[headerContent leadingAnchor] constraintEqualToAnchor:[header leadingAnchor] constant:18.0],
		[[headerContent trailingAnchor] constraintEqualToAnchor:[header trailingAnchor] constant:-8.0],
		[[headerContent topAnchor] constraintEqualToAnchor:[header topAnchor] constant:14.0],
		[[headerContent bottomAnchor] constraintEqualToAnchor:[header bottomAnchor] constant:-14.0],
		[[header heightAnchor] constraintGreaterThanOrEqualToConstant:72.0],
	]];
	[header setAccessibilityLabel:[NSString stringWithFormat:@"%@, %@", [profile name], displayStatus]];
	[header setAccessibilityHint:expanded ? @"Collapses connection controls"
	                                      : @"Expands connection controls"];

	UIButton *chevron = [UIButton buttonWithType:UIButtonTypeSystem];
	UIButtonConfiguration *chevronConfiguration = [UIButtonConfiguration plainButtonConfiguration];
	[chevronConfiguration setImage:[UIImage systemImageNamed:@"chevron.down"]];
	[chevronConfiguration setBaseForegroundColor:[UIColor tertiaryLabelColor]];
	[chevron setConfiguration:chevronConfiguration];
	[chevron setTransform:expanded ? CGAffineTransformMakeRotation((CGFloat)M_PI)
	                                : CGAffineTransformIdentity];
	[chevron addAction:[UIAction actionWithHandler:^(UIAction *action) {
		          (void)action;
		          [controller toggleProfileCardWithIdentifier:profileIdentifier];
	          }]
	        forControlEvents:UIControlEventTouchUpInside];
	[chevron setAccessibilityLabel:expanded ? @"Collapse connection" : @"Expand connection"];
	[[chevron widthAnchor] constraintEqualToConstant:50.0].active = YES;
	[[chevron heightAnchor] constraintGreaterThanOrEqualToConstant:50.0].active = YES;

	UIStackView *headerRow = [[[UIStackView alloc]
	    initWithArrangedSubviews:@[ header, chevron ]] autorelease];
	[headerRow setAxis:UILayoutConstraintAxisHorizontal];
	[headerRow setAlignment:UIStackViewAlignmentCenter];
	[headerRow setLayoutMargins:UIEdgeInsetsMake(0.0, 0.0, 0.0, 6.0)];
	[headerRow setLayoutMarginsRelativeArrangement:YES];

	UIStackView *content = [[[UIStackView alloc] initWithArrangedSubviews:@[ headerRow ]] autorelease];
	[content setAxis:UILayoutConstraintAxisVertical];
	[content setAlignment:UIStackViewAlignmentFill];

	{
		UIView *divider = [[[UIView alloc] init] autorelease];
		[divider setBackgroundColor:[UIColor separatorColor]];
		[[divider heightAnchor] constraintEqualToConstant:0.5].active = YES;

		UIButton *connectButton = [UIButton buttonWithType:UIButtonTypeSystem];
		[connectButton addTarget:self
		                  action:@selector(connectPressed:)
		        forControlEvents:UIControlEventTouchUpInside];
		UIButtonConfiguration *connect = [UIButtonConfiguration prominentGlassButtonConfiguration];
		[connect setImage:[UIImage systemImageNamed:@"play.fill"]];
		[connect setCornerStyle:UIButtonConfigurationCornerStyleCapsule];
		[connect setBaseBackgroundColor:[UIColor systemTealColor]];
		[connect setBaseForegroundColor:[UIColor whiteColor]];
		[connect setContentInsets:NSDirectionalEdgeInsetsMake(14.0, 14.0, 14.0, 14.0)];
		[connectButton setConfiguration:connect];
		[connectButton setAccessibilityLabel:@"Connect"];
		[connectButton setAccessibilityHint:[NSString
		    stringWithFormat:@"Connects to %@", [profile name]]];

		UIButton *edit = [UIButton buttonWithType:UIButtonTypeSystem];
		UIButtonConfiguration *editConfiguration = [UIButtonConfiguration glassButtonConfiguration];
		[editConfiguration setImage:[UIImage systemImageNamed:@"pencil"]];
		[editConfiguration setCornerStyle:UIButtonConfigurationCornerStyleCapsule];
		[edit setConfiguration:editConfiguration];
		[edit setAccessibilityLabel:@"Edit connection"];
		[edit setAccessibilityHint:[NSString stringWithFormat:@"Edits %@", [profile name]]];
		[edit addAction:[UIAction actionWithHandler:^(UIAction *action) {
			      (void)action;
			      [controller->_profileStore selectProfileWithIdentifier:profileIdentifier];
			      [controller editProfilePressed:nil];
		      }]
		    forControlEvents:UIControlEventTouchUpInside];

		UIButton *info = [UIButton buttonWithType:UIButtonTypeSystem];
		UIButtonConfiguration *infoConfiguration = [UIButtonConfiguration glassButtonConfiguration];
		[infoConfiguration setImage:[UIImage systemImageNamed:@"info.circle"]];
		[infoConfiguration setCornerStyle:UIButtonConfigurationCornerStyleCapsule];
		[info setConfiguration:infoConfiguration];
		[info setAccessibilityLabel:@"Connection details"];
		[info setAccessibilityHint:[NSString stringWithFormat:@"Shows details for %@", [profile name]]];
		[info addAction:[UIAction actionWithHandler:^(UIAction *action) {
			      (void)action;
			      [controller->_profileStore selectProfileWithIdentifier:profileIdentifier];
			      [controller showConnectionDetails];
		      }]
		    forControlEvents:UIControlEventTouchUpInside];

		UIButton *delete = [UIButton buttonWithType:UIButtonTypeSystem];
		UIButtonConfiguration *deleteConfiguration = [UIButtonConfiguration glassButtonConfiguration];
		[deleteConfiguration setImage:[UIImage systemImageNamed:@"trash"]];
		[deleteConfiguration setCornerStyle:UIButtonConfigurationCornerStyleCapsule];
		[deleteConfiguration setBaseForegroundColor:[UIColor systemRedColor]];
		[delete setConfiguration:deleteConfiguration];
		[delete setAccessibilityLabel:@"Delete connection"];
		[delete setAccessibilityHint:[NSString stringWithFormat:@"Deletes %@", [profile name]]];
		[delete addAction:[UIAction actionWithHandler:^(UIAction *action) {
			        (void)action;
			        [controller->_profileStore selectProfileWithIdentifier:profileIdentifier];
			        [controller deleteProfilePressed:nil];
		        }]
		      forControlEvents:UIControlEventTouchUpInside];

		UIStackView *actions = [[[UIStackView alloc]
		    initWithArrangedSubviews:@[ connectButton, edit, info, delete ]] autorelease];
		[actions setAxis:UILayoutConstraintAxisHorizontal];
		[actions setAlignment:UIStackViewAlignmentCenter];
		[actions setDistribution:UIStackViewDistributionFill];
		[actions setSpacing:14.0];
		for (UIButton *button in @[ connectButton, edit, info, delete ])
		{
			[[button widthAnchor] constraintEqualToConstant:54.0].active = YES;
			[[button heightAnchor] constraintEqualToConstant:54.0].active = YES;
		}

		UIView *actionsContainer = [[[UIView alloc] init] autorelease];
		[actionsContainer addSubview:actions];
		[actions setTranslatesAutoresizingMaskIntoConstraints:NO];
		[NSLayoutConstraint activateConstraints:@[
			[[actions centerXAnchor] constraintEqualToAnchor:[actionsContainer centerXAnchor]],
			[[actions topAnchor] constraintEqualToAnchor:[actionsContainer topAnchor] constant:14.0],
			[[actions bottomAnchor] constraintEqualToAnchor:[actionsContainer bottomAnchor]
			                                            constant:-20.0],
		]];

		UIStackView *details = [[[UIStackView alloc]
		    initWithArrangedSubviews:@[ divider, actionsContainer ]] autorelease];
		[details setAxis:UILayoutConstraintAxisVertical];
		[details setAlignment:UIStackViewAlignmentFill];
		[details setHidden:!expanded];
		[details setAlpha:expanded ? 1.0 : 0.0];
		[content addArrangedSubview:details];

		[_profileCardViews setObject:@{
			OrbisCardViewKey : card,
			OrbisCardDetailsKey : details,
			OrbisCardChevronKey : chevron,
			OrbisCardHeaderKey : header,
			OrbisCardStatusLabelKey : statusLabel,
			OrbisCardStatusIconKey : statusIconView,
			OrbisCardActivityIndicatorKey : activityIndicator,
			OrbisCardConnectButtonKey : connectButton,
		} forKey:profileIdentifier];
	}

	[content setTranslatesAutoresizingMaskIntoConstraints:NO];
	[card addSubview:content];
	[NSLayoutConstraint activateConstraints:@[
		[[content leadingAnchor] constraintEqualToAnchor:[card leadingAnchor]],
		[[content trailingAnchor] constraintEqualToAnchor:[card trailingAnchor]],
		[[content topAnchor] constraintEqualToAnchor:[card topAnchor]],
		[[content bottomAnchor] constraintEqualToAnchor:[card bottomAnchor]],
	]];
	return card;
}

- (void)refreshProfileUI
{
	[_statusLabel release];
	_statusLabel = nil;
	[_statusIconView release];
	_statusIconView = nil;
	[_activityIndicator release];
	_activityIndicator = nil;
	[_connectButton release];
	_connectButton = nil;
	[_profileCardViews removeAllObjects];

	NSArray *existingViews = [[_connectionsStack arrangedSubviews] copy];
	for (UIView *view in existingViews)
	{
		[_connectionsStack removeArrangedSubview:view];
		[view removeFromSuperview];
	}
	[existingViews release];

	NSArray *profiles = [_profileStore profiles];
	for (OrbisProfile *profile in profiles)
		[_connectionsStack addArrangedSubview:[self connectionCardForProfile:profile]];

	if ([profiles count] == 0)
	{
		UILabel *empty = [[[UILabel alloc] init] autorelease];
		[empty setText:@"No connections yet. Add a computer to get started."];
		[empty setTextColor:[UIColor secondaryLabelColor]];
		[empty setTextAlignment:NSTextAlignmentCenter];
		[empty setFont:[UIFont preferredFontForTextStyle:UIFontTextStyleBody]];
		[empty setNumberOfLines:0];
		[empty setBackgroundColor:[UIColor secondarySystemGroupedBackgroundColor]];
		[empty setClipsToBounds:YES];
		[[empty layer] setCornerCurve:kCACornerCurveContinuous];
		[[empty layer] setCornerRadius:22.0];
		[[empty heightAnchor] constraintGreaterThanOrEqualToConstant:110.0].active = YES;
		[_connectionsStack addArrangedSubview:empty];
	}

	[self bindSelectedProfileControls];
	[self setConnectionBusy:_isStartingConnection status:_connectionStatus];
}

- (void)bindSelectedProfileControls
{
	[_statusLabel release];
	_statusLabel = nil;
	[_statusIconView release];
	_statusIconView = nil;
	[_activityIndicator release];
	_activityIndicator = nil;
	[_connectButton release];
	_connectButton = nil;

	NSString *identifier = [[_profileStore selectedProfile] identifier];
	NSDictionary *cardViews = [_profileCardViews objectForKey:identifier];
	_statusLabel = [[cardViews objectForKey:OrbisCardStatusLabelKey] retain];
	_statusIconView = [[cardViews objectForKey:OrbisCardStatusIconKey] retain];
	_activityIndicator = [[cardViews objectForKey:OrbisCardActivityIndicatorKey] retain];
	_connectButton = [[cardViews objectForKey:OrbisCardConnectButtonKey] retain];
}

- (void)prepareStatusForCardViews:(NSDictionary *)cardViews selected:(BOOL)selected
{
	UILabel *statusLabel = [cardViews objectForKey:OrbisCardStatusLabelKey];
	UIImageView *statusIcon = [cardViews objectForKey:OrbisCardStatusIconKey];
	UIActivityIndicatorView *activity =
	    [cardViews objectForKey:OrbisCardActivityIndicatorKey];
	UIButton *connectButton = [cardViews objectForKey:OrbisCardConnectButtonKey];

	if (selected)
	{
		[statusLabel setText:_connectionStatus];
		return;
	}

	[statusLabel setText:@"Disconnected"];
	[statusIcon setHidden:NO];
	[statusIcon setImage:[UIImage systemImageNamed:@"wifi.slash"]];
	[statusIcon setTintColor:[UIColor systemOrangeColor]];
	[activity stopAnimating];
	[connectButton setEnabled:YES];
}

- (void)applyPresentationToCardViews:(NSDictionary *)cardViews
	                       expanded:(BOOL)expanded
	                       selected:(BOOL)selected
{
	UIView *card = [cardViews objectForKey:OrbisCardViewKey];
	UIView *details = [cardViews objectForKey:OrbisCardDetailsKey];
	UIButton *chevron = [cardViews objectForKey:OrbisCardChevronKey];
	UIControl *header = [cardViews objectForKey:OrbisCardHeaderKey];

	[[card layer] setBorderWidth:selected ? 2.0 : 0.5];
	[[card layer] setBorderColor:(selected ? [UIColor systemTealColor]
	                                        : [UIColor separatorColor]).CGColor];
	[[card layer] setShadowOpacity:expanded ? 0.10f : 0.05f];
	[[card layer] setShadowRadius:expanded ? 20.0 : 10.0];
	[[card layer] setShadowOffset:CGSizeMake(0.0, expanded ? 10.0 : 5.0)];
	[details setHidden:!expanded];
	[details setAlpha:expanded ? 1.0 : 0.0];
	[chevron setTransform:expanded ? CGAffineTransformMakeRotation((CGFloat)M_PI)
	                                : CGAffineTransformIdentity];
	[chevron setAccessibilityLabel:expanded ? @"Collapse connection" : @"Expand connection"];
	[header setAccessibilityHint:expanded ? @"Collapses connection controls"
	                                      : @"Expands connection controls"];
}

- (void)toggleProfileCardWithIdentifier:(NSString *)identifier
{
	if (_cardAnimator)
	{
		if ([_cardAnimator isRunning])
		{
			[_cardAnimator stopAnimation:NO];
			[_cardAnimator finishAnimationAtPosition:UIViewAnimatingPositionCurrent];
		}
		[_cardAnimator release];
		_cardAnimator = nil;
	}

	BOOL collapse = [_expandedProfileIdentifier isEqualToString:identifier];
	[_expandedProfileIdentifier release];
	_expandedProfileIdentifier = collapse ? nil : [identifier copy];
	if (!collapse)
		[_profileStore selectProfileWithIdentifier:identifier];

	NSString *selectedIdentifier = [[_profileStore selectedProfile] identifier];
	for (NSString *profileIdentifier in _profileCardViews)
	{
		BOOL selected = [profileIdentifier isEqualToString:selectedIdentifier];
		[self prepareStatusForCardViews:[_profileCardViews objectForKey:profileIdentifier]
		                         selected:selected];
	}
	[self bindSelectedProfileControls];
	[self setConnectionBusy:_isStartingConnection status:_connectionStatus];

	[[self view] layoutIfNeeded];
	NSTimeInterval duration = UIAccessibilityIsReduceMotionEnabled() ? 0.18 : 0.42;
	CGFloat damping = UIAccessibilityIsReduceMotionEnabled() ? 1.0 : 0.88;
	__block OrbisController *controller = self;
	_cardAnimator = [[UIViewPropertyAnimator alloc]
	    initWithDuration:duration
	         dampingRatio:damping
	            animations:^{
		            NSString *currentSelection =
		                [[controller->_profileStore selectedProfile] identifier];
		            for (NSString *profileIdentifier in controller->_profileCardViews)
		            {
			            BOOL expanded = [profileIdentifier
			                isEqualToString:controller->_expandedProfileIdentifier];
			            BOOL selected = [profileIdentifier isEqualToString:currentSelection];
			            [controller
			                applyPresentationToCardViews:
			                    [controller->_profileCardViews objectForKey:profileIdentifier]
			                                     expanded:expanded
			                                     selected:selected];
		            }
		            [[controller view] layoutIfNeeded];
	            }];
	[_cardAnimator startAnimation];

	UISelectionFeedbackGenerator *feedback =
	    [[[UISelectionFeedbackGenerator alloc] init] autorelease];
	[feedback selectionChanged];
}

- (void)addProfilePressed:(id)sender
{
	(void)sender;
	OrbisProfileEditorController *editor =
	    [[[OrbisProfileEditorController alloc] initWithProfile:nil] autorelease];
	[editor setDelegate:self];
	UINavigationController *navigation =
	    [[[UINavigationController alloc] initWithRootViewController:editor] autorelease];
	[navigation setModalPresentationStyle:UIModalPresentationFormSheet];
	[self presentViewController:navigation animated:YES completion:nil];
}

- (void)editProfilePressed:(id)sender
{
	(void)sender;
	OrbisProfile *profile = [_profileStore selectedProfile];
	if (!profile)
		return [self addProfilePressed:nil];
	OrbisProfileEditorController *editor =
	    [[[OrbisProfileEditorController alloc]
	        initWithProfile:profile
	         hasSavedPassword:[[self savedPasswordForProfile:profile error:nil] length] > 0]
	        autorelease];
	[editor setDelegate:self];
	UINavigationController *navigation =
	    [[[UINavigationController alloc] initWithRootViewController:editor] autorelease];
	[navigation setModalPresentationStyle:UIModalPresentationFormSheet];
	[self presentViewController:navigation animated:YES completion:nil];
}

- (BOOL)profileEditor:(OrbisProfileEditorController *)editor
       didSaveProfile:(OrbisProfile *)profile
             password:(NSString *)password
{
	if ([password length] > 0)
	{
		NSError *error = nil;
		if (![self savePassword:password forProfile:profile error:&error])
		{
			UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Keychain Error"
			                                                               message:[error localizedDescription]
			                                                        preferredStyle:
			                                                            UIAlertControllerStyleAlert];
			[alert addAction:[UIAlertAction actionWithTitle:@"OK"
			                                         style:UIAlertActionStyleDefault
			                                       handler:nil]];
			[editor presentViewController:alert animated:YES completion:nil];
			return NO;
		}
	}
	[_profileStore saveProfile:profile];
	[_expandedProfileIdentifier release];
	_expandedProfileIdentifier = [[profile identifier] copy];
	[self refreshProfileUI];
	[self setConnectionBusy:NO status:@"Ready to connect"];
	return YES;
}

- (void)profileSelected:(OrbisProfile *)profile
{
	[_profileStore selectProfileWithIdentifier:[profile identifier]];
	[_expandedProfileIdentifier release];
	_expandedProfileIdentifier = [[profile identifier] copy];
	[self refreshProfileUI];
	[self setConnectionBusy:NO status:@"Ready to connect"];
}

- (void)deleteProfilePressed:(id)sender
{
	(void)sender;
	OrbisProfile *profile = [_profileStore selectedProfile];
	if (!profile)
		return;
	NSString *message = [NSString
	    stringWithFormat:@"%@ and its saved password will be removed from this iPad.", [profile name]];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete connection?"
	                                                               message:message
	                                                        preferredStyle:
	                                                            UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
	                                         style:UIAlertActionStyleCancel
	                                       handler:nil]];
	NSString *identifier = [profile identifier];
	[alert addAction:[UIAlertAction
	                     actionWithTitle:@"Delete"
	                               style:UIAlertActionStyleDestructive
	                             handler:^(UIAlertAction *action) {
		                             (void)action;
		                             OrbisProfile *deleting =
		                                 [_profileStore profileWithIdentifier:identifier];
		                             NSError *error = nil;
		                             [OrbisCredentialStore deletePasswordForProfile:deleting error:&error];
		                             [_profileStore deleteProfileWithIdentifier:identifier];
		                             [_expandedProfileIdentifier release];
		                             _expandedProfileIdentifier =
		                                 [[[_profileStore selectedProfile] identifier] copy];
		                             [self refreshProfileUI];
		                             [self setConnectionBusy:NO
		                                                  status:[_profileStore selectedProfile]
		                                                             ? @"Ready to connect"
		                                                             : @"Add a connection to begin"];
	                             }]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)connectPressed:(id)sender
{
	(void)sender;
	if (![_profileStore selectedProfile])
		return [self addProfilePressed:nil];
	[self startConnection];
}

- (NSString *)savedPasswordForProfile:(OrbisProfile *)profile error:(NSError **)error
{
	return [OrbisCredentialStore passwordForProfile:profile error:error];
}

- (BOOL)savePassword:(NSString *)password forProfile:(OrbisProfile *)profile error:(NSError **)error
{
	return [OrbisCredentialStore setPassword:password forProfile:profile error:error];
}

- (BOOL)discardStoredCertificateForProfile:(OrbisProfile *)profile error:(NSError **)error
{
	if (error)
		*error = nil;
	if (!profile || [profile acceptAllCertificates])
		return YES;

	char *configPath = freerdp_settings_get_config_path();
	char *certificateName =
	    freerdp_certificate_data_hash([[profile host] UTF8String], (UINT16)[profile port]);
	if (!configPath || !certificateName)
	{
		free(configPath);
		free(certificateName);
		if (error)
			*error = [NSError errorWithDomain:@"com.dnexus.orbis.certificate-store"
			                             code:1
			                         userInfo:@{
				                         NSLocalizedDescriptionKey :
				                             @"Orbis could not prepare certificate verification."
			                         }];
		return NO;
	}

	NSString *basePath = [NSString stringWithUTF8String:configPath];
	NSString *fileName = [NSString stringWithUTF8String:certificateName];
	free(configPath);
	free(certificateName);
	if (!basePath || !fileName)
	{
		if (error)
			*error = [NSError errorWithDomain:@"com.dnexus.orbis.certificate-store"
			                             code:2
			                         userInfo:@{
				                         NSLocalizedDescriptionKey :
				                             @"Orbis could not locate the certificate store."
			                         }];
		return NO;
	}

	NSString *path =
	    [[basePath stringByAppendingPathComponent:@"server"] stringByAppendingPathComponent:fileName];
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if (![fileManager fileExistsAtPath:path])
		return YES;
	return [fileManager removeItemAtPath:path error:error];
}

- (void)showConnectionDetails
{
	OrbisProfile *profile = [_profileStore selectedProfile];
	if (!profile)
		return;
	NSString *certificate = [profile acceptAllCertificates] ? @"Accepted automatically"
	                                                             : @"Ask when untrusted";
	NSString *automatic = [profile connectAutomatically] ? @"Yes" : @"No";
	NSString *message = [NSString
	    stringWithFormat:@"%@:%lu\nAccount: %@\nCertificate: %@\nAuto-connect: %@\n\nThe password "
	                     @"is stored only in this iPad's Keychain.",
	                     [profile host], (unsigned long)[profile port], [profile username],
	                     certificate, automatic];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:[profile name]
	                                                               message:message
	                                                        preferredStyle:
	                                                            UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"Done"
	                                         style:UIAlertActionStyleDefault
	                                       handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)startConnection
{
	if (_isStartingConnection || _isPresentingPasswordPrompt)
		return;
	OrbisProfile *profile = [_profileStore selectedProfile];
	if (!profile)
		return;

	NSError *error = nil;
	NSString *password = [self savedPasswordForProfile:profile error:&error];
	if (error)
	{
		[self showErrorWithTitle:@"Keychain Error" message:[error localizedDescription]];
		return;
	}
	if ([password length] == 0)
	{
		[self presentPasswordPrompt];
		return;
	}
	[self startConnectionWithPassword:password];
}

- (void)presentPasswordPrompt
{
	if (_isPresentingPasswordPrompt)
		return;
	OrbisProfile *profile = [_profileStore selectedProfile];
	if (!profile)
		return;
	_isPresentingPasswordPrompt = YES;
	NSString *message = [NSString
	    stringWithFormat:@"Enter the Remote Desktop password for %@ on %@. It will be stored only "
	                     @"in iPad Keychain.",
	                     [profile username], [profile name]];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remote Desktop password"
	                                                               message:message
	                                                        preferredStyle:
	                                                            UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
		[textField setPlaceholder:@"Password"];
		[textField setSecureTextEntry:YES];
		[textField setTextContentType:UITextContentTypePassword];
		[textField setReturnKeyType:UIReturnKeyGo];
	}];
	[alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
	                                         style:UIAlertActionStyleCancel
	                                       handler:^(UIAlertAction *action) {
		                                       (void)action;
		                                       _isPresentingPasswordPrompt = NO;
	                                       }]];
	[alert addAction:[UIAlertAction
	                     actionWithTitle:@"Save and Connect"
	                               style:UIAlertActionStyleDefault
	                             handler:^(UIAlertAction *action) {
		                             (void)action;
		                             _isPresentingPasswordPrompt = NO;
		                             NSString *password = [[[alert textFields] firstObject] text];
		                             if ([password length] == 0)
		                             {
			                             [self showErrorWithTitle:@"Password Required"
			                                                    message:@"Enter the Remote Desktop "
			                                                            @"password."];
			                             return;
		                             }
		                             NSError *error = nil;
		                             if (![self savePassword:password forProfile:profile error:&error])
		                             {
			                             [self showErrorWithTitle:@"Keychain Error"
			                                                    message:[error localizedDescription]];
			                             return;
		                             }
		                             [self startConnectionWithPassword:password];
	                             }]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)startConnectionWithPassword:(NSString *)password
{
	OrbisProfile *profile = [_profileStore selectedProfile];
	if (!profile)
		return;
	NSError *certificateError = nil;
	if (![self discardStoredCertificateForProfile:profile error:&certificateError])
	{
		[self showErrorWithTitle:@"Certificate Store Error"
		                       message:[certificateError localizedDescription]];
		return;
	}
	[self setConnectionBusy:YES
	                   status:[NSString stringWithFormat:@"Connecting to %@…", [profile name]]];

	ConnectionParams *params =
	    [[[ConnectionParams alloc] initWithBaseDefaultParameters] autorelease];
	[params setValue:[profile host] forKey:@"hostname"];
	[params setInt:(int)[profile port] forKey:@"port"];
	[params setValue:[profile username] forKey:@"username"];
	[params setValue:password forKey:@"password"];
	[params setValue:@"" forKey:@"domain"];
	[params setBool:[profile acceptAllCertificates] forKey:@"accept_all_certificates"];
	[params setInt:0 forKey:@"width"];
	[params setInt:0 forKey:@"height"];

	ComputerBookmark *bookmark =
	    [[[ComputerBookmark alloc] initWithConnectionParameters:params] autorelease];
	[bookmark setLabel:[profile name]];
	[bookmark setConntectedViaWLAN:YES];

	RDPSession *session = [[[RDPSession alloc] initWithBookmark:bookmark] autorelease];
	if (!session)
	{
		[self setConnectionBusy:NO status:@"Could not create the RDP session"];
		return;
	}

	RDPSessionViewController *controller = [[[RDPSessionViewController alloc]
	    initWithNibName:@"RDPSessionView"
	            bundle:nil
	           session:session] autorelease];
	[controller setHidesBottomBarWhenPushed:YES];
	[[self navigationController] pushViewController:controller animated:YES];
}

- (void)setConnectionBusy:(BOOL)busy status:(NSString *)status
{
	_isStartingConnection = busy;
	NSString *newStatus = [status copy];
	[_connectionStatus release];
	_connectionStatus = newStatus;
	[_statusLabel setText:status];
	[_connectButton setEnabled:!busy];
	if (busy)
	{
		[_statusIconView setHidden:YES];
		[_activityIndicator startAnimating];
	}
	else
	{
		[_statusIconView setHidden:NO];
		[_activityIndicator stopAnimating];
		NSString *symbol = @"checkmark.circle.fill";
		UIColor *color = [UIColor systemGreenColor];
		if ([status isEqualToString:@"Connection failed"])
		{
			symbol = @"exclamationmark.triangle.fill";
			color = [UIColor systemRedColor];
		}
		else if ([status isEqualToString:@"Disconnected"])
		{
			symbol = @"wifi.slash";
			color = [UIColor systemOrangeColor];
		}
		[_statusIconView setImage:[UIImage systemImageNamed:symbol]];
		[_statusIconView setTintColor:color];
	}
}

- (void)showErrorWithTitle:(NSString *)title message:(NSString *)message
{
	[self setConnectionBusy:NO status:@"Ready to connect"];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
	                                                               message:message
	                                                        preferredStyle:
	                                                            UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK"
	                                         style:UIAlertActionStyleDefault
	                                       handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)sessionDidEnd:(NSNotification *)notification
{
	BOOL failed = [[notification name] isEqualToString:TSXSessionDidFailToConnectNotification];
	[self setConnectionBusy:NO status:(failed ? @"Connection failed" : @"Disconnected")];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_profileStore release];
	[_connectionsStack release];
	[_statusLabel release];
	[_statusIconView release];
	[_connectButton release];
	[_activityIndicator release];
	[_profileCardViews release];
	[_cardAnimator release];
	[_expandedProfileIdentifier release];
	[_connectionStatus release];
	[super dealloc];
}

@end
