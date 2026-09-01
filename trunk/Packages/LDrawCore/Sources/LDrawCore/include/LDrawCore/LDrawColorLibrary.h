//==============================================================================
//
//  File:       LDrawColorLibrary.h
//  Package:    LDrawCore
//
//  Purpose:    A repository of methods, functions, and data types used to
//              support LDraw colors. Color-panel search and selection policy
//              live in LDrawFeatures (LDrawColorPanelModel).
//
//  Modified:   2/26/05 Allen Smith. Creation date (LDrawColor.m)
//              3/16/08 Allen Smith. Moved to LDrawColorLibrary as part of
//              ldconfig.ldr support.
//  Copyright 2005. All rights reserved.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawColor.h>

NS_ASSUME_NONNULL_BEGIN

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
/// @class      LDrawColorLibrary
///
/// @abstract   A repository of methods, functions, and data types used to
///             support LDraw colors.
///
//------------------------------------------------------------------------------
@interface LDrawColorLibrary : NSObject
{
	NSMutableDictionary	*colors;		// keys are LDrawColorT codes; objects are LDrawColors
	NSMutableDictionary *privateColors;	// colors we might be asked to display, but should NOT be in the color picker
}

// Initialization
+ (LDrawColorLibrary *)sharedColorLibrary;

// Accessors
- (NSArray *)colors;
- (LDrawColor *)colorForCode:(LDrawColorT)colorCode;
- (void)getComplementRGBA:(float * _Nonnull)complementRGBA forCode:(LDrawColorT)colorCode;

// Registering Colors
- (void)addColor:(LDrawColor *)newColor;
- (void)addPrivateColor:(LDrawColor *)newColor;

// Utilities
void complementColor(const float * _Nonnull originalColor, float * _Nonnull complementRGBA);

@end

NS_ASSUME_NONNULL_END
