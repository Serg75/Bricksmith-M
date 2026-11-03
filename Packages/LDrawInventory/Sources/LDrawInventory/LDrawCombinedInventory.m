//==============================================================================
//
//  File:       LDrawCombinedInventory.m
//  Package:    LDrawInventory
//
//  Purpose:    An inventory the user puts together: sets, each counted once or
//              more, plus loose parts.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawInventory/LDrawCombinedInventory.h>

#import <LDrawInventory/LDrawInventoryItem.h>
#import <LDrawInventory/LDrawSetInventory.h>

#import <LDrawInventory/LDrawInventoryJSON.h>

static NSString * const InventoryIdentifierKey	= @"identifier";
static NSString * const InventoryNameKey		= @"name";
static NSString * const InventorySetsKey		= @"sets";
static NSString * const InventoryLooseKey		= @"loose";


@implementation LDrawCombinedInventory


// MARK: - INITIALIZATION -


//========== initWithIdentifier:... ============================================
///
/// @abstract	Designated initializer.
///
//==============================================================================
- (instancetype) initWithIdentifier:(NSString *)identifier
							   name:(NSString *)name
						  setCounts:(NSDictionary<NSString *, NSNumber *> *)setCounts
						 looseItems:(NSArray<LDrawInventoryItem *> *)looseItems
{
	self = [super init];
	if (self) {
		self->_identifier	= [identifier copy];
		self->_name			= [name copy];
		self->_setCounts	= [setCounts copy];
		self->_looseItems	= [looseItems copy];
	}
	return self;

}//end initWithIdentifier:...


//---------- inventoryWithName: --------------------------------------[static]--
//------------------------------------------------------------------------------
+ (instancetype) inventoryWithName:(NSString *)name
{
	return [[self alloc] initWithIdentifier:[[NSUUID UUID] UUIDString]
									   name:name
								  setCounts:@{}
								 looseItems:@[]];
}


//---------- inventoryWithDictionary: --------------------------------[static]--
///
/// @abstract	An inventory read back from what the store wrote.
///
//------------------------------------------------------------------------------
+ (instancetype) inventoryWithDictionary:(NSDictionary<NSString *, id> *)dictionary
{
	NSString			*identifier	= nil;
	NSMutableDictionary	*setCounts	= [NSMutableDictionary dictionary];
	NSMutableArray		*looseItems	= [NSMutableArray array];
	NSDictionary		*sets		= nil;

	if (LDrawJSONDictionary(dictionary) == nil)
		return nil;

	identifier = LDrawJSONString(dictionary[InventoryIdentifierKey]);
	if (identifier == nil)
		return nil;

	sets = LDrawJSONDictionary(dictionary[InventorySetsKey]);
	for (id key in sets)
	{
		NSString	*setNumber	= [LDrawSetInventory normalizedSetNumber:LDrawJSONString(key)];
		NSInteger	 count		= LDrawJSONInteger(sets[key], 0);

		if (setNumber != nil && count > 0)
			setCounts[setNumber] = @(count);
	}

	for (id itemDictionary in LDrawJSONArray(dictionary[InventoryLooseKey]))
	{
		LDrawInventoryItem *item = [LDrawInventoryItem itemWithDictionary:itemDictionary];
		if (item != nil)
			[looseItems addObject:item];
	}

	return [[self alloc] initWithIdentifier:identifier
									   name:LDrawJSONString(dictionary[InventoryNameKey]) ?: @""
								  setCounts:setCounts
								 looseItems:looseItems];

}//end inventoryWithDictionary:


// MARK: - ACCESSORS -


//========== loosePartCount ====================================================
//==============================================================================
- (NSUInteger) loosePartCount
{
	NSUInteger count = 0;

	for (LDrawInventoryItem *item in self.looseItems)
		count += item.quantity + item.spareQuantity;
	return count;
}


//========== looseSpareCount ===================================================
//==============================================================================
- (NSUInteger) looseSpareCount
{
	NSUInteger count = 0;

	for (LDrawInventoryItem *item in self.looseItems)
		count += item.spareQuantity;
	return count;
}


// MARK: - DERIVED INVENTORIES -


//========== inventoryByRenamingTo: ============================================
//==============================================================================
- (LDrawCombinedInventory *) inventoryByRenamingTo:(NSString *)name
{
	NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	return [[LDrawCombinedInventory alloc] initWithIdentifier:self.identifier
														 name:([trimmed length] > 0) ? trimmed : self.name
													setCounts:self.setCounts
												   looseItems:self.looseItems];
}


//========== inventoryByReplacingSetCounts: ====================================
//==============================================================================
- (LDrawCombinedInventory *) inventoryByReplacingSetCounts:(NSDictionary<NSString *, NSNumber *> *)setCounts
{
	return [[LDrawCombinedInventory alloc] initWithIdentifier:self.identifier
														 name:self.name
													setCounts:setCounts
												   looseItems:self.looseItems];
}


//========== inventoryByReplacingLooseItems: ===================================
//==============================================================================
- (LDrawCombinedInventory *) inventoryByReplacingLooseItems:(NSArray<LDrawInventoryItem *> *)looseItems
{
	return [[LDrawCombinedInventory alloc] initWithIdentifier:self.identifier
														 name:self.name
													setCounts:self.setCounts
												   looseItems:looseItems];
}


//========== inventoryBySettingCount:forSetNumber: =============================
//==============================================================================
- (LDrawCombinedInventory *) inventoryBySettingCount:(NSInteger)count forSetNumber:(NSString *)setNumber
{
	NSMutableDictionary *counts = [self.setCounts mutableCopy];

	if (count > 0)
		counts[setNumber] = @(count);
	else
		[counts removeObjectForKey:setNumber];
	return [self inventoryByReplacingSetCounts:counts];
}


//========== inventoryByAddingLooseItems: ======================================
//==============================================================================
- (LDrawCombinedInventory *) inventoryByAddingLooseItems:(NSArray<LDrawInventoryItem *> *)items
{
	NSMutableArray		*merged		= [NSMutableArray array];
	NSMutableDictionary	*indexes	= [NSMutableDictionary dictionary];	// part and color → index in merged

	for (LDrawInventoryItem *item in [self.looseItems arrayByAddingObjectsFromArray:items])
	{
		NSString	*key	= [LDrawCombinedInventory keyForItem:item];
		NSNumber	*index	= indexes[key];

		if (index == nil)
		{
			indexes[key] = @([merged count]);
			[merged addObject:item];
		}
		else
		{
			NSUInteger at = [index unsignedIntegerValue];
			merged[at] = [merged[at] itemByAddingQuantity:item.quantity spareQuantity:item.spareQuantity];
		}
	}
	return [self inventoryByReplacingLooseItems:merged];

}//end inventoryByAddingLooseItems:


// MARK: - ARCHIVING -


//========== dictionaryRepresentation ==========================================
//==============================================================================
- (NSDictionary<NSString *, id> *) dictionaryRepresentation
{
	return @{
		InventoryIdentifierKey	: self.identifier,
		InventoryNameKey		: self.name,
		InventorySetsKey		: self.setCounts,
		InventoryLooseKey		: [self.looseItems valueForKey:@"dictionaryRepresentation"],
	};
}


// MARK: - NSObject -


//========== description =======================================================
//==============================================================================
- (NSString *) description
{
	return [NSString stringWithFormat:@"<%@ \"%@\" sets %@, %lu loose>",
			[self class], self.name, self.setCounts, (unsigned long)[self.looseItems count]];
}


// MARK: - UTILITIES -


//---------- keyForItem: ---------------------------------------------[static]--
///
/// @abstract	An item's part and color: its LDraw ones when it has an LDraw
/// 			part, else its Rebrickable ones.
///
//------------------------------------------------------------------------------
+ (NSString *) keyForItem:(LDrawInventoryItem *)item
{
	if (item.ldrawPartName != nil)
		return [NSString stringWithFormat:@"L\n%@\n%ld", item.ldrawPartName, (long)item.ldrawColorCode];
	return [NSString stringWithFormat:@"R\n%@\n%ld", item.rebrickablePartNumber ?: @"",
			(long)item.rebrickableColorID];
}

@end
