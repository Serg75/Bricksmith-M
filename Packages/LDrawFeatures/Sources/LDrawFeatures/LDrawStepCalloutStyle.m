//==============================================================================
//
//  File:       LDrawStepCalloutStyle.m
//  Package:    LDrawFeatures
//
//  Purpose:    Works out how one callout's box looks on LPub3D's page.
//
//  Notes:      A file writes lengths in its own unit, radii in dots, and font
//              sizes as dots too. All of them come out of here in page inches.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawFeatures/LDrawStepCalloutStyle.h>

#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LPubCalloutBackground.h>
#import <LDrawCore/LPubCalloutFont.h>
#import <LDrawCore/LPubCalloutMargins.h>
#import <LDrawCore/LPubCalloutSeparator.h>
#import <LDrawCore/LPubCalloutSubmodelColor.h>

#import <LDrawFeatures/LDrawStepCallout.h>
#import <LDrawFeatures/LDrawStepPartListPolicy.h>

#import "LDrawStepStyleInternal.h"


/// LPub3D's fonts for a file that names none, and its margin, in inches.
static NSString * const	DEFAULT_FONT_FAMILY			= @"Arial";
static const double		DEFAULT_STEP_NUMBER_SIZE	= 36.0;
static const double		DEFAULT_COUNT_SIZE			= 24.0;
static const double		DEFAULT_MARGIN				= 0.05;

/// How wide a digit is and how tall a line is, as a share of the font's size,
/// and the dots Qt keeps clear around a piece of text.
static const double		CHARACTER_WIDTH_FRACTION	= 0.56;
static const double		LINE_HEIGHT_FRACTION		= 1.15;
static const double		TEXT_PADDING_DOTS			= 4.0;


@interface LDrawStepCalloutText ()

- (instancetype) initWithFont:(nullable LPubCalloutFont *)font
						color:(nullable LPubCalloutFont *)color
				  defaultSize:(double)defaultSize
					dotInches:(double)dotInches;

@end


// MARK: - READING THE LINES -


//========== LDrawStepReadBorder() =============================================
LDrawStepBorderStyle LDrawStepReadBorder(LDrawStepStyleLookup lookup, LPubStyleBranch branch,
										 double unit, double dotInches)
{
	LPubCalloutBorder *border = lookup(^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubCalloutBorder class]]
			&& ((LPubCalloutBorder *)directive).branch == branch;
	});
	LPubCalloutBorder *spaced = lookup(^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubCalloutBorder class]]
			&& ((LPubCalloutBorder *)directive).branch == branch
			&& ((LPubCalloutBorder *)directive).hasMargins;
	});

	// A border with no line behind it is LPub3D's own, which is in inches
	// whatever unit the file is in.
	double lineUnit		= (border != nil) ? unit : 1.0;
	double marginUnit	= (spaced != nil) ? unit : 1.0;

	border = border ?: [LPubCalloutBorder new];
	spaced = spaced ?: [LPubCalloutBorder new];

	LDrawStepBorderStyle style;

	style.shape				= border.shape;
	style.lineStyle			= border.lineStyle;
	style.color				= border.color;
	style.thickness			= (border.shape == LPubBorderShapeNone) ? 0.0 : border.thickness * lineUnit;
	style.cornerRadius		= (border.shape == LPubBorderShapeRound) ? border.radius * dotInches : 0.0;
	style.margins			= V2MakeSize(spaced.margins.width * marginUnit, spaced.margins.height * marginUnit);
	style.hidesArrowTips	= border.hidesArrowTips;

	return style;

}//end LDrawStepReadBorder


//========== LDrawStepReadMargins() ============================================
Size2 LDrawStepReadMargins(LDrawStepStyleLookup lookup, LPubStyleBranch branch, LPubCalloutPart part, double unit)
{
	LPubCalloutMargins *margins = lookup(^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubCalloutMargins class]]
			&& ((LPubCalloutMargins *)directive).branch == branch
			&& ((LPubCalloutMargins *)directive).part == part;
	});

	if (margins == nil) {
		return V2MakeSize(DEFAULT_MARGIN, DEFAULT_MARGIN);
	}

	return V2MakeSize(margins.margins.width * unit, margins.margins.height * unit);

}//end LDrawStepReadMargins


//========== LDrawStepReadBackground() =========================================
LPubCalloutBackground *LDrawStepReadBackground(LDrawStepStyleLookup lookup, LPubStyleBranch branch)
{
	return lookup(^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubCalloutBackground class]]
			&& ((LPubCalloutBackground *)directive).branch == branch;
	});

}//end LDrawStepReadBackground


//========== FindFontLine() ====================================================
///
/// @abstract	The FONT line of one branch and part in force, or with `isColor`
/// 			its FONT_COLOR line. Nil for none.
///
//==============================================================================
static LPubCalloutFont *FindFontLine(LDrawStepStyleLookup lookup, LPubStyleBranch branch, LPubCalloutPart part,
									 BOOL isColor)
{
	return lookup(^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubCalloutFont class]]
			&& ((LPubCalloutFont *)directive).branch == branch
			&& ((LPubCalloutFont *)directive).part == part
			&& ((LPubCalloutFont *)directive).isColor == isColor;
	});

}//end FindFontLine


//========== LDrawStepReadText() ===============================================
LDrawStepCalloutText *LDrawStepReadText(LDrawStepStyleLookup lookup, LPubStyleBranch branch,
										LPubCalloutPart part, double defaultSize, double dotInches)
{
	LPubCalloutFont *font	= FindFontLine(lookup, branch, part, NO);
	LPubCalloutFont *color	= FindFontLine(lookup, branch, part, YES);

	return [[LDrawStepCalloutText alloc] initWithFont:font color:color defaultSize:defaultSize dotInches:dotInches];

}//end LDrawStepReadText


//========== LDrawStepReadGivenText() ==========================================
LDrawStepCalloutText *LDrawStepReadGivenText(LDrawStepStyleLookup lookup, LPubStyleBranch branch,
											 LPubCalloutPart part, double dotInches)
{
	LPubCalloutFont *font = FindFontLine(lookup, branch, part, NO);

	if (font == nil) {
		return nil;
	}

	LPubCalloutFont *color = FindFontLine(lookup, branch, part, YES);

	return [[LDrawStepCalloutText alloc] initWithFont:font color:color defaultSize:font.size dotInches:dotInches];

}//end LDrawStepReadGivenText


//========== LDrawStepReadTextColor() ==========================================
BOOL LDrawStepReadTextColor(LDrawStepStyleLookup lookup, LPubStyleBranch branch, LPubCalloutPart part,
							LPubColorComponents *outColor)
{
	LPubCalloutFont *color = FindFontLine(lookup, branch, part, YES);

	if (color == nil) {
		return NO;
	}

	*outColor = color.color;
	return YES;

}//end LDrawStepReadTextColor


// MARK: -

@implementation LDrawStepCalloutText
{
	/// The clear room around the text, in page inches.
	double _padding;
}

//========== initWithFont:color:defaultSize:dotInches: =========================
///
/// @abstract	The text a FONT line and a FONT_COLOR line describe. Either may
/// 			be nil.
///
//==============================================================================
- (instancetype) initWithFont:(nullable LPubCalloutFont *)font
						color:(nullable LPubCalloutFont *)color
				  defaultSize:(double)defaultSize
					dotInches:(double)dotInches
{
	self = [super init];
	if (self) {
		self->_fontFamily	= (font != nil) ? [font.family copy] : DEFAULT_FONT_FAMILY;
		self->_fontSize		= ((font != nil) ? font.size : defaultSize) * dotInches;
		self->_isBold		= (font != nil) ? font.isBold : YES;
		self->_isItalic		= (font != nil) ? font.isItalic : NO;
		self->_color		= (color != nil) ? color.color : LPubColorBlack;
		self->_padding		= TEXT_PADDING_DOTS * dotInches;
	}
	return self;

}//end initWithFont:color:defaultSize:dotInches:


//========== sizeForCharacterCount: ============================================
- (Size2) sizeForCharacterCount:(NSUInteger)count
{
	return V2MakeSize(self.fontSize * CHARACTER_WIDTH_FRACTION * count + 2.0 * self->_padding,
					  self.fontSize * LINE_HEIGHT_FRACTION + 2.0 * self->_padding);

}//end sizeForCharacterCount:

@end


// MARK: -

@implementation LDrawStepCalloutStyle

//---------- styleForCallout: ----------------------------------------[static]--
+ (instancetype) styleForCallout:(LDrawStepCallout *)callout
{
	return [[self alloc] initWithCallout:callout];

}//end styleForCallout:


//========== initWithCallout: ==================================================
- (instancetype) initWithCallout:(LDrawStepCallout *)callout
{
	self = [super init];
	if (self == nil) {
		return nil;
	}

	LDrawModel	*model		= [callout.step enclosingModel];
	double		 unit		= [LDrawStepPartListPolicy inchesPerUnitInModel:model];
	double		 dotInches	= [LDrawStepPartListPolicy inchesPerDotInModel:model];

	LDrawStepStyleLookup lookup = ^id (BOOL (NS_NOESCAPE ^matching)(LDrawDirective *)) {
		return [callout directiveInForceMatching:matching];
	};

	LDrawStepBorderStyle border = LDrawStepReadBorder(lookup, LPubStyleBranchCallout, unit, dotInches);

	self->_borderShape		= border.shape;
	self->_borderLineStyle	= border.lineStyle;
	self->_borderColor		= border.color;
	self->_borderThickness	= border.thickness;
	self->_cornerRadius		= border.cornerRadius;
	self->_hidesArrowTips	= border.hidesArrowTips;
	self->_borderMargins	= border.margins;

	[self readFillOfCallout:callout background:LDrawStepReadBackground(lookup, LPubStyleBranchCallout) inModel:model];
	[self readSeparatorOfCallout:callout unit:unit];

	self->_margins				= LDrawStepReadMargins(lookup, LPubStyleBranchCallout, LPubCalloutPartBox, unit);
	self->_assemblyMargins		= LDrawStepReadMargins(lookup, LPubStyleBranchCallout, LPubCalloutPartAssembly, unit);
	self->_partsListMargins		= LDrawStepReadMargins(lookup, LPubStyleBranchCallout, LPubCalloutPartPartsList, unit);
	self->_stepNumberMargins	= LDrawStepReadMargins(lookup, LPubStyleBranchCallout, LPubCalloutPartStepNumber, unit);
	self->_countMargins			= LDrawStepReadMargins(lookup, LPubStyleBranchCallout, LPubCalloutPartInstanceCount,
													   unit);

	self->_stepNumberText	= LDrawStepReadText(lookup, LPubStyleBranchCallout, LPubCalloutPartStepNumber,
												DEFAULT_STEP_NUMBER_SIZE, dotInches);
	self->_countText		= LDrawStepReadText(lookup, LPubStyleBranchCallout, LPubCalloutPartInstanceCount,
												DEFAULT_COUNT_SIZE, dotInches);

	return self;

}//end initWithCallout:


//========== readFillOfCallout:background:inModel: =============================
///
/// @abstract	Takes the fill from the BACKGROUND line in force.
///
/// @discussion	With no such line the fill is the color for the submodel's
/// 			depth: a callout is one level deeper than the model it is in. A
/// 			picture or a gradient cannot be drawn here, and gets that color
/// 			too.
///
//==============================================================================
- (void) readFillOfCallout:(LDrawStepCallout *)callout
				background:(nullable LPubCalloutBackground *)background
				   inModel:(nullable LDrawModel *)model
{
	if (background.kind == LPubCalloutBackgroundKindTransparent) {
		self->_hasFill = NO;
		return;
	}

	self->_hasFill = YES;

	if (background.kind == LPubCalloutBackgroundKindColor) {
		self->_fillColor = background.color;
		return;
	}

	LPubCalloutSubmodelColor *colors = [callout directiveInForceMatching:^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubCalloutSubmodelColor class]];
	}];
	NSUInteger level = [LDrawStepPartListPolicy submodelDepthOfModel:model] + 1;

	self->_fillColor = (colors != nil) ? [colors colorAtLevel:level]
									   : [LPubCalloutSubmodelColor defaultColorAtLevel:level];

}//end readFillOfCallout:background:inModel:


//========== readSeparatorOfCallout:unit: ======================================
- (void) readSeparatorOfCallout:(LDrawStepCallout *)callout unit:(double)unit
{
	LPubCalloutSeparator *separator = [callout directiveInForceMatching:^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubCalloutSeparator class]];
	}];

	// LPub3D's own line is in inches whatever unit the file is in.
	double lineUnit = (separator != nil) ? unit : 1.0;

	separator = separator ?: [LPubCalloutSeparator new];

	self->_separatorThickness	= separator.thickness * lineUnit;
	self->_separatorColor		= separator.color;
	self->_separatorMargins		= V2MakeSize(separator.margins.width * lineUnit, separator.margins.height * lineUnit);

}//end readSeparatorOfCallout:unit:

@end
