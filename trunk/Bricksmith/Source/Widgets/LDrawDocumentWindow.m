//==============================================================================
//
// File:		LDrawDocumentWindow.m
//
// Purpose:		Window for LDraw. Provides minor niceties.
//
//  Created by Allen Smith on 4/4/05.
//  Copyright 2005. All rights reserved.
//==============================================================================
#import "LDrawDocumentWindow.h"


@implementation LDrawDocumentWindow


#pragma mark -
#pragma mark EVENTS
#pragma mark -

//========== keyDown: ==========================================================
//
// Purpose:		Time to do something exciting in response to a keypress.
//
//==============================================================================
- (void)keyDown:(NSEvent *)theEvent
{
	// You can trap certain key events here. But really, why?

	[super keyDown:theEvent];
		
}//end keyDown:


@end
