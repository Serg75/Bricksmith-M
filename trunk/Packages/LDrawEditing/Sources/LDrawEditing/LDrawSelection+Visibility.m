//==============================================================================
//
//  File:       LDrawSelection+Visibility.m
//  Package:    LDrawEditing
//
//  Purpose:    Hide, show, and visibility helpers for LDrawSelection.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import <LDrawEditing/LDrawSelection.h>

@implementation LDrawSelection (Visibility)

//========== setSelectionToHidden: =============================================
//
// Purpose:		Hides or shows all the hideable selected elements.
//
//==============================================================================
+ (NSArray *)hideableDirectivesInSelection:(NSArray *)selection
{
	NSMutableArray *hideable = [NSMutableArray array];
	for (id currentObject in selection)
	{
		if ([currentObject respondsToSelector:@selector(setHidden:)])
		{
			[hideable addObject:currentObject];
		}
	}
	return hideable;
}


//---------- setHidden:forDirectives: -------------------------------[static]--
//
// Purpose:		Show or hide every hideable directive in the list.
//
//------------------------------------------------------------------------------
+ (void)setHidden:(BOOL)hidden forDirectives:(NSArray *)directives
{
	for (id currentDirective in directives)
	{
		[currentDirective setHidden:hidden];
	}
}


//---------- setSelected:forDirectives: -----------------------------[static]--
//
// Purpose:		Set the selected flag on every directive in the list.
//
//------------------------------------------------------------------------------
+ (void)setSelected:(BOOL)selected forDirectives:(NSArray *)directives
{
	// while a part is dragged, it is drawn selected
	for (id currentObject in directives)
	{
		[currentObject setSelected:selected];
	}
}

//---------- hiddenHideableDirectivesIn: ----------------------------[static]--
//
// Purpose:		Return hideable directives that are currently hidden, for Show.
//
//------------------------------------------------------------------------------
+ (NSArray *)hiddenHideableDirectivesIn:(NSArray *)directives
{
	NSMutableArray *hidden = [NSMutableArray array];
	for (id currentObject in directives)
	{
		if (	[currentObject respondsToSelector:@selector(setHidden:)]
		   &&	[currentObject respondsToSelector:@selector(isHidden)]
		   &&	[currentObject isHidden] == YES)
		{
			[hidden addObject:currentObject];
		}
	}
	return hidden;
}


//---------- visibleDirectivesIn: ------------------------------------[static]--
//
// Purpose:		Selects all the visible LDraw elements in the active model. This
//				does not select the steps or model--only the contained elements
//				themselves. Hidden elements are also ignored.
//
//------------------------------------------------------------------------------
+ (NSArray *)visibleDirectivesIn:(NSArray *)directives
{
	NSMutableArray *visibleElements = [NSMutableArray arrayWithCapacity:[directives count]];

	for (id currentElement in directives)
	{
		if ([currentElement respondsToSelector:@selector(isHidden)] == NO
		   || [currentElement isHidden] == NO)
		{
			[visibleElements addObject:currentElement];
		}
	}
	return visibleElements;
}

//========== elementsAreSelectedOfVisibility: ==================================
//
// Purpose:		Returns YES if there are elements selected which have the 
//				requested visibility.
//
//==============================================================================
+ (BOOL)selection:(NSArray *)selection containsVisibility:(BOOL)visibleFlag
{
	BOOL invisibleSelected = NO;
	BOOL visibleSelected   = NO;

	for (id currentObject in selection)
	{
		if ([currentObject respondsToSelector:@selector(isHidden)])
		{
			invisibleSelected = invisibleSelected || [currentObject isHidden];
			visibleSelected   = visibleSelected   || ([currentObject isHidden] == NO);
		}
	}

	return visibleFlag ? visibleSelected : invisibleSelected;
}


@end
