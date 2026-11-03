//==============================================================================
//
//  File:       LDrawPartLimitTable.h
//  Package:    LDrawInventory
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawPartLimitStatus.h>

@class LDrawInventoryItem;
@class LDrawPartAvailability;
@class LDrawPartIdentity;
@class LDrawPartLimit;
@class LDrawShortcutMap;
@class LDrawShortcutPiece;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawPartLimitTable
///
/// @abstract   What a limit allows, ready for lookups by LDraw part name and
///             color code.
///
/// @discussion Immutable. It is built once for a limit, from the catalog or
///             the inventory's items and the identity map, so a lookup is a
///             few dictionary hits. Build it again when any of them changes.
///
///             Parts are counted by pool: a part, its molds and alternates,
///             and with any print, its prints. An item in Rebrickable's "any
///             color" counts toward every color of its pool. A part with no
///             Rebrickable number pools by its LDraw name.
///
///             With a shortcut map, an inventory counts an assembly by its
///             pieces, such as a hinge by its two halves, so a model can build
///             it either way. Available now also allows the pieces of an
///             assembly that came in a set, in its color. An assembly is
///             allowed when its pieces are.
///
//------------------------------------------------------------------------------
@interface LDrawPartLimitTable : NSObject

/// A table for no limit, which allows everything.
+ (instancetype) unrestrictedTable NS_SWIFT_NAME(unrestricted());

/// A table for the limit. Available now reads `availability`; an inventory
/// reads `items`, every set and loose part already put together. The other is
/// ignored. `currentYear` is the year Available now counts back from.
+ (instancetype) tableForLimit:(LDrawPartLimit *)limit
				  availability:(nullable LDrawPartAvailability *)availability
						 items:(nullable NSArray<LDrawInventoryItem *> *)items
					  identity:(LDrawPartIdentity *)identity
						  year:(NSInteger)currentYear
	NS_SWIFT_NAME(init(limit:availability:items:identity:year:));

/// The same, splitting assemblies into their pieces through `shortcuts`.
+ (instancetype) tableForLimit:(LDrawPartLimit *)limit
				  availability:(nullable LDrawPartAvailability *)availability
						 items:(nullable NSArray<LDrawInventoryItem *> *)items
					  identity:(LDrawPartIdentity *)identity
					 shortcuts:(nullable LDrawShortcutMap *)shortcuts
						  year:(NSInteger)currentYear
	NS_SWIFT_NAME(init(limit:availability:items:identity:shortcuts:year:));

@property (nonatomic, readonly) LDrawPartLimit *limit;

/// Whether the limit has the data it needs. Without it, every part has no
/// data.
@property (nonatomic, readonly) BOOL hasData;

/// How the part stands in this color. Never `TooMany`, since a table does not
/// count what a model uses. A rubber color is not the color of a part that is
/// not rubber, though it matches the same Rebrickable color.
- (LDrawPartLimitStatus) statusForPartNamed:(NSString *)partName
								  colorCode:(LDrawColorT)colorCode
	NS_SWIFT_NAME(status(forPartNamed:colorCode:));

/// Whether the color matches a Rebrickable color. Every part in a color that
/// does not has no data.
- (BOOL) matchesColorCode:(LDrawColorT)colorCode;

/// Whether the limit allows the part in at least one color.
- (BOOL) allowsPartNamed:(NSString *)partName;

/// Whether the limit allows the part in this color.
- (BOOL) allowsPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode;

/// Whether the part may be given this color: NO only when the limit does more
/// than warn and the part is not made in the color.
- (BOOL) allowsPickingColorCode:(LDrawColorT)colorCode forPartNamed:(NSString *)partName;

/// How many of the part in this color the inventory holds, spares included
/// when the limit says so. `NSNotFound` when the limit does not count.
- (NSUInteger) ownedCountForPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode;

/// The LDraw colors the part is allowed in, lowest code first, one for each
/// Rebrickable color: the first LDraw color it links to. Nil when the limit
/// does not restrict its colors. Colors with no LDraw match are left out.
- (nullable NSArray<NSNumber *> *) colorCodesForPartNamed:(NSString *)partName;

/// The same with every LDraw color those Rebrickable colors link to that
/// suits the part, such as rubber black with black for a tire. A rubber color
/// suits only a part Rebrickable makes of rubber.
- (nullable NSArray<NSNumber *> *) everyColorCodeForPartNamed:(NSString *)partName;

/// The colors some part is allowed in, lowest code first, one for each
/// Rebrickable color. Nil when the limit does not restrict colors.
- (nullable NSArray<NSNumber *> *) allowedColorCodes;

/// The same with every LDraw color those Rebrickable colors link to that
/// suits a part allowed in them.
- (nullable NSArray<NSNumber *> *) everyAllowedColorCode;

/// What copies of the part in this color are counted under: its pool and the
/// Rebrickable colors its color is, so LDraw colors that are one Rebrickable
/// color share one count. Nil when the part or the color has no match.
- (nullable NSString *) countKeyForPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode;

/// The pieces an inventory counts a copy of the part as, each in its own
/// color, 16 for the copy's. Nil when the part counts as itself.
- (nullable NSArray<LDrawShortcutPiece *> *) countedPiecesOfPartNamed:(NSString *)partName
	NS_SWIFT_NAME(countedPieces(ofPartNamed:));

/// An inventory's rows: one per pool and color, with LDraw ids filled in
/// where the identity map knows them, and assemblies as their pieces. Empty
/// for other limits.
- (NSArray<LDrawInventoryItem *> *) items;

/// An inventory's items that match no part, or no color while colors count.
- (NSArray<LDrawInventoryItem *> *) unmatchedItems;

@end

NS_ASSUME_NONNULL_END
