//==============================================================================
//
//  File:       LDrawStepCalloutStyle.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LPubCalloutBorder.h>
#import <LDrawCore/LPubColor.h>
#import <LDrawCore/MatrixMath.h>

@class LDrawStepCallout;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepCalloutText
///
/// @abstract   How one kind of text in a callout's box is drawn.
///
//------------------------------------------------------------------------------
@interface LDrawStepCalloutText : NSObject

- (instancetype) init NS_UNAVAILABLE;

@property (nonatomic, readonly, copy) NSString		*fontFamily;

/// The size of the font, in page inches.
@property (nonatomic, readonly) double				fontSize;
@property (nonatomic, readonly) BOOL				isBold;
@property (nonatomic, readonly) BOOL				isItalic;
@property (nonatomic, readonly) LPubColorComponents	color;

/// The room a line of this many characters takes, in page inches. An
/// estimate: the host draws the text in the middle of it.
- (Size2) sizeForCharacterCount:(NSUInteger)count NS_SWIFT_NAME(size(forCharacterCount:));

/// The same for a line of this text. A symbol outside plain ASCII is counted
/// as two characters, since most are about as wide as two digits.
- (Size2) sizeForText:(NSString *)text NS_SWIFT_NAME(size(for:));

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawStepCalloutStyle
///
/// @abstract   How one callout's box looks on LPub3D's page: the lines of the
///             file in force for it, and LPub3D's own choice where the file
///             says nothing.
///
/// @discussion Lengths are in page inches.
///
//------------------------------------------------------------------------------
@interface LDrawStepCalloutStyle : NSObject

- (instancetype) init NS_UNAVAILABLE;

+ (instancetype) styleForCallout:(LDrawStepCallout *)callout NS_SWIFT_NAME(init(callout:));

// The outline
@property (nonatomic, readonly) LPubBorderShape		borderShape;
@property (nonatomic, readonly) LPubLineStyle		borderLineStyle;
@property (nonatomic, readonly) LPubColorComponents	borderColor;
@property (nonatomic, readonly) double				borderThickness;
@property (nonatomic, readonly) double				cornerRadius;

/// The room between the outline and what is inside.
@property (nonatomic, readonly) Size2				borderMargins;

/// Arrows are drawn in the outline's color. YES draws them with no head.
@property (nonatomic, readonly) BOOL				hidesArrowTips;

/// The fill. NO for a box that is see-through.
@property (nonatomic, readonly) BOOL				hasFill;
@property (nonatomic, readonly) LPubColorComponents	fillColor;

/// The room kept between the box and what it is placed against.
@property (nonatomic, readonly) Size2				margins;

/// The room kept around a step's picture, its parts list, its number, and
/// the count of how many times the box is built.
@property (nonatomic, readonly) Size2				assemblyMargins;
@property (nonatomic, readonly) Size2				partsListMargins;
@property (nonatomic, readonly) Size2				stepNumberMargins;
@property (nonatomic, readonly) Size2				countMargins;

/// The line between two groups of steps, and the room on each side of it.
@property (nonatomic, readonly) double				separatorThickness;
@property (nonatomic, readonly) LPubColorComponents	separatorColor;
@property (nonatomic, readonly) Size2				separatorMargins;

@property (nonatomic, readonly) LDrawStepCalloutText *stepNumberText;
@property (nonatomic, readonly) LDrawStepCalloutText *countText;

@end

NS_ASSUME_NONNULL_END
