//==============================================================================
//
// File:		PartBrowserLimitViews.m
//
// Purpose:		The Part Browser's views for the parts limit: the bar over the
//				list, the color strip under the preview, and color swatches.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//==============================================================================
#import "PartBrowserLimitViews.h"

#import <LDrawCore/LDrawColorLibrary.h>
#import <LDrawFeatures/LDrawPartBrowserModel.h>

static const CGFloat BarInset			= 6.0;
static const CGFloat ChipSize			= 18.0;
static const CGFloat ChipSpacing		= 4.0;
static const CGFloat StripInset			= 5.0;
static const NSUInteger StripMaxRows	= 2;


//========== PartBrowserSwatchImage ============================================
//
// Purpose:		A rounded square of the color, with a ring around it when
//				ringed, or a red line through it when struck.
//
//==============================================================================
NSImage *PartBrowserSwatchImage(LDrawColorT colorCode, NSSize size, BOOL ringed, BOOL struck)
{
	LDrawColor	*color		= [[LDrawColorLibrary sharedColorLibrary] colorForCode:colorCode];
	float		 rgba[4]	= {0.5f, 0.5f, 0.5f, 1.0f};

	[color getColorRGBA:rgba];

	// A block cannot capture a C array, so the color is made here.
	NSColor *fill = [NSColor colorWithSRGBRed:rgba[0] green:rgba[1] blue:rgba[2] alpha:MAX(rgba[3], 0.35f)];

	return [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect bounds) {
		NSRect			 swatch	= NSInsetRect(bounds, ringed ? 3.0 : 1.0, ringed ? 3.0 : 1.0);
		NSBezierPath	*path	= [NSBezierPath bezierPathWithRoundedRect:swatch xRadius:3 yRadius:3];

		[fill setFill];
		[path fill];
		[[NSColor colorWithWhite:0.0 alpha:0.35] setStroke];
		[path setLineWidth:1.0];
		[path stroke];

		if(ringed)
		{
			NSBezierPath *ring = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 1.0, 1.0)
																 xRadius:4.5 yRadius:4.5];
			[[NSColor controlAccentColor] setStroke];
			[ring setLineWidth:2.0];
			[ring stroke];
		}

		if(struck)
		{
			NSBezierPath *line = [NSBezierPath bezierPath];
			[line moveToPoint:NSMakePoint(NSMinX(swatch), NSMinY(swatch))];
			[line lineToPoint:NSMakePoint(NSMaxX(swatch), NSMaxY(swatch))];
			[[NSColor systemRedColor] setStroke];
			[line setLineWidth:2.0];
			[line stroke];
		}
		return YES;
	}];

}//end PartBrowserSwatchImage


//========== ColorName =========================================================
//==============================================================================
static NSString *ColorName(LDrawColorT colorCode)
{
	return [[[LDrawColorLibrary sharedColorLibrary] colorForCode:colorCode] localizedName]
		   ?: [NSString stringWithFormat:@"%d", colorCode];
}


@implementation PartBrowserLimitBar
{
	NSTextField	*label;
}

//========== initWithFrame: ====================================================
//==============================================================================
- (instancetype) initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if (self)
	{
		label		= [NSTextField labelWithString:@""];
		_button		= [NSButton buttonWithTitle:@"" target:nil action:NULL];

		[label setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
		[label setTextColor:[NSColor secondaryLabelColor]];
		[label setLineBreakMode:NSLineBreakByTruncatingTail];
		[_button setBezelStyle:NSBezelStyleRecessed];
		[_button setShowsBorderOnlyWhileMouseInside:YES];
		[_button setControlSize:NSControlSizeSmall];
		[_button setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];

		[self addSubview:label];
		[self addSubview:_button];
	}
	return self;
}


//========== setText:buttonTitle: =============================================
//==============================================================================
- (void) setText:(NSString *)text buttonTitle:(NSString *)buttonTitle
{
	[label setStringValue:text];
	[label setToolTip:text];
	[_button setTitle:buttonTitle ?: @""];
	[_button setHidden:(buttonTitle == nil)];
	[self setNeedsLayout:YES];
}


//========== layout ============================================================
//
// Purpose:		The button at the end, the text before it.
//
//==============================================================================
- (void) layout
{
	NSRect	bounds	= [self bounds];
	NSRect	button	= NSZeroRect;
	NSRect	text	= NSZeroRect;
	CGFloat	right	= NSMaxX(bounds) - BarInset;

	[super layout];

	if([_button isHidden] == NO)
	{
		[_button sizeToFit];
		button			= [_button frame];
		button.origin.x	= right - NSWidth(button);
		button.origin.y	= NSMidY(bounds) - NSHeight(button) / 2;
		[_button setFrame:button];
		right = NSMinX(button) - BarInset;
	}

	text.size.height	= ceil([[label cell] cellSize].height);
	text.origin.x		= NSMinX(bounds) + BarInset;
	text.origin.y		= NSMidY(bounds) - NSHeight(text) / 2;
	text.size.width		= MAX(right - NSMinX(text), 0);
	[label setFrame:text];
}


//========== drawRect: =========================================================
//
// Purpose:		Fills the background and draws a line under it.
//
//==============================================================================
- (void) drawRect:(NSRect)dirtyRect
{
	NSRect bounds = [self bounds];

	[[NSColor controlBackgroundColor] setFill];
	NSRectFill(bounds);
	[[NSColor separatorColor] setFill];
	NSRectFill(NSMakeRect(NSMinX(bounds), [self isFlipped] ? NSMaxY(bounds) - 1 : NSMinY(bounds),
						  NSWidth(bounds), 1));
}

@end


@implementation PartColorStripView
{
	NSArray<LDrawPartBrowserColorChip *>	*chips;
	LDrawColorT								 currentColor;
	NSNumber								*struckColor;
	NSString								*struckTooltip;
	CGFloat									 laidOutWidth;
}


//========== setChips:currentColor:struckColor:struckTooltip: ==================
//==============================================================================
- (void) setChips:(NSArray<LDrawPartBrowserColorChip *> *)newChips
	 currentColor:(LDrawColorT)newCurrentColor
	  struckColor:(NSNumber *)newStruckColor
	struckTooltip:(NSString *)newStruckTooltip
{
	self->chips			= [newChips copy];
	self->currentColor	= newCurrentColor;
	self->struckColor	= newStruckColor;
	self->struckTooltip	= [newStruckTooltip copy];
	self->laidOutWidth	= -1;

	[self setHidden:([newChips count] == 0)];
	[self rebuild];
	[[self superview] setNeedsLayout:YES];
}


//========== rebuild ===========================================================
//
// Purpose:		Makes a button per chip, in rows that fit the width. What does
//				not fit in two rows goes into a "+N" chip's menu.
//
//==============================================================================
- (void) rebuild
{
	CGFloat			 width		= NSWidth([self bounds]);
	NSMutableArray	*buttons	= [NSMutableArray array];
	NSMutableArray	*rest		= [NSMutableArray array];
	CGFloat			 x			= StripInset;
	NSUInteger		 row		= 0;
	NSFont			*font		= [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];

	[[self subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];
	self->laidOutWidth = width;

	if(self->struckColor != nil)
	{
		NSButton *struck = [self chipButtonWithColor:(LDrawColorT)[self->struckColor intValue]
											   title:nil ringed:YES struck:YES font:font];
		[struck setToolTip:self->struckTooltip];
		[struck setTag:-1];
		[buttons addObject:struck];
	}

	for(NSUInteger index = 0; index < [self->chips count]; index++)
	{
		LDrawPartBrowserColorChip	*chip	= self->chips[index];
		NSString					*count	= chip.hasCount ? [NSString stringWithFormat:@"%ld", (long)chip.leftCount]
															: nil;
		NSButton					*button	= [self chipButtonWithColor:chip.colorCode
																  title:count
																 ringed:(chip.colorCode == self->currentColor)
																 struck:NO
																   font:font];
		NSString					*tip	= ColorName(chip.colorCode);

		if(chip.hasCount)
			tip = [NSString stringWithFormat:NSLocalizedString(@"%@: %ld left", nil), tip, (long)chip.leftCount];
		[button setToolTip:tip];
		[button setTag:(NSInteger)index];
		[button setTarget:self];
		[button setAction:@selector(chipClicked:)];
		[buttons addObject:button];
	}

	// Place the buttons in rows. The last place of the last row keeps room for
	// the "+N" chip when some do not fit.
	for(NSUInteger index = 0; index < [buttons count]; index++)
	{
		NSButton	*button		= buttons[index];
		CGFloat		 buttonWidth	= NSWidth([button frame]);
		BOOL		 lastRow	= (row == StripMaxRows - 1);
		CGFloat		 reserve	= (lastRow && index + 1 < [buttons count]) ? ChipSize * 2 + ChipSpacing : 0;

		if(x + buttonWidth + reserve > width - StripInset && x > StripInset)
		{
			if(lastRow)
			{
				[rest addObjectsFromArray:[buttons subarrayWithRange:NSMakeRange(index, [buttons count] - index)]];
				break;
			}
			row++;
			x = StripInset;
		}
		[button setFrameOrigin:NSMakePoint(x, StripInset + row * (ChipSize + ChipSpacing))];
		[self addSubview:button];
		x += buttonWidth + ChipSpacing;
	}

	if([rest count] > 0)
	{
		NSButton *more = [NSButton buttonWithTitle:[NSString stringWithFormat:@"+%lu", (unsigned long)[rest count]]
											target:self
											action:@selector(showMore:)];
		[more setBezelStyle:NSBezelStyleRecessed];
		[more setControlSize:NSControlSizeSmall];
		[more setFont:font];
		[more sizeToFit];
		[more setFrame:NSMakeRect(x, StripInset + row * (ChipSize + ChipSpacing), NSWidth([more frame]), ChipSize)];
		[[more cell] setRepresentedObject:rest];
		[self addSubview:more];
	}

	// Rows count from the bottom, as the view is not flipped; the first row
	// goes on top.
	NSUInteger	rows	= row + 1;
	CGFloat		height	= StripInset * 2 + rows * ChipSize + (rows - 1) * ChipSpacing;

	for(NSView *view in [self subviews])
	{
		NSRect frame = [view frame];
		frame.origin.y = height - StripInset - ChipSize - (frame.origin.y - StripInset);
		[view setFrame:frame];
	}

	if(NSHeight([self frame]) != height)
	{
		[self setFrameSize:NSMakeSize(NSWidth([self frame]), height)];
		[[self superview] setNeedsLayout:YES];
	}

}//end rebuild


//========== chipButtonWithColor:title:ringed:struck:font: =====================
//==============================================================================
- (NSButton *) chipButtonWithColor:(LDrawColorT)colorCode
							 title:(NSString *)title
							ringed:(BOOL)ringed
							struck:(BOOL)struck
							  font:(NSFont *)font
{
	NSImage		*image	= PartBrowserSwatchImage(colorCode, NSMakeSize(ChipSize, ChipSize), ringed, struck);
	NSButton	*button	= [NSButton buttonWithImage:image target:nil action:NULL];

	[button setBordered:NO];
	[button setImagePosition:(title != nil) ? NSImageLeading : NSImageOnly];
	[button setImageScaling:NSImageScaleNone];
	if(title != nil)
	{
		[button setTitle:title];
		[button setFont:font];
	}
	[button sizeToFit];
	[button setFrameSize:NSMakeSize(MAX(NSWidth([button frame]), ChipSize), ChipSize)];
	return button;
}


//========== layout ============================================================
//
// Purpose:		Lays the chips out again when the width changed.
//
//==============================================================================
- (void) layout
{
	[super layout];
	if(NSWidth([self bounds]) != self->laidOutWidth)
		[self rebuild];
}


//========== chipClicked: ======================================================
//==============================================================================
- (void) chipClicked:(id)sender
{
	NSInteger index = [sender tag];

	if(index < 0 || index >= (NSInteger)[self->chips count])
		return;
	self->_clickedChip = self->chips[index];
	[NSApp sendAction:self.action to:self.target from:self];
}


//========== showMore: =========================================================
//
// Purpose:		A menu of the chips that did not fit.
//
//==============================================================================
- (void) showMore:(id)sender
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];

	for(NSButton *button in [[sender cell] representedObject])
	{
		NSMenuItem *item = [menu addItemWithTitle:[button toolTip] ?: @""
										   action:@selector(chipClicked:)
									keyEquivalent:@""];
		[item setImage:[button image]];
		[item setTag:[button tag]];
		[item setTarget:self];
		[item setEnabled:([button action] != NULL)];
	}
	[menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight([sender bounds])) inView:sender];
}

@end
