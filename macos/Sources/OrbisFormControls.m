/* SPDX-License-Identifier: MIT */
#import "OrbisFormControls.h"

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

void OrbisConfigureFormField(NSTextField *field, NSString *identifier)
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

