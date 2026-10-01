/* SPDX-License-Identifier: MIT */

#import "OrbisAboutController.h"

#import "OrbisAcknowledgements.h"

@implementation OrbisAboutController

- (id)init
{
	NSWindow *window = [[[NSWindow alloc]
	    initWithContentRect:NSMakeRect(0.0, 0.0, 560.0, 620.0)
	              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
	                backing:NSBackingStoreBuffered
	                  defer:NO] autorelease];
	if (!(self = [super initWithWindow:window]))
		return nil;
	[window setTitle:@"About Orbis"];
	[self buildContent];
	return self;
}

- (NSAttributedString *)acknowledgementText
{
	NSMutableAttributedString *text = [[[NSMutableAttributedString alloc] init] autorelease];
	NSDictionary *bodyAttributes = @{
		NSFontAttributeName : [NSFont systemFontOfSize:12.0],
		NSForegroundColorAttributeName : [NSColor secondaryLabelColor]
	};
	NSDictionary *nameAttributes = @{
		NSFontAttributeName : [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold],
		NSForegroundColorAttributeName : [NSColor labelColor]
	};

	[text appendAttributedString:[[[NSAttributedString alloc]
	    initWithString:[NSString stringWithFormat:@"%@\n\n", OrbisProductDescription]
	       attributes:bodyAttributes] autorelease]];
	[text appendAttributedString:[[[NSAttributedString alloc]
	    initWithString:@"Orbis is possible because these projects publish their work as open source. Thank you to their maintainers and contributors.\n\n"
	       attributes:bodyAttributes] autorelease]];

	for (NSDictionary *project in [OrbisAcknowledgements projects])
	{
		NSString *heading = [NSString stringWithFormat:@"%@  ·  %@\n",
		                                                 [project objectForKey:OrbisProjectNameKey],
		                                                 [project objectForKey:OrbisProjectLicenseKey]];
		[text appendAttributedString:[[[NSAttributedString alloc] initWithString:heading
		                                                              attributes:nameAttributes] autorelease]];
		NSString *description = [NSString stringWithFormat:@"%@\n",
		                                                       [project objectForKey:OrbisProjectDetailKey]];
		[text appendAttributedString:[[[NSAttributedString alloc] initWithString:description
		                                                              attributes:bodyAttributes] autorelease]];
		NSString *repository = @"Source repository\n\n";
		NSMutableAttributedString *link = [[[NSMutableAttributedString alloc]
		    initWithString:repository
		       attributes:bodyAttributes] autorelease];
		[link addAttribute:NSLinkAttributeName
		            value:[project objectForKey:OrbisProjectURLKey]
		            range:NSMakeRange(0, [@"Source repository" length])];
		[text appendAttributedString:link];
	}
	return text;
}

- (void)buildContent
{
	NSView *content = [[self window] contentView];
	[content setWantsLayer:YES];

	NSImageView *icon = [[[NSImageView alloc] initWithFrame:NSZeroRect] autorelease];
	[icon setImage:[NSApp applicationIconImage]];
	[icon setImageScaling:NSImageScaleProportionallyUpOrDown];
	[[icon widthAnchor] constraintEqualToConstant:72.0].active = YES;
	[[icon heightAnchor] constraintEqualToConstant:72.0].active = YES;

	NSTextField *title = [NSTextField labelWithString:@"Orbis"];
	[title setFont:[NSFont systemFontOfSize:24.0 weight:NSFontWeightSemibold]];
	NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
	NSString *version = [info objectForKey:@"CFBundleShortVersionString"] ?: @"Development";
	NSString *build = [info objectForKey:@"CFBundleVersion"] ?: @"local";
	NSTextField *versionLabel = [NSTextField
	    labelWithString:[NSString stringWithFormat:@"Version %@ (%@)", version, build]];
	[versionLabel setTextColor:[NSColor secondaryLabelColor]];

	NSStackView *identity = [NSStackView stackViewWithViews:@[ title, versionLabel ]];
	[identity setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[identity setAlignment:NSLayoutAttributeLeading];
	[identity setSpacing:2.0];
	NSStackView *header = [NSStackView stackViewWithViews:@[ icon, identity ]];
	[header setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
	[header setAlignment:NSLayoutAttributeCenterY];
	[header setSpacing:14.0];

	_tabs = [[NSTabView alloc] initWithFrame:NSZeroRect];
	[_tabs setTabViewType:NSNoTabsNoBorder];
	[_tabs setAccessibilityIdentifier:@"about-tabs"];
	NSArray *texts = @[ [self changelogText], [self acknowledgementText] ];
	NSArray *titles = @[ @"Changelog", @"Acknowledgements" ];
	for (NSUInteger index = 0; index < [titles count]; index++)
	{
		NSTabViewItem *item = [[[NSTabViewItem alloc] initWithIdentifier:titles[index]] autorelease];
		[item setLabel:titles[index]];
		[item setView:[self scrollViewWithText:texts[index]]];
		[_tabs addTabViewItem:item];
	}
	NSSegmentedControl *sections = [NSSegmentedControl segmentedControlWithLabels:titles
	    trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changeSection:)];
	[sections setSelectedSegment:0];
	[sections setControlSize:NSControlSizeLarge];
	[sections setAccessibilityLabel:@"About sections"];
	[sections setAccessibilityIdentifier:@"about-sections"];
	NSStackView *pages = [NSStackView stackViewWithViews:@[ sections, _tabs ]];
	[pages setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[pages setAlignment:NSLayoutAttributeCenterX];
	[pages setSpacing:12.0];
	[[_tabs widthAnchor] constraintEqualToAnchor:[pages widthAnchor]].active = YES;

	NSButton *done = [NSButton buttonWithTitle:@"Done" target:self action:@selector(closeSheet:)];
	[done setBezelStyle:NSBezelStyleRounded];
	[done setControlSize:NSControlSizeLarge];
	[done setKeyEquivalent:@"\r"];
	NSView *buttonSpacer = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
	[buttonSpacer setContentHuggingPriority:NSLayoutPriorityDefaultLow
	                           forOrientation:NSLayoutConstraintOrientationHorizontal];
	NSStackView *footer = [NSStackView stackViewWithViews:@[ buttonSpacer, done ]];
	[footer setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
	[footer setAlignment:NSLayoutAttributeCenterY];

	NSStackView *stack = [NSStackView stackViewWithViews:@[ header, pages, footer ]];
	[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[stack setAlignment:NSLayoutAttributeLeading];
	[stack setSpacing:18.0];
	[stack setTranslatesAutoresizingMaskIntoConstraints:NO];
	[content addSubview:stack];
	for (NSView *view in @[ header, pages, footer ])
		[[view widthAnchor] constraintEqualToAnchor:[stack widthAnchor]].active = YES;
	[[_tabs heightAnchor] constraintEqualToConstant:380.0].active = YES;
	[[done widthAnchor] constraintGreaterThanOrEqualToConstant:100.0].active = YES;
	[NSLayoutConstraint activateConstraints:@[
		[[stack leadingAnchor] constraintEqualToAnchor:[content leadingAnchor] constant:30.0],
		[[stack trailingAnchor] constraintEqualToAnchor:[content trailingAnchor] constant:-30.0],
		[[stack topAnchor] constraintEqualToAnchor:[content topAnchor] constant:26.0],
		[[stack bottomAnchor] constraintLessThanOrEqualToAnchor:[content bottomAnchor] constant:-24.0]
	]];
}

- (void)changeSection:(NSSegmentedControl *)sender
{
	[_tabs selectTabViewItemAtIndex:[sender selectedSegment]];
}

- (NSScrollView *)scrollViewWithText:(NSAttributedString *)text
{
	NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 480, 380)] autorelease];
	[scroll setBorderType:NSNoBorder];
	[scroll setDrawsBackground:NO];
	[scroll setHasVerticalScroller:YES];
	[scroll setAutohidesScrollers:YES];
	NSTextView *textView = [[[NSTextView alloc] initWithFrame:[[scroll contentView] bounds]] autorelease];
	[textView setEditable:NO];
	[textView setSelectable:YES];
	[textView setDrawsBackground:NO];
	[textView setTextContainerInset:NSMakeSize(14.0, 14.0)];
	[textView setVerticallyResizable:YES];
	[textView setHorizontallyResizable:NO];
	[textView setAutoresizingMask:NSViewWidthSizable];
	[textView setMaxSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
	[[textView textContainer] setWidthTracksTextView:YES];
	[[textView textStorage] setAttributedString:text];
	[scroll setDocumentView:textView];
	return scroll;
}

- (NSAttributedString *)changelogText
{
	NSURL *url = [[NSBundle mainBundle] URLForResource:@"CHANGELOG" withExtension:@"md"];
	NSString *source = url ? [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil] : nil;
	if (![source length])
		source = @"Changelog unavailable in this build.";
	NSMutableAttributedString *text = [[[NSMutableAttributedString alloc] init] autorelease];
	for (NSString *line in [source componentsSeparatedByString:@"\n"])
	{
		if ([line isEqualToString:@"# Changelog"])
			continue;
		BOOL release = [line hasPrefix:@"## "];
		BOOL section = [line hasPrefix:@"### "];
		NSString *display = (release || section) ? [line substringFromIndex:release ? 3 : 4] : line;
		if ([display isEqualToString:@"Unreleased"])
			display = @"Latest changes";
		if ([display hasPrefix:@"- "])
			display = [@"• " stringByAppendingString:[display substringFromIndex:2]];
		NSMutableParagraphStyle *paragraph = [[[NSMutableParagraphStyle alloc] init] autorelease];
		[paragraph setParagraphSpacing:release ? 8.0 : 5.0];
		[paragraph setLineSpacing:3.0];
		NSDictionary *attributes = @{
			NSFontAttributeName : [NSFont systemFontOfSize:release ? 17.0 : 12.0
			    weight:(release || section) ? NSFontWeightSemibold : NSFontWeightRegular],
			NSForegroundColorAttributeName : [NSColor labelColor],
			NSParagraphStyleAttributeName : paragraph
		};
		[text appendAttributedString:[[[NSAttributedString alloc]
		    initWithString:[display stringByAppendingString:@"\n"] attributes:attributes] autorelease]];
	}
	return text;
}

- (void)beginSheetForWindow:(NSWindow *)parentWindow
{
	[parentWindow beginSheet:[self window] completionHandler:nil];
}

- (void)closeSheet:(id)sender
{
	(void)sender;
	NSWindow *parent = [[self window] sheetParent];
	if (parent)
		[parent endSheet:[self window]];
}

- (void)dealloc
{
	[_tabs release];
	[super dealloc];
}

@end
