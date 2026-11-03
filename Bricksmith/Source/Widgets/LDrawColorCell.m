//==============================================================================
//
// File:		LDrawColorCell.m
//
// Purpose:		Displays a swatch of an LDraw color in a cell.
//
//  Created by Allen Smith on 2/26/05.
//  Copyright 2005. All rights reserved.
//==============================================================================
#import "LDrawColorCell.h"

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawColorLibrary.h>

@implementation LDrawColorCell

//========== drawInteriorWithFrame:inView: =====================================
//
// Purpose:		Draw a swatch representing the current color without alpha.
//
//==============================================================================
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	LDrawColor  *colorObject    = [self objectValue];
	NSColor     *cellColor      = nil;
	float       components[4];
	
	// Get the color components and covert them. Discard alpha.
	[colorObject getColorRGBA:components];
	cellColor = [NSColor colorWithCalibratedRed:components[0]
										  green:components[1]
										   blue:components[2]
										  alpha:1.0 ];
	
	// Draw
	if(self.struck)
		cellColor = [cellColor colorWithAlphaComponent:0.35];
	[cellColor set];
	NSRectFillUsingOperation(cellFrame, NSCompositingOperationSourceOver);

	if(self.struck)
	{
		NSBezierPath *line = [NSBezierPath bezierPath];

		[line moveToPoint:NSMakePoint(NSMinX(cellFrame), NSMaxY(cellFrame))];
		[line lineToPoint:NSMakePoint(NSMaxX(cellFrame), NSMinY(cellFrame))];
		[[NSColor systemRedColor] setStroke];
		[line setLineWidth:1.5];
		[line stroke];
	}
	
}//end drawInteriorWithFrame:inView:

@end
