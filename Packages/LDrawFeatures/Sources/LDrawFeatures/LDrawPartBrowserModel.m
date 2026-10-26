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

#import <LDrawCore/LDrawLocalization.h>
#import <LDrawCore/NSString+LDraw.h>
#import <LDrawFeatures/LDrawPartLimitCheck.h>
#import <LDrawFeatures/LDrawPartLimitSession.h>
#import <LDrawInventory/LDrawCombinedInventory.h>
#import <LDrawInventory/LDrawInventoryItem.h>
#import <LDrawInventory/LDrawInventoryStore.h>
#import <LDrawInventory/LDrawPartLimit.h>
#import <LDrawInventory/LDrawPartLimitTable.h>
#import <LDrawInventory/LDrawSetInventory.h>

NSString * const LDrawPartBrowserColorCodeKey	= @"LDrawPartBrowserColorCode";
NSString * const LDrawPartBrowserLEGONumberKey	= @"LDrawPartBrowserLEGONumber";
NSString * const LDrawPartBrowserUsedKey		= @"LDrawPartBrowserUsed";
NSString * const LDrawPartBrowserOwnedKey		= @"LDrawPartBrowserOwned";
NSString * const LDrawPartBrowserSparesKey		= @"LDrawPartBrowserSpares";
NSString * const LDrawPartBrowserLeftKey		= @"LDrawPartBrowserLeft";
NSString * const LDrawPartBrowserCountTextKey	= @"LDrawPartBrowserCountText";

// A set or inventory under Sets is shown by a category of this prefix and its
// identifier.
static NSString * const InventoryCategoryPrefix	= @"Inventory:";
static NSString * const SetsGroupName			= @"Sets";


@interface LDrawPartBrowserColorChip ()

- (instancetype)initWithColorCode:(LDrawColorT)colorCode
						 hasCount:(BOOL)hasCount
						leftCount:(NSInteger)leftCount
						   record:(nullable NSDictionary *)record;

@end


@implementation LDrawPartBrowserColorChip

//========== initWithColorCode:hasCount:leftCount:record: ======================
//==============================================================================
- (instancetype)initWithColorCode:(LDrawColorT)colorCode
						 hasCount:(BOOL)hasCount
						leftCount:(NSInteger)leftCount
						   record:(NSDictionary *)record
{
	self = [super init];
	if (self)
	{
		_colorCode	= colorCode;
		_hasCount	= hasCount;
		_leftCount	= leftCount;
		_record		= record;
	}
	return self;
}

@end


@interface LDrawPartBrowserModel ()
@property (nonatomic, strong, readwrite) NSArray *filteredParts;
@property (nonatomic, strong, readwrite, nullable) LDrawPartLimitTable *activeTable;
@property (nonatomic, assign, readwrite) BOOL showsInventoryRows;
@end


@implementation LDrawPartBrowserModel
{
	NSArray<NSDictionary *> *inventoryRows;		// every row of the inventory shown, before any filter
}

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
		_hidesDisallowedParts = YES;
	}
	return self;
}


//========== reloadFilter ======================================================
//
// Purpose:		Lists the parts of the category, or of the search, as the limit
//				allows them.
//
//==============================================================================
- (void)reloadFilter
{
	NSString			*search			= self.searchString ?: @"";
	BOOL				 searchesAll	= ([search length] > 0
										   && self.searchMode == LDrawPartBrowserSearchAllCategories);
	NSString			*inventoryID	= [[self class] inventoryIdentifierForCategory:self.currentCategory];
	NSString			*category		= self.currentCategory;
	LDrawPartLimitTable	*limitTable		= [self restrictingTable];
	NSArray				*records		= nil;
	NSSet				*excluded		= nil;

	// A search of every category, or the library's parts while a set is chosen.
	if (searchesAll || inventoryID != nil)
		category = Category_All;

	self.activeTable		= limitTable;
	self.showsInventoryRows	= NO;
	self->inventoryRows		= nil;

	if (inventoryID != nil && searchesAll == NO)
	{
		self.activeTable	= [self.limitSession tableForInventoryIdentifier:inventoryID];
		records				= [self inventoryRowsInCategory:Category_All];
	}
	else if (limitTable.limit.kind == LDrawPartLimitKindInventory && self.hidesDisallowedParts)
	{
		records = [self inventoryRowsInCategory:category];
	}
	else
	{
		records = [self.partLibrary partCatalogRecordsInCategory:category];
		records = [self recordsAllowedFrom:records inCategory:category];
		if (searchesAll)
			excluded = [NSSet setWithArray:[[self.partLibrary partCatalogRecordsInCategory:Category_Alias]
											valueForKey:PART_NUMBER_KEY]];
	}

	self.filteredParts = [self filterPartRecords:records
								  bySearchString:search
									excludeParts:excluded];
}


//========== restrictingTable ==================================================
//
// Purpose:		The limit's table when it limits anything and has its data.
//				Without data nothing could be listed.
//
//==============================================================================
- (LDrawPartLimitTable *)restrictingTable
{
	LDrawPartLimitTable *table = self.limitSession.table;

	if (table.limit.isRestricting && table.hasData)
		return table;
	return nil;
}


//========== recordsAllowedFrom:inCategory: ====================================
//
// Purpose:		Leaves out the library's parts the limit does not allow, and
//				with a color filter, those it does not allow in that color.
//
// Notes:		Listing every part still applies the color filter.
//
//==============================================================================
- (NSArray *)recordsAllowedFrom:(NSArray *)records inCategory:(NSString *)category
{
	LDrawPartLimitTable	*table		= self.activeTable;
	NSNumber			*color		= self.colorFilter;
	NSMutableArray		*allowed	= nil;

	if (	table == nil
		||	[self isUnfilteredCategory:category]
		||	(self.hidesDisallowedParts == NO && color == nil) )
		return records;

	allowed = [NSMutableArray arrayWithCapacity:[records count]];
	for (NSDictionary *record in records)
	{
		NSString *partName = [record objectForKey:PART_NUMBER_KEY];

		if (color != nil
			? [table allowsPartNamed:partName colorCode:(LDrawColorT)[color intValue]]
			: [table allowsPartNamed:partName])
			[allowed addObject:record];
	}
	return allowed;
}


//========== isUnfilteredCategory: =============================================
//
// Purpose:		Primitives and subparts are for making parts, not models, so
//				the limit does not apply to them.
//
//==============================================================================
- (BOOL)isUnfilteredCategory:(NSString *)category
{
	return [category isEqualToString:Category_Primitives] || [category isEqualToString:Category_Subparts];
}


//========== inventoryRowsInCategory: ==========================================
//
// Purpose:		The active table's inventory as rows, those of the category and
//				the color filter.
//
//==============================================================================
- (NSArray *)inventoryRowsInCategory:(NSString *)category
{
	NSArray			*favorites	= [self.partLibrary favoritePartNames];
	NSNumber		*color		= self.colorFilter;
	NSMutableArray	*rows		= [NSMutableArray array];

	self.showsInventoryRows	= YES;
	self->inventoryRows		= [self buildInventoryRows];

	for (NSDictionary *row in self->inventoryRows)
	{
		NSString *partName = row[PART_NUMBER_KEY];

		if (color != nil && [row[LDrawPartBrowserColorCodeKey] isEqual:color] == NO)
			continue;
		if ([category isEqualToString:Category_Favorites] && [favorites containsObject:partName] == NO)
			continue;
		if (	[category isEqualToString:Category_All] == NO
			&&	[category isEqualToString:Category_Favorites] == NO
			&&	[row[PART_CATEGORY_KEY] isEqualToString:category] == NO )
			continue;

		[rows addObject:row];
	}
	return rows;
}


//========== buildInventoryRows ================================================
//
// Purpose:		One row per part and color of the active table's inventory,
//				with the library's record of the part, and how many the model
//				uses and the inventory holds.
//
// Notes:		A part the library lacks cannot be inserted, so its row has no
//				PART_NUMBER_KEY.
//
//==============================================================================
- (NSArray *)buildInventoryRows
{
	LDrawPartLimitTable		*table		= self.activeTable;
	LDrawPartLimitReport	*report		= nil;
	NSMutableDictionary		*library	= [NSMutableDictionary dictionary];
	NSMutableArray			*rows		= [NSMutableArray array];
	BOOL					 spares		= table.limit.includesSpares;

	if (table == nil)
		return @[];

	if (self.partUsage != nil)
		report = [LDrawPartLimitCheck reportForUsage:self.partUsage table:table];

	for (NSDictionary *record in [self.partLibrary allPartCatalogRecords])
	{
		NSString *partName = [record objectForKey:PART_NUMBER_KEY];
		if (partName != nil)
			library[partName] = record;
	}

	for (LDrawInventoryItem *item in [[table items] arrayByAddingObjectsFromArray:[table unmatchedItems]])
	{
		NSMutableDictionary	*row		= [NSMutableDictionary dictionary];
		NSDictionary		*record		= (item.ldrawPartName != nil) ? library[item.ldrawPartName] : nil;
		BOOL				 hasColor	= (item.ldrawColorCode != LDrawColorBogus);
		NSUInteger			 owned		= item.quantity + (spares ? item.spareQuantity : 0);
		NSUInteger			 used		= 0;

		if (record != nil)
			[row addEntriesFromDictionary:record];
		else
			row[PART_NAME_KEY] = item.rebrickablePartNumber ?: item.ldrawPartName ?: @"";

		if (record != nil && hasColor && report != nil)
			used = [report usedCountForPartNamed:item.ldrawPartName colorCode:item.ldrawColorCode];

		if (hasColor)
			row[LDrawPartBrowserColorCodeKey] = @(item.ldrawColorCode);
		if (item.rebrickablePartNumber != nil)
			row[LDrawPartBrowserLEGONumberKey] = item.rebrickablePartNumber;

		row[LDrawPartBrowserUsedKey]		= @(used);
		row[LDrawPartBrowserOwnedKey]		= @(owned);
		row[LDrawPartBrowserSparesKey]		= @(spares ? item.spareQuantity : 0);
		row[LDrawPartBrowserLeftKey]		= @((NSInteger)owned - (NSInteger)used);
		row[LDrawPartBrowserCountTextKey]	= [NSString stringWithFormat:@"%lu / %lu",
											   (unsigned long)used, (unsigned long)owned];
		[rows addObject:row];
	}
	return rows;
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

		NSString *legoNumber = [record objectForKey:LDrawPartBrowserLEGONumberKey];

		BOOL matches = YES;
		for (NSString *word in searchWords)
		{
			if (!([partNumber ldraw_containsString:word options:NSCaseInsensitiveSearch] ||
				 [partSansWhitespace ldraw_containsString:word options:NSCaseInsensitiveSearch] ||
				 [legoNumber ldraw_containsString:word options:NSCaseInsensitiveSearch]))
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


//========== categoryHierarchy =================================================
//
// Purpose:		The library's categories, and the store's sets and inventories
//				in a Sets group after Part Categories.
//
//==============================================================================
- (NSArray *)categoryHierarchy
{
	NSMutableArray			*hierarchy	= [[self.partLibrary categoryHierarchy] mutableCopy] ?: [NSMutableArray array];
	LDrawInventoryStore		*store		= self.limitSession.store;
	NSMutableArray			*children	= [NSMutableArray array];
	NSMutableArray			*identifiers	= [NSMutableArray array];

	[identifiers addObjectsFromArray:[store setNumbers] ?: @[]];
	[identifiers addObjectsFromArray:[[store combinedInventories] valueForKey:@"identifier"] ?: @[]];

	for (NSString *identifier in identifiers)
	{
		[children addObject:@{
			CategoryNameKey: [[self class] categoryForInventoryIdentifier:identifier],
			CategoryDisplayNameKey: [self titleForInventoryIdentifier:identifier] ?: identifier,
		}];
	}

	if ([children count] > 0)
	{
		[hierarchy insertObject:@{
			CategoryNameKey: SetsGroupName,
			CategoryDisplayNameKey: [LDrawLocalization stringForKey:@"CategoryGroup_Sets"],
			CategoryChildrenKey: children,
		} atIndex:MIN((NSUInteger)2, [hierarchy count])];
	}
	return hierarchy;
}


//========== hasCategory: ======================================================
//==============================================================================
- (BOOL)hasCategory:(NSString *)category
{
	NSString *identifier = [[self class] inventoryIdentifierForCategory:category];

	if (category == nil)
		return NO;
	if (identifier != nil)
		return [self titleForInventoryIdentifier:identifier] != nil;
	return [self.partLibrary partCatalogRecordsInCategory:category] != nil;
}


//========== displayNameForCategory: ===========================================
//==============================================================================
- (NSString *)displayNameForCategory:(NSString *)category
{
	NSString *identifier = [[self class] inventoryIdentifierForCategory:category];

	if (identifier != nil)
		return [self titleForInventoryIdentifier:identifier] ?: identifier;
	return [self.partLibrary displayNameForCategory:category];
}


//========== titleForInventoryIdentifier: ======================================
//
// Purpose:		A set's number and name, or an inventory's name. Nil when the
//				store has neither.
//
//==============================================================================
- (NSString *)titleForInventoryIdentifier:(NSString *)identifier
{
	LDrawInventoryStore		*store		= self.limitSession.store;
	LDrawSetInventory		*set		= [store setInventoryForNumber:identifier];
	LDrawCombinedInventory	*inventory	= [store combinedInventoryWithIdentifier:identifier];

	if (set != nil)
		return [NSString stringWithFormat:@"%@ %@", set.setNumber, set.name];
	return inventory.name;
}


//---------- categoryForInventoryIdentifier: -------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *)categoryForInventoryIdentifier:(NSString *)identifier
{
	return [InventoryCategoryPrefix stringByAppendingString:identifier];
}


//---------- inventoryIdentifierForCategory: -------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *)inventoryIdentifierForCategory:(NSString *)category
{
	if ([category hasPrefix:InventoryCategoryPrefix] == NO)
		return nil;
	return [category substringFromIndex:[InventoryCategoryPrefix length]];
}


//========== stateForRecord: ===================================================
//
// Purpose:		How a row is drawn: an inventory row by its count, a library
//				part by whether the active table allows it.
//
//==============================================================================
- (LDrawPartBrowserRowState)stateForRecord:(NSDictionary *)record
{
	NSString	*partName	= [record objectForKey:PART_NUMBER_KEY];
	NSString	*category	= [record objectForKey:PART_CATEGORY_KEY];

	if ([record objectForKey:LDrawPartBrowserCountTextKey] != nil)
	{
		NSInteger	left	= [[record objectForKey:LDrawPartBrowserLeftKey] integerValue];
		NSUInteger	owned	= [[record objectForKey:LDrawPartBrowserOwnedKey] unsignedIntegerValue];

		if (partName == nil)
			return LDrawPartBrowserRowNoPart;
		if (left < 0)
			return LDrawPartBrowserRowOver;
		if (left == 0 && owned > 0)
			return LDrawPartBrowserRowAllUsed;
		return LDrawPartBrowserRowNormal;
	}

	if (self.activeTable == nil || partName == nil || [self isUnfilteredCategory:category])
		return LDrawPartBrowserRowNormal;
	return [self.activeTable allowsPartNamed:partName] ? LDrawPartBrowserRowNormal : LDrawPartBrowserRowDimmed;
}


//========== filterColorCodes ==================================================
//==============================================================================
- (NSArray<NSNumber *> *)filterColorCodes
{
	if (self.showsInventoryRows)
	{
		NSSet *codes = [NSSet setWithArray:[self->inventoryRows valueForKey:LDrawPartBrowserColorCodeKey]];
		NSMutableSet *known = [codes mutableCopy];

		[known removeObject:[NSNull null]];
		return [[known allObjects] sortedArrayUsingSelector:@selector(compare:)];
	}
	return [self.activeTable allowedColorCodes];
}


//========== colorChipsForPartNamed: ===========================================
//==============================================================================
- (NSArray<LDrawPartBrowserColorChip *> *)colorChipsForPartNamed:(NSString *)partName
{
	NSMutableArray *chips = [NSMutableArray array];

	if (partName == nil)
		return chips;

	if (self.showsInventoryRows)
	{
		for (NSDictionary *row in self->inventoryRows)
		{
			NSNumber	*color	= row[LDrawPartBrowserColorCodeKey];
			NSInteger	 left	= [row[LDrawPartBrowserLeftKey] integerValue];

			if (color == nil || [row[PART_NUMBER_KEY] isEqualToString:partName] == NO)
				continue;
			[chips addObject:[[LDrawPartBrowserColorChip alloc] initWithColorCode:(LDrawColorT)[color intValue]
																		 hasCount:YES
																		leftCount:left
																		   record:row]];
		}
		[chips sortUsingComparator:^NSComparisonResult(LDrawPartBrowserColorChip *a, LDrawPartBrowserColorChip *b) {
			return [@(a.colorCode) compare:@(b.colorCode)];
		}];
		return chips;
	}

	for (NSNumber *color in [self.activeTable colorCodesForPartNamed:partName])
	{
		[chips addObject:[[LDrawPartBrowserColorChip alloc] initWithColorCode:(LDrawColorT)[color intValue]
																	 hasCount:NO
																	leftCount:0
																	   record:nil]];
	}
	return chips;
}


//========== statusForPartNamed:colorCode: =====================================
//==============================================================================
- (LDrawPartLimitStatus)statusForPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode
{
	if (self.activeTable == nil)
		return LDrawPartLimitStatusAllowed;
	return [self.activeTable statusForPartNamed:partName colorCode:colorCode];
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
