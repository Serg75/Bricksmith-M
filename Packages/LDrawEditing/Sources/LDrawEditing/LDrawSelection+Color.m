//==============================================================================
//
//  File:       LDrawSelection+Color.m
//  Package:    LDrawEditing
//
//  Purpose:    Color assignment helpers for LDrawSelection.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import <stdlib.h>

#import <LDrawEditing/LDrawSelection.h>

#import <LDrawCore/LDrawColorLibrary.h>

@implementation LDrawSelection (Color)

//---------- colorableDirectivesInSelection: ------------------------[static]--
//
// Purpose:		Return the subset of selection that accepts an LDraw color
//				change.
//
//------------------------------------------------------------------------------
+ (NSArray *)colorableDirectivesInSelection:(NSArray *)selection
{
	NSMutableArray *colorable = [NSMutableArray array];
	for (id currentObject in selection)
	{
		if ([currentObject conformsToProtocol:@protocol(LDrawColorable)])
		{
			[colorable addObject:currentObject];
		}
	}
	return colorable;
}

//========== randomizeLDrawColors: =============================================
//
// Purpose:		Randomizes every part in the selection to be one of the parts
//				found in the selection.
//
//				This is meant for a power tool, e.g. if you want to turn a big
//				pile of 1x1 plates into "gravel", you can color the entire set
//				gray and then change a few to the other colors (maybe black,
//				brown, etc.).  randomizeLDrawColors will randomize the entire
//				set.
//
// Notes:		We try to avoid consecutive colors - if the underlying bricks
//				were built "in order", this gives an author a way to avoid
//				aesthetically ugly blocks of repeating colors that are present
//				in true random distributions.
//
//				This routine depends on LDrawColors hashing into sets with
//				deduplication.  This _does_ work for colors that come from
//				the palette, but I have not tested it with models that use
//				custom colors in an LDraw directive in their MPD file.
//
//				With allowedColors, each directive picks only among the colors
//				it may take.
//
//==============================================================================
+ (NSArray *)randomizedColorsForDirectives:(NSArray *)colorable
							 allowedColors:(BOOL (^)(id directive, LDrawColor *color))allowedColors
{
	NSUInteger count = [colorable count];
	if (count == 0)
	{
		return @[];
	}

	NSMutableSet *allColors = [NSMutableSet setWithCapacity:count];
	// Build a hash set of all colors
	for (id currentObject in colorable)
	{
		[allColors addObject:[currentObject LDrawColor]];
	}

	if ([allColors count] == 0)
	{
		return @[];
	}

	NSArray        *palette = [allColors allObjects];
	NSMutableArray *result  = [NSMutableArray arrayWithCapacity:count];
	LDrawColor     *last    = nil;

	for (id directive in colorable)
	{
		NSArray *choices = palette;

		if (allowedColors != nil)
		{
			choices = [palette objectsAtIndexes:[palette indexesOfObjectsPassingTest:
						^BOOL(LDrawColor *color, NSUInteger index, BOOL *stop) {
							return allowedColors(directive, color);
						}]];
		}

		if ([choices count] == 0)
		{
			[result addObject:[directive LDrawColor]];
			continue;
		}

		LDrawColor *pick = [choices objectAtIndex:(NSUInteger)(rand() % (int)[choices count])];
		// Try to avoid consecutives if we have enough palette --
		// this technically makes the distribution not random, but
		// it probably looks better unless the parts are just super
		// tiny.
		while ([choices count] > 1 && pick == last)
		{
			pick = [choices objectAtIndex:(NSUInteger)(rand() % (int)[choices count])];
		}
		last = pick;
		[result addObject:pick];
	}
	return result;
}


@end
