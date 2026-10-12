//==============================================================================
//
//  File:       LPubCalloutSubmodelColor.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubColor.h>
#import <LDrawCore/LPubCommand.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LPubCalloutSubmodelColor
///
/// @abstract   The fill of a callout's box at each depth of submodel:
///             0 !LPUB CALLOUT SUBMODEL_BACKGROUND_COLOR [GLOBAL|LOCAL]
///                 <color> [<color> ...]
///
/// @discussion The first color is for the top model, the next for a submodel
///             placed in it, and so on. A callout takes the color one level
///             deeper than the model it is in.
///
///             The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubCalloutSubmodelColor : LPubCommand

@property (nonatomic, readonly) LPubMetaScope	scope;

/// How many colors the line gives. At least one.
@property (nonatomic, readonly) NSUInteger		colorCount;

/// The color for a level, counted from 0. A level past the end takes the last
/// color, as in LPub3D.
- (LPubColorComponents) colorAtLevel:(NSUInteger)level NS_SWIFT_NAME(color(atLevel:));

/// LPub3D's color for a level when a file says nothing.
+ (LPubColorComponents) defaultColorAtLevel:(NSUInteger)level NS_SWIFT_NAME(defaultColor(atLevel:));

@end

NS_ASSUME_NONNULL_END
