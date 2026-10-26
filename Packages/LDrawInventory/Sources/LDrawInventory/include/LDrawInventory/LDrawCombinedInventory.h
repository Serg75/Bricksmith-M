//==============================================================================
//
//  File:       LDrawCombinedInventory.h
//  Package:    LDrawInventory
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawInventoryItem;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawCombinedInventory
///
/// @abstract   An inventory the user puts together: sets, each counted once or
///             more, plus loose parts.
///
/// @discussion Immutable. It names its sets by number; their parts are in the
///             store, so a set fetched again changes every inventory that
///             holds it.
///
//------------------------------------------------------------------------------
@interface LDrawCombinedInventory : NSObject

/// A UUID string, which does not change when the inventory is renamed.
@property (nonatomic, readonly, copy) NSString *identifier;

@property (nonatomic, readonly, copy) NSString *name;

/// How many of each set, by set number.
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSNumber *> *setCounts;

@property (nonatomic, readonly, copy) NSArray<LDrawInventoryItem *> *looseItems;

- (instancetype) initWithIdentifier:(NSString *)identifier
							   name:(NSString *)name
						  setCounts:(NSDictionary<NSString *, NSNumber *> *)setCounts
						 looseItems:(NSArray<LDrawInventoryItem *> *)looseItems NS_DESIGNATED_INITIALIZER;

- (instancetype) init NS_UNAVAILABLE;

/// A new, empty inventory with a new identifier.
+ (instancetype) inventoryWithName:(NSString *)name NS_SWIFT_NAME(init(name:));

/// The same inventory with another name or other contents.
- (LDrawCombinedInventory *) inventoryByRenamingTo:(NSString *)name NS_SWIFT_NAME(renamed(to:));
- (LDrawCombinedInventory *) inventoryByReplacingSetCounts:(NSDictionary<NSString *, NSNumber *> *)setCounts
	NS_SWIFT_NAME(replacingSetCounts(_:));
- (LDrawCombinedInventory *) inventoryByReplacingLooseItems:(NSArray<LDrawInventoryItem *> *)looseItems
	NS_SWIFT_NAME(replacingLooseItems(_:));

/// What the store writes.
- (NSDictionary<NSString *, id> *) dictionaryRepresentation;

/// Nil when the dictionary has no identifier. Set counts below one, and loose
/// items that do not read, are skipped.
+ (nullable instancetype) inventoryWithDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;

@end

NS_ASSUME_NONNULL_END
