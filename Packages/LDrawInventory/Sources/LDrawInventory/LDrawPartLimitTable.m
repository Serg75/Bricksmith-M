//==============================================================================
//
//  File:       LDrawPartLimitTable.m
//  Package:    LDrawInventory
//
//  Purpose:    What a limit allows, ready for lookups by LDraw part name and
//              color code.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawInventory/LDrawPartLimitTable.h>

#import <LDrawInventory/LDrawInventoryItem.h>
#import <LDrawInventory/LDrawPartAvailability.h>
#import <LDrawInventory/LDrawPartIdentity.h>
#import <LDrawInventory/LDrawPartLimit.h>


@implementation LDrawPartLimitTable
{
	LDrawPartIdentity	*identity;

	// Pool → Rebrickable color → what is owned there. For Available now the
	// value is the number of sets, which is not used. Nil without data.
	NSDictionary<NSString *, NSDictionary<NSNumber *, NSNumber *> *>	*colorsByPool;

	NSArray<LDrawInventoryItem *>	*rows;
	NSArray<LDrawInventoryItem *>	*unmatched;
	NSArray<NSNumber *>				*allowedColorCodes;	// worked out when first asked
}


// MARK: - INITIALIZATION -


//========== initWithLimit:identity: ===========================================
//==============================================================================
- (instancetype) initWithLimit:(LDrawPartLimit *)limit identity:(LDrawPartIdentity *)partIdentity
{
	self = [super init];
	if (self) {
		self->_limit	= [limit copy];
		self->identity	= partIdentity;
		self->rows		= @[];
		self->unmatched	= @[];
	}
	return self;
}


//---------- unrestrictedTable ---------------------------------------[static]--
//------------------------------------------------------------------------------
+ (instancetype) unrestrictedTable
{
	return [[self alloc] initWithLimit:[LDrawPartLimit noLimit] identity:[LDrawPartIdentity emptyIdentity]];
}


//---------- tableForLimit:availability:items:identity:year: ---------[static]--
///
/// @abstract	A table for the limit, built from what it reads.
///
//------------------------------------------------------------------------------
+ (instancetype) tableForLimit:(LDrawPartLimit *)limit
				  availability:(LDrawPartAvailability *)availability
						 items:(NSArray<LDrawInventoryItem *> *)items
					  identity:(LDrawPartIdentity *)partIdentity
						  year:(NSInteger)currentYear
{
	LDrawPartLimitTable *table = [[self alloc] initWithLimit:limit identity:partIdentity];

	switch (limit.kind)
	{
		case LDrawPartLimitKindNone:
			break;

		case LDrawPartLimitKindAvailableNow:
			if (availability != nil)
				[table fillFromAvailability:availability year:currentYear];
			break;

		case LDrawPartLimitKindInventory:
			if (items != nil)
				[table fillFromItems:items];
			break;
	}
	return table;

}//end tableForLimit:availability:items:identity:year:


//========== fillFromAvailability:year: ========================================
///
/// @abstract	Keeps the parts and colors that came in a set recent enough.
///
//==============================================================================
- (void) fillFromAvailability:(LDrawPartAvailability *)availability year:(NSInteger)currentYear
{
	LDrawPartLimit		*limit		= self.limit;
	NSInteger			 firstYear	= currentYear - limit.yearsBack + 1;
	NSMutableDictionary	*pools		= [NSMutableDictionary dictionary];

	for (NSString *partNumber in [availability partNumbers])
	{
		NSString					*pool	= [self->identity poolKeyForRebrickablePartNumber:partNumber
																	  matchesMoldVariants:limit.matchesMoldVariants
																		  matchesAnyPrint:limit.matchesAnyPrint];
		__block NSMutableDictionary	*colors	= pools[pool];

		[availability enumerateRecordsForPartNumber:partNumber usingBlock:^(LDrawPartAvailabilityRecord record) {
			BOOL isRecent	= (limit.yearsBack == 0 || record.lastYear >= firstYear);
			BOOL isCounted	= (record.onlyInDatabaseSets == NO || limit.countsPickABrickParts);

			if (isRecent && isCounted)
			{
				if (colors == nil)
				{
					colors = [NSMutableDictionary dictionary];
					pools[pool] = colors;
				}
				NSNumber *color = limit.matchesAnyColor ? @(LDrawRebrickableColorAny) : @(record.colorID);
				colors[color] = @([colors[color] unsignedIntegerValue] + record.setCount);
			}
		}];
	}
	self->colorsByPool = pools;

}//end fillFromAvailability:year:


//========== fillFromItems: ====================================================
///
/// @abstract	Adds up the inventory by pool and color, and keeps one row for
/// 			each.
///
//==============================================================================
- (void) fillFromItems:(NSArray<LDrawInventoryItem *> *)items
{
	LDrawPartLimit		*limit			= self.limit;
	NSMutableDictionary	*pools			= [NSMutableDictionary dictionary];
	NSMutableDictionary	*rowsByKey		= [NSMutableDictionary dictionary];
	NSMutableArray		*rowKeys		= [NSMutableArray array];
	NSMutableArray		*unmatchedItems	= [NSMutableArray array];

	for (LDrawInventoryItem *item in items)
	{
		NSString	*partNumber	= item.rebrickablePartNumber;
		NSInteger	 colorID	= item.rebrickableColorID;
		NSString	*pool		= nil;
		NSString	*rowKey		= nil;
		NSUInteger	 owned		= item.quantity + (limit.includesSpares ? item.spareQuantity : 0);

		if (partNumber == nil && item.ldrawPartName != nil)
			partNumber = [self->identity rebrickablePartNumberForPartName:item.ldrawPartName];
		if (colorID == LDrawRebrickableColorNone && item.ldrawColorCode != LDrawColorBogus)
		{
			NSArray *colorIDs = [self->identity rebrickableColorIDsForColorCode:item.ldrawColorCode];
			colorID = [colorIDs count] > 0 ? [colorIDs[0] integerValue] : LDrawRebrickableColorNone;
		}
		if (limit.matchesAnyColor)
			colorID = LDrawRebrickableColorAny;

		if (	partNumber == nil
			||	colorID == LDrawRebrickableColorNone
			||	colorID == LDrawRebrickableColorUnknown )
		{
			[unmatchedItems addObject:item];
			continue;
		}

		pool = [self->identity poolKeyForRebrickablePartNumber:partNumber
										   matchesMoldVariants:limit.matchesMoldVariants
											   matchesAnyPrint:limit.matchesAnyPrint];

		NSMutableDictionary *colors = pools[pool];
		if (colors == nil)
		{
			colors = [NSMutableDictionary dictionary];
			pools[pool] = colors;
		}
		colors[@(colorID)] = @([colors[@(colorID)] unsignedIntegerValue] + owned);

		rowKey = [NSString stringWithFormat:@"%@\n%ld", pool, (long)colorID];
		if (rowsByKey[rowKey] == nil)
		{
			[rowKeys addObject:rowKey];
			rowsByKey[rowKey] = [self rowForItem:item partNumber:partNumber colorID:colorID];
		}
		else
		{
			rowsByKey[rowKey] = [rowsByKey[rowKey] itemByAddingQuantity:item.quantity
														  spareQuantity:item.spareQuantity];
		}
	}

	self->colorsByPool	= pools;
	self->rows			= [rowsByKey objectsForKeys:rowKeys notFoundMarker:[NSNull null]];
	self->unmatched		= unmatchedItems;

}//end fillFromItems:


//========== rowForItem:partNumber:colorID: ====================================
///
/// @abstract	The first item of a row, with both kinds of ids filled in.
///
//==============================================================================
- (LDrawInventoryItem *) rowForItem:(LDrawInventoryItem *)item
						 partNumber:(NSString *)partNumber
							colorID:(NSInteger)colorID
{
	NSString	*partName	= item.ldrawPartName ?: [self->identity partNameForRebrickablePartNumber:partNumber];
	LDrawColorT	 colorCode	= item.ldrawColorCode;

	if (colorCode == LDrawColorBogus)
		colorCode = [self->identity colorCodeForRebrickableColorID:colorID];

	return [[LDrawInventoryItem alloc] initWithRebrickablePartNumber:partNumber
												  rebrickableColorID:colorID
													   ldrawPartName:partName
													  ldrawColorCode:colorCode
															quantity:item.quantity
													   spareQuantity:item.spareQuantity];

}//end rowForItem:partNumber:colorID:


// MARK: - LOOKUPS -


//========== hasData ===========================================================
//==============================================================================
- (BOOL) hasData
{
	return self.limit.isRestricting == NO || self->colorsByPool != nil;
}


//========== statusForPartNamed:colorCode: =====================================
///
/// @abstract	How the part stands in this color.
///
//==============================================================================
- (LDrawPartLimitStatus) statusForPartNamed:(NSString *)partName
								  colorCode:(LDrawColorT)colorCode
{
	NSString		*pool		= nil;
	NSDictionary	*colors		= nil;
	BOOL			 isAllowed	= NO;

	if (self.limit.isRestricting == NO)
		return LDrawPartLimitStatusAllowed;
	if (self->colorsByPool == nil)
		return LDrawPartLimitStatusNoData;

	pool = [self poolKeyForPartNamed:partName];
	if (pool == nil)
		return LDrawPartLimitStatusNoData;

	colors = self->colorsByPool[pool];
	if ([colors count] == 0)
		return LDrawPartLimitStatusNotAvailable;
	if (self.limit.matchesAnyColor || colors[@(LDrawRebrickableColorAny)] != nil)
		return LDrawPartLimitStatusAllowed;

	NSArray *colorIDs = [self->identity rebrickableColorIDsForColorCode:colorCode];
	if ([colorIDs count] == 0)
		return LDrawPartLimitStatusNoData;

	for (NSNumber *colorID in colorIDs)
		isAllowed = isAllowed || (colors[colorID] != nil);

	return isAllowed ? LDrawPartLimitStatusAllowed : LDrawPartLimitStatusNotInColor;

}//end statusForPartNamed:colorCode:


//========== allowsPartNamed: ==================================================
//==============================================================================
- (BOOL) allowsPartNamed:(NSString *)partName
{
	NSString *pool = nil;

	if (self.limit.isRestricting == NO)
		return YES;

	pool = [self poolKeyForPartNamed:partName];
	return pool != nil && [self->colorsByPool[pool] count] > 0;
}


//========== allowsPartNamed:colorCode: ========================================
//==============================================================================
- (BOOL) allowsPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode
{
	return [self statusForPartNamed:partName colorCode:colorCode] == LDrawPartLimitStatusAllowed;
}


//========== ownedCountForPartNamed:colorCode: =================================
///
/// @abstract	How many the inventory holds. What came in "any color" counts
/// 			toward every color.
///
//==============================================================================
- (NSUInteger) ownedCountForPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode
{
	NSString		*pool	= nil;
	NSDictionary	*colors	= nil;
	NSUInteger		 owned	= 0;

	if (self.limit.kind != LDrawPartLimitKindInventory)
		return NSNotFound;

	pool	= [self poolKeyForPartNamed:partName];
	colors	= (pool != nil) ? self->colorsByPool[pool] : nil;
	owned	= [colors[@(LDrawRebrickableColorAny)] unsignedIntegerValue];

	if (self.limit.matchesAnyColor == NO)
	{
		for (NSNumber *colorID in [self->identity rebrickableColorIDsForColorCode:colorCode])
			owned += [colors[colorID] unsignedIntegerValue];
	}
	return owned;

}//end ownedCountForPartNamed:colorCode:


//========== colorCodesForPartNamed: ===========================================
//==============================================================================
- (NSArray<NSNumber *> *) colorCodesForPartNamed:(NSString *)partName
{
	NSString		*pool	= nil;
	NSDictionary	*colors	= nil;

	if (self.limit.isRestricting == NO || self.limit.matchesAnyColor)
		return nil;

	pool	= [self poolKeyForPartNamed:partName];
	colors	= (pool != nil) ? self->colorsByPool[pool] : nil;
	if (colors[@(LDrawRebrickableColorAny)] != nil)
		return nil;

	return [self colorCodesForColorIDs:[colors allKeys]];

}//end colorCodesForPartNamed:


//========== allowedColorCodes =================================================
//==============================================================================
- (NSArray<NSNumber *> *) allowedColorCodes
{
	if (self.limit.isRestricting == NO || self.limit.matchesAnyColor)
		return nil;

	if (self->allowedColorCodes == nil)
	{
		NSMutableSet *colorIDs = [NSMutableSet set];

		for (NSString *pool in self->colorsByPool)
			[colorIDs addObjectsFromArray:[self->colorsByPool[pool] allKeys]];
		self->allowedColorCodes = [self colorCodesForColorIDs:[colorIDs allObjects]];
	}
	return self->allowedColorCodes;

}//end allowedColorCodes


//========== poolKeyForPartNamed: ==============================================
//==============================================================================
- (NSString *) poolKeyForPartNamed:(NSString *)partName
{
	NSString *partNumber = [self->identity rebrickablePartNumberForPartName:partName];

	if (partNumber == nil)
		return nil;

	return [self->identity poolKeyForRebrickablePartNumber:partNumber
									   matchesMoldVariants:self.limit.matchesMoldVariants
										   matchesAnyPrint:self.limit.matchesAnyPrint];
}


//========== countKeyForPartNamed:colorCode: ===================================
//==============================================================================
- (NSString *) countKeyForPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode
{
	NSString	*pool		= [self poolKeyForPartNamed:partName];
	NSArray		*colorIDs	= nil;

	if (pool == nil)
		return nil;
	if (self.limit.matchesAnyColor)
		return [pool stringByAppendingString:@"\n*"];

	colorIDs = [self->identity rebrickableColorIDsForColorCode:colorCode];
	if ([colorIDs count] == 0)
		return nil;

	return [NSString stringWithFormat:@"%@\n%@", pool, [colorIDs componentsJoinedByString:@","]];

}//end countKeyForPartNamed:colorCode:


//========== items =============================================================
//==============================================================================
- (NSArray<LDrawInventoryItem *> *) items
{
	return self->rows;
}


//========== unmatchedItems ====================================================
//==============================================================================
- (NSArray<LDrawInventoryItem *> *) unmatchedItems
{
	return self->unmatched;
}


// MARK: - UTILITIES -


//========== colorCodesForColorIDs: ============================================
///
/// @abstract	The LDraw colors of these Rebrickable colors, each once, lowest
/// 			first. Colors with no LDraw match are left out.
///
//==============================================================================
- (NSArray<NSNumber *> *) colorCodesForColorIDs:(NSArray<NSNumber *> *)colorIDs
{
	NSMutableSet *codes = [NSMutableSet set];

	for (NSNumber *colorID in colorIDs)
	{
		LDrawColorT code = [self->identity colorCodeForRebrickableColorID:[colorID integerValue]];
		if (code != LDrawColorBogus)
			[codes addObject:@(code)];
	}
	return [[codes allObjects] sortedArrayUsingSelector:@selector(compare:)];

}//end colorCodesForColorIDs:

@end
