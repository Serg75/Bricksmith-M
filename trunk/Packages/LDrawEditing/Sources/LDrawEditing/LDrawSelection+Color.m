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

#import <LDrawCore/ColorLibrary.h>

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
//==============================================================================
+ (NSArray *)randomizedColorsForDirectives:(NSArray *)colorable
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

	NSUInteger colorCount = [allColors count];
	if (colorCount == 0)
	{
		return @[];
	}

	NSArray        *palette = [allColors allObjects];
	NSMutableArray *result  = [NSMutableArray arrayWithCapacity:count];
	int             last    = -1;

	for (NSUInteger counter = 0; counter < count; ++counter)
	{
		int r = rand() % (int)colorCount;
		// Try to avoid consecutives if we have enough palette --
		// this technically makes the distribution not random, but
		// it probably looks better unless the parts are just super
		// tiny.
		while (colorCount > 1 && r == last)
		{
			r = rand() % (int)colorCount;
		}
		last = r;
		[result addObject:[palette objectAtIndex:(NSUInteger)r]];
	}
	return result;
}


@end
