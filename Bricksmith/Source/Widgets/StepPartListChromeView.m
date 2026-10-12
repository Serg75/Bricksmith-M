//==============================================================================
//
// File:		StepPartListChromeView.m
//
// Purpose:		Draws everything in the step parts list that is not a part.
//
// Notes:		The drawing is in LDrawStepRendering. This view is there to put
//				it above the nested 3D view.
//
// Created by Sergey Slobodenyuk on 2026-09-10.
//
//==============================================================================
#import "StepPartListChromeView.h"

#import <LDrawFeatures/LDrawStepPartListLayout.h>
#import <LDrawStepRendering/LDrawStepOverlayRenderer.h>


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
	if (self.layout == nil) {
		return;
	}

	[LDrawStepOverlayRenderer drawLabelsOfLayout:self.layout
										  chrome:self.chrome
									contentWidth:NSWidth(self.bounds)
								  overflowFormat:NSLocalizedString(@"StepPartListOverflow", nil)
									   inContext:[[NSGraphicsContext currentContext] CGContext]];

}//end drawRect:


@end
