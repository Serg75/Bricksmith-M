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

#import <LDrawCore/LDrawPartLibrary.h>

NS_ASSUME_NONNULL_BEGIN

typedef enum SearchMode
{
	SearchModeAllCategories	= 0,
	SearchModeSelectedCategory = 1

} SearchModeT;

//------------------------------------------------------------------------------
///
/// @class      LDrawPartBrowserModel
///
/// @abstract   Foundation-only data model for the part browser.
///
//------------------------------------------------------------------------------
@interface LDrawPartBrowserModel : NSObject

@property (nonatomic, strong)         LDrawPartLibrary *partLibrary;
@property (nonatomic, copy)           NSString         *currentCategory;
@property (nonatomic, copy, nullable) NSString         *searchString;
@property (nonatomic, assign)         SearchModeT       searchMode;
@property (nonatomic, readonly)       NSArray          *filteredParts;

- (instancetype)initWithPartLibrary:(LDrawPartLibrary *)library;

// Apply category + search filter and update -filteredParts.
- (void)reloadFilter;

// Searches -filteredParts. Returns NSNotFound if `partName` is not visible.
- (NSUInteger)indexOfPartNamed:(nullable NSString *)partName;

+ (NSUInteger)indexOfPartNamed:(nullable NSString *)partName inRecords:(NSArray *)records;

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
