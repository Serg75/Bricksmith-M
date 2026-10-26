//==============================================================================
//
//  File:       LDrawRebrickableCatalog.m
//  Package:    LDrawRebrickable
//
//  Purpose:    What Rebrickable's downloads tell about every part: when it
//              came in which colors, how parts relate, and which parts exist.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawRebrickable/LDrawRebrickableCatalog.h>

#import <LDrawInventory/LDrawInventoryStore.h>
#import <LDrawInventory/LDrawPartAvailability.h>
#import <LDrawInventory/LDrawPartIdentity.h>
#import <LDrawRebrickable/LDrawRebrickableCSVReader.h>
#import <LDrawRebrickable/LDrawRebrickableDownloads.h>
#import <LDrawRebrickable/LDrawRebrickableSetList.h>

#import "LDrawRebrickableInventoryIndex.h"

/// Sets inside sets go only a few levels deep; a loop must not hang.
static const NSUInteger MaximumNesting = 6;


@interface LDrawRebrickableCatalog ()

@property (nonatomic, readwrite) LDrawPartAvailability *availability;
@property (nonatomic, readwrite, copy) NSArray<NSArray<NSString *> *> *relations;
@property (nonatomic, readwrite, copy) NSSet<NSString *> *knownPartNumbers;
@property (nonatomic, readwrite) LDrawRebrickableSetList *setList;

@end


@implementation LDrawRebrickableCatalog


//---------- catalogFromDownloads:error: -----------------------------[static]--
///
/// @abstract	Reads the set list, the inventories, every part row, the part
/// 			relations and the part list.
///
//------------------------------------------------------------------------------
+ (instancetype) catalogFromDownloads:(LDrawRebrickableDownloads *)downloads error:(NSError **)error
{
	LDrawRebrickableCatalog			*catalog	= [[self alloc] init];
	LDrawRebrickableInventoryIndex	*index		= nil;
	LDrawPartAvailabilityBuilder	*builder	= [[LDrawPartAvailabilityBuilder alloc] init];
	NSMutableDictionary				*owners		= [NSMutableDictionary dictionary];	// number → sets that hold it
	NSMutableSet					*seen		= [NSMutableSet set];
	__block NSString				*lastID		= nil;

	catalog.setList = [LDrawRebrickableSetList setListFromDownloads:downloads error:error];
	if (catalog.setList == nil)
		return nil;

	index = [LDrawRebrickableInventoryIndex indexFromDownloads:downloads error:error];
	if (index == nil)
		return nil;

	// A part counts once for each set that holds it, directly or in a
	// minifigure or a set inside it. The file lists an inventory's rows
	// together, so remembering one inventory's parts is enough to skip a part
	// listed twice there, as a spare and not.
	BOOL didRead = [index enumeratePartsUsingBlock:^(NSString *inventoryID, NSString *partNumber, NSInteger colorID,
													 NSUInteger quantity, BOOL isSpare, BOOL *stop) {
		NSString *number = [index numberOfLatestInventoryID:inventoryID];

		if (number == nil || colorID < 0)
			return;

		if ([inventoryID isEqualToString:lastID] == NO)
		{
			[seen removeAllObjects];
			lastID = inventoryID;
		}

		NSString *key = [NSString stringWithFormat:@"%@\n%ld", partNumber, (long)colorID];
		if ([seen containsObject:key])
			return;
		[seen addObject:key];

		for (LDrawRebrickableSet *set in [catalog setsHoldingNumber:number index:index cache:owners depth:0])
		{
			[builder notePartNumber:partNumber colorID:colorID year:set.year inDatabaseSet:set.isDatabaseSet];
		}
	} error:error];

	if (didRead == NO)
		return nil;

	catalog.availability = [builder availabilityWithDate:[downloads dataDateForFileNamed:@"inventory_parts"]
														 ?: [NSDate date]];

	if ([catalog readRelationsFromDownloads:downloads error:error] == NO)
		return nil;
	if ([catalog readKnownPartsFromDownloads:downloads error:error] == NO)
		return nil;

	return catalog;

}//end catalogFromDownloads:error:


//========== setsHoldingNumber:index:cache:depth: ==============================
///
/// @abstract	The sets a set or minifigure is in: itself when it is a set,
/// 			and every set whose inventory holds it, all the way up.
///
//==============================================================================
- (NSArray<LDrawRebrickableSet *> *) setsHoldingNumber:(NSString *)number
												 index:(LDrawRebrickableInventoryIndex *)index
												 cache:(NSMutableDictionary *)cache
												 depth:(NSUInteger)depth
{
	NSMutableArray		*sets	= nil;
	LDrawRebrickableSet	*own	= nil;

	if (cache[number] != nil)
		return cache[number];

	sets	= [NSMutableArray array];
	own		= [self.setList setForNumber:number];
	if (own != nil)
		[sets addObject:own];

	if (depth < MaximumNesting)
	{
		for (NSArray *parent in [index parentsOfNumber:number])
		{
			NSString *parentNumber = [index numberOfLatestInventoryID:parent[0]];

			if (parentNumber != nil && [parentNumber isEqualToString:number] == NO)
			{
				NSArray *holders = [self setsHoldingNumber:parentNumber index:index cache:cache depth:depth + 1];

				for (LDrawRebrickableSet *set in holders)
				{
					if ([sets containsObject:set] == NO)
						[sets addObject:set];
				}
			}
		}
	}

	cache[number] = sets;
	return sets;

}//end setsHoldingNumber:index:cache:depth:


//========== readRelationsFromDownloads:error: =================================
//==============================================================================
- (BOOL) readRelationsFromDownloads:(LDrawRebrickableDownloads *)downloads error:(NSError **)error
{
	NSURL						*url		= [downloads localURLForFileNamed:@"part_relationships"];
	LDrawRebrickableCSVReader	*reader		= [[LDrawRebrickableCSVReader alloc] initWithURL:url error:error];
	NSArray						*columns	= [reader indexesOfColumns:@[@"rel_type", @"child_part_num",
																		 @"parent_part_num"]
															   error:error];
	NSUInteger					 last		= [LDrawRebrickableCSVReader lastIndexOfColumns:columns];
	NSMutableArray				*relations	= [NSMutableArray array];

	if (columns == nil)
		return NO;

	if ([reader enumerateRowsUsingBlock:^(NSArray<NSString *> *fields, BOOL *stop) {
			if ([fields count] > last)
			{
				[relations addObject:@[fields[[columns[0] unsignedIntegerValue]],
									   fields[[columns[1] unsignedIntegerValue]],
									   fields[[columns[2] unsignedIntegerValue]]]];
			}
		} error:error] == NO)
		return NO;

	self.relations = relations;
	return YES;

}//end readRelationsFromDownloads:error:


//========== readKnownPartsFromDownloads:error: ================================
//==============================================================================
- (BOOL) readKnownPartsFromDownloads:(LDrawRebrickableDownloads *)downloads error:(NSError **)error
{
	NSURL						*url	= [downloads localURLForFileNamed:@"parts"];
	LDrawRebrickableCSVReader	*reader	= [[LDrawRebrickableCSVReader alloc] initWithURL:url error:error];
	NSUInteger					 column	= [[[reader indexesOfColumns:@[@"part_num"] error:error] firstObject]
										   unsignedIntegerValue];
	NSMutableSet				*known	= [NSMutableSet set];

	if (reader == nil || [reader indexOfColumn:@"part_num"] == NSNotFound)
		return NO;

	if ([reader enumerateRowsUsingBlock:^(NSArray<NSString *> *fields, BOOL *stop) {
			if ([fields count] > column && [fields[column] length] > 0)
				[known addObject:fields[column]];
		} error:error] == NO)
		return NO;

	self.knownPartNumbers = known;
	return YES;

}//end readKnownPartsFromDownloads:error:


// MARK: - SAVING -


//========== saveIntoStore:colorLinks:error: ===================================
///
/// @abstract	Saves the catalog and the identity data. The part links the
/// 			store has came from set fetches, so they stay.
///
//==============================================================================
- (BOOL) saveIntoStore:(LDrawInventoryStore *)store
			colorLinks:(NSDictionary<NSNumber *, id> *)colorLinks
				 error:(NSError **)error
{
	NSDictionary *data = [LDrawPartIdentity rebrickableDataByUpdating:[store rebrickableIdentityData]
															partLinks:nil
														   colorLinks:colorLinks
															relations:self.relations
													 knownPartNumbers:self.knownPartNumbers];

	return	[store saveAvailability:self.availability error:error]
		&&	[store saveRebrickableIdentityData:data error:error];

}//end saveIntoStore:colorLinks:error:

@end
