//==============================================================================
//
//  File:       LPubCalloutBorder.h
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
/// @enum       LPubBorderShape
///
/// @abstract   The outline of a box.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LPubBorderShape) {
	LPubBorderShapeNone		= 0,
	LPubBorderShapeSquare	= 1,
	LPubBorderShapeRound	= 2
};


//------------------------------------------------------------------------------
///
/// @enum       LPubLineStyle
///
/// @abstract   How a line is drawn, numbered as LPub3D writes it.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LPubLineStyle) {
	LPubLineStyleNone		= 0,
	LPubLineStyleSolid		= 1,
	LPubLineStyleDash		= 2,
	LPubLineStyleDot		= 3,
	LPubLineStyleDashDot	= 4,
	LPubLineStyleDashDotDot	= 5
};


//------------------------------------------------------------------------------
///
/// @class      LPubCalloutBorder
///
/// @abstract   The outline of a callout's box, a parts list or the page:
///             0 !LPUB (CALLOUT|PLI|PAGE) BORDER [GLOBAL|LOCAL] NONE [<line>]
///             0 !LPUB (CALLOUT|PLI|PAGE) BORDER [GLOBAL|LOCAL]
///                 (SQUARE|HIDDEN) [<line>] <color> <thickness>
///             0 !LPUB (CALLOUT|PLI|PAGE) BORDER [GLOBAL|LOCAL] ROUND [<line>]
///                 <color> <thickness> <radius>
///             each with an optional MARGINS <x> <y> at the end.
///
/// @discussion The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubCalloutBorder : LPubCommand <LPubStyleLine>

@property (nonatomic, readonly) LPubStyleBranch		branch;
@property (nonatomic, readonly) LPubMetaScope		scope;
@property (nonatomic, readonly) LPubBorderShape		shape;

/// YES for HIDDEN: a square outline whose arrows have no head.
@property (nonatomic, readonly) BOOL				hidesArrowTips;

/// Solid when the line has no number for it.
@property (nonatomic, readonly) LPubLineStyle		lineStyle;

/// Black for NONE, and for a color that cannot be read.
@property (nonatomic, readonly) LPubColorComponents	color;

/// How thick the outline is, in inches.
@property (nonatomic, readonly) double				thickness;

/// How round the corners are, in dots at the file's resolution.
@property (nonatomic, readonly) double				radius;

/// The room between the outline and what is inside, in inches. Only when the
/// line has MARGINS: without it LPub3D keeps what it had.
@property (nonatomic, readonly) BOOL				hasMargins;
@property (nonatomic, readonly) Size2				margins;

@end

NS_ASSUME_NONNULL_END
