//==============================================================================
//
// File:		StepPartListChromeView.m
//
// Purpose:		Draws everything in the step parts list that is not a part.
//
// Notes:		Rectangles come from the layout, colors and point sizes from
//				the policy. This view only strokes, fills and draws text, so
//				another host can reuse the layout with its own view.
//
// Created by Sergey Slobodenyuk on 2026-09-10.
//
//==============================================================================
#import "StepPartListChromeView.h"

#import <LDrawCore/LDrawStepPartListEntry.h>
#import <LDrawFeatures/LDrawStepPartListLayout.h>
#import <LDrawFeatures/LDrawStepPartListModelBuilder.h>


//========== StepPartListColorFromRGBA =========================================
///
/// @abstract	Makes an AppKit color from four sRGB floats.
///
//==============================================================================
NSColor *StepPartListColorFromRGBA(const double *rgba)
{
	return [NSColor colorWithSRGBRed:rgba[0] green:rgba[1] blue:rgba[2] alpha:rgba[3]];

}//end StepPartListColorFromRGBA


//========== StepPartListRectFromBox ===========================================
///
/// @abstract	Makes an AppKit rect from a layout box. The views are flipped,
///				so the numbers copy straight across.
///
//==============================================================================
NSRect StepPartListRectFromBox(Box2 box)
{
	return NSMakeRect(box.origin.x, box.origin.y, box.size.width, box.size.height);

}//end StepPartListRectFromBox


@implementation StepPartListChromeView

//========== isFlipped =========================================================
///
/// @abstract	Layout coordinates run y-down, so the view does too.
///
//==============================================================================
- (BOOL) isFlipped
{
	return YES;

}//end isFlipped


//========== setLayout: ========================================================
- (void) setLayout:(LDrawStepPartListLayout *)layout
{
	self->_layout = layout;
	[self setNeedsDisplay:YES];

}//end setLayout:


//========== setChrome: ========================================================
- (void) setChrome:(LDrawStepPartListChrome)chrome
{
	self->_chrome = chrome;
	[self setNeedsDisplay:YES];

}//end setChrome:


// MARK: - DRAWING -


//========== drawRect: =========================================================
///
/// @abstract	Draws the cell decorations over the icons.
///
//==============================================================================
- (void) drawRect:(NSRect)dirtyRect
{
	LDrawStepPartListLayout *layout = self.layout;

	if (layout == nil) {
		return;
	}

	for (LDrawStepPartListPlacement *placement in layout.placements) {

		if ([LDrawStepPartListModelBuilder isDrawablePlacement:placement] == NO) {
			[self drawPlaceholderInRect:StepPartListRectFromBox(placement.iconFrame)];
		}

		[self drawAnnotationForPlacement:placement];
		[self drawLabelForPlacement:placement];
	}

	[self drawOverflowNotice];

}//end drawRect:


//========== drawLabelForPlacement: ============================================
///
/// @abstract	Draws the quantity, centered under the icon.
///
//==============================================================================
- (void) drawLabelForPlacement:(LDrawStepPartListPlacement *)placement
{
	[self drawText:[LDrawStepPartListLayout quantityTextForQuantity:placement.entry.quantity]
			inRect:StepPartListRectFromBox(placement.labelFrame)
		 pointSize:self.chrome.labelPointSize
			 color:StepPartListColorFromRGBA(self.chrome.labelRGBA)
			  bold:YES];

}//end drawLabelForPlacement:


//========== drawPlaceholderInRect: ============================================
///
/// @abstract	Draws a dashed box where a part would be, for a reference that
///				does not resolve. It shows the part is missing, not absent.
///
//==============================================================================
- (void) drawPlaceholderInRect:(NSRect)rect
{
	if (NSIsEmptyRect(rect)) {
		return;
	}

	NSBezierPath	*path		= [NSBezierPath bezierPathWithRect:NSInsetRect(rect, 1.0, 1.0)];
	CGFloat			 pattern[2]	= { self.chrome.placeholderDashLength, self.chrome.placeholderGapLength };

	[path setLineWidth:1.0];
	[path setLineDash:pattern count:2 phase:0.0];
	[StepPartListColorFromRGBA(self.chrome.borderRGBA) set];
	[path stroke];

}//end drawPlaceholderInRect:


//========== drawAnnotationForPlacement: =======================================
///
/// @abstract	Draws the part's size in studs as a badge.
///
/// @discussion	Long thin parts look alike, so the size tells them apart. A
///				part drawn at reduced scale gets the marker color.
///
//==============================================================================
- (void) drawAnnotationForPlacement:(LDrawStepPartListPlacement *)placement
{
	NSString	*text	= placement.annotationText;
	NSRect		 slot	= StepPartListRectFromBox(placement.annotationFrame);

	if (text == nil || NSIsEmptyRect(slot)) {
		return;
	}

	LDrawStepPartListChrome		chrome	= self.chrome;
	LDrawStepPartListBadgeStyle	style	= [LDrawStepPartListPolicy badgeStyleForScaledDownPart:placement.isScaledDown
																						chrome:chrome];

	NSFont	*font	= [NSFont systemFontOfSize:chrome.annotationPointSize weight:NSFontWeightMedium];
	NSColor	*color	= StepPartListColorFromRGBA(style.textRGBA);

	NSDictionary *attributes = @{
		NSFontAttributeName:			font,
		NSForegroundColorAttributeName:	color,
	};

	NSSize	textSize	= [text sizeWithAttributes:attributes];
	Box2	badgeBox	= [LDrawStepPartListLayout badgeRectForTextSize:V2MakeSize(textSize.width, textSize.height)
																 inSlot:placement.annotationFrame];
	NSRect	badge		= StepPartListRectFromBox(badgeBox);
	CGFloat	radius		= NSHeight(badge) / 2.0;

	// Stroke on the half-point so a one-point outline is crisp.
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(badge, 0.5, 0.5)
														 xRadius:radius
														 yRadius:radius];

	[StepPartListColorFromRGBA(style.fillRGBA) set];
	[path fill];

	[StepPartListColorFromRGBA(style.borderRGBA) set];
	[path setLineWidth:1.0];
	[path stroke];

	[text drawAtPoint:NSMakePoint(NSMidX(badge) - textSize.width / 2.0,
								  NSMidY(badge) - textSize.height / 2.0)
	   withAttributes:attributes];

}//end drawAnnotationForPlacement:


//========== drawOverflowNotice ================================================
///
/// @abstract	Says how many parts were left out, when the list was cut short.
///				It goes along the top, where the dropped rows would have been.
///
//==============================================================================
- (void) drawOverflowNotice
{
	NSUInteger overflow = self.layout.overflowCount;

	if (overflow == 0) {
		return;
	}

	NSString	*format	= NSLocalizedString(@"StepPartListOverflow", nil);
	NSString	*text	= [NSString stringWithFormat:format, (unsigned long)overflow];
	Box2		 box	= [LDrawStepPartListPolicy overflowNoticeRectForContentWidth:NSWidth(self.bounds)
																			  chrome:self.chrome];
	NSRect		 rect	= StepPartListRectFromBox(box);

	[self drawText:text
			inRect:rect
		 pointSize:self.chrome.labelPointSize
			 color:StepPartListColorFromRGBA(self.chrome.labelRGBA)
			  bold:NO];

}//end drawOverflowNotice


// MARK: - UTILITIES -


//========== drawText:inRect:pointSize:color:bold: =============================
///
/// @abstract	Draws one line of text, centered in the rect.
///
//==============================================================================
- (void) drawText:(NSString *)text
		   inRect:(NSRect)rect
		pointSize:(CGFloat)pointSize
			color:(NSColor *)color
			 bold:(BOOL)bold
{
	NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];

	[style setAlignment:NSTextAlignmentCenter];
	[style setLineBreakMode:NSLineBreakByTruncatingTail];

	NSFont *font = bold ? [NSFont boldSystemFontOfSize:pointSize] : [NSFont systemFontOfSize:pointSize];

	NSDictionary *attributes = @{
		NSFontAttributeName:			font,
		NSForegroundColorAttributeName:	color,
		NSParagraphStyleAttributeName:	style,
	};

	// Center the text in the rect instead of letting it sit at the top.
	NSSize	measured	= [text sizeWithAttributes:attributes];
	NSRect	textRect	= rect;

	if (measured.height < rect.size.height) {
		textRect.origin.y += (rect.size.height - measured.height) / 2.0;
		textRect.size.height = measured.height;
	}

	[text drawInRect:textRect withAttributes:attributes];

}//end drawText:inRect:pointSize:color:bold:


@end
