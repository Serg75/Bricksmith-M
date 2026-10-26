//==============================================================================
//
//  File:       LDrawInventoryItem.h
//  Package:    LDrawInventory
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawColor.h>

NS_ASSUME_NONNULL_BEGIN

/// Rebrickable's color for "any color", used for parts that come in no
/// particular color.
extern const NSInteger LDrawRebrickableColorAny;

/// Rebrickable's color for "unknown".
extern const NSInteger LDrawRebrickableColorUnknown;

/// No Rebrickable color is given. Not a Rebrickable value.
extern const NSInteger LDrawRebrickableColorNone;


//------------------------------------------------------------------------------
///
/// @class      LDrawInventoryItem
///
/// @abstract   One part in one color, and how many of it an inventory holds.
///
/// @discussion Immutable. An item keeps the ids its source gave: Rebrickable's
///             part and color for a set, LDraw's for a loose part typed in
///             LDraw terms, or both when Rebrickable named the LDraw part
///             itself. The limit table matches the rest through the identity
///             map, so a better map can match an item again later.
///
//------------------------------------------------------------------------------
@interface LDrawInventoryItem : NSObject <NSCopying>

/// Rebrickable's part number, e.g. "3001" or "3626cpr1234". Nil for a part
/// given only in LDraw terms.
@property (nonatomic, readonly, copy, nullable) NSString *rebrickablePartNumber;

/// Rebrickable's color id, or `LDrawRebrickableColorNone`.
@property (nonatomic, readonly) NSInteger rebrickableColorID;

/// The LDraw part the source named, e.g. "3001.dat", or nil.
@property (nonatomic, readonly, copy, nullable) NSString *ldrawPartName;

/// The LDraw color the source named, or `LDrawColorBogus`.
@property (nonatomic, readonly) LDrawColorT ldrawColorCode;

/// How many the inventory holds, spares not included.
@property (nonatomic, readonly) NSUInteger quantity;

/// How many spares come on top of `quantity`.
@property (nonatomic, readonly) NSUInteger spareQuantity;

- (instancetype) initWithRebrickablePartNumber:(nullable NSString *)partNumber
							rebrickableColorID:(NSInteger)colorID
								 ldrawPartName:(nullable NSString *)ldrawPartName
								ldrawColorCode:(LDrawColorT)ldrawColorCode
									  quantity:(NSUInteger)quantity
								 spareQuantity:(NSUInteger)spareQuantity NS_DESIGNATED_INITIALIZER;

- (instancetype) init NS_UNAVAILABLE;

/// The same part and color with these counts added.
- (LDrawInventoryItem *) itemByAddingQuantity:(NSUInteger)quantity
								spareQuantity:(NSUInteger)spareQuantity
	NS_SWIFT_NAME(adding(quantity:spareQuantity:));

/// The same part and color with its counts multiplied, for a set counted more
/// than once.
- (LDrawInventoryItem *) itemMultipliedBy:(NSUInteger)factor NS_SWIFT_NAME(multiplied(by:));

/// What the store writes.
- (NSDictionary<NSString *, id> *) dictionaryRepresentation;

/// Nil when the dictionary names no part, or holds nothing.
+ (nullable instancetype) itemWithDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;

@end

NS_ASSUME_NONNULL_END
