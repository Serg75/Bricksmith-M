//==============================================================================
//
//  File:       LDrawRebrickableInventoryIndex.h
//  Package:    LDrawRebrickable
//
//  Purpose:    How Rebrickable's inventory files hang together: which
//              inventory is a set's latest, and which sets and minifigures an
//              inventory holds. Shared by the catalog and the set import.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawRebrickableDownloads;

NS_ASSUME_NONNULL_BEGIN

/// One row of `inventory_parts`.
typedef void (^LDrawRebrickablePartRowBlock)(NSString *inventoryID, NSString *partNumber, NSInteger colorID,
											 NSUInteger quantity, BOOL isSpare, BOOL *stop);

@interface LDrawRebrickableInventoryIndex : NSObject

/// Reads `inventories`, `inventory_sets` and `inventory_minifigs`.
+ (nullable instancetype) indexFromDownloads:(LDrawRebrickableDownloads *)downloads error:(NSError **)error;

/// The id of the newest version of a set's or minifigure's inventory.
- (nullable NSString *) latestInventoryIDForNumber:(NSString *)number;

/// The set or minifigure number of an inventory, when it is the newest one.
- (nullable NSString *) numberOfLatestInventoryID:(NSString *)inventoryID;

/// The sets and minifigures an inventory holds, as rows of number and count.
- (NSArray<NSArray *> *) childrenOfInventoryID:(NSString *)inventoryID;

/// The inventories whose children include this set or minifigure, as rows of
/// inventory id and count.
- (NSArray<NSArray *> *) parentsOfNumber:(NSString *)number;

/// Reads `inventory_parts` a row at a time.
- (BOOL) enumeratePartsUsingBlock:(NS_NOESCAPE LDrawRebrickablePartRowBlock)block error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
