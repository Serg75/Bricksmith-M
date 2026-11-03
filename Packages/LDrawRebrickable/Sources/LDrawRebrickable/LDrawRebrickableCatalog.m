//==============================================================================
//
//  File:       LDrawRebrickableCatalog.m
//  Package:    LDrawRebrickable
//
//  Purpose:    What Rebrickable's downloads tell about every part: when it
//              came in which colors, how parts relate, which parts exist and
//              which are rubber.
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

/// The `part_material` of rubber parts.
static NSString * const RubberMaterial = @"Rubber";


@interface LDrawRebrickableCatalog ()

@property (nonatomic, readwrite) LDrawPartAvailability *availability;
@property (nonatomic, readwrite, copy) NSArray<NSArray<NSString *> *> *relations;
@property (nonatomic, readwrite, copy) NSSet<NSString *> *knownPartNumbers;
@property (nonatomic, readwrite, copy) NSSet<NSString *> *rubberPartNumbers;
@property (nonatomic, readwrite) LDrawRebrickableSetList *setList;

@end


@implementation LDrawRebrickableCatalog


// MARK: - READING -


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
	NSSet							*known		= nil;
	NSSet							*rubber		= nil;

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

	NSDate *dataDate = [downloads dataDateForFileNamed:@"inventory_parts"] ?: [NSDate date];
	catalog.availability = [builder availabilityWithDate:dataDate];

	if ([catalog readRelationsFromDownloads:downloads error:error] == NO)
		return nil;
	if ([self readPartsFromDownloads:downloads known:&known rubber:&rubber error:error] == NO)
		return nil;
	catalog.knownPartNumbers	= known;
	catalog.rubberPartNumbers	= rubber;

	return catalog;

}//end catalogFromDownloads:error:


//---------- rubberPartNumbersFromDownloads:error: -------------------[static]--
//------------------------------------------------------------------------------
+ (NSSet<NSString *> *) rubberPartNumbersFromDownloads:(LDrawRebrickableDownloads *)downloads
												 error:(NSError **)error
{
	NSSet *rubber = nil;

	if ([self readPartsFromDownloads:downloads known:NULL rubber:&rubber error:error] == NO)
		return nil;
	return rubber;
}


// MARK: - SAVING -


//========== saveIntoStore:colorLinks:error: ===================================
///
/// @abstract	Saves the catalog and the identity data in one change.
///
//==============================================================================
- (BOOL) saveIntoStore:(LDrawInventoryStore *)store
			colorLinks:(NSDictionary<NSNumber *, id> *)colorLinks
				 error:(NSError **)error
{
	NSDictionary	*data	= [LDrawPartIdentity rebrickableDataByUpdating:[store rebrickableIdentityData]
																 partLinks:nil
																colorLinks:colorLinks
																 relations:self.relations
														  knownPartNumbers:self.knownPartNumbers
														 rubberPartNumbers:self.rubberPartNumbers];
	__block BOOL	 saved	= NO;

	[store performChanges:^{
		saved =		[store saveAvailability:self.availability error:error]
				&&	[store saveRebrickableIdentityData:data error:error];
	}];
	return saved;

}//end saveIntoStore:colorLinks:error:


// MARK: - UTILITIES -


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

	if (depth < LDrawRebrickableMaximumNesting)
	{
		for (NSString *parentID in [index parentInventoryIDsOfNumber:number])
		{
			NSString *parentNumber = [index numberOfLatestInventoryID:parentID];

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


//---------- readPartsFromDownloads:known:rubber:error: --------------[static]--
///
/// @abstract	Reads every part number in the part list, and those made of
/// 			rubber.
///
//------------------------------------------------------------------------------
+ (BOOL) readPartsFromDownloads:(LDrawRebrickableDownloads *)downloads
						  known:(NSSet **)knownOut
						 rubber:(NSSet **)rubberOut
						  error:(NSError **)error
{
	NSURL						*url		= [downloads localURLForFileNamed:@"parts"];
	LDrawRebrickableCSVReader	*reader		= [[LDrawRebrickableCSVReader alloc] initWithURL:url error:error];
	NSArray						*columns	= [reader indexesOfColumns:@[@"part_num"] error:error];
	NSUInteger					 column		= [[columns firstObject] unsignedIntegerValue];
	NSUInteger					 material	= [reader indexOfColumn:@"part_material"];
	NSMutableSet				*known		= [NSMutableSet set];
	NSMutableSet				*rubber		= [NSMutableSet set];

	if (columns == nil)
		return NO;

	if ([reader enumerateRowsUsingBlock:^(NSArray<NSString *> *fields, BOOL *stop) {
			if ([fields count] <= column || [fields[column] length] == 0)
				return;
			[known addObject:fields[column]];
			if (material < [fields count] && [fields[material] isEqualToString:RubberMaterial])
				[rubber addObject:fields[column]];
		} error:error] == NO)
		return NO;

	if (knownOut != NULL)
		*knownOut = known;
	if (rubberOut != NULL)
		*rubberOut = rubber;
	return YES;

}//end readPartsFromDownloads:known:rubber:error:

@end
