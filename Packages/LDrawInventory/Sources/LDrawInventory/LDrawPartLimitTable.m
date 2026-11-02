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
#import <LDrawInventory/LDrawShortcutMap.h>

// Starts the pool of a part with no Rebrickable number, followed by its name.
static NSString * const LDrawNamePoolPrefix = @"ldraw:";


@interface LDrawPartLimitTable ()

@property (nonatomic, readonly) LDrawShortcutMap *shortcuts;

@end


@implementation LDrawPartLimitTable
{
	LDrawPartIdentity	*identity;

	// Pool → Rebrickable color → what is owned there. For Available now the
	// value is the number of sets, which is not used. Nil without data.
	NSDictionary<NSString *, NSDictionary<NSNumber *, NSNumber *> *>	*colorsByPool;

	NSArray<LDrawInventoryItem *>	*rows;
	NSArray<LDrawInventoryItem *>	*unmatched;
	NSArray<NSNumber *>				*allowedColorCodes;	// worked out when first asked
	NSMutableDictionary				*poolsByName;		// part name → pool, or NSNull for none
}


// MARK: - INITIALIZATION -


//========== initWithLimit:identity:shortcuts: =================================
//==============================================================================
- (instancetype) initWithLimit:(LDrawPartLimit *)limit
					  identity:(LDrawPartIdentity *)partIdentity
					 shortcuts:(LDrawShortcutMap *)shortcuts
{
	self = [super init];
	if (self) {
		self->_limit		= [limit copy];
		self->_shortcuts	= shortcuts;
		self->identity		= partIdentity;
		self->rows			= @[];
		self->unmatched		= @[];
		self->poolsByName	= [NSMutableDictionary dictionary];
	}
	return self;
}


//---------- unrestrictedTable ---------------------------------------[static]--
//------------------------------------------------------------------------------
+ (instancetype) unrestrictedTable
{
	return [[self alloc] initWithLimit:[LDrawPartLimit noLimit]
							  identity:[LDrawPartIdentity emptyIdentity]
							 shortcuts:nil];
}


//---------- tableForLimit:availability:items:identity:year: ---------[static]--
//------------------------------------------------------------------------------
+ (instancetype) tableForLimit:(LDrawPartLimit *)limit
				  availability:(LDrawPartAvailability *)availability
						 items:(NSArray<LDrawInventoryItem *> *)items
					  identity:(LDrawPartIdentity *)partIdentity
						  year:(NSInteger)currentYear
{
	return [self tableForLimit:limit
				  availability:availability
						 items:items
					  identity:partIdentity
					 shortcuts:nil
						  year:currentYear];
}


//---------- tableForLimit:availability:items:identity:shortcuts:year: [static]-
///
/// @abstract	A table for the limit, built from what it reads.
///
//------------------------------------------------------------------------------
+ (instancetype) tableForLimit:(LDrawPartLimit *)limit
				  availability:(LDrawPartAvailability *)availability
						 items:(NSArray<LDrawInventoryItem *> *)items
					  identity:(LDrawPartIdentity *)partIdentity
					 shortcuts:(LDrawShortcutMap *)shortcuts
						  year:(NSInteger)currentYear
{
	LDrawPartLimitTable *table = [[self alloc] initWithLimit:limit identity:partIdentity shortcuts:shortcuts];

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

}//end tableForLimit:availability:items:identity:shortcuts:year:


//========== fillFromAvailability:year: ========================================
///
/// @abstract	Keeps the parts and colors that came in a set recent enough,
/// 			and the pieces of the assemblies among them.
///
//==============================================================================
- (void) fillFromAvailability:(LDrawPartAvailability *)availability year:(NSInteger)currentYear
{
	LDrawPartLimit		*limit		= self.limit;
	NSInteger			 firstYear	= currentYear - limit.yearsBack + 1;
	NSMutableDictionary	*pools		= [NSMutableDictionary dictionary];

	for (NSString *partNumber in [availability partNumbers])
	{
		NSString		*pool		= [self->identity poolKeyForRebrickablePartNumber:partNumber
																 matchesMoldVariants:limit.matchesMoldVariants
																	 matchesAnyPrint:limit.matchesAnyPrint];
		NSMutableArray	*piecePools	= [NSMutableArray array];	// pool, and color or NSNull for the record's

		for (LDrawShortcutPiece *piece in [self piecesOfRebrickablePartNumber:partNumber partName:nil])
		{
			NSString	*piecePool	= [self poolKeyForFillingPartNamed:piece.partName];
			NSInteger	 colorID	= [self->identity rebrickableColorIDForColorCode:piece.colorCode];

			if (piecePool == nil)
				continue;
			if (piece.colorCode == LDrawCurrentColor)
				[piecePools addObject:@[piecePool, [NSNull null]]];
			else if (colorID != LDrawRebrickableColorNone)
				[piecePools addObject:@[piecePool, @(colorID)]];
		}

		[availability enumerateRecordsForPartNumber:partNumber usingBlock:^(LDrawPartAvailabilityRecord record) {
			BOOL isRecent	= (limit.yearsBack == 0 || record.lastYear >= firstYear);
			BOOL isCounted	= (record.onlyInDatabaseSets == NO || limit.countsPickABrickParts);

			if (isRecent == NO || isCounted == NO)
				return;

			[self addCount:record.setCount colorID:record.colorID pool:pool to:pools];

			for (NSArray *piece in piecePools)
			{
				NSInteger colorID = (piece[1] == [NSNull null]) ? record.colorID : [piece[1] integerValue];
				[self addCount:record.setCount colorID:colorID pool:piece[0] to:pools];
			}
		}];
	}
	self->colorsByPool = pools;

}//end fillFromAvailability:year:


//========== addCount:colorID:pool:to: =========================================
///
/// @abstract	Adds to what a pool holds in a color, or in any color when the
/// 			limit matches any.
///
//==============================================================================
- (void) addCount:(NSUInteger)count
		  colorID:(NSInteger)colorID
			 pool:(NSString *)pool
			   to:(NSMutableDictionary<NSString *, NSMutableDictionary *> *)pools
{
	NSMutableDictionary	*colors	= pools[pool];
	NSNumber			*color	= self.limit.matchesAnyColor ? @(LDrawRebrickableColorAny) : @(colorID);

	if (colors == nil)
	{
		colors = [NSMutableDictionary dictionary];
		pools[pool] = colors;
	}
	colors[color] = @([colors[color] unsignedIntegerValue] + count);

}//end addCount:colorID:pool:to:


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

	for (LDrawInventoryItem *item in [self itemsSplittingAssemblies:items])
	{
		NSString	*partNumber	= item.rebrickablePartNumber;
		NSInteger	 colorID	= item.rebrickableColorID;
		NSString	*pool		= nil;
		NSString	*rowKey		= nil;
		NSUInteger	 owned		= item.quantity + (limit.includesSpares ? item.spareQuantity : 0);

		if (partNumber == nil && item.ldrawPartName != nil)
			partNumber = [self->identity rebrickablePartNumberForPartName:item.ldrawPartName];
		if (colorID == LDrawRebrickableColorNone && item.ldrawColorCode != LDrawColorBogus)
			colorID = [self->identity rebrickableColorIDForColorCode:item.ldrawColorCode];
		if (limit.matchesAnyColor)
			colorID = LDrawRebrickableColorAny;

		if (partNumber != nil)
			pool = [self->identity poolKeyForRebrickablePartNumber:partNumber
											   matchesMoldVariants:limit.matchesMoldVariants
												   matchesAnyPrint:limit.matchesAnyPrint];
		else if (item.ldrawPartName != nil)
			pool = [self poolKeyForFillingPartNamed:item.ldrawPartName];

		if (	pool == nil
			||	colorID == LDrawRebrickableColorNone
			||	colorID == LDrawRebrickableColorUnknown )
		{
			[unmatchedItems addObject:item];
			continue;
		}

		// A spare left out owns nothing, so it must not allow its color.
		if (owned > 0)
			[self addCount:owned colorID:colorID pool:pool to:pools];

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


//========== itemsSplittingAssemblies: =========================================
///
/// @abstract	The items with each assembly replaced by its pieces, in the
/// 			same counts.
///
//==============================================================================
- (NSArray<LDrawInventoryItem *> *) itemsSplittingAssemblies:(NSArray<LDrawInventoryItem *> *)items
{
	NSMutableArray *result = nil;

	if (self.shortcuts == nil)
		return items;

	result = [NSMutableArray arrayWithCapacity:[items count]];
	for (LDrawInventoryItem *item in items)
	{
		NSArray *pieces = [self piecesOfRebrickablePartNumber:item.rebrickablePartNumber partName:item.ldrawPartName];

		if (pieces == nil)
		{
			[result addObject:item];
			continue;
		}

		for (LDrawShortcutPiece *piece in pieces)
		{
			BOOL				 takesColor	= (piece.colorCode == LDrawCurrentColor);
			NSInteger			 colorID	= takesColor ? item.rebrickableColorID : LDrawRebrickableColorNone;
			LDrawColorT			 colorCode	= takesColor ? item.ldrawColorCode : piece.colorCode;
			LDrawInventoryItem	*pieceItem	= nil;

			pieceItem = [[LDrawInventoryItem alloc] initWithRebrickablePartNumber:nil
															   rebrickableColorID:colorID
																	ldrawPartName:piece.partName
																   ldrawColorCode:colorCode
																		 quantity:item.quantity
																	spareQuantity:item.spareQuantity];
			[result addObject:pieceItem];
		}
	}
	return result;

}//end itemsSplittingAssemblies:


//========== piecesOfRebrickablePartNumber:partName: ===========================
///
/// @abstract	The pieces a Rebrickable part stands for, or nil. A part the
/// 			library has under the same number decides alone, so a plain part
/// 			is not split because a stickered one links to its number.
///
//==============================================================================
- (NSArray<LDrawShortcutPiece *> *) piecesOfRebrickablePartNumber:(NSString *)partNumber
														 partName:(NSString *)partName
{
	NSMutableArray	*names	= [NSMutableArray array];
	NSArray			*linked	= nil;
	NSString		*same	= nil;

	if (self.shortcuts == nil)
		return nil;

	if (partNumber != nil)
	{
		linked	= [self->identity partNamesForRebrickablePartNumber:partNumber];
		same	= [[partNumber lowercaseString] stringByAppendingPathExtension:@"dat"];
		if ([linked containsObject:same] && [self.shortcuts hasPartNamed:same])
			return [self.shortcuts piecesOfPartNamed:same];
	}

	if (partName != nil)
		[names addObject:partName];
	[names addObjectsFromArray:linked ?: @[]];
	return [self piecesOfPartNames:names];

}//end piecesOfRebrickablePartNumber:partName:


//========== piecesOfPartNames: ================================================
///
/// @abstract	The pieces of the first of these parts that is a shortcut, or
/// 			nil.
///
//==============================================================================
- (NSArray<LDrawShortcutPiece *> *) piecesOfPartNames:(NSArray<NSString *> *)partNames
{
	if (self.shortcuts == nil)
		return nil;

	for (NSString *partName in partNames)
	{
		NSArray *pieces = [self.shortcuts piecesOfPartNamed:partName];
		if (pieces != nil)
			return pieces;
	}
	return nil;

}//end piecesOfPartNames:


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
/// @abstract	How the part stands in this color. An assembly the part itself
/// 			does not allow stands as its pieces do.
///
//==============================================================================
- (LDrawPartLimitStatus) statusForPartNamed:(NSString *)partName
								  colorCode:(LDrawColorT)colorCode
{
	LDrawPartLimitStatus	 status		= [self statusOfOnePartNamed:partName colorCode:colorCode];
	LDrawPartLimitStatus	 ofPieces	= LDrawPartLimitStatusAllowed;
	BOOL					 isInventory	= (self.limit.kind == LDrawPartLimitKindInventory);
	NSArray					*pieces		= nil;

	// An inventory holds assemblies as their pieces, so its pieces decide
	// even when a print of one piece shares the assembly's number.
	if ((status == LDrawPartLimitStatusAllowed && isInventory == NO) || self->colorsByPool == nil)
		return status;

	pieces = [self.shortcuts piecesOfPartNamed:partName];
	if (pieces == nil)
		return status;

	for (LDrawShortcutPiece *piece in pieces)
		ofPieces = MAX(ofPieces, [self statusOfOnePartNamed:piece.partName
												  colorCode:[piece colorCodeInAssemblyColor:colorCode]]);

	if (isInventory || status == LDrawPartLimitStatusNoData)
		return ofPieces;
	if (ofPieces == LDrawPartLimitStatusNoData)
		return status;
	return MIN(status, ofPieces);

}//end statusForPartNamed:colorCode:


//========== allowsPartNamed: ==================================================
//==============================================================================
- (BOOL) allowsPartNamed:(NSString *)partName
{
	NSArray *pieces = nil;

	if (self.limit.isRestricting == NO)
		return YES;

	// An inventory decides an assembly by its pieces alone.
	pieces = (self->colorsByPool != nil) ? [self.shortcuts piecesOfPartNamed:partName] : nil;
	if (pieces == nil || self.limit.kind != LDrawPartLimitKindInventory)
	{
		if ([self allowsOnePartNamed:partName])
			return YES;
		if (pieces == nil)
			return NO;
	}

	NSArray *colors = [self colorCodesOfPieces:pieces];
	return colors == nil || [colors count] > 0;

}//end allowsPartNamed:


//========== allowsPartNamed:colorCode: ========================================
//==============================================================================
- (BOOL) allowsPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode
{
	return [self statusForPartNamed:partName colorCode:colorCode] == LDrawPartLimitStatusAllowed;
}


//========== ownedCountForPartNamed:colorCode: =================================
///
/// @abstract	How many the inventory holds. An assembly counts as many as
/// 			its scarcest piece allows.
///
//==============================================================================
- (NSUInteger) ownedCountForPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode
{
	NSArray				*pieces		= [self countedPiecesOfPartNamed:partName];
	NSCountedSet		*needed		= nil;
	NSUInteger			 owned		= NSNotFound;

	if (self.limit.kind != LDrawPartLimitKindInventory)
		return NSNotFound;
	if (pieces == nil)
		return [self ownedCountOfOnePartNamed:partName colorCode:colorCode];

	needed = [NSCountedSet set];
	for (LDrawShortcutPiece *piece in pieces)
		[needed addObject:@[piece.partName, @([piece colorCodeInAssemblyColor:colorCode])]];

	for (NSArray *piece in needed)
	{
		NSUInteger held = [self ownedCountOfOnePartNamed:piece[0] colorCode:(LDrawColorT)[piece[1] intValue]];
		owned = MIN(owned, held / [needed countForObject:piece]);
	}
	return owned;

}//end ownedCountForPartNamed:colorCode:


//========== colorCodesForPartNamed: ===========================================
///
/// @abstract	The colors the part is allowed in. An assembly adds the colors
/// 			its pieces are all allowed in; under an inventory it has only
/// 			those.
///
//==============================================================================
- (NSArray<NSNumber *> *) colorCodesForPartNamed:(NSString *)partName
{
	NSArray<NSNumber *>	*colors		= nil;
	NSArray<NSNumber *>	*ofPieces	= nil;
	NSArray				*pieces		= nil;

	if (self.limit.isRestricting == NO || self.limit.matchesAnyColor)
		return nil;

	colors = [self colorCodesOfOnePartNamed:partName];
	pieces = (self->colorsByPool != nil) ? [self.shortcuts piecesOfPartNamed:partName] : nil;
	if (pieces == nil)
		return colors;

	ofPieces = [self colorCodesOfPieces:pieces];
	if (self.limit.kind == LDrawPartLimitKindInventory)
		return ofPieces;
	if (colors == nil || ofPieces == nil)
		return nil;

	NSMutableSet *both = [NSMutableSet setWithArray:colors];
	[both addObjectsFromArray:ofPieces];
	return [[both allObjects] sortedArrayUsingSelector:@selector(compare:)];

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
///
/// @abstract	The pool of the part's Rebrickable number, or else of its LDraw
/// 			name when the table has one. Each name is worked out once, since
/// 			every lookup starts here.
///
//==============================================================================
- (NSString *) poolKeyForPartNamed:(NSString *)partName
{
	id pool = nil;

	if (partName == nil)
		return nil;

	@synchronized (self->poolsByName) {
		pool = self->poolsByName[partName];
	}
	if (pool == nil)
	{
		pool = [self poolKeyForFillingPartNamed:partName];
		if ([pool hasPrefix:LDrawNamePoolPrefix] && self->colorsByPool[pool] == nil)
			pool = nil;

		@synchronized (self->poolsByName) {
			self->poolsByName[partName] = pool ?: [NSNull null];
		}
	}
	return (pool == [NSNull null]) ? nil : pool;

}//end poolKeyForPartNamed:


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


//========== countedPiecesOfPartNamed: =========================================
//==============================================================================
- (NSArray<LDrawShortcutPiece *> *) countedPiecesOfPartNamed:(NSString *)partName
{
	if (self.limit.kind != LDrawPartLimitKindInventory)
		return nil;
	return [self.shortcuts piecesOfPartNamed:partName];
}


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


// MARK: - ONE PART -


//========== statusOfOnePartNamed:colorCode: ===================================
///
/// @abstract	How the part stands in this color, not looking at its pieces.
///
//==============================================================================
- (LDrawPartLimitStatus) statusOfOnePartNamed:(NSString *)partName
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

}//end statusOfOnePartNamed:colorCode:


//========== allowsOnePartNamed: ===============================================
//==============================================================================
- (BOOL) allowsOnePartNamed:(NSString *)partName
{
	NSString *pool = [self poolKeyForPartNamed:partName];
	return pool != nil && [self->colorsByPool[pool] count] > 0;
}


//========== ownedCountOfOnePartNamed:colorCode: ===============================
///
/// @abstract	How many the inventory holds. What came in "any color" counts
/// 			toward every color.
///
//==============================================================================
- (NSUInteger) ownedCountOfOnePartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode
{
	NSString		*pool	= [self poolKeyForPartNamed:partName];
	NSDictionary	*colors	= (pool != nil) ? self->colorsByPool[pool] : nil;
	NSUInteger		 owned	= [colors[@(LDrawRebrickableColorAny)] unsignedIntegerValue];

	if (self.limit.matchesAnyColor == NO)
	{
		for (NSNumber *colorID in [self->identity rebrickableColorIDsForColorCode:colorCode])
			owned += [colors[colorID] unsignedIntegerValue];
	}
	return owned;

}//end ownedCountOfOnePartNamed:colorCode:


//========== colorCodesOfOnePartNamed: =========================================
///
/// @abstract	The colors the part is allowed in, not looking at its pieces.
/// 			Nil when they are not restricted.
///
//==============================================================================
- (NSArray<NSNumber *> *) colorCodesOfOnePartNamed:(NSString *)partName
{
	NSString		*pool	= [self poolKeyForPartNamed:partName];
	NSDictionary	*colors	= (pool != nil) ? self->colorsByPool[pool] : nil;

	if (colors[@(LDrawRebrickableColorAny)] != nil)
		return nil;
	return [self colorCodesForColorIDs:[colors allKeys]];
}


//========== colorCodesOfPieces: ===============================================
///
/// @abstract	The colors an assembly can take with every piece allowed. Nil
/// 			for any color; empty when a piece is not allowed at all.
///
//==============================================================================
- (NSArray<NSNumber *> *) colorCodesOfPieces:(NSArray<LDrawShortcutPiece *> *)pieces
{
	NSMutableSet *common = nil;	// nil while any color goes

	for (LDrawShortcutPiece *piece in pieces)
	{
		if (piece.colorCode != LDrawCurrentColor)
		{
			LDrawPartLimitStatus status = [self statusOfOnePartNamed:piece.partName colorCode:piece.colorCode];
			if (status != LDrawPartLimitStatusAllowed)
				return @[];
			continue;
		}

		if ([self allowsOnePartNamed:piece.partName] == NO)
			return @[];

		NSArray *colors = [self colorCodesOfOnePartNamed:piece.partName];
		if (colors == nil)
			continue;
		if (common == nil)
			common = [NSMutableSet setWithArray:colors];
		else
			[common intersectSet:[NSSet setWithArray:colors]];
	}
	return (common != nil) ? [[common allObjects] sortedArrayUsingSelector:@selector(compare:)] : nil;

}//end colorCodesOfPieces:


// MARK: - UTILITIES -


//========== poolKeyForFillingPartNamed: =======================================
///
/// @abstract	The pool a part goes into: its Rebrickable number's, or else
/// 			its LDraw name's. Nil for no name.
///
//==============================================================================
- (NSString *) poolKeyForFillingPartNamed:(NSString *)partName
{
	NSString *partNumber	= [self->identity rebrickablePartNumberForPartName:partName];
	NSString *name			= nil;

	if (partNumber != nil)
		return [self->identity poolKeyForRebrickablePartNumber:partNumber
										   matchesMoldVariants:self.limit.matchesMoldVariants
											   matchesAnyPrint:self.limit.matchesAnyPrint];

	name = [LDrawPartIdentity normalizedPartName:partName];
	return (name != nil) ? [LDrawNamePoolPrefix stringByAppendingString:name] : nil;

}//end poolKeyForFillingPartNamed:


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
