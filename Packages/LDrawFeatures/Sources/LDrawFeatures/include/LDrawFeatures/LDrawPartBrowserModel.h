//==============================================================================
//
//  File:       LDrawPartBrowserModel.h
//  Package:    LDrawFeatures
//
//  Purpose:    Foundation-only data model for the part browser.
//
//  Info:       Owns the current category, search string, search scope, and
//              filtered part list. Independent of AppKit table-view machinery;
//              hosts consume -filteredParts and -indexOfPartNamed:.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawCore/LDrawPartLimitStatus.h>

@class LDrawPartLimitSession;
@class LDrawPartLimitTable;
@class LDrawPartUsage;

NS_ASSUME_NONNULL_BEGIN

/// Keys of an inventory row, besides the part keys of a catalog record. A row
/// is one part in one color. PART_NUMBER_KEY is missing when the inventory's
/// part has no LDraw match.
extern NSString * const LDrawPartBrowserColorCodeKey;		// NSNumber, the row's LDraw color
extern NSString * const LDrawPartBrowserLEGONumberKey;		// NSString, Rebrickable's part number
extern NSString * const LDrawPartBrowserOwnedKey;			// NSNumber, copies the inventory holds
extern NSString * const LDrawPartBrowserSparesKey;			// NSNumber, spares among the owned
extern NSString * const LDrawPartBrowserLeftKey;			// NSNumber, owned less used; below zero when over
extern NSString * const LDrawPartBrowserCountTextKey;		// NSString, "used / owned"

/// How the host draws a row.
typedef NS_ENUM(NSInteger, LDrawPartBrowserRowState)
{
	LDrawPartBrowserRowNormal	= 0,

	/// The limit does not allow the part. Shown only when the browser lists
	/// every part.
	LDrawPartBrowserRowDimmed	= 1,

	/// An inventory row whose copies the model uses up exactly.
	LDrawPartBrowserRowAllUsed	= 2,

	/// An inventory row the model uses more of than the inventory holds.
	LDrawPartBrowserRowOver		= 3,

	/// An inventory row with no LDraw part, which cannot be inserted.
	LDrawPartBrowserRowNoPart	= 4
};

typedef NS_ENUM(NSInteger, LDrawPartBrowserSearchMode)
{
	LDrawPartBrowserSearchAllCategories	= 0,
	LDrawPartBrowserSearchSelectedCategory = 1

};

//------------------------------------------------------------------------------
///
/// @class      LDrawPartBrowserColorChip
///
/// @abstract   One color the selected part comes in, for the strip under the
///             preview.
///
//------------------------------------------------------------------------------
@interface LDrawPartBrowserColorChip : NSObject

@property (nonatomic, readonly) LDrawColorT colorCode;

/// Whether the chip shows how many are left: when it has an inventory row.
@property (nonatomic, readonly) BOOL hasCount;

/// Owned less used. Below zero when the model uses more than the inventory
/// holds.
@property (nonatomic, readonly) NSInteger leftCount;

/// The inventory row of this color, which a click selects. Nil when the chip
/// picks a color instead.
@property (nonatomic, readonly, nullable) NSDictionary *record;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawPartBrowserModel
///
/// @abstract   Foundation-only data model for the part browser.
///
/// @discussion With a parts limit the list keeps only the parts the limit
///             allows, or lists every part and dims the others. With an
///             inventory as the limit, and whenever a set or inventory is
///             chosen under Sets, the rows are the inventory's: one per part
///             and color, with how many the model uses and the inventory
///             holds. Primitives and Subparts are never filtered.
///
//------------------------------------------------------------------------------
@interface LDrawPartBrowserModel : NSObject

@property (nonatomic, strong)         LDrawPartLibrary              *partLibrary;
@property (nonatomic, copy)           NSString                      *currentCategory;
@property (nonatomic, copy, nullable) NSString                      *searchString;
@property (nonatomic, assign)         LDrawPartBrowserSearchMode    searchMode;
@property (nonatomic, readonly)       NSArray                       *filteredParts;

/// The session whose limit the list follows, and whose store lists the sets.
/// Nil for no limit and no Sets group.
@property (nonatomic, strong, nullable) LDrawPartLimitSession *limitSession;

/// What the model uses, for the counts of inventory rows. Nil counts nothing
/// as used.
@property (nonatomic, strong, nullable) LDrawPartUsage *partUsage;

/// Whether parts the limit does not allow are left out. NO lists them dimmed,
/// and with an inventory as the limit, lists the library's parts instead of
/// the inventory's rows. Default YES.
@property (nonatomic, assign) BOOL hidesDisallowedParts;

/// An LDraw color code. Only parts the limit allows in it are listed, or an
/// inventory's rows in it. Nil for any color.
@property (nonatomic, copy, nullable) NSNumber *colorFilter;

/// The table the rows are checked against: the set chosen under Sets, or the
/// limit in force. Nil when nothing limits the list. Set by -reloadFilter.
@property (nonatomic, readonly, nullable) LDrawPartLimitTable *activeTable;

/// Whether the rows are an inventory's. Set by -reloadFilter.
@property (nonatomic, readonly) BOOL showsInventoryRows;

- (instancetype)initWithPartLibrary:(LDrawPartLibrary *)library;

/// The library's categories, with a Sets group after Part Categories when the
/// store has sets or inventories.
- (NSArray *)categoryHierarchy;

/// Whether the category is one the browser can show.
- (BOOL)hasCategory:(nullable NSString *)category;

/// A category's name for the user. A set's is its number and name.
- (NSString *)displayNameForCategory:(NSString *)category;

/// The category that shows a set or inventory, and back.
+ (NSString *)categoryForInventoryIdentifier:(NSString *)identifier;
+ (nullable NSString *)inventoryIdentifierForCategory:(nullable NSString *)category;

/// How the host draws the row.
- (LDrawPartBrowserRowState)stateForRecord:(NSDictionary *)record;

/// The colors the color filter offers, lowest code first: the colors of the
/// inventory's rows, or every color the limit allows. Nil when the limit does
/// not restrict colors.
- (nullable NSArray<NSNumber *> *)filterColorCodes;

/// The colors of the part for the strip under the preview, lowest code first:
/// the inventory's rows of the part with what is left of each, or the colors
/// the limit allows the part in. Empty when the limit does not restrict its
/// colors.
- (NSArray<LDrawPartBrowserColorChip *> *)colorChipsForPartNamed:(nullable NSString *)partName;

/// How the part stands in this color under the active table. Allowed when
/// nothing limits the list.
- (LDrawPartLimitStatus)statusForPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode;

/// The color a record's part goes in: an inventory row's own, else the
/// current color.
+ (LDrawColorT)colorCodeForRecord:(nullable NSDictionary *)record currentColorCode:(LDrawColorT)currentColorCode;

/// Why the record's part cannot go in the current color, or nil when it can.
/// An inventory row brings its own color, and a limit that only warns lets
/// any color through.
- (nullable NSString *)insertionProblemForRecord:(nullable NSDictionary *)record currentColor:(LDrawColor *)color;

/// What the bar over the list says about the limit, or nil when no limit is
/// on.
- (nullable NSString *)limitBarTextForCategory:(nullable NSString *)category;

/// The bar's button: Show All, or Hide Others while every part shows.
+ (NSString *)limitBarButtonTitleShowingAll:(BOOL)showsAll;

/// A row's tooltip: why an inventory row cannot be inserted, or in the count
/// column the spares among the owned. Nil for none.
- (nullable NSString *)toolTipForRecord:(nullable NSDictionary *)record inCountColumn:(BOOL)isCountColumn;

/// Clears the color filter when the colors on offer no longer hold it, as
/// after the limit changed. YES when it did; the host then reloads.
- (BOOL)clearUnofferedColorFilter;

// Apply category + search filter and update -filteredParts.
- (void)reloadFilter;

// Searches -filteredParts. Returns NSNotFound if `partName` is not visible.
- (NSUInteger)indexOfPartNamed:(nullable NSString *)partName;

+ (NSUInteger)indexOfPartNamed:(nullable NSString *)partName inRecords:(NSArray *)records;

/// The row for the same part in the same color, since an inventory lists a
/// part once per color. Else the first row for the part, or NSNotFound.
+ (NSUInteger)indexOfRecord:(nullable NSDictionary *)record inRecords:(NSArray *)records;

/// Category dictionary whose Name matches, walking group Children. Nil if none.
/// The host still asks the outline for the row and selects it.
+ (nullable id)categoryItemNamed:(nullable NSString *)name inHierarchy:(NSArray *)categoryList;

/// Selected part is in the favorites list.
+ (BOOL)partNamed:(nullable NSString *)partName isInFavorites:(nullable NSArray *)favorites;

/// Search-scope buttons: there is a search string and the category is not All.
+ (BOOL)shouldShowSearchScopeButtonsForSearchString:(nullable NSString *)searchString
										   category:(nullable NSString *)category;

/// After reload, keep preferredIndex when found; otherwise select the first
/// row (0). Attempt to restore the original selection (happens especially
/// when clearing the search field).
+ (NSUInteger)tableSelectionIndexPreferring:(NSUInteger)preferredIndex;

/// Recent-searches empty menu title. The host still localizes.
+ (NSString *)noRecentSearchesLocalizationKey;

/// Part-browser toolbar button tooltips. The host still localizes.
+ (NSString *)zoomInTooltipLocalizationKey;
+ (NSString *)zoomOutTooltipLocalizationKey;
+ (NSString *)addRemoveFavoritesTooltipLocalizationKey;

/// Root is the category list; a group’s children are CategoryChildrenKey.
/// Nil if the item has no children array. The host still asks the outline.
+ (nullable NSArray *)categoryChildrenOfItem:(nullable id)item inHierarchy:(NSArray *)categoryList;

/// Favorite Add/Remove button image name from show-add policy.
+ (NSString *)favoriteButtonImageNameWhenShowingAdd:(BOOL)showAdd;

@end

NS_ASSUME_NONNULL_END
