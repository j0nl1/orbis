/* SPDX-License-Identifier: MIT */

#import "OrbisAboutController.h"

#import "OrbisAcknowledgements.h"

@implementation OrbisAboutController

- (void)viewDidLoad
{
	[super viewDidLoad];
	[self setTitle:@"About Orbis"];
	[[self view] setBackgroundColor:[UIColor systemGroupedBackgroundColor]];
	[[self navigationItem] setRightBarButtonItem:[[[UIBarButtonItem alloc]
	    initWithBarButtonSystemItem:UIBarButtonSystemItemDone
	                     target:self
	                     action:@selector(close:)] autorelease]];

	UIScrollView *scroll = [[[UIScrollView alloc] init] autorelease];
	[scroll setAlwaysBounceVertical:YES];
	[scroll setTranslatesAutoresizingMaskIntoConstraints:NO];
	[[self view] addSubview:scroll];

	UIView *content = [[[UIView alloc] init] autorelease];
	[content setTranslatesAutoresizingMaskIntoConstraints:NO];
	[scroll addSubview:content];

	UIImageView *icon = [[[UIImageView alloc] initWithImage:[UIImage imageNamed:@"OrbisIcon.png"]]
	    autorelease];
	[icon setContentMode:UIViewContentModeScaleAspectFit];
	[[icon widthAnchor] constraintEqualToConstant:96.0].active = YES;
	[[icon heightAnchor] constraintEqualToConstant:96.0].active = YES;

	UILabel *title = [[[UILabel alloc] init] autorelease];
	[title setText:@"Orbis"];
	[title setFont:[UIFont preferredFontForTextStyle:UIFontTextStyleTitle1]];
	[title setTextAlignment:NSTextAlignmentCenter];
	[title setAdjustsFontForContentSizeCategory:YES];

	NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
	NSString *version = [info objectForKey:@"CFBundleShortVersionString"] ?: @"Development";
	NSString *build = [info objectForKey:@"CFBundleVersion"] ?: @"local";
	UILabel *versionLabel = [[[UILabel alloc] init] autorelease];
	[versionLabel setText:[NSString stringWithFormat:@"Version %@ (%@)", version, build]];
	[versionLabel setFont:[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]];
	[versionLabel setTextColor:[UIColor secondaryLabelColor]];
	[versionLabel setTextAlignment:NSTextAlignmentCenter];

	UILabel *description = [[[UILabel alloc] init] autorelease];
	[description setText:OrbisProductDescription];
	[description setFont:[UIFont preferredFontForTextStyle:UIFontTextStyleBody]];
	[description setTextColor:[UIColor secondaryLabelColor]];
	[description setTextAlignment:NSTextAlignmentCenter];
	[description setNumberOfLines:0];
	[description setAdjustsFontForContentSizeCategory:YES];

	UILabel *thanks = [[[UILabel alloc] init] autorelease];
	[thanks setText:@"Orbis is possible because these projects publish their work as open source. Thank you to their maintainers and contributors."];
	[thanks setFont:[UIFont preferredFontForTextStyle:UIFontTextStyleBody]];
	[thanks setTextColor:[UIColor secondaryLabelColor]];
	[thanks setTextAlignment:NSTextAlignmentCenter];
	[thanks setNumberOfLines:0];

	UIStackView *projects = [[[UIStackView alloc] init] autorelease];
	[projects setAxis:UILayoutConstraintAxisVertical];
	[projects setSpacing:10.0];
	NSUInteger index = 0;
	for (NSDictionary *project in [OrbisAcknowledgements projects])
	{
		UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
		UIButtonConfiguration *configuration = [UIButtonConfiguration tintedButtonConfiguration];
		[configuration setTitle:[NSString stringWithFormat:@"%@  ·  %@",
		                                                        [project objectForKey:OrbisProjectNameKey],
		                                                        [project objectForKey:OrbisProjectLicenseKey]]];
		[configuration setSubtitle:[project objectForKey:OrbisProjectDetailKey]];
		[configuration setImage:[UIImage systemImageNamed:@"arrow.up.right"]];
		[configuration setImagePlacement:NSDirectionalRectEdgeTrailing];
		[configuration setImagePadding:12.0];
		[configuration setTitleAlignment:UIButtonConfigurationTitleAlignmentLeading];
		[configuration setCornerStyle:UIButtonConfigurationCornerStyleLarge];
		[configuration setBaseForegroundColor:[UIColor labelColor]];
		[button setConfiguration:configuration];
		[button setTag:(NSInteger)index++];
		[button addTarget:self
		           action:@selector(openProject:)
		 forControlEvents:UIControlEventTouchUpInside];
		[button setAccessibilityHint:@"Opens the project source repository"];
		[[button heightAnchor] constraintGreaterThanOrEqualToConstant:64.0].active = YES;
		[projects addArrangedSubview:button];
	}

	UIStackView *stack = [[[UIStackView alloc]
	    initWithArrangedSubviews:@[ icon, title, versionLabel, description, thanks, projects ]]
	    autorelease];
	[stack setAxis:UILayoutConstraintAxisVertical];
	[stack setAlignment:UIStackViewAlignmentCenter];
	[stack setSpacing:10.0];
	[stack setCustomSpacing:20.0 afterView:versionLabel];
	[stack setCustomSpacing:20.0 afterView:description];
	[stack setCustomSpacing:22.0 afterView:thanks];
	[stack setTranslatesAutoresizingMaskIntoConstraints:NO];
	[content addSubview:stack];
	[[description widthAnchor] constraintEqualToAnchor:[stack widthAnchor]].active = YES;
	[[thanks widthAnchor] constraintEqualToAnchor:[stack widthAnchor]].active = YES;
	[[projects widthAnchor] constraintEqualToAnchor:[stack widthAnchor]].active = YES;

	UILayoutGuide *safeArea = [[self view] safeAreaLayoutGuide];
	[NSLayoutConstraint activateConstraints:@[
		[[scroll leadingAnchor] constraintEqualToAnchor:[safeArea leadingAnchor]],
		[[scroll trailingAnchor] constraintEqualToAnchor:[safeArea trailingAnchor]],
		[[scroll topAnchor] constraintEqualToAnchor:[safeArea topAnchor]],
		[[scroll bottomAnchor] constraintEqualToAnchor:[[self view] bottomAnchor]],
		[[content leadingAnchor] constraintEqualToAnchor:[[scroll contentLayoutGuide] leadingAnchor]],
		[[content trailingAnchor] constraintEqualToAnchor:[[scroll contentLayoutGuide] trailingAnchor]],
		[[content topAnchor] constraintEqualToAnchor:[[scroll contentLayoutGuide] topAnchor]],
		[[content bottomAnchor] constraintEqualToAnchor:[[scroll contentLayoutGuide] bottomAnchor]],
		[[content widthAnchor] constraintEqualToAnchor:[[scroll frameLayoutGuide] widthAnchor]],
		[[stack leadingAnchor] constraintEqualToAnchor:[content leadingAnchor] constant:28.0],
		[[stack trailingAnchor] constraintEqualToAnchor:[content trailingAnchor] constant:-28.0],
		[[stack topAnchor] constraintEqualToAnchor:[content topAnchor] constant:28.0],
		[[stack bottomAnchor] constraintEqualToAnchor:[content bottomAnchor] constant:-36.0]
	]];
}

- (void)openProject:(UIButton *)sender
{
	NSArray *projects = [OrbisAcknowledgements projects];
	NSInteger index = [sender tag];
	if (index < 0 || (NSUInteger)index >= [projects count])
		return;
	NSString *value = [[projects objectAtIndex:(NSUInteger)index] objectForKey:OrbisProjectURLKey];
	NSURL *url = [NSURL URLWithString:value];
	if (url)
		[[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)close:(id)sender
{
	(void)sender;
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
