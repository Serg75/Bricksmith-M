//==============================================================================
//
//  File:       LDrawRebrickableSetImporter.m
//  Package:    LDrawRebrickable
//
//  Purpose:    Gets the parts of one set from the downloads.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawRebrickable/LDrawRebrickableSetImporter.h>

#import <LDrawInventory/LDrawInventoryItem.h>
#import <LDrawInventory/LDrawSetInventory.h>
#import <LDrawRebrickable/LDrawRebrickableCSVReader.h>
#import <LDrawRebrickable/LDrawRebrickableSetList.h>

#import "LDrawRebrickableInventoryIndex.h"

NSString * const LDrawRebrickableSourceDownloads	= @"rebrickable-downloads";
NSString * const LDrawRebrickableSourceAPI			= @"rebrickable-api";


@implementation LDrawRebrickableSetImporter


// MARK: - IMPORTING -


//---------- setInventoryForNumber:fromDownloads:setList:error: ------[static]--
//------------------------------------------------------------------------------
+ (LDrawSetInventory *) setInventoryForNumber:(NSString *)setNumber
								fromDownloads:(LDrawRebrickableDownloads *)downloads
									  setList:(LDrawRebrickableSetList *)setList
										error:(NSError **)error
{
	LDrawRebrickableSet				*set			= [setList setForNumber:setNumber];
	LDrawRebrickableInventoryIndex	*index			= nil;
	NSMutableDictionary				*multipliers	= [NSMutableDictionary dictionary];	// inventory id → count
	NSMutableDictionary				*items			= [NSMutableDictionary dictionary];	// part and color → item

	if (set == nil)
	{
		NSString *reason = [NSString stringWithFormat:@"Rebrickable has no set %@.", setNumber];

		if (error != NULL)
			*error = LDrawRebrickableMakeError(LDrawRebrickableErrorNotFound, reason, nil);
		return nil;
	}

	index = [LDrawRebrickableInventoryIndex indexFromDownloads:downloads error:error];
	if (index == nil)
		return nil;

	[self addInventoryOfNumber:set.setNumber count:1 index:index multipliers:multipliers depth:0];

	BOOL didRead = [index enumeratePartsUsingBlock:^(NSString *inventoryID, NSString *partNumber, NSInteger colorID,
													 NSUInteger quantity, BOOL isSpare, BOOL *stop) {
		NSUInteger count = [multipliers[inventoryID] unsignedIntegerValue];

		if (count > 0)
			[self addPartNumber:partNumber colorID:colorID quantity:quantity * count isSpare:isSpare toItems:items];
	} error:error];

	if (didRead == NO)
		return nil;

	// Saving a set with no parts would hide that the downloads did not match.
	if ([items count] == 0)
	{
		NSString *reason = [NSString stringWithFormat:@"Rebrickable lists no parts for set %@.", set.setNumber];

		if (error != NULL)
			*error = LDrawRebrickableMakeError(LDrawRebrickableErrorNotFound, reason, nil);
		return nil;
	}

	return [[LDrawSetInventory alloc] initWithSetNumber:set.setNumber
												   name:set.name
												   year:set.year
											  themeName:set.themeName
											   imageURL:set.imageURL
												  items:[self sortedItems:[items allValues]]
											  fetchDate:[NSDate date]
												 source:LDrawRebrickableSourceDownloads];

}//end setInventoryForNumber:fromDownloads:setList:error:


// MARK: - UTILITIES -


//---------- addInventoryOfNumber:count:index:multipliers:depth: -----[static]--
///
/// @abstract	Counts a set's or minifigure's newest inventory, and what it
/// 			holds, as many times as it comes.
///
//------------------------------------------------------------------------------
+ (void) addInventoryOfNumber:(NSString *)number
						count:(NSUInteger)count
						index:(LDrawRebrickableInventoryIndex *)index
				  multipliers:(NSMutableDictionary *)multipliers
						depth:(NSUInteger)depth
{
	NSString *inventoryID = [index latestInventoryIDForNumber:number];

	if (inventoryID == nil || depth > LDrawRebrickableMaximumNesting)
		return;

	multipliers[inventoryID] = @([multipliers[inventoryID] unsignedIntegerValue] + count);

	for (NSArray *child in [index childrenOfInventoryID:inventoryID])
	{
		[self addInventoryOfNumber:child[0]
							 count:count * [child[1] unsignedIntegerValue]
							 index:index
					   multipliers:multipliers
							 depth:depth + 1];
	}

}//end addInventoryOfNumber:count:index:multipliers:depth:


//---------- addPartNumber:colorID:quantity:isSpare:toItems: ---------[static]--
///
/// @abstract	Adds a part row to the items, which hold one item for each part
/// 			and color.
///
//------------------------------------------------------------------------------
+ (void) addPartNumber:(NSString *)partNumber
			   colorID:(NSInteger)colorID
			  quantity:(NSUInteger)quantity
			   isSpare:(BOOL)isSpare
			   toItems:(NSMutableDictionary<NSString *, LDrawInventoryItem *> *)items
{
	NSString			*key		= [NSString stringWithFormat:@"%@\n%ld", partNumber, (long)colorID];
	NSUInteger			 regular	= isSpare ? 0 : quantity;
	NSUInteger			 spares		= isSpare ? quantity : 0;
	LDrawInventoryItem	*item		= items[key];

	if (item == nil)
		item = [[LDrawInventoryItem alloc] initWithRebrickablePartNumber:partNumber
													  rebrickableColorID:colorID
														   ldrawPartName:nil
														  ldrawColorCode:LDrawColorBogus
																quantity:regular
														   spareQuantity:spares];
	else
		item = [item itemByAddingQuantity:regular spareQuantity:spares];

	items[key] = item;

}//end addPartNumber:colorID:quantity:isSpare:toItems:


//---------- sortedItems: --------------------------------------------[static]--
///
/// @abstract	By part number in natural order, then color.
///
//------------------------------------------------------------------------------
+ (NSArray<LDrawInventoryItem *> *) sortedItems:(NSArray<LDrawInventoryItem *> *)items
{
	return [items sortedArrayUsingComparator:^NSComparisonResult(LDrawInventoryItem *a, LDrawInventoryItem *b) {
		NSComparisonResult order = [a.rebrickablePartNumber localizedStandardCompare:b.rebrickablePartNumber];
		if (order != NSOrderedSame)
			return order;
		return [@(a.rebrickableColorID) compare:@(b.rebrickableColorID)];
	}];
}

@end
