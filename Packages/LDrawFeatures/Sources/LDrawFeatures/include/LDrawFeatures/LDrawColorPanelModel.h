//==============================================================================
//
//  File:       LDrawColorPanelModel.h
//  Package:    LDrawFeatures
//
//  Purpose:    Foundation-only packing for the color panel: material filter,
//              search predicate, selection policy, and tooltip format. The
//              host still owns the table and NSArrayController.
//
//  Created by Sergey Slobodenyuk on 2026-09-01.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawColor.h>

NS_ASSUME_NONNULL_BEGIN

/// Color-panel material popup tags (1-based filter kinds after All = 0).
typedef NS_ENUM(NSInteger, LDrawColorFilter) {
	LDrawColorFilterAll           = 0,
	LDrawColorFilterSolid         = 1,
	LDrawColorFilterTransparent   = 2,
	LDrawColorFilterChrome        = 3,
	LDrawColorFilterPearlescent   = 4,
	LDrawColorFilterRubber        = 5,
	LDrawColorFilterMetal         = 6,
	LDrawColorFilterOther         = 7
};


//------------------------------------------------------------------------------
///
/// @class      LDrawColorPanelModel
///
/// @abstract   Foundation-only packing for the color panel. The color registry
///             stays in LDrawColorLibrary.
///
//------------------------------------------------------------------------------
@interface LDrawColorPanelModel : NSObject

/// Row index of colorSought in colors, or NSNotFound if it is not in the list.
/// A brute-force search by colorCode. The host still uses arrangedObjects.
+ (NSInteger)indexOfColor:(LDrawColor *)colorSought inColors:(NSArray *)colors;

/// Search predicate for the color panel. Nil search string (or empty) matches
/// any name/code; All material matches any material. Nil means find all.
/// If the search string parses as an integer, it matches colorCode exactly;
/// otherwise localizedName CONTAINS[cd]. The host still applies the predicate
/// to NSArrayController.
+ (nullable NSPredicate *)predicateForSearchString:(nullable NSString *)searchString
										  material:(LDrawColorFilter)material;

/// YES when the filtered list no longer contains the previous selection and
/// the host should select the first color to avoid an empty selection.
+ (BOOL)shouldSelectFirstColorAfterFilterWhenPreviousIndex:(NSInteger)index;

/// YES when the sought color is not in the filtered list and the host should
/// clear the filter to search the master list.
+ (BOOL)shouldClearColorFilterWhenIndexNotFound:(NSInteger)index;

/// YES when a row index refers to a color in the current list.
+ (BOOL)canSelectColorAtRowIndex:(NSInteger)index;

/// First selected color, or fallback when the list selection is empty.
+ (nullable LDrawColor *)colorFromListSelection:(NSArray *)selection
								  fallbackColor:(nullable LDrawColor *)fallbackColor;

/// Color-bar tooltip: “LDraw {code}\n{localizedName}”.
+ (NSString *)tooltipForColorCode:(LDrawColorT)colorCode
					localizedName:(NSString *)localizedName;

@end

NS_ASSUME_NONNULL_END
