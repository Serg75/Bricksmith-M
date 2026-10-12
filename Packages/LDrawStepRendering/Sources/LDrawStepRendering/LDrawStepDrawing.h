//==============================================================================
//
//  File:       LDrawStepDrawing.h
//  Package:    LDrawStepRendering
//
//  Purpose:    The fills, strokes and text the overlay is drawn with. Private
//              to the package.
//
//              Every context has its origin at the top left, with y running
//              down.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>

#import <LDrawCore/LPubColor.h>
#import <LDrawCore/MatrixMath.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LDrawStepFontWeight) {
	LDrawStepFontWeightRegular	= 0,
	LDrawStepFontWeightMedium	= 1,
	LDrawStepFontWeightBold		= 2
};

/// A font to draw with. The system's own is measured a little differently.
typedef struct LDrawStepFont
{
	CTFontRef	font;
	BOOL		isSystemFont;

} LDrawStepFont;

// Geometry and color
extern CGRect LDrawStepRectFromBox(Box2 box);

/// A color from four sRGB values. The caller releases it.
extern CGColorRef LDrawStepColorCreateRGBA(const double *rgba) CF_RETURNS_RETAINED;

/// Sets the color for both filling and stroking: four sRGB values.
extern void LDrawStepSetRGBA(CGContextRef context, const double *rgba);
extern void LDrawStepSetColorComponents(CGContextRef context, LPubColorComponents color);
extern void LDrawStepSetColor(CGContextRef context, CGColorRef color);

/// Adds a rectangle with round corners to the context's path. A radius the
/// rectangle is too small for is cut down to fit.
extern void LDrawStepAddRoundedRect(CGContextRef context, CGRect rect, CGFloat radius);

/// Adds the oval that fills a rectangle to the context's path.
extern void LDrawStepAddOval(CGContextRef context, CGRect rect);

/// Draws a picture upright in a rectangle.
extern void LDrawStepDrawImage(CGContextRef context, CGImageRef image, CGRect rect);

// Fonts. Each one made is released with LDrawStepFontRelease.
extern LDrawStepFont LDrawStepFontCreateSystem(CGFloat size, LDrawStepFontWeight weight);

/// A font of a family. The system's when the family is not installed.
extern LDrawStepFont LDrawStepFontCreateOfFamily(NSString *family, BOOL isBold, BOOL isItalic, CGFloat size);
extern void LDrawStepFontRelease(LDrawStepFont font);

// Text
/// The room one line of text takes.
extern CGSize LDrawStepTextSize(NSString *text, LDrawStepFont font);

/// Draws one line of text with its middle at the middle of the rect. The text
/// is not cut short when the rect is too small for it.
extern void LDrawStepDrawTextCentered(CGContextRef context, NSString *text, CGRect rect, LDrawStepFont font,
									  const double *rgba);

/// Draws one line of text centered in the rect. Text wider than the rect is
/// cut short with an ellipsis.
extern void LDrawStepDrawTextInRect(CGContextRef context, NSString *text, CGRect rect, LDrawStepFont font,
									const double *rgba);

NS_ASSUME_NONNULL_END
