//==============================================================================
//
//  File:       LDrawStepPageNumberStyle.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-10-19.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>

@class LDrawModel;
@class LDrawStepCalloutText;
@class LPubPlacement;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepPageNumberStyle
///
/// @abstract   How the page's number looks on LPub3D's page, and where it
///             goes: the PAGE lines in force for the visible step, and
///             LPub3D's own choice where the file says nothing.
///
/// @discussion Lengths are in page inches.
///
//------------------------------------------------------------------------------
@interface LDrawStepPageNumberStyle : NSObject

- (instancetype) init NS_UNAVAILABLE;

/// Nil when PAGE DISPLAY_PAGE_NUMBER hides the number.
+ (nullable instancetype) styleForVisibleStepOfModel:(LDrawModel *)model NS_SWIFT_NAME(init(visibleStepOf:));

/// From PAGE NUMBER FONT and FONT_COLOR. LPub3D's own is a bold Arial 24
/// dots high, in black.
@property (nonatomic, readonly) LDrawStepCalloutText			*text;

/// The room kept around the number, from PAGE NUMBER MARGINS.
@property (nonatomic, readonly) Size2							margins;

/// The page's own margins, from PAGE MARGINS. LPub3D keeps the larger of
/// these and the number's.
@property (nonatomic, readonly) Size2							pageMargins;

/// The PAGE NUMBER PLACEMENT line in force, or nil for none.
@property (nonatomic, readonly, nullable) LPubPlacement			*placement;

/// Whether an even page has the number on the other side, from PAGE
/// TOGGLE_PAGE_NUMBER_PLACEMENT.
@property (nonatomic, readonly) BOOL							togglesSides;

/// Where a number of `size` points goes on page `pageNumber`, drawn at
/// `pageRect` with `pointsPerInch` points to the page inch. With no PAGE
/// NUMBER PLACEMENT line it goes in the bottom right corner. Only a place
/// inside the page is read, since the page's header and footer are not drawn.
- (Box2) rectForSize:(Size2)size
		  pageNumber:(NSUInteger)pageNumber
			  onPage:(Box2)pageRect
	   pointsPerInch:(double)pointsPerInch
	NS_SWIFT_NAME(rect(forSize:pageNumber:onPage:pointsPerInch:));

@end

NS_ASSUME_NONNULL_END
