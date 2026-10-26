//==============================================================================
//
//  File:       LDrawSetInventory.h
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
/// @class      LDrawSetInventory
///
/// @abstract   The parts of one LEGO set, as an import fetched them.
///
/// @discussion Immutable. The items hold the parts of the set's minifigures
///             too, and its spares, each part and color once.
///
//------------------------------------------------------------------------------
@interface LDrawSetInventory : NSObject

/// Rebrickable's set number, e.g. "42115-1".
@property (nonatomic, readonly, copy) NSString *setNumber;

@property (nonatomic, readonly, copy) NSString *name;

/// The year the set came out, or 0 when it is not known.
@property (nonatomic, readonly) NSInteger year;

@property (nonatomic, readonly, copy, nullable) NSString *themeName;

/// Where a picture of the set is, as the source gave it.
@property (nonatomic, readonly, copy, nullable) NSString *imageURL;

@property (nonatomic, readonly, copy) NSArray<LDrawInventoryItem *> *items;

/// When the parts were fetched, or nil when it is not known.
@property (nonatomic, readonly, copy, nullable) NSDate *fetchDate;

/// What the parts were fetched from, e.g. "rebrickable-downloads" or
/// "rebrickable-api".
@property (nonatomic, readonly, copy, nullable) NSString *source;

/// The parts of the set, spares not included.
@property (nonatomic, readonly) NSUInteger partCount;

/// The spares that come on top.
@property (nonatomic, readonly) NSUInteger spareCount;

- (instancetype) initWithSetNumber:(NSString *)setNumber
							  name:(NSString *)name
							  year:(NSInteger)year
						 themeName:(nullable NSString *)themeName
						  imageURL:(nullable NSString *)imageURL
							 items:(NSArray<LDrawInventoryItem *> *)items
						 fetchDate:(nullable NSDate *)fetchDate
							source:(nullable NSString *)source
	NS_SWIFT_NAME(init(setNumber:name:year:themeName:imageURL:items:fetchDate:source:)) NS_DESIGNATED_INITIALIZER;

- (instancetype) init NS_UNAVAILABLE;

/// A set number as Rebrickable writes it: trimmed, lowercase, and with "-1"
/// added when it has no version, so "42115" is "42115-1". Nil for an empty
/// string.
+ (nullable NSString *) normalizedSetNumber:(nullable NSString *)setNumber;

/// What the store writes.
- (NSDictionary<NSString *, id> *) dictionaryRepresentation;

/// Nil when the dictionary has no set number. Items that do not read are
/// skipped.
+ (nullable instancetype) setInventoryWithDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;

@end

NS_ASSUME_NONNULL_END
