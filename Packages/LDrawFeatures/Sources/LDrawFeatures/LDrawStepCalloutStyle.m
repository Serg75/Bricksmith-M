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


//========== MarginsOfPart() ===================================================
///
/// @abstract	The MARGINS in force for one thing in a callout, in inches, or
/// 			LPub3D's margin. `unit` is how many inches the file's unit is.
///
//==============================================================================
static Size2 MarginsOfPart(LDrawStepCallout *callout, LPubCalloutPart part, double unit)
{
	LPubCalloutMargins *margins = [callout directiveInForceMatching:^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubCalloutMargins class]] && ((LPubCalloutMargins *)directive).part == part;
	}];

	if (margins == nil) {
		return V2MakeSize(DEFAULT_MARGIN, DEFAULT_MARGIN);
	}

	return V2MakeSize(margins.margins.width * unit, margins.margins.height * unit);

}//end MarginsOfPart


// MARK: -

@implementation LDrawStepCalloutText
{
	/// The clear room around the text, in page inches.
	double _padding;
}

//========== initWithFont:color:defaultSize:dotInches: =========================
///
/// @abstract	The text a FONT line and a FONT_COLOR line describe. Either may
/// 			be nil. `defaultSize` is LPub3D's size for a file with no FONT
/// 			line, in dots, and such text is bold.
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

	[self readBorderOfCallout:callout unit:unit dotInches:dotInches];
	[self readFillOfCallout:callout inModel:model];
	[self readSeparatorOfCallout:callout unit:unit];

	self->_margins				= MarginsOfPart(callout, LPubCalloutPartBox, unit);
	self->_assemblyMargins		= MarginsOfPart(callout, LPubCalloutPartAssembly, unit);
	self->_partsListMargins		= MarginsOfPart(callout, LPubCalloutPartPartsList, unit);
	self->_stepNumberMargins	= MarginsOfPart(callout, LPubCalloutPartStepNumber, unit);
	self->_countMargins			= MarginsOfPart(callout, LPubCalloutPartInstanceCount, unit);

	self->_stepNumberText	= [LDrawStepCalloutStyle textOfPart:LPubCalloutPartStepNumber
													  inCallout:callout
													defaultSize:DEFAULT_STEP_NUMBER_SIZE
													  dotInches:dotInches];
	self->_countText		= [LDrawStepCalloutStyle textOfPart:LPubCalloutPartInstanceCount
													  inCallout:callout
													defaultSize:DEFAULT_COUNT_SIZE
													  dotInches:dotInches];

	return self;

}//end initWithCallout:


//========== readBorderOfCallout:unit:dotInches: ===============================
///
/// @abstract	Takes the outline from the BORDER line in force.
///
/// @discussion	LPub3D keeps the margins it had when a line gives none, so they
/// 			come from the last line in force that has them.
///
//==============================================================================
- (void) readBorderOfCallout:(LDrawStepCallout *)callout unit:(double)unit dotInches:(double)dotInches
{
	LPubCalloutBorder *border = [callout directiveInForceMatching:^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubCalloutBorder class]];
	}];
	LPubCalloutBorder *spaced = [callout directiveInForceMatching:^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubCalloutBorder class]] && ((LPubCalloutBorder *)directive).hasMargins;
	}];

	// A border with no line behind it is LPub3D's own, which is in inches
	// whatever unit the file is in.
	double lineUnit		= (border != nil) ? unit : 1.0;
	double marginUnit	= (spaced != nil) ? unit : 1.0;

	border = border ?: [LPubCalloutBorder new];
	spaced = spaced ?: [LPubCalloutBorder new];

	self->_borderShape		= border.shape;
	self->_borderLineStyle	= border.lineStyle;
	self->_borderColor		= border.color;
	self->_borderThickness	= (border.shape == LPubBorderShapeNone) ? 0.0 : border.thickness * lineUnit;
	self->_cornerRadius		= (border.shape == LPubBorderShapeRound) ? border.radius * dotInches : 0.0;
	self->_hidesArrowTips	= border.hidesArrowTips;
	self->_borderMargins	= V2MakeSize(spaced.margins.width * marginUnit, spaced.margins.height * marginUnit);

}//end readBorderOfCallout:unit:dotInches:


//========== readFillOfCallout:inModel: ========================================
///
/// @abstract	Takes the fill from the BACKGROUND line in force.
///
/// @discussion	With no such line the fill is the color for the submodel's
/// 			depth: a callout is one level deeper than the model it is in. A
/// 			picture or a gradient cannot be drawn here, and gets that color
/// 			too.
///
//==============================================================================
- (void) readFillOfCallout:(LDrawStepCallout *)callout inModel:(nullable LDrawModel *)model
{
	LPubCalloutBackground *background = [callout directiveInForceMatching:^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubCalloutBackground class]];
	}];

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

}//end readFillOfCallout:inModel:


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


//---------- textOfPart:inCallout:defaultSize:dotInches: -------------[static]--
///
/// @abstract	The FONT and FONT_COLOR in force for one kind of text.
///
//------------------------------------------------------------------------------
+ (LDrawStepCalloutText *) textOfPart:(LPubCalloutPart)part
							inCallout:(LDrawStepCallout *)callout
						  defaultSize:(double)defaultSize
							dotInches:(double)dotInches
{
	LPubCalloutFont *font = [callout directiveInForceMatching:^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubCalloutFont class]]
			&& ((LPubCalloutFont *)directive).part == part
			&& ((LPubCalloutFont *)directive).isColor == NO;
	}];
	LPubCalloutFont *color = [callout directiveInForceMatching:^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubCalloutFont class]]
			&& ((LPubCalloutFont *)directive).part == part
			&& ((LPubCalloutFont *)directive).isColor;
	}];

	return [[LDrawStepCalloutText alloc] initWithFont:font color:color defaultSize:defaultSize dotInches:dotInches];

}//end textOfPart:inCallout:defaultSize:dotInches:

@end
