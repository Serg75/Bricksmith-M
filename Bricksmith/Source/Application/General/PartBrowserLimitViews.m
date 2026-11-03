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

	// A block cannot capture a C array, so the color is made here. A clear
	// color keeps enough alpha to be seen.
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
																 xRadius:4.5
																 yRadius:4.5];
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


//========== SmallFont =========================================================
//==============================================================================
static NSFont *SmallFont(void)
{
	return [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
}


//========== StripRowY =========================================================
//
// Purpose:		The top of a row of chips in the strip.
//
//==============================================================================
static CGFloat StripRowY(NSUInteger row)
{
	return StripInset + row * (ChipSize + ChipSpacing);
}


////////////////////////////////////////////////////////////////////////////////
//
// class PartBrowserLimitBar
//
////////////////////////////////////////////////////////////////////////////////
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

		[label setFont:SmallFont()];
		[label setTextColor:[NSColor secondaryLabelColor]];
		[label setLineBreakMode:NSLineBreakByTruncatingTail];
		[_button setBezelStyle:NSBezelStyleRecessed];
		[_button setShowsBorderOnlyWhileMouseInside:YES];
		[_button setControlSize:NSControlSizeSmall];
		[_button setFont:SmallFont()];

		[self addSubview:label];
		[self addSubview:_button];
	}
	return self;
}


//========== setText:buttonTitle: ==============================================
//==============================================================================
- (void) setText:(NSString *)text buttonTitle:(NSString *)buttonTitle
{
	[label setStringValue:text];
	[label setToolTip:text];
	[_button setTitle:buttonTitle];
	[self setNeedsLayout:YES];
}


//========== layout ============================================================
//
// Purpose:		Puts the button at the end and the text before it.
//
//==============================================================================
- (void) layout
{
	NSRect	bounds	= [self bounds];
	NSRect	button	= NSZeroRect;
	NSRect	text	= NSZeroRect;

	[super layout];

	[_button sizeToFit];
	button			= [_button frame];
	button.origin.x	= NSMaxX(bounds) - BarInset - NSWidth(button);
	button.origin.y	= NSMidY(bounds) - NSHeight(button) / 2;
	[_button setFrame:button];

	text.size.height	= ceil([[label cell] cellSize].height);
	text.origin.x		= NSMinX(bounds) + BarInset;
	text.origin.y		= NSMidY(bounds) - NSHeight(text) / 2;
	text.size.width		= MAX(NSMinX(button) - BarInset - NSMinX(text), 0);
	[label setFrame:text];
}


//========== drawRect: =========================================================
//
// Purpose:		Fills the background and draws a line along the bottom.
//
//==============================================================================
- (void) drawRect:(NSRect)dirtyRect
{
	NSRect bounds = [self bounds];

	[[NSColor controlBackgroundColor] setFill];
	NSRectFill(bounds);
	[[NSColor separatorColor] setFill];
	NSRectFill(NSMakeRect(NSMinX(bounds), NSMinY(bounds), NSWidth(bounds), 1));
}

@end


////////////////////////////////////////////////////////////////////////////////
//
// class PartColorStripView
//
////////////////////////////////////////////////////////////////////////////////
@implementation PartColorStripView
{
	NSArray<LDrawPartBrowserColorChip *>	*chips;
	LDrawColorT								 currentColor;
	NSNumber								*struckColor;
	NSString								*struckTooltip;
	CGFloat									 laidOutWidth;
}


//========== isFlipped =========================================================
//
// Purpose:		The rows are placed from the top.
//
//==============================================================================
- (BOOL) isFlipped
{
	return YES;
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

	[self setHidden:([newChips count] == 0)];
	[self rebuild];

	// The container gives the strip room only while it shows.
	[[self superview] setNeedsLayout:YES];
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


//========== rebuild ===========================================================
//
// Purpose:		Places a button per chip in rows that fit the width. What does
//				not fit in two rows goes into a "+N" chip's menu.
//
//==============================================================================
- (void) rebuild
{
	CGFloat		 width		= NSWidth([self bounds]);
	NSArray		*buttons	= [self makeChipButtons];
	NSArray		*rest		= nil;
	CGFloat		 x			= StripInset;
	NSUInteger	 row		= 0;
	CGFloat		 height		= 0;

	[[self subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];
	self->laidOutWidth = width;

	for(NSUInteger index = 0; index < [buttons count]; index++)
	{
		NSButton	*button			= buttons[index];
		CGFloat		 buttonWidth	= NSWidth([button frame]);
		BOOL		 lastRow		= (row == StripMaxRows - 1);
		CGFloat		 reserve		= 0;

		// The last row keeps room for the "+N" chip while more buttons follow.
		if(lastRow && index + 1 < [buttons count])
			reserve = ChipSize * 2 + ChipSpacing;

		if(x + buttonWidth + reserve > width - StripInset && x > StripInset)
		{
			if(lastRow)
			{
				rest = [buttons subarrayWithRange:NSMakeRange(index, [buttons count] - index)];
				break;
			}
			row++;
			x = StripInset;
		}
		[button setFrameOrigin:NSMakePoint(x, StripRowY(row))];
		[self addSubview:button];
		x += buttonWidth + ChipSpacing;
	}

	if(rest != nil)
	{
		NSString	*title	= [NSString stringWithFormat:@"+%lu", (unsigned long)[rest count]];
		NSButton	*more	= [NSButton buttonWithTitle:title target:self action:@selector(showMore:)];

		[more setBezelStyle:NSBezelStyleRecessed];
		[more setControlSize:NSControlSizeSmall];
		[more setFont:SmallFont()];
		[more sizeToFit];
		[more setFrame:NSMakeRect(x, StripRowY(row), NSWidth([more frame]), ChipSize)];
		[[more cell] setRepresentedObject:rest];
		[self addSubview:more];
	}

	height = StripInset * 2 + (row + 1) * ChipSize + row * ChipSpacing;
	if(NSHeight([self frame]) != height)
	{
		[self setFrameSize:NSMakeSize(NSWidth([self frame]), height)];
		[[self superview] setNeedsLayout:YES];
	}

}//end rebuild


//========== makeChipButtons ===================================================
//
// Purpose:		A button per chip, after the struck color's when there is one.
//				The struck button has no action and the tag -1.
//
//==============================================================================
- (NSArray<NSButton *> *) makeChipButtons
{
	NSMutableArray *buttons = [NSMutableArray array];

	if(self->struckColor != nil)
	{
		NSButton *struck = [self chipButtonWithColor:(LDrawColorT)[self->struckColor intValue]
											   title:nil
											  ringed:YES
											  struck:YES];
		[struck setToolTip:self->struckTooltip];
		[struck setTag:-1];
		[buttons addObject:struck];
	}

	for(NSUInteger index = 0; index < [self->chips count]; index++)
	{
		LDrawPartBrowserColorChip	*chip	= self->chips[index];
		NSString					*count	= nil;
		NSString					*tip	= ColorName(chip.colorCode);
		NSButton					*button	= nil;

		if(chip.hasCount)
		{
			count	= [NSString stringWithFormat:@"%ld", (long)chip.leftCount];
			tip		= [NSString stringWithFormat:NSLocalizedString(@"%@: %ld left", nil), tip, (long)chip.leftCount];
		}

		button = [self chipButtonWithColor:chip.colorCode
									 title:count
									ringed:(chip.colorCode == self->currentColor)
									struck:NO];
		[button setToolTip:tip];
		[button setTag:(NSInteger)index];
		[button setTarget:self];
		[button setAction:@selector(chipClicked:)];
		[buttons addObject:button];
	}

	return buttons;

}//end makeChipButtons


//========== chipButtonWithColor:title:ringed:struck: ==========================
//
// Purpose:		A swatch button, with the title after the swatch when given.
//
//==============================================================================
- (NSButton *) chipButtonWithColor:(LDrawColorT)colorCode
							 title:(NSString *)title
							ringed:(BOOL)ringed
							struck:(BOOL)struck
{
	NSImage		*image	= PartBrowserSwatchImage(colorCode, NSMakeSize(ChipSize, ChipSize), ringed, struck);
	NSButton	*button	= [NSButton buttonWithImage:image target:nil action:NULL];

	[button setBordered:NO];
	[button setImagePosition:(title != nil) ? NSImageLeading : NSImageOnly];
	[button setImageScaling:NSImageScaleNone];
	if(title != nil)
	{
		[button setTitle:title];
		[button setFont:SmallFont()];
	}
	[button sizeToFit];
	[button setFrameSize:NSMakeSize(MAX(NSWidth([button frame]), ChipSize), ChipSize)];
	return button;
}


//========== chipClicked: ======================================================
//
// Purpose:		Sends the action for a chip button or a "+N" menu item.
//
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
// Purpose:		Shows a menu of the chips that did not fit.
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
