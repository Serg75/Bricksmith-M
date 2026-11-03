//==============================================================================
//
//  File:       LDrawRebrickableInventoryIndex.m
//  Package:    LDrawRebrickable
//
//  Purpose:    How Rebrickable's inventory files hang together.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import "LDrawRebrickableInventoryIndex.h"

#import <LDrawInventory/LDrawInventoryJSON.h>
#import <LDrawInventory/LDrawSetInventory.h>
#import <LDrawRebrickable/LDrawRebrickableCSVReader.h>
#import <LDrawRebrickable/LDrawRebrickableDownloads.h>


@implementation LDrawRebrickableInventoryIndex
{
	LDrawRebrickableDownloads									*downloads;
	NSMutableDictionary<NSString *, NSString *>					*latestByNumber;	// number → inventory id
	NSMutableDictionary<NSString *, NSString *>					*numberByLatest;	// inventory id → number
	NSMutableDictionary<NSString *, NSMutableArray<NSArray *> *>	*children;		// inventory id → [number, count]
	NSMutableDictionary<NSString *, NSMutableArray<NSString *> *>	*parents;		// number → inventory ids
}


// MARK: - INITIALIZATION -


//---------- indexFromDownloads:error: -------------------------------[static]--
//------------------------------------------------------------------------------
+ (instancetype) indexFromDownloads:(LDrawRebrickableDownloads *)downloads error:(NSError **)error
{
	LDrawRebrickableInventoryIndex *index = [[self alloc] init];

	index->downloads		= downloads;
	index->latestByNumber	= [NSMutableDictionary dictionary];
	index->numberByLatest	= [NSMutableDictionary dictionary];
	index->children			= [NSMutableDictionary dictionary];
	index->parents			= [NSMutableDictionary dictionary];

	if (	[index readInventoriesWithError:error] == NO
		||	[index readChildrenFromFileNamed:@"inventory_sets" numberColumn:@"set_num" error:error] == NO
		||	[index readChildrenFromFileNamed:@"inventory_minifigs" numberColumn:@"fig_num" error:error] == NO )
	{
		return nil;
	}
	return index;

}//end indexFromDownloads:error:


// MARK: - LOOKUPS -


//========== latestInventoryIDForNumber: =======================================
//==============================================================================
- (NSString *) latestInventoryIDForNumber:(NSString *)number
{
	return self->latestByNumber[number];
}


//========== numberOfLatestInventoryID: ========================================
//==============================================================================
- (NSString *) numberOfLatestInventoryID:(NSString *)inventoryID
{
	return self->numberByLatest[inventoryID];
}


//========== childrenOfInventoryID: ============================================
//==============================================================================
- (NSArray<NSArray *> *) childrenOfInventoryID:(NSString *)inventoryID
{
	return self->children[inventoryID] ?: @[];
}


//========== parentInventoryIDsOfNumber: =======================================
//==============================================================================
- (NSArray<NSString *> *) parentInventoryIDsOfNumber:(NSString *)number
{
	return self->parents[number] ?: @[];
}


// MARK: - PARTS -


//========== enumeratePartsUsingBlock:error: ===================================
///
/// @abstract	Reads every part row. Over a million of them; the block should
/// 			be quick.
///
//==============================================================================
- (BOOL) enumeratePartsUsingBlock:(NS_NOESCAPE LDrawRebrickablePartRowBlock)block error:(NSError **)error
{
	NSURL						*url		= [self->downloads localURLForFileNamed:@"inventory_parts"];
	LDrawRebrickableCSVReader	*reader		= [[LDrawRebrickableCSVReader alloc] initWithURL:url error:error];
	NSArray						*columns	= [reader indexesOfColumns:@[@"inventory_id", @"part_num", @"color_id",
																		 @"quantity", @"is_spare"]
																 error:error];
	NSUInteger					 last		= [LDrawRebrickableCSVReader lastIndexOfColumns:columns];
	NSUInteger					 inventory	= [columns[0] unsignedIntegerValue];
	NSUInteger					 part		= [columns[1] unsignedIntegerValue];
	NSUInteger					 color		= [columns[2] unsignedIntegerValue];
	NSUInteger					 quantity	= [columns[3] unsignedIntegerValue];
	NSUInteger					 spare		= [columns[4] unsignedIntegerValue];

	if (columns == nil)
		return NO;

	return [reader enumerateRowsUsingBlock:^(NSArray<NSString *> *fields, BOOL *stop) {
		if ([fields count] <= last)
			return;

		NSInteger	 count		= LDrawJSONInteger(fields[quantity], 0);
		NSString	*flag		= fields[spare];
		BOOL		 isSpare	= (	[flag caseInsensitiveCompare:@"t"] == NSOrderedSame
								||	[flag caseInsensitiveCompare:@"true"] == NSOrderedSame
								||	[flag isEqualToString:@"1"] );

		if (count <= 0)
			return;

		block(fields[inventory], fields[part], LDrawJSONInteger(fields[color], -1), (NSUInteger)count, isSpare, stop);
	} error:error];

}//end enumeratePartsUsingBlock:error:


// MARK: - UTILITIES -


//========== readInventoriesWithError: =========================================
///
/// @abstract	Keeps each number's newest version. Versions do not always
/// 			start at 1, so the highest wins, not the first.
///
//==============================================================================
- (BOOL) readInventoriesWithError:(NSError **)error
{
	NSURL						*url		= [self->downloads localURLForFileNamed:@"inventories"];
	LDrawRebrickableCSVReader	*reader		= [[LDrawRebrickableCSVReader alloc] initWithURL:url error:error];
	NSArray						*columns	= [reader indexesOfColumns:@[@"id", @"version", @"set_num"] error:error];
	NSUInteger					 last		= [LDrawRebrickableCSVReader lastIndexOfColumns:columns];
	NSMutableDictionary			*versions	= [NSMutableDictionary dictionary];

	if (columns == nil)
		return NO;

	if ([reader enumerateRowsUsingBlock:^(NSArray<NSString *> *fields, BOOL *stop) {
			if ([fields count] <= last)
				return;

			NSString	*inventoryID	= fields[[columns[0] unsignedIntegerValue]];
			NSInteger	 version		= LDrawJSONInteger(fields[[columns[1] unsignedIntegerValue]], 0);
			NSString	*setNumber		= fields[[columns[2] unsignedIntegerValue]];
			NSString	*number			= [LDrawSetInventory normalizedSetNumber:setNumber];

			if (number == nil)
				return;
			if (versions[number] == nil || [versions[number] integerValue] < version)
			{
				versions[number]				= @(version);
				self->latestByNumber[number]	= inventoryID;
			}
		} error:error] == NO)
		return NO;

	for (NSString *number in self->latestByNumber)
		self->numberByLatest[self->latestByNumber[number]] = number;

	return YES;

}//end readInventoriesWithError:


//========== readChildrenFromFileNamed:numberColumn:error: =====================
//==============================================================================
- (BOOL) readChildrenFromFileNamed:(NSString *)name numberColumn:(NSString *)numberColumn error:(NSError **)error
{
	NSURL						*url		= [self->downloads localURLForFileNamed:name];
	LDrawRebrickableCSVReader	*reader		= [[LDrawRebrickableCSVReader alloc] initWithURL:url error:error];
	NSArray						*columns	= [reader indexesOfColumns:@[@"inventory_id", numberColumn, @"quantity"]
																 error:error];
	NSUInteger					 last		= [LDrawRebrickableCSVReader lastIndexOfColumns:columns];

	if (columns == nil)
		return NO;

	return [reader enumerateRowsUsingBlock:^(NSArray<NSString *> *fields, BOOL *stop) {
		if ([fields count] <= last)
			return;

		NSString	*inventoryID	= fields[[columns[0] unsignedIntegerValue]];
		NSString	*number			= [LDrawSetInventory normalizedSetNumber:fields[[columns[1] unsignedIntegerValue]]];
		NSInteger	 count			= LDrawJSONInteger(fields[[columns[2] unsignedIntegerValue]], 0);

		if (number == nil || count <= 0)
			return;

		if (self->children[inventoryID] == nil)
			self->children[inventoryID] = [NSMutableArray array];
		[self->children[inventoryID] addObject:@[number, @(count)]];

		if (self->parents[number] == nil)
			self->parents[number] = [NSMutableArray array];
		[self->parents[number] addObject:inventoryID];
	} error:error];

}//end readChildrenFromFileNamed:numberColumn:error:

@end
