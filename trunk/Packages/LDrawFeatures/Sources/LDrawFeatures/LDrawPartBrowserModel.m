//==============================================================================
//
//  File:       LDrawPartBrowserModel.m
//  Package:    LDrawFeatures
//
//  Purpose:    Category and search filtering for the part browser.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <LDrawFeatures/LDrawPartBrowserModel.h>

#import <LDrawCore/NSString+LDraw.h>

@interface LDrawPartBrowserModel ()
@property (nonatomic, strong, readwrite) NSArray *filteredParts;
@end


@implementation LDrawPartBrowserModel

//========== initWithPartLibrary: =============================================
//
// Purpose:		Create a part-browser data model backed by the given library,
//				starting in the All category with an empty search.
//
//==============================================================================
- (instancetype)initWithPartLibrary:(LDrawPartLibrary *)library
{
	self = [super init];
	if (self)
	{
		_partLibrary     = library;
		_currentCategory = Category_All;
		_searchString    = @"";
		_searchMode      = LDrawPartBrowserSearchAllCategories;
		_filteredParts   = @[];
	}
	return self;
}


//========== performSearch =====================================================
//
// Purpose:		Executes the search based on the current search settings.
//
//==============================================================================
- (void)reloadFilter
{
	NSString *search   = self.searchString ?: @"";
	NSArray  *allParts = nil;
	NSSet    *excluded = nil;

	if ([search length] == 0 || self.searchMode == LDrawPartBrowserSearchSelectedCategory)
	{
		allParts = [self.partLibrary partCatalogRecordsInCategory:self.currentCategory];
	}
	else
	{
		allParts = [self.partLibrary partCatalogRecordsInCategory:Category_All];
		excluded = [NSSet setWithArray:[[self.partLibrary partCatalogRecordsInCategory:Category_Alias]
						   valueForKey:PART_NUMBER_KEY]];
	}

	self.filteredParts = [self filterPartRecords:allParts
								  bySearchString:search
									excludeParts:excluded];
}


//========== indexOfPartNamed: =================================================
//
// Purpose:		Returns the index of the part with the given name in the current 
//				found set. 
//
//				Returns NSNotFound if the part is not a member of the 
//				currently-displayed part list. 
//
//==============================================================================
- (NSUInteger)indexOfPartNamed:(NSString *)partName
{
	return [[self class] indexOfPartNamed:partName inRecords:self.filteredParts];
}


//========== indexOfPartNamed:inRecords: =======================================
//
// Purpose:		Returns the index of the part with the given name in the current 
//				found set. 
//
//				Returns NSNotFound if the part is not a member of the 
//				currently-displayed part list. 
//
//==============================================================================
+ (NSUInteger)indexOfPartNamed:(NSString *)searchName inRecords:(NSArray *)records
{
	NSUInteger currentIndex = 0;

	for (NSDictionary *partRecord in records)
	{
		NSString *partName = [partRecord objectForKey:PART_NUMBER_KEY];
		if ([partName isEqualToString:searchName])
		{
			return currentIndex;
		}
		currentIndex++;
	}
	return NSNotFound;
}


//========== filterPartRecords:bySearchString: =================================
//
// Purpose:		Searches partRecords for all records containing searchString; 
//				returns the matching records. The search will be conducted on 
//				both the part numbers and descriptions.
//
// Returns:		An array with all matching parts, or an empty array if no parts 
//				match.
//
// Notes:		The nasty problem is that LDraw names are formed so that they 
//				line up nicely in a monospaced font. Thus we have names like 
//				"Brick  2 x  4" (note extra spaces!). I sidestep the problem by 
//				stripping all the spaces from the search and find strings. It's 
//				still lame, but probably okay for most uses.
//
//				Tiger has fantabulous search predicates that would reduce a 
//				hefty hunk of this code to a 1-liner AND be whitespace neutral 
//				too. But I don't have Tiger, so instead I'm going for the 
//				cheeseball approach.  
//
//==============================================================================
- (NSArray *)filterPartRecords:(NSArray *)partRecords
				bySearchString:(NSString *)searchString
				  excludeParts:(NSSet *)excludedParts
{
	if ([searchString length] == 0)
	{
		// Everybody's a winner here.
		return partRecords ?: @[];
	}

	NSMutableArray *matchingParts        = [NSMutableArray array];
	NSString       *searchSansWhitespace = [searchString ldraw_stringByRemovingWhitespace];
	NSArray        *searchWords          = [searchString componentsSeparatedByCharactersInSet:
											[NSCharacterSet whitespaceCharacterSet]];

	// Search through all the given records and try to find matches on the 
	// search string. But search part names whitespace-neutral so as not to 
	// be thrown off by goofy name spacing. 
	for (NSDictionary *record in partRecords)
	{
		NSString *partNumber        = [record objectForKey:PART_NUMBER_KEY];
		NSString *partDescription   = [record objectForKey:PART_NAME_KEY];
		NSString *partSansWhitespace = [partDescription ldraw_stringByRemovingWhitespace];

		if ([excludedParts containsObject:partNumber])
		{
			continue;
		}

		// LLW - Change to treat each word in a search string as an item in a list, and
		// a match happens only if each word can be found in the either the part number or
		// the name. This is independent of order, so a search like "2x2 plate" and "plate 2x2"
		// will return the same results.
		//
		// Some examples of results that are returned with this change that would _not_
		// be returned with the original code:
		//  Search          Sample result
		//  "2x2 plate"     "Plate 2 x 2"
		//  "tile clip"     "Tile 1x1 with clip"
		//  "four studs"    "Brick 1 x 1 with Studs on Four Sides"
		//  "offset plate"  "Plate 1 x 4 Offset"
		//  "axle pin 2x2"  "Brick 2 x 2 with Pin and Axlehole"

		BOOL matches = YES;
		for (NSString *word in searchWords)
		{
			if (!([partNumber ldraw_containsString:word options:NSCaseInsensitiveSearch] ||
				 [partSansWhitespace ldraw_containsString:word options:NSCaseInsensitiveSearch]))
			{
				matches = NO;
				break;
			}
		}

		if (matches)
		{
			[matchingParts addObject:record];
			continue;
		}

		for (NSString *keyword in [record objectForKey:PART_KEYWORDS_KEY])
		{
            if ([[keyword ldraw_stringByRemovingWhitespace] ldraw_containsString:searchSansWhitespace
                                                                         options:NSCaseInsensitiveSearch])
			{
				[matchingParts addObject:record];
				break;
			}
		}
	}

	return matchingParts;
}


//---------- categoryItemNamed:inHierarchy: --------------------------[static]--
//
// Purpose:		Selects the current category in the category table. Walks group
//				Children for a Name match. The host still asks the outline for
//				the row.
//
//------------------------------------------------------------------------------
+ (id)categoryItemNamed:(NSString *)name inHierarchy:(NSArray *)categoryList
{
	if (name == nil) return nil;
	for (NSDictionary *group in categoryList)
	{
		NSArray *children = [group objectForKey:CategoryChildrenKey];
		for (NSDictionary *category in children)
		{
			if ([[category objectForKey:CategoryNameKey] isEqualToString:name])
			{
				return category;
			}
		}
	}
	return nil;
}


//---------- partNamed:isInFavorites: --------------------------------[static]--
//
// Purpose:		Sets the enabled or disabled state of controls in the part
//				browser. Favorites Add/Remove depends on this.
//
//------------------------------------------------------------------------------
+ (BOOL)partNamed:(NSString *)partName isInFavorites:(NSArray *)favorites
{
	if (partName == nil) return NO;
	return [favorites containsObject:partName];
}


//---------- shouldShowSearchScopeButtonsForSearchString:category: ---[static]--
//
// Purpose:		Search-scope buttons appear when there is a search string and
//				the category is not All.
//
//------------------------------------------------------------------------------
+ (BOOL)shouldShowSearchScopeButtonsForSearchString:(NSString *)searchString
										   category:(NSString *)category
{
	return [searchString length] > 0
		&& [category isEqualToString:Category_All] == NO;
}


//---------- tableSelectionIndexPreferring: --------------------------[static]--
//
// Purpose:		Attempt to restore the original selection (happens especially
//				if clearing the search field). If the previous part is no longer
//				in the list, select the first row.
//
//------------------------------------------------------------------------------
+ (NSUInteger)tableSelectionIndexPreferring:(NSUInteger)preferredIndex
{
	if (preferredIndex == NSNotFound)
		return 0;
	return preferredIndex;
}





//---------- noRecentSearchesLocalizationKey -------------------------[static]--
//
// Purpose:		Recent-searches empty menu title. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)noRecentSearchesLocalizationKey
{
	return @"NoRecentSearches";
}


//---------- zoomInTooltipLocalizationKey ----------------------------[static]--
//
// Purpose:		Part-browser toolbar button tooltips. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)zoomInTooltipLocalizationKey
{
	return @"ZoomInTooltip";
}


//---------- zoomOutTooltipLocalizationKey --------------------------[static]--
//
// Purpose:		Localization key for the part-browser zoom-out button tooltip.
//				The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)zoomOutTooltipLocalizationKey
{
	return @"ZoomOutTooltip";
}


//---------- addRemoveFavoritesTooltipLocalizationKey ---------------[static]--
//
// Purpose:		Localization key for the add/remove-favorites button tooltip.
//				The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)addRemoveFavoritesTooltipLocalizationKey
{
	return @"AddRemoveFavoritesTooltip";
}


//---------- categoryChildrenOfItem:inHierarchy: ---------------------[static]--
//
// Purpose:		Root is the category list; a group’s children are
//				CategoryChildrenKey. The host still asks the outline.
//
//------------------------------------------------------------------------------
+ (NSArray *)categoryChildrenOfItem:(id)item inHierarchy:(NSArray *)categoryList
{
	if (item == nil)
		return categoryList;
	return [item objectForKey:CategoryChildrenKey];
}




//---------- favoriteButtonImageNameWhenShowingAdd: ------------------[static]--
//
// Purpose:		Favorite Add/Remove button image name from show-add policy.
//
//------------------------------------------------------------------------------
+ (NSString *)favoriteButtonImageNameWhenShowingAdd:(BOOL)showAdd
{
	if (showAdd)
		return @"FavoriteAdd";
	return @"FavoriteRemove";
}

@end
