//==============================================================================
//
//  File:       LDrawColorPanelModel.m
//  Package:    LDrawFeatures
//
//  Purpose:    Color-panel search predicate, selection policy, and tooltip.
//
//  Created by Sergey Slobodenyuk on 2026-09-01.
//
//==============================================================================

#import <LDrawFeatures/LDrawColorPanelModel.h>


@implementation LDrawColorPanelModel

//---------- indexOfColor:inColors: ----------------------------------[static]--
//
// Purpose:		Returns the row index of colorCodeSought in the panel's table,
//				or NSNotFound if colorCodeSought is not displayed.
//
//------------------------------------------------------------------------------
+ (NSInteger)indexOfColor:(LDrawColor *)colorSought inColors:(NSArray *)colors
{
	LDrawColorT colorCodeSought = [colorSought colorCode];
	NSInteger   numberColors    = (NSInteger)[colors count];
	NSInteger   counter         = 0;

	// Search through all the colors in the current color set and see if the
	// one we are after is in there. A brute force search.
	for (counter = 0; counter < numberColors; counter++)
	{
		LDrawColor *currentColor = [colors objectAtIndex:(NSUInteger)counter];
		if ([currentColor colorCode] == colorCodeSought)
		{
			return counter;
		}
	}
	return NSNotFound;
}


//---------- shouldSelectFirstColorAfterFilterWhenPreviousIndex: ----[static]--
//
// Purpose:		The array controller will automatically maintain the selection
//				if it can. But if it can't, we need to come up a reasonable new
//				answer. If the previous color is no longer in the list, what
//				should we do? I have chosen to automatically select the first
//				color, since I don't want to introduce the UI confusion of
//				empty selection.
//
//------------------------------------------------------------------------------
+ (BOOL)shouldSelectFirstColorAfterFilterWhenPreviousIndex:(NSInteger)index
{
	return index == NSNotFound;
}


//---------- shouldClearColorFilterWhenIndexNotFound: ----------------[static]--
//
// Purpose:		It wasn't in the currently-displayed list. Search the master
//				list.
//
//------------------------------------------------------------------------------
+ (BOOL)shouldClearColorFilterWhenIndexNotFound:(NSInteger)index
{
	return index == NSNotFound;
}


//---------- canSelectColorAtRowIndex: -------------------------------[static]--
//
// Purpose:		We'd better have found it by now!
//
//------------------------------------------------------------------------------
+ (BOOL)canSelectColorAtRowIndex:(NSInteger)index
{
	return index != NSNotFound;
}


//---------- colorFromListSelection:fallbackColor: -------------------[static]--
//
// Purpose:		It is possible there are no rows selected, if a search has
//				limited the color list out of existence. Just return whatever
//				was last selected.
//
//------------------------------------------------------------------------------
+ (LDrawColor *)colorFromListSelection:(NSArray *)selection
						 fallbackColor:(LDrawColor *)fallbackColor
{
	if ([selection count] > 0)
		return [selection objectAtIndex:0];
	return fallbackColor;
}


//---------- tooltipForColorCode:localizedName: ----------------------[static]--
//
// Purpose:		Create a tool tip to identify the LDraw color code.
//
//------------------------------------------------------------------------------
+ (NSString *)tooltipForColorCode:(LDrawColorT)colorCode
					localizedName:(NSString *)localizedName
{
	return [NSString stringWithFormat:@"LDraw %d\n%@", (int)colorCode, localizedName];
}


//---------- predicateForSearchString:material: ----------------------[static]--
//
// Purpose:		Returns a search predicate suitable for finding colors based on
//				the given search string.
//
//				If the search string consists entirely of numerals, the
//				predicate will search for colors having that exact integer code.
//
//------------------------------------------------------------------------------
+ (NSPredicate *)predicateForSearchString:(NSString *)searchString
								 material:(LDrawColorFilter)material
{
	NSString        *keywordFormat      = nil;
	NSArray         *keywordArguments   = nil;
	NSString        *materialFormat     = nil;
	NSArray         *materialArguments  = nil;
	NSMutableString *predicateFormat    = nil;
	NSMutableArray  *predicateArguments = nil;
	NSPredicate     *searchPredicate    = nil;
	BOOL             searchByCode       = NO; // color name search by default.
	NSScanner       *digitScanner       = nil;
	NSInteger        colorCode          = 0;

	// If there is no string, then clear the search predicate (find all).
	if ([searchString length] == 0)
	{
		searchPredicate = nil;
	}
	else
	{
		// Find out whether this search is intended to be based on the LDraw
		// code. If the search string can be parsed into an integer, we'll
		// assume this is a color-code search. Otherwise, it will be a name
		// search.
		digitScanner = [NSScanner scannerWithString:searchString];
		searchByCode = [digitScanner scanInteger:&colorCode];

		// If it is an LDraw code search, try to find a color code equal to the
		// search number entered.
		if (searchByCode == YES)
		{
			keywordFormat     = @"%K == %@";
			keywordArguments  = @[NSStringFromSelector(@selector(colorCode)), @(colorCode)];
		}
		else
		{
			// This is a search based on color names. If we can find the search
			// string in any component of the color string, we consider it a
			// match.
			keywordFormat     = @"%K CONTAINS[cd] %@";
			keywordArguments  = @[NSStringFromSelector(@selector(localizedName)), searchString];
		}
	}

	switch (material)
	{
		case LDrawColorFilterAll:
			break;
		case LDrawColorFilterSolid:
			materialFormat    = @"(%K == %@) AND (%K == 1.0)";
			materialArguments = @[NSStringFromSelector(@selector(material)), @(LDrawColorMaterialNone), NSStringFromSelector(@selector(alpha))];
			break;
		case LDrawColorFilterTransparent:
			materialFormat    = @"(%K == %@) AND (%K < 1.0)";
			materialArguments = @[NSStringFromSelector(@selector(material)), @(LDrawColorMaterialNone), NSStringFromSelector(@selector(alpha))];
			break;
		case LDrawColorFilterChrome:
			materialFormat    = @"(%K == %@)";
			materialArguments = @[NSStringFromSelector(@selector(material)), @(LDrawColorMaterialChrome)];
			break;
		case LDrawColorFilterPearlescent:
			materialFormat    = @"(%K == %@)";
			materialArguments = @[NSStringFromSelector(@selector(material)), @(LDrawColorMaterialPearlescent)];
			break;
		case LDrawColorFilterRubber:
			materialFormat    = @"(%K == %@)";
			materialArguments = @[NSStringFromSelector(@selector(material)), @(LDrawColorMaterialRubber)];
			break;
		case LDrawColorFilterMetal:
			materialFormat    = @"(%K == %@) OR (%K == %@)";
			materialArguments = @[NSStringFromSelector(@selector(material)), @(LDrawColorMaterialMetal), NSStringFromSelector(@selector(material)), @(LDrawColorMaterialMatteMetallic)];
			break;
		case LDrawColorFilterOther:
			materialFormat    = @"((%K == %@) OR (%K == %@) OR (%K == %@))";
			materialArguments = @[NSStringFromSelector(@selector(material)), @(LDrawColorMaterialCustom),
								 NSStringFromSelector(@selector(colorCode)), @(LDrawCurrentColor),
								 NSStringFromSelector(@selector(colorCode)), @(LDrawEdgeColor)];
			break;
	}

	if (keywordFormat || materialFormat)
	{
		predicateFormat    = [NSMutableString string];
		predicateArguments = [NSMutableArray array];
	}

	if (keywordFormat)
	{
		[predicateFormat appendString:keywordFormat];
		[predicateArguments addObjectsFromArray:keywordArguments];
	}

	if (materialFormat)
	{
		if ([predicateFormat length])
			[predicateFormat appendString:@"AND "];

		[predicateFormat appendFormat:@"(%@)", materialFormat];
		[predicateArguments addObjectsFromArray:materialArguments];
	}

	if (predicateFormat)
	{
		searchPredicate = [NSPredicate predicateWithFormat:predicateFormat argumentArray:predicateArguments];
	}

	return searchPredicate;
}

@end
