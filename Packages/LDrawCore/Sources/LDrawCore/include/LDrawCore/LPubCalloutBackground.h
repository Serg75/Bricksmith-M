//==============================================================================
//
//  File:       LPubCalloutBackground.h
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
/// @enum       LPubCalloutBackgroundKind
///
/// @abstract   What a callout's box is filled with.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LPubCalloutBackgroundKind) {
	/// The color LPub3D gives the submodel's depth. Its choice for a file
	/// that says nothing.
	LPubCalloutBackgroundKindSubmodelColor	= 0,
	LPubCalloutBackgroundKindTransparent	= 1,
	LPubCalloutBackgroundKindColor			= 2,
	LPubCalloutBackgroundKindPicture		= 3,
	LPubCalloutBackgroundKindGradient		= 4
};


//------------------------------------------------------------------------------
///
/// @class      LPubCalloutBackground
///
/// @abstract   What a callout's box is filled with:
///             0 !LPUB CALLOUT BACKGROUND [GLOBAL|LOCAL] (TRANSPARENT |
///                 SUBMODEL_BACKGROUND_COLOR | COLOR <color> |
///                 PICTURE <file> [STRETCH] | GRADIENT <8 values>)
///
/// @discussion The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubCalloutBackground : LPubCommand

@property (nonatomic, readonly) LPubMetaScope				scope;
@property (nonatomic, readonly) LPubCalloutBackgroundKind	kind;

/// The fill of a COLOR line. Black when it cannot be read, as in LPub3D, and
/// for any other kind.
@property (nonatomic, readonly) LPubColorComponents			color;

@end

NS_ASSUME_NONNULL_END
