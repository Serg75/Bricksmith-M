//==============================================================================
//
//  File:       ColorLibrary.h
//  Package:    LDrawCore
//
//  Purpose:    A repository of methods, functions, and data types used to
//              support LDraw colors.
//
//  Modified:   2/26/05 Allen Smith. Creation date (LDrawColor.m)
//              3/16/08 Allen Smith. Moved to ColorLibrary as part of
//              ldconfig.ldr support.
//  Copyright 2005. All rights reserved.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawColor.h>

NS_ASSUME_NONNULL_BEGIN

/// Color-panel material popup tags (1-based filter kinds after All = 0).
typedef enum {
    LDrawColorFilterAll           = 0,
    LDrawColorFilterSolid         = 1,
    LDrawColorFilterTransparent   = 2,
    LDrawColorFilterChrome        = 3,
    LDrawColorFilterPearlescent   = 4,
    LDrawColorFilterRubber        = 5,
    LDrawColorFilterMetal         = 6,
    LDrawColorFilterOther         = 7
} LDrawColorFilterT;


//------------------------------------------------------------------------------
///
/// @protocol   LDrawColorable
///
/// @abstract   This protocol is adopted by classes that accept colors, such as
///             LDrawPart and LDrawQuadrilateral.
///
//------------------------------------------------------------------------------
@protocol LDrawColorable

- (LDrawColor *)LDrawColor;
- (void)setLDrawColor:(LDrawColor *)newColor;

@end


//------------------------------------------------------------------------------
///
/// @class      ColorLibrary
///
/// @abstract   A repository of methods, functions, and data types used to
///             support LDraw colors.
///
//------------------------------------------------------------------------------
@interface ColorLibrary : NSObject
{
	NSMutableDictionary	*colors;		// keys are LDrawColorT codes; objects are LDrawColors
	NSMutableDictionary *privateColors;	// colors we might be asked to display, but should NOT be in the color picker
}

// Initialization
+ (ColorLibrary *)sharedColorLibrary;

// Accessors
- (NSArray *)colors;
- (LDrawColor *)colorForCode:(LDrawColorT)colorCode;
- (void)getComplimentRGBA:(float * _Nonnull)complimentRGBA forCode:(LDrawColorT)colorCode;

// Registering Colors
- (void)addColor:(LDrawColor *)newColor;
- (void)addPrivateColor:(LDrawColor *)newColor;

/// Row index of colorSought in colors, or NSNotFound if it is not in the list.
/// A brute-force search by colorCode. The host still uses arrangedObjects.
+ (NSInteger)indexOfColor:(LDrawColor *)colorSought inColors:(NSArray *)colors;

/// Search predicate for the color panel. Nil search string (or empty) matches
/// any name/code; All material matches any material. Nil means find all.
/// If the search string parses as an integer, it matches colorCode exactly;
/// otherwise localizedName CONTAINS[cd]. The host still applies the predicate
/// to NSArrayController.
+ (nullable NSPredicate *)predicateForSearchString:(nullable NSString *)searchString
										  material:(LDrawColorFilterT)material;

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

// Utilities
void complimentColor(const float * _Nonnull originalColor, float * _Nonnull complimentColor);

@end

NS_ASSUME_NONNULL_END
