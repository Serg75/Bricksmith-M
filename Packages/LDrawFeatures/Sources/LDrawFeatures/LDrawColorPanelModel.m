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

#import <LDrawCore/LDrawLocalization.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawFeatures/LDrawPartLimitPresentation.h>
#import <LDrawInventory/LDrawPartLimit.h>
#import <LDrawInventory/LDrawPartLimitTable.h>


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


//---------- predicateForSearchString:material:allowedColorCodes: ----[static]--
//
// Purpose:		Returns a search predicate suitable for finding colors based on
//				the given search string, narrowed to the allowed colors.
//
//				If the search string consists entirely of numerals, the
//				predicate will search for colors having that exact integer code.
//
//------------------------------------------------------------------------------
+ (NSPredicate *)predicateForSearchString:(NSString *)searchString
								 material:(LDrawColorFilter)material
						allowedColorCodes:(NSArray<NSNumber *> *)allowedColorCodes
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
		case LDrawColorFilterSelectedPart:
		case LDrawColorFilterLimit:
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

	if (allowedColorCodes != nil)
	{
		NSString *allowedFormat = @"(%K IN %@)";
		NSArray  *allowedArgs   = @[NSStringFromSelector(@selector(colorCode)), allowedColorCodes];

		// Kept in the material clause, so the join below covers it.
		if (materialFormat)
		{
			materialFormat    = [NSString stringWithFormat:@"(%@) AND %@", materialFormat, allowedFormat];
			materialArguments = [materialArguments arrayByAddingObjectsFromArray:allowedArgs];
		}
		else
		{
			materialFormat    = allowedFormat;
			materialArguments = allowedArgs;
		}
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
			[predicateFormat appendString:@" AND "];

		[predicateFormat appendFormat:@"(%@)", materialFormat];
		[predicateArguments addObjectsFromArray:materialArguments];
	}

	if (predicateFormat)
	{
		searchPredicate = [NSPredicate predicateWithFormat:predicateFormat argumentArray:predicateArguments];
	}

	return searchPredicate;
}


// MARK: - PARTS LIMIT -


//---------- partNamesInSelection: -----------------------------------[static]--
//
// Purpose:		The names of the parts in a selection, in order. Other
//				directives are skipped.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)partNamesInSelection:(NSArray *)selection
{
	NSMutableArray *names = [NSMutableArray array];

	for (id object in selection)
	{
		if ([object isKindOfClass:[LDrawPart class]] && [object displayName] != nil)
			[names addObject:[object displayName]];
	}
	return names;
}


//---------- limitPartNamesForSelectedPartNames:hasSelection:browserPartName: --
//
// Purpose:		The parts the colors are narrowed to: the selection's, or the
//				Part Browser's part when nothing is selected.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)limitPartNamesForSelectedPartNames:(NSArray<NSString *> *)selectedPartNames
											   hasSelection:(BOOL)hasSelection
											browserPartName:(NSString *)browserPartName
{
	if (hasSelection)
		return selectedPartNames;
	return (browserPartName != nil) ? @[browserPartName] : @[];
}


//---------- allowedColorCodesForPartNames:table: --------------------[static]--
//
// Purpose:		The colors every part may take: those all of their lists share.
//
//------------------------------------------------------------------------------
+ (NSArray<NSNumber *> *)allowedColorCodesForPartNames:(NSArray<NSString *> *)partNames
												 table:(LDrawPartLimitTable *)table
{
	NSMutableSet *allowed = nil;

	// A selection often holds many copies of one part.
	for (NSString *partName in [NSOrderedSet orderedSetWithArray:partNames])
	{
		NSArray *codes = [table everyColorCodeForPartNamed:partName];

		if ([codes count] == 0)
			continue;
		if (allowed == nil)
			allowed = [NSMutableSet setWithArray:codes];
		else
			[allowed intersectSet:[NSSet setWithArray:codes]];
	}

	return [[allowed allObjects] sortedArrayUsingSelector:@selector(compare:)];
}


//---------- canSelectColorCode:allowedColorCodes:warnsOnly: ---------[static]--
//
// Purpose:		Whether the user may pick the color under the limit.
//
//------------------------------------------------------------------------------
+ (BOOL)canSelectColorCode:(LDrawColorT)colorCode
		 allowedColorCodes:(NSArray<NSNumber *> *)allowedColorCodes
				 warnsOnly:(BOOL)warnsOnly
{
	if (allowedColorCodes == nil || warnsOnly || colorCode == LDrawCurrentColor)
		return YES;
	return [allowedColorCodes containsObject:@(colorCode)];
}


//---------- footerForPartNames:table: -------------------------------[static]--
//
// Purpose:		How many colors the parts may take, and which parts: one part
//				by name and number, or several by count.
//
//------------------------------------------------------------------------------
+ (NSString *)footerForPartNames:(NSArray<NSString *> *)partNames table:(LDrawPartLimitTable *)table
{
	NSArray			*allowed	= [self allowedColorCodesForPartNames:partNames table:table];
	NSMutableSet	*narrowing	= [NSMutableSet set];
	NSString		*parts		= nil;
	NSString		*key		= nil;

	if (allowed == nil)
		return nil;

	for (NSString *name in partNames)
	{
		if ([[table everyColorCodeForPartNamed:name] count] > 0)
			[narrowing addObject:name];
	}

	if ([narrowing count] == 1)
	{
		NSString *partName	= [narrowing anyObject];
		NSString *title		= [[LDrawPartLibrary sharedPartLibraryIfRegistered] descriptionForPartName:partName];

		parts = [NSString stringWithFormat:@"%@ (%@)", title ?: partName, [partName stringByDeletingPathExtension]];
	}
	else
	{
		parts = [NSString stringWithFormat:[LDrawLocalization stringForKey:@"%lu parts"],
				 (unsigned long)[narrowing count]];
	}

	key = ([allowed count] == 1) ? @"%lu color for %@" : @"%lu colors for %@";
	return [NSString stringWithFormat:[LDrawLocalization stringForKey:key], (unsigned long)[allowed count], parts];
}


//---------- limitFilterTitleForLimit:store: -------------------------[static]--
//
// Purpose:		The title of the filter for every color the limit allows.
//
//------------------------------------------------------------------------------
+ (NSString *)limitFilterTitleForLimit:(LDrawPartLimit *)limit store:(LDrawInventoryStore *)store
{
	if (limit.kind == LDrawPartLimitKindAvailableNow)
		return [LDrawLocalization stringForKey:@"Made Now"];
	return [NSString stringWithFormat:[LDrawLocalization stringForKey:@"In %@"],
			[LDrawPartLimitPresentation titleForLimit:limit store:store]];
}


//---------- randomColorTestForTable: --------------------------------[static]--
//
// Purpose:		A part takes only colors it may be picked in; anything else
//				takes any color. Many parts share a name, so each answer is
//				kept.
//
//------------------------------------------------------------------------------
+ (BOOL (^)(id, LDrawColor *))randomColorTestForTable:(LDrawPartLimitTable *)table
{
	NSMutableDictionary *answers = [NSMutableDictionary dictionary];	// allowed, by part and color

	if (table == nil || table.limit.warnsOnly)
		return nil;

	return ^BOOL(id directive, LDrawColor *color) {
		NSString	*name	= nil;
		NSString	*key	= nil;
		NSNumber	*answer	= nil;

		if ([directive isKindOfClass:[LDrawPart class]] == NO)
			return YES;

		name	= [(LDrawPart *)directive displayName];
		key		= [NSString stringWithFormat:@"%@\n%d", name, (int)[color colorCode]];
		answer	= answers[key];
		if (answer == nil)
		{
			answer			= @([table allowsPickingColorCode:[color colorCode] forPartNamed:name]);
			answers[key]	= answer;
		}
		return [answer boolValue];
	};
}

@end
