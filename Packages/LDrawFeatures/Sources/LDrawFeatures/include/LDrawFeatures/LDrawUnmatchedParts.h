//==============================================================================
//
//  File:       LDrawUnmatchedParts.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-10-28.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawInventoryItem;
@class LDrawPartIdentity;
@class LDrawPartLimit;
@class LDrawPartUsage;
@class LDrawShortcutMap;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawUnmatchedPart
///
/// @abstract   A part found on one side with no match on the other.
///
//------------------------------------------------------------------------------
@interface LDrawUnmatchedPart : NSObject

/// The LDraw part a model places, e.g. "3069bp0k.dat", or nil for an
/// inventory's part.
@property (nonatomic, readonly, copy, nullable) NSString *partName;

/// The Rebrickable part an inventory holds, or nil for a model's part.
@property (nonatomic, readonly, copy, nullable) NSString *rebrickablePartNumber;

/// How many copies the models place, or how many the inventory holds with
/// its spares.
@property (nonatomic, readonly) NSUInteger count;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawUnmatchedParts
///
/// @abstract   The parts that match nothing, for the user to match by hand.
///
/// @discussion A hand match names the Rebrickable part an LDraw part is. The
///             host keeps the matches in the store, where the identity map
///             reads them.
///
//------------------------------------------------------------------------------
@interface LDrawUnmatchedParts : NSObject

/// The library parts the models use that have no Rebrickable part, the most
/// used first. An assembly with no match of its own lists its pieces that
/// have none. A part only in a model nothing places is listed with a count
/// of 0.
+ (NSArray<LDrawUnmatchedPart *> *) partsInUsages:(NSArray<LDrawPartUsage *> *)usages
										 identity:(LDrawPartIdentity *)identity
										shortcuts:(nullable LDrawShortcutMap *)shortcuts
	NS_SWIFT_NAME(parts(in:identity:shortcuts:));

/// The Rebrickable parts the items hold that have no LDraw part in the
/// library, the most held first. A part whose pool has one, under the limit's
/// options, is matched. `libraryHasPart` is asked about names such as
/// "3001.dat".
+ (NSArray<LDrawUnmatchedPart *> *) partsInItems:(NSArray<LDrawInventoryItem *> *)items
										   limit:(LDrawPartLimit *)limit
										identity:(LDrawPartIdentity *)identity
								  libraryHasPart:(BOOL (^)(NSString *partName))libraryHasPart
	NS_SWIFT_NAME(parts(in:limit:identity:libraryHasPart:));

/// The hand matches with this LDraw part matched to a Rebrickable part, or
/// its match removed when `partNumber` is nil or empty. LDraw names are kept
/// the way the identity map keys them.
+ (NSDictionary<NSString *, NSString *> *) overrides:(nullable NSDictionary<NSString *, NSString *> *)overrides
								 byMatchingPartNamed:(NSString *)partName
										toPartNumber:(nullable NSString *)partNumber
	NS_SWIFT_NAME(overrides(_:matching:to:));

@end

NS_ASSUME_NONNULL_END
