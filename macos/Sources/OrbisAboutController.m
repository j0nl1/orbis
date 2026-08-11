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

	NSTextView *textView = [[[NSTextView alloc] initWithFrame:NSZeroRect] autorelease];
	[textView setEditable:NO];
	[textView setSelectable:YES];
	[textView setDrawsBackground:NO];
	[textView setTextContainerInset:NSMakeSize(8.0, 8.0)];
	[[textView textStorage] setAttributedString:[self acknowledgementText]];

	NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSZeroRect] autorelease];
	[scroll setBorderType:NSNoBorder];
	[scroll setDrawsBackground:NO];
	[scroll setHasVerticalScroller:YES];
	[scroll setAutohidesScrollers:YES];
	[scroll setDocumentView:textView];

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

	NSStackView *stack = [NSStackView stackViewWithViews:@[ header, scroll, footer ]];
	[stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[stack setAlignment:NSLayoutAttributeLeading];
	[stack setSpacing:18.0];
	[stack setTranslatesAutoresizingMaskIntoConstraints:NO];
	[content addSubview:stack];
	for (NSView *view in @[ header, scroll, footer ])
		[[view widthAnchor] constraintEqualToAnchor:[stack widthAnchor]].active = YES;
	[[scroll heightAnchor] constraintEqualToConstant:420.0].active = YES;
	[[done widthAnchor] constraintGreaterThanOrEqualToConstant:100.0].active = YES;
	[NSLayoutConstraint activateConstraints:@[
		[[stack leadingAnchor] constraintEqualToAnchor:[content leadingAnchor] constant:30.0],
		[[stack trailingAnchor] constraintEqualToAnchor:[content trailingAnchor] constant:-30.0],
		[[stack topAnchor] constraintEqualToAnchor:[content topAnchor] constant:26.0],
		[[stack bottomAnchor] constraintLessThanOrEqualToAnchor:[content bottomAnchor] constant:-24.0]
	]];
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

@end
