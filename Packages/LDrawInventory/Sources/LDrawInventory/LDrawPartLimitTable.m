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


//========== SortedCodes =======================================================
//==============================================================================
static NSArray<NSNumber *> *SortedCodes(NSSet<NSNumber *> *codes)
{
	return [[codes allObjects] sortedArrayUsingSelector:@selector(compare:)];
}


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
	NSArray<NSNumber *>				*allowedCodes;		// worked out when first asked
	NSArray<NSNumber *>				*everyAllowedCode;	// worked out when first asked
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


// MARK: - FILLING -


//========== fillFromAvailability:year: ========================================
///
/// @abstract	Keeps the parts and colors that came in a set recent enough,
/// 			and the pieces of the assemblies among them.
///
//==============================================================================
- (void) fillFromAvailability:(LDrawPartAvailability *)availability year:(NSInteger)currentYear
{
	LDrawPartLimit		*limit		= self.limit;
	NSInteger			 firstYear	= [limit firstYearForCurrentYear:currentYear];
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
			BOOL isRecent	= (record.lastYear >= firstYear);
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
/// @abstract	The pieces of the first of the part's LDraw parts that is a
/// 			shortcut, or nil. A part the library has under the same number
/// 			decides alone, so a plain part is not split because a stickered
/// 			one links to its number.
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

	for (NSString *name in names)
	{
		NSArray *pieces = [self.shortcuts piecesOfPartNamed:name];
		if (pieces != nil)
			return pieces;
	}
	return nil;

}//end piecesOfRebrickablePartNumber:partName:


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
	LDrawPartLimitStatus	 status			= [self statusOfOnePartNamed:partName colorCode:colorCode];
	LDrawPartLimitStatus	 ofPieces		= LDrawPartLimitStatusAllowed;
	BOOL					 isInventory	= (self.limit.kind == LDrawPartLimitKindInventory);
	NSArray					*pieces			= nil;

	// An inventory holds assemblies as their pieces, so its pieces decide
	// even when a print of one piece shares the assembly's number.
	if (status == LDrawPartLimitStatusAllowed && isInventory == NO)
		return status;

	pieces = [self piecesOfAssemblyNamed:partName];
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


//========== matchesColorCode: =================================================
//==============================================================================
- (BOOL) matchesColorCode:(LDrawColorT)colorCode
{
	return [[self->identity rebrickableColorIDsForColorCode:colorCode] count] > 0;
}


//========== allowsPartNamed: ==================================================
//==============================================================================
- (BOOL) allowsPartNamed:(NSString *)partName
{
	NSArray *pieces = nil;
	NSArray *colors = nil;

	if (self.limit.isRestricting == NO)
		return YES;

	pieces = [self piecesOfAssemblyNamed:partName];
	if (pieces == nil)
		return [self allowsOnePartNamed:partName];

	// An inventory decides an assembly by its pieces alone.
	if (self.limit.kind != LDrawPartLimitKindInventory && [self allowsOnePartNamed:partName])
		return YES;

	colors = [self colorCodesOfPieces:pieces everyCode:YES];
	return colors == nil || [colors count] > 0;

}//end allowsPartNamed:


//========== allowsPartNamed:colorCode: ========================================
//==============================================================================
- (BOOL) allowsPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode
{
	return [self statusForPartNamed:partName colorCode:colorCode] == LDrawPartLimitStatusAllowed;
}


//========== allowsPickingColorCode:forPartNamed: ==============================
//==============================================================================
- (BOOL) allowsPickingColorCode:(LDrawColorT)colorCode forPartNamed:(NSString *)partName
{
	return		self.limit.warnsOnly
			||	[self statusForPartNamed:partName colorCode:colorCode] != LDrawPartLimitStatusNotInColor;
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
//==============================================================================
- (NSArray<NSNumber *> *) colorCodesForPartNamed:(NSString *)partName
{
	return [self colorCodesForPartNamed:partName everyCode:NO];
}


//========== everyColorCodeForPartNamed: =======================================
//==============================================================================
- (NSArray<NSNumber *> *) everyColorCodeForPartNamed:(NSString *)partName
{
	return [self colorCodesForPartNamed:partName everyCode:YES];
}


//========== colorCodesForPartNamed:everyCode: =================================
///
/// @abstract	The colors the part is allowed in. An assembly adds the colors
/// 			its pieces are all allowed in; under an inventory it has only
/// 			those.
///
//==============================================================================
- (NSArray<NSNumber *> *) colorCodesForPartNamed:(NSString *)partName everyCode:(BOOL)everyCode
{
	NSArray<NSNumber *>	*colors		= nil;
	NSArray<NSNumber *>	*ofPieces	= nil;
	NSArray				*pieces		= nil;

	if (self.limit.isRestricting == NO || self.limit.matchesAnyColor)
		return nil;

	colors = [self colorCodesOfOnePartNamed:partName everyCode:everyCode];
	pieces = [self piecesOfAssemblyNamed:partName];
	if (pieces == nil)
		return colors;

	ofPieces = [self colorCodesOfPieces:pieces everyCode:everyCode];
	if (self.limit.kind == LDrawPartLimitKindInventory)
		return ofPieces;
	if (colors == nil || ofPieces == nil)
		return nil;

	return SortedCodes([[NSSet setWithArray:colors] setByAddingObjectsFromArray:ofPieces]);

}//end colorCodesForPartNamed:everyCode:


//========== allowedColorCodes =================================================
//==============================================================================
- (NSArray<NSNumber *> *) allowedColorCodes
{
	return [self allowedColorCodesWithEveryCode:NO];
}


//========== everyAllowedColorCode =============================================
//==============================================================================
- (NSArray<NSNumber *> *) everyAllowedColorCode
{
	return [self allowedColorCodesWithEveryCode:YES];
}


//========== allowedColorCodesWithEveryCode: ===================================
///
/// @abstract	The colors of every pool, each pool taking the colors its own
/// 			part suits.
///
//==============================================================================
- (NSArray<NSNumber *> *) allowedColorCodesWithEveryCode:(BOOL)everyCode
{
	NSArray			*cached	= everyCode ? self->everyAllowedCode : self->allowedCodes;
	NSMutableSet	*codes	= nil;

	if (self.limit.isRestricting == NO || self.limit.matchesAnyColor)
		return nil;
	if (cached != nil)
		return cached;

	// A pool is keyed by a Rebrickable number, which tells if it is rubber.
	codes = [NSMutableSet set];
	for (NSString *pool in self->colorsByPool)
	{
		[self addColorCodesForColorIDs:[self->colorsByPool[pool] allKeys]
						  ofPartNumber:pool
							 everyCode:everyCode
									to:codes];
	}
	cached = SortedCodes(codes);

	if (everyCode)
		self->everyAllowedCode = cached;
	else
		self->allowedCodes = cached;
	return cached;

}//end allowedColorCodesWithEveryCode:


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
	NSArray			*colorIDs	= nil;
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

	colorIDs = [self->identity rebrickableColorIDsForColorCode:colorCode];
	if ([colorIDs count] == 0)
		return LDrawPartLimitStatusNoData;

	for (NSNumber *colorID in colorIDs)
		isAllowed = isAllowed || (colors[colorID] != nil);
	if (isAllowed == NO)
		return LDrawPartLimitStatusNotInColor;

	// Rubber red matches red, but a part that is not rubber is not made in it.
	if ([self->identity colorCode:colorCode suitsPartNamed:partName] == NO)
		return LDrawPartLimitStatusNotInColor;
	return LDrawPartLimitStatusAllowed;

}//end statusOfOnePartNamed:colorCode:


//========== allowsOnePartNamed: ===============================================
//==============================================================================
- (BOOL) allowsOnePartNamed:(NSString *)partName
{
	return [[self colorsOfPartNamed:partName] count] > 0;
}


//========== ownedCountOfOnePartNamed:colorCode: ===============================
///
/// @abstract	How many the inventory holds. What came in "any color" counts
/// 			toward every color.
///
//==============================================================================
- (NSUInteger) ownedCountOfOnePartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode
{
	NSDictionary	*colors	= [self colorsOfPartNamed:partName];
	NSUInteger		 owned	= [colors[@(LDrawRebrickableColorAny)] unsignedIntegerValue];

	if (self.limit.matchesAnyColor == NO)
	{
		for (NSNumber *colorID in [self->identity rebrickableColorIDsForColorCode:colorCode])
			owned += [colors[colorID] unsignedIntegerValue];
	}
	return owned;

}//end ownedCountOfOnePartNamed:colorCode:


//========== colorCodesOfOnePartNamed:everyCode: ===============================
///
/// @abstract	The colors the part is allowed in, not looking at its pieces.
/// 			Nil when they are not restricted.
///
//==============================================================================
- (NSArray<NSNumber *> *) colorCodesOfOnePartNamed:(NSString *)partName everyCode:(BOOL)everyCode
{
	NSDictionary	*colors	= [self colorsOfPartNamed:partName];
	NSString		*number	= nil;
	NSMutableSet	*codes	= [NSMutableSet set];

	if (colors[@(LDrawRebrickableColorAny)] != nil)
		return nil;

	// Only the extra codes depend on the part, so it is looked up only for them.
	if (everyCode)
		number = [self->identity rebrickablePartNumberForPartName:partName];
	[self addColorCodesForColorIDs:[colors allKeys] ofPartNumber:number everyCode:everyCode to:codes];
	return SortedCodes(codes);

}//end colorCodesOfOnePartNamed:everyCode:


//========== colorCodesOfPieces:everyCode: =====================================
///
/// @abstract	The colors an assembly can take with every piece allowed. Nil
/// 			for any color; empty when a piece is not allowed at all.
///
//==============================================================================
- (NSArray<NSNumber *> *) colorCodesOfPieces:(NSArray<LDrawShortcutPiece *> *)pieces everyCode:(BOOL)everyCode
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

		NSArray *colors = [self colorCodesOfOnePartNamed:piece.partName everyCode:everyCode];
		if (colors == nil)
			continue;
		if (common == nil)
			common = [NSMutableSet setWithArray:colors];
		else
			[common intersectSet:[NSSet setWithArray:colors]];
	}
	return (common != nil) ? SortedCodes(common) : nil;

}//end colorCodesOfPieces:everyCode:


// MARK: - UTILITIES -


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


//========== colorsOfPartNamed: ================================================
///
/// @abstract	What the part's pool holds, by Rebrickable color, or nil.
///
//==============================================================================
- (NSDictionary<NSNumber *, NSNumber *> *) colorsOfPartNamed:(NSString *)partName
{
	NSString *pool = [self poolKeyForPartNamed:partName];
	return (pool != nil) ? self->colorsByPool[pool] : nil;
}


//========== piecesOfAssemblyNamed: ============================================
///
/// @abstract	The pieces of a shortcut, or nil for any other part. Nil too
/// 			while the table has no data, since no piece is allowed then.
///
//==============================================================================
- (NSArray<LDrawShortcutPiece *> *) piecesOfAssemblyNamed:(NSString *)partName
{
	if (self->colorsByPool == nil)
		return nil;
	return [self.shortcuts piecesOfPartNamed:partName];
}


//========== addColorCodesForColorIDs:ofPartNumber:everyCode:to: ===============
///
/// @abstract	Adds the LDraw colors of these Rebrickable colors: the first
/// 			one each links to, or with everyCode each one that suits the
/// 			part. Colors with no LDraw match add nothing.
///
//==============================================================================
- (void) addColorCodesForColorIDs:(NSArray<NSNumber *> *)colorIDs
					 ofPartNumber:(NSString *)partNumber
						everyCode:(BOOL)everyCode
							   to:(NSMutableSet<NSNumber *> *)codes
{
	for (NSNumber *colorID in colorIDs)
	{
		NSArray *linked = [self->identity colorCodesForRebrickableColorID:[colorID integerValue]
															 ofPartNumber:partNumber];
		if (everyCode)
			[codes addObjectsFromArray:linked];
		else if ([linked count] > 0)
			[codes addObject:linked[0]];
	}

}//end addColorCodesForColorIDs:ofPartNumber:everyCode:to:

@end
