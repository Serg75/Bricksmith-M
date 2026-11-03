//==============================================================================
//
//  File:       LDrawPartIdentity.h
//  Package:    LDrawInventory
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawColor.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawPartIdentity
///
/// @abstract   Which LEGO part an LDraw part is, which color an LDraw color is,
///             and which parts count as one.
///
/// @discussion Immutable. LEGO parts and colors go by Rebrickable's numbers.
///
///             An LDraw part finds its Rebrickable number, in this order: a
///             match the user made by hand; the "Rebrickable <number>" keyword
///             the LDraw library writes when the numbers differ; Rebrickable's
///             own LDraw links; the old number of a part the library renamed,
///             while Rebrickable has only that; and last the same number.
///
///             Colors are matched only through links. Rebrickable's color ids
///             are not LDraw codes, though many agree. Rebrickable has no
///             rubber colors, so LDraw's rubber black is Black there.
///
//------------------------------------------------------------------------------
@interface LDrawPartIdentity : NSObject

/// The identity of an empty map: every part keeps its own number, and no
/// color matches.
+ (instancetype) emptyIdentity NS_SWIFT_NAME(empty());

/// Merges what is known about parts, weakest first: the same number, the old
/// numbers of renamed parts, Rebrickable's links from `rebrickableData`, the
/// library's keywords from `catalogRecords`, then `overrides`. Every argument
/// may be nil.
///
/// `catalogRecords` are the part library's records, with
/// `PART_NUMBER_KEY`, `PART_NAME_KEY` and `PART_KEYWORDS_KEY`.
/// `rebrickableData` is what `+rebrickableDataWith...` makes, as the store
/// keeps it. `overrides` maps LDraw part names to Rebrickable numbers.
+ (instancetype) identityWithCatalogRecords:(nullable NSArray<NSDictionary *> *)catalogRecords
							rebrickableData:(nullable NSDictionary *)rebrickableData
								  overrides:(nullable NSDictionary<NSString *, NSString *> *)overrides;

/// The same, knowing which LDraw colors are rubber, such as rubber black.
+ (instancetype) identityWithCatalogRecords:(nullable NSArray<NSDictionary *> *)catalogRecords
							rebrickableData:(nullable NSDictionary *)rebrickableData
								  overrides:(nullable NSDictionary<NSString *, NSString *> *)overrides
						   rubberColorCodes:(nullable NSSet<NSNumber *> *)rubberColorCodes;

/// What Rebrickable tells about parts and colors, in the form the store keeps.
///
/// - `partLinks`: LDraw part name → Rebrickable number.
/// - `colorLinks`: Rebrickable color id → LDraw color code, or a list of
///   codes when one Rebrickable color stands for several, as Black does for
///   LDraw's black and rubber black.
/// - `relations`: rows of relation code, child, parent, as Rebrickable's
///   `part_relationships` has them: "P" print, "T" pattern, "M" mold,
///   "A" alternate. "B" sub-part and "R" pair are kept but not used.
/// - `knownPartNumbers`: every part Rebrickable has, or nil when not known. A
///   part outside it has no data.
/// - `rubberPartNumbers`: the parts Rebrickable makes of rubber, such as
///   tires, or nil when not known.
+ (NSDictionary *) rebrickableDataWithPartLinks:(nullable NSDictionary<NSString *, NSString *> *)partLinks
									 colorLinks:(nullable NSDictionary<NSNumber *, id> *)colorLinks
									  relations:(nullable NSArray<NSArray<NSString *> *> *)relations
							   knownPartNumbers:(nullable NSSet<NSString *> *)knownPartNumbers
							  rubberPartNumbers:(nullable NSSet<NSString *> *)rubberPartNumbers;

/// Rebrickable data with some parts replaced. Part links are added to the
/// links `data` has; any other argument that is not nil replaces what `data`
/// has. `data` may be nil.
+ (NSDictionary *) rebrickableDataByUpdating:(nullable NSDictionary *)data
								   partLinks:(nullable NSDictionary<NSString *, NSString *> *)addedPartLinks
								  colorLinks:(nullable NSDictionary<NSNumber *, id> *)colorLinks
								   relations:(nullable NSArray<NSArray<NSString *> *> *)relations
							knownPartNumbers:(nullable NSSet<NSString *> *)knownPartNumbers
						   rubberPartNumbers:(nullable NSSet<NSString *> *)rubberPartNumbers;

/// The color links in Rebrickable data, or an empty dictionary.
+ (NSDictionary<NSNumber *, NSArray<NSNumber *> *> *) colorLinksInRebrickableData:(nullable NSDictionary *)data;

/// The rubber parts in Rebrickable data, or nil when it does not say.
+ (nullable NSSet<NSString *> *) rubberPartNumbersInRebrickableData:(nullable NSDictionary *)data;

/// An LDraw part name as the map keys it: lowercase, no ".dat", and "/" for a
/// path. "3001.DAT" is "3001". Nil for an empty name.
+ (nullable NSString *) normalizedPartName:(nullable NSString *)partName;

/// A part's file name as the part library lists it: lowercase, with ".dat"
/// when it has no extension, and a backslash before a folder's part. " 3001 "
/// is "3001.dat", and "S/3001s01" is "s\3001s01.dat". Nil for an empty name.
+ (nullable NSString *) libraryPartName:(nullable NSString *)partName;

/// "Rebrickable <number>" keywords: normalized LDraw name → number.
+ (NSDictionary<NSString *, NSString *> *) keywordLinksFromCatalogRecords:(NSArray<NSDictionary *> *)catalogRecords;

/// Rebrickable's number for an LDraw part, following moved parts. Nil when
/// Rebrickable does not have the part, as far as is known.
- (nullable NSString *) rebrickablePartNumberForPartName:(NSString *)partName;

/// The LDraw part for a Rebrickable number, e.g. "3001.dat": the library's
/// part of the same number when it has one that has not moved and links
/// nowhere else, else a linked one, else the same number. The library may
/// not have it; the host checks.
- (NSString *) partNameForRebrickablePartNumber:(NSString *)partNumber;

/// Every LDraw part that may be a Rebrickable part: the one
/// `partNameForRebrickablePartNumber:` gives first, then the linked ones and
/// the same number unless that LDraw part links elsewhere.
- (NSArray<NSString *> *) partNamesForRebrickablePartNumber:(NSString *)partNumber;

/// Every Rebrickable color an LDraw color can be, lowest id first. Several
/// Rebrickable colors can share one LDraw color. Empty when none links.
- (NSArray<NSNumber *> *) rebrickableColorIDsForColorCode:(LDrawColorT)colorCode;

/// The lowest of those, or `LDrawRebrickableColorNone`.
- (NSInteger) rebrickableColorIDForColorCode:(LDrawColorT)colorCode;

/// The LDraw color for a Rebrickable color, the first when it has several,
/// or `LDrawColorBogus`.
- (LDrawColorT) colorCodeForRebrickableColorID:(NSInteger)colorID;

/// Every LDraw color a Rebrickable color links to that suits the part, that
/// first one first. A rubber color suits only a part Rebrickable makes of
/// rubber, or any part when that is not known. Empty when none links.
- (NSArray<NSNumber *> *) colorCodesForRebrickableColorID:(NSInteger)colorID
											 ofPartNumber:(nullable NSString *)partNumber;

/// Whether the LDraw color suits the part, by the same rule. Only a rubber
/// color on a part that is not rubber does not.
- (BOOL) colorCode:(LDrawColorT)colorCode suitsPartNamed:(NSString *)partName;

/// The part that stands for a whole pool. With `matchesAnyPrint`, a print or
/// pattern stands for its plain part. With `matchesMoldVariants`, a part's
/// molds and alternates share one key.
- (NSString *) poolKeyForRebrickablePartNumber:(NSString *)partNumber
						   matchesMoldVariants:(BOOL)matchesMoldVariants
							   matchesAnyPrint:(BOOL)matchesAnyPrint;

@end

NS_ASSUME_NONNULL_END
