//==============================================================================
//
//  File:       LDrawStepDrawing.m
//  Package:    LDrawStepRendering
//
//  Purpose:    The fills, strokes and text the overlay is drawn with.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import "LDrawStepDrawing.h"


/// How far a corner's control points sit from its ends, as a share of the
/// radius. AppKit rounds a corner with this value.
static const CGFloat CORNER_CONTROL_FACTOR = 0.55228;

/// The same for a quarter of an oval, which AppKit draws with the exact value.
static const CGFloat OVAL_CONTROL_FACTOR = 0.5522847498307936;

/// The weight of the system's medium font.
static const CGFloat MEDIUM_FONT_WEIGHT = 0.23;

/// Below this size AppKit measures a line of the system font with its descent
/// rounded up.
static const CGFloat SYSTEM_FONT_TALL_LINE_LIMIT = 21.0;


// MARK: - GEOMETRY AND COLOR -


//========== LDrawStepRectFromBox ==============================================
CGRect LDrawStepRectFromBox(Box2 box)
{
	return CGRectMake(box.origin.x, box.origin.y, box.size.width, box.size.height);

}//end LDrawStepRectFromBox


//========== LDrawStepBoxFromRect ==============================================
Box2 LDrawStepBoxFromRect(CGRect rect)
{
	return V2MakeBox(CGRectGetMinX(rect), CGRectGetMinY(rect), CGRectGetWidth(rect), CGRectGetHeight(rect));

}//end LDrawStepBoxFromRect


//========== LDrawStepColorCreateRGBA ==========================================
CGColorRef LDrawStepColorCreateRGBA(const double *rgba)
{
	return CGColorCreateSRGB(rgba[0], rgba[1], rgba[2], rgba[3]);

}//end LDrawStepColorCreateRGBA


//========== LDrawStepSetColor =================================================
void LDrawStepSetColor(CGContextRef context, CGColorRef color)
{
	CGContextSetFillColorWithColor(context, color);
	CGContextSetStrokeColorWithColor(context, color);

}//end LDrawStepSetColor


//========== LDrawStepSetRGBA ==================================================
void LDrawStepSetRGBA(CGContextRef context, const double *rgba)
{
	CGColorRef color = LDrawStepColorCreateRGBA(rgba);

	LDrawStepSetColor(context, color);
	CGColorRelease(color);

}//end LDrawStepSetRGBA


//========== LDrawStepSetColorComponents =======================================
void LDrawStepSetColorComponents(CGContextRef context, LPubColorComponents color)
{
	double rgba[4];

	LPubColorComponentsGetRGBA(color, rgba);
	LDrawStepSetRGBA(context, rgba);

}//end LDrawStepSetColorComponents


//========== LDrawStepAddRoundedRect ===========================================
///
/// @abstract	Adds a rectangle with round corners to the context's path.
///
/// @discussion	The path starts and runs as AppKit's does, so a dashed outline
///				has its dashes in the same places in every host.
///
//==============================================================================
void LDrawStepAddRoundedRect(CGContextRef context, CGRect rect, CGFloat radius)
{
	CGFloat	radiusX	= MIN(radius, CGRectGetWidth(rect) / 2.0);
	CGFloat	radiusY	= MIN(radius, CGRectGetHeight(rect) / 2.0);

	if (radiusX <= 0.0 || radiusY <= 0.0) {
		CGContextAddRect(context, rect);
		return;
	}

	CGFloat	minX		= CGRectGetMinX(rect);
	CGFloat	maxX		= CGRectGetMaxX(rect);
	CGFloat	minY		= CGRectGetMinY(rect);
	CGFloat	maxY		= CGRectGetMaxY(rect);
	CGFloat	controlX	= radiusX * (1.0 - CORNER_CONTROL_FACTOR);
	CGFloat	controlY	= radiusY * (1.0 - CORNER_CONTROL_FACTOR);

	CGContextMoveToPoint(context, minX + radiusX, maxY);
	CGContextAddCurveToPoint(context, minX + controlX, maxY, minX, maxY - controlY, minX, maxY - radiusY);
	CGContextAddLineToPoint(context, minX, minY + radiusY);
	CGContextAddCurveToPoint(context, minX, minY + controlY, minX + controlX, minY, minX + radiusX, minY);
	CGContextAddLineToPoint(context, maxX - radiusX, minY);
	CGContextAddCurveToPoint(context, maxX - controlX, minY, maxX, minY + controlY, maxX, minY + radiusY);
	CGContextAddLineToPoint(context, maxX, maxY - radiusY);
	CGContextAddCurveToPoint(context, maxX, maxY - controlY, maxX - controlX, maxY, maxX - radiusX, maxY);
	CGContextClosePath(context);

}//end LDrawStepAddRoundedRect


//========== LDrawStepAddOval ==================================================
///
/// @abstract	Adds the oval that fills a rectangle to the context's path.
///
/// @discussion	Four quarters, the first starting an eighth of a turn before
///				the x axis, as AppKit builds an oval.
///
//==============================================================================
void LDrawStepAddOval(CGContextRef context, CGRect rect)
{
	CGFloat	radiusX	= CGRectGetWidth(rect) / 2.0;
	CGFloat	radiusY	= CGRectGetHeight(rect) / 2.0;
	CGFloat	midX	= CGRectGetMidX(rect);
	CGFloat	midY	= CGRectGetMidY(rect);
	CGFloat	angle	= -M_PI_4;

	CGContextMoveToPoint(context, midX + radiusX * cos(angle), midY + radiusY * sin(angle));

	for (NSInteger quarter = 0; quarter < 4; quarter++) {
		CGFloat next = angle + M_PI_2;

		// Each control point lies along the oval's direction at its end.
		CGContextAddCurveToPoint(context,
								 midX + radiusX * (cos(angle) - OVAL_CONTROL_FACTOR * sin(angle)),
								 midY + radiusY * (sin(angle) + OVAL_CONTROL_FACTOR * cos(angle)),
								 midX + radiusX * (cos(next) + OVAL_CONTROL_FACTOR * sin(next)),
								 midY + radiusY * (sin(next) - OVAL_CONTROL_FACTOR * cos(next)),
								 midX + radiusX * cos(next),
								 midY + radiusY * sin(next));
		angle = next;
	}

	CGContextClosePath(context);

}//end LDrawStepAddOval


//========== LDrawStepDrawImage ================================================
///
/// @abstract	Draws a picture upright in a rectangle.
///
/// @discussion	CoreGraphics draws a picture with y running up, so the context
///				is turned over for it.
///
//==============================================================================
void LDrawStepDrawImage(CGContextRef context, CGImageRef image, CGRect rect)
{
	CGContextSaveGState(context);
	CGContextTranslateCTM(context, CGRectGetMinX(rect), CGRectGetMaxY(rect));
	CGContextScaleCTM(context, 1.0, -1.0);
	CGContextDrawImage(context, CGRectMake(0.0, 0.0, CGRectGetWidth(rect), CGRectGetHeight(rect)), image);
	CGContextRestoreGState(context);

}//end LDrawStepDrawImage


// MARK: - FONTS -


//========== LDrawStepFontCreateSystem =========================================
LDrawStepFont LDrawStepFontCreateSystem(CGFloat size, LDrawStepFontWeight weight)
{
	BOOL		isBold	= (weight == LDrawStepFontWeightBold);
	CTFontRef	font	= CTFontCreateUIFontForLanguage(isBold ? kCTFontUIFontEmphasizedSystem : kCTFontUIFontSystem,
														size, NULL);

	if (weight == LDrawStepFontWeightMedium) {
		NSDictionary		*traits		= @{ (id)kCTFontWeightTrait: @(MEDIUM_FONT_WEIGHT) };
		NSDictionary		*attributes	= @{ (id)kCTFontTraitsAttribute: traits };
		CTFontDescriptorRef	 regular	= CTFontCopyFontDescriptor(font);
		CTFontDescriptorRef	 medium		= NULL;

		medium = CTFontDescriptorCreateCopyWithAttributes(regular, (__bridge CFDictionaryRef)attributes);

		CFRelease(font);
		font = CTFontCreateWithFontDescriptor(medium, size, NULL);

		CFRelease(regular);
		CFRelease(medium);
	}

	return (LDrawStepFont){ font, YES };

}//end LDrawStepFontCreateSystem


//========== LDrawStepFontCreateOfFamily =======================================
LDrawStepFont LDrawStepFontCreateOfFamily(NSString *family, BOOL isBold, BOOL isItalic, CGFloat size)
{
	CTFontSymbolicTraits symbolic = (isBold ? kCTFontTraitBold : 0) | (isItalic ? kCTFontTraitItalic : 0);

	NSDictionary *attributes = @{
		(id)kCTFontFamilyNameAttribute:	family,
		(id)kCTFontTraitsAttribute:		@{ (id)kCTFontSymbolicTrait: @(symbolic) },
	};

	CTFontDescriptorRef	 descriptor	= CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)attributes);
	CTFontRef			 font		= CTFontCreateWithFontDescriptor(descriptor, size, NULL);
	NSString			*found		= CFBridgingRelease(CTFontCopyFamilyName(font));

	CFRelease(descriptor);

	// CoreText answers with another family when this one is not installed.
	if ([found caseInsensitiveCompare:family] != NSOrderedSame) {
		CFRelease(font);
		return LDrawStepFontCreateSystem(size, isBold ? LDrawStepFontWeightBold : LDrawStepFontWeightRegular);
	}

	return (LDrawStepFont){ font, NO };

}//end LDrawStepFontCreateOfFamily


//========== LDrawStepFontRelease ==============================================
void LDrawStepFontRelease(LDrawStepFont font)
{
	if (font.font != NULL) {
		CFRelease(font.font);
	}

}//end LDrawStepFontRelease


// MARK: - TEXT -


//========== LineAscent ========================================================
///
/// @abstract	How far under the top of its line a font's baseline is.
///
//==============================================================================
static CGFloat LineAscent(LDrawStepFont font)
{
	return round(CTFontGetAscent(font.font));

}//end LineAscent


//========== LineHeight ========================================================
///
/// @abstract	How tall one line of a font is.
///
/// @discussion	Measured as AppKit measures it, so text sits where an AppKit
///				host puts it.
///
//==============================================================================
static CGFloat LineHeight(LDrawStepFont font)
{
	CGFloat	descent		= CTFontGetDescent(font.font);
	BOOL	roundsUp	= font.isSystemFont && CTFontGetSize(font.font) < SYSTEM_FONT_TALL_LINE_LIMIT;

	return LineAscent(font) + (roundsUp ? ceil(descent) : round(descent));

}//end LineHeight


//========== CreateLine ========================================================
///
/// @abstract	One line of text in a font. The color is only needed to draw
///				the line, so a line made to be measured passes NULL.
///
//==============================================================================
static CTLineRef CreateLine(NSString *text, LDrawStepFont font, CGColorRef _Nullable color) CF_RETURNS_RETAINED
{
	NSMutableDictionary *attributes = [NSMutableDictionary dictionary];

	attributes[(id)kCTFontAttributeName] = (__bridge id)font.font;

	if (color != NULL) {
		attributes[(id)kCTForegroundColorAttributeName] = (__bridge id)color;
	}

	NSAttributedString *string = [[NSAttributedString alloc] initWithString:text attributes:attributes];

	return CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)string);

}//end CreateLine


//========== LineWidth =========================================================
static CGFloat LineWidth(CTLineRef line)
{
	return CTLineGetTypographicBounds(line, NULL, NULL, NULL);

}//end LineWidth


//========== DrawLine ==========================================================
///
/// @abstract	Draws a line of text with its top left corner at a point.
///
//==============================================================================
static void DrawLine(CGContextRef context, CTLineRef line, CGFloat x, CGFloat top, LDrawStepFont font)
{
	// CoreText draws with y running up, so the letters are turned over.
	CGContextSetTextMatrix(context, CGAffineTransformMakeScale(1.0, -1.0));
	CGContextSetTextPosition(context, x, top + LineAscent(font));
	CTLineDraw(line, context);

}//end DrawLine


//========== LDrawStepTextSize =================================================
CGSize LDrawStepTextSize(NSString *text, LDrawStepFont font)
{
	CTLineRef	line	= CreateLine(text, font, NULL);
	CGSize		size	= CGSizeMake(LineWidth(line), LineHeight(font));

	CFRelease(line);

	return size;

}//end LDrawStepTextSize


//========== LDrawStepDrawTextCentered =========================================
void LDrawStepDrawTextCentered(CGContextRef context, NSString *text, CGRect rect, LDrawStepFont font,
							   const double *rgba)
{
	CGColorRef	color	= LDrawStepColorCreateRGBA(rgba);
	CTLineRef	line	= CreateLine(text, font, color);
	CGFloat		x		= CGRectGetMidX(rect) - LineWidth(line) / 2.0;
	CGFloat		top		= CGRectGetMidY(rect) - LineHeight(font) / 2.0;

	DrawLine(context, line, x, top, font);

	CFRelease(line);
	CGColorRelease(color);

}//end LDrawStepDrawTextCentered


//========== LDrawStepDrawTextInRect ===========================================
void LDrawStepDrawTextInRect(CGContextRef context, NSString *text, CGRect rect, LDrawStepFont font,
							 const double *rgba)
{
	CGColorRef	color	= LDrawStepColorCreateRGBA(rgba);
	CTLineRef	line	= CreateLine(text, font, color);
	CGFloat		height	= LineHeight(font);
	CGFloat		top		= CGRectGetMinY(rect);

	if (LineWidth(line) > CGRectGetWidth(rect)) {
		CTLineRef	ellipsis	= CreateLine(@"…", font, color);
		CTLineRef	shortened	= CTLineCreateTruncatedLine(line, CGRectGetWidth(rect), kCTLineTruncationEnd, ellipsis);

		CFRelease(ellipsis);

		// NULL when not even the ellipsis fits. The whole line is drawn then.
		if (shortened != NULL) {
			CFRelease(line);
			line = shortened;
		}
	}

	// A rect too low for the line holds it at its top.
	if (height < CGRectGetHeight(rect)) {
		top += (CGRectGetHeight(rect) - height) / 2.0;
	}

	DrawLine(context, line, CGRectGetMinX(rect) + (CGRectGetWidth(rect) - LineWidth(line)) / 2.0, top, font);

	CFRelease(line);
	CGColorRelease(color);

}//end LDrawStepDrawTextInRect
