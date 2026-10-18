//==============================================================================
//
//  File:       LDrawStepPartListStyle.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-10-15.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LPubCalloutBorder.h>
#import <LDrawCore/LPubColor.h>
#import <LDrawCore/MatrixMath.h>
#import <LDrawFeatures/LDrawStepPartListLayout.h>
#import <LDrawFeatures/LDrawStepPartListPolicy.h>

@class LDrawModel;
@class LDrawStepCalloutText;
@class LPubPlacement;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepPartListStyle
///
/// @abstract   How the visible step's parts list looks on LPub3D's page, and
///             where it sits: the PLI lines of the file in force for the step,
///             and LPub3D's own choice where the file says nothing.
///
/// @discussion Lengths are in page inches.
///
//------------------------------------------------------------------------------
@interface LDrawStepPartListStyle : NSObject

- (instancetype) init NS_UNAVAILABLE;

/// From PLI BORDER, BACKGROUND, MARGINS, PLACEMENT, and INSTANCE_COUNT and
/// ANNOTATE FONT and FONT_COLOR, and PAGE MARGINS and BACKGROUND.
+ (instancetype) styleForVisibleStepOfModel:(nullable LDrawModel *)model NS_SWIFT_NAME(init(visibleStepOf:));

// The outline
@property (nonatomic, readonly) LPubBorderShape		borderShape;
@property (nonatomic, readonly) LPubLineStyle		borderLineStyle;
@property (nonatomic, readonly) LPubColorComponents	borderColor;

/// 0 for NONE.
@property (nonatomic, readonly) double				borderThickness;

/// 0 unless the outline is round.
@property (nonatomic, readonly) double				cornerRadius;

/// The room between the outline and the parts.
@property (nonatomic, readonly) Size2				borderMargins;

/// The fill. NO for a list that is see-through.
@property (nonatomic, readonly) BOOL				hasFill;
@property (nonatomic, readonly) LPubColorComponents	fillColor;

/// The room kept between the list and what it is placed against.
@property (nonatomic, readonly) Size2				margins;

/// The room the page keeps inside its edges, from PAGE MARGINS.
@property (nonatomic, readonly) Size2				pageMargins;

/// The page's color, from a PAGE BACKGROUND COLOR line. NO for a file that
/// gives none, or gives something else, which leaves the host's own color.
@property (nonatomic, readonly) BOOL				hasPageColor;
@property (nonatomic, readonly) LPubColorComponents	pageColor;

/// The PLI PLACEMENT line in force, or nil for none.
@property (nonatomic, readonly, nullable) LPubPlacement	*placement;

/// How the count under each part is written.
@property (nonatomic, readonly) LDrawStepCalloutText *countText;

/// The font of the size badges, from PLI ANNOTATE FONT. Nil for a file that
/// gives none, and the badges are then written as big as the counts in the
/// host's font.
@property (nonatomic, readonly, nullable) LDrawStepCalloutText *annotationText;

/// The color of the badges' text, from PLI ANNOTATE FONT_COLOR. NO for a file
/// that gives none, which leaves the chrome's.
@property (nonatomic, readonly) BOOL				hasAnnotationColor;
@property (nonatomic, readonly) LPubColorComponents	annotationColor;

/// The same metrics with the frame's padding and the room for a count and a
/// size badge taken from this style, in points at this many to the page inch.
- (LDrawStepPartListMetrics) metricsFromMetrics:(LDrawStepPartListMetrics)metrics
							  pointsPerPageInch:(double)pointsPerPageInch
	NS_SWIFT_NAME(metrics(from:pointsPerPageInch:));

/// The same chrome with the frame's outline and fill, the counts' size and
/// color, and the badges' size and text color, taken from this style.
- (LDrawStepPartListChrome) chromeFromChrome:(LDrawStepPartListChrome)chrome
						   pointsPerPageInch:(double)pointsPerPageInch
	NS_SWIFT_NAME(chrome(from:pointsPerPageInch:));

@end

NS_ASSUME_NONNULL_END
