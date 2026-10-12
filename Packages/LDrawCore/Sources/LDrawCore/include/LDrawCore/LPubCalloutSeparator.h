//==============================================================================
//
//  File:       LPubCalloutSeparator.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubColor.h>
#import <LDrawCore/LPubCommand.h>
#import <LDrawCore/MatrixMath.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LPubCalloutSeparator
///
/// @abstract   The line between two groups of steps in a callout's box:
///             0 !LPUB CALLOUT SEPARATOR [GLOBAL|LOCAL] <thickness> <color>
///                 <margin x> <margin y>
///
/// @discussion LPub3D also writes forms that start with how long the line is,
///             and that name the thickness and the margins.
///
///             The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubCalloutSeparator : LPubCommand

@property (nonatomic, readonly) LPubMetaScope		scope;

/// How thick the line is, in inches.
@property (nonatomic, readonly) double				thickness;

/// Black for a color that cannot be read.
@property (nonatomic, readonly) LPubColorComponents	color;

/// The room kept on each side of the line, in inches.
@property (nonatomic, readonly) Size2				margins;

@end

NS_ASSUME_NONNULL_END
