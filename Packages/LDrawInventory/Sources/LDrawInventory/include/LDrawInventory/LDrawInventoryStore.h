//==============================================================================
//
//  File:       LDrawInventoryStore.h
//  Package:    LDrawInventory
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawCombinedInventory;
@class LDrawInventoryItem;
@class LDrawPartAvailability;
@class LDrawPartIdentity;
@class LDrawPartLimit;
@class LDrawPartLimitTable;
@class LDrawSetInventory;

NS_ASSUME_NONNULL_BEGIN

/// Something in the store was saved or removed. Object is the store. No
/// userInfo.
extern NSString * const LDrawInventoryStoreDidChangeNotification;


//------------------------------------------------------------------------------
///
/// @class      LDrawInventoryStore
///
/// @abstract   The imported sets, the user's inventories, the catalog and the
///             identity data, kept as JSON files in one folder.
///
/// @discussion The host names the folder. Each file has a version, and a
///             reader skips what it does not know:
///
///             - `inventories.json`: the combined inventories.
///             - `sets/<set number>.json`: one imported set each.
///             - `catalog.json`: the availability catalog.
///             - `identity.json`: what Rebrickable tells about parts and colors.
///             - `identity-overrides.json`: matches the user made by hand.
///
///             Read and written on one thread. What is read is kept in memory,
///             and a save changes the file and the memory together.
///
//------------------------------------------------------------------------------
@interface LDrawInventoryStore : NSObject

@property (nonatomic, readonly, copy) NSURL *folderURL;

- (instancetype) initWithFolderURL:(NSURL *)folderURL NS_DESIGNATED_INITIALIZER;
- (instancetype) init NS_UNAVAILABLE;


// MARK: - Combined inventories

/// Sorted by name.
- (NSArray<LDrawCombinedInventory *> *) combinedInventories;
- (nullable LDrawCombinedInventory *) combinedInventoryWithIdentifier:(NSString *)identifier;

/// Adds the inventory, or replaces the one with its identifier.
- (BOOL) saveCombinedInventory:(LDrawCombinedInventory *)inventory error:(NSError **)error
	NS_SWIFT_NAME(saveCombinedInventory(_:));
- (BOOL) removeCombinedInventoryWithIdentifier:(NSString *)identifier error:(NSError **)error
	NS_SWIFT_NAME(removeCombinedInventory(withIdentifier:));


// MARK: - Sets

/// Sorted.
- (NSArray<NSString *> *) setNumbers;
- (nullable LDrawSetInventory *) setInventoryForNumber:(NSString *)setNumber
	NS_SWIFT_NAME(setInventory(forNumber:));

/// Adds the set, or replaces the one with its number.
- (BOOL) saveSetInventory:(LDrawSetInventory *)setInventory error:(NSError **)error
	NS_SWIFT_NAME(saveSetInventory(_:));
- (BOOL) removeSetInventoryForNumber:(NSString *)setNumber error:(NSError **)error
	NS_SWIFT_NAME(removeSetInventory(forNumber:));


// MARK: - What a limit reads

/// Every item of a combined inventory, its sets counted as many times as it
/// says, or of one set. Sets the store does not have are left out. Nil when
/// the identifier names neither.
- (nullable NSArray<LDrawInventoryItem *> *) itemsForInventoryIdentifier:(NSString *)identifier;

/// The limit, or no limit when it names an inventory the store does not
/// have. The options stay as they were.
- (LDrawPartLimit *) resolvedLimit:(LDrawPartLimit *)limit;

/// The table for a limit, from what the store has.
- (LDrawPartLimitTable *) tableForLimit:(LDrawPartLimit *)limit
							   identity:(LDrawPartIdentity *)identity
								   year:(NSInteger)currentYear
	NS_SWIFT_NAME(table(for:identity:year:));


// MARK: - Catalog and identity

/// Nil until a catalog is saved.
- (nullable LDrawPartAvailability *) availability;
- (BOOL) saveAvailability:(LDrawPartAvailability *)availability error:(NSError **)error
	NS_SWIFT_NAME(saveAvailability(_:));

/// What `+[LDrawPartIdentity rebrickableDataWithPartLinks:...]` made, or nil.
- (nullable NSDictionary *) rebrickableIdentityData;
- (BOOL) saveRebrickableIdentityData:(NSDictionary *)data error:(NSError **)error
	NS_SWIFT_NAME(saveRebrickableIdentityData(_:));

/// LDraw part name → Rebrickable number.
- (NSDictionary<NSString *, NSString *> *) identityOverrides;
- (BOOL) saveIdentityOverrides:(NSDictionary<NSString *, NSString *> *)overrides error:(NSError **)error
	NS_SWIFT_NAME(saveIdentityOverrides(_:));

/// The identity map from the store's data and the part library's records.
- (LDrawPartIdentity *) identityWithCatalogRecords:(nullable NSArray<NSDictionary *> *)catalogRecords;

@end

NS_ASSUME_NONNULL_END
