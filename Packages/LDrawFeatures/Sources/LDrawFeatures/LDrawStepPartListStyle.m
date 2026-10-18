//==============================================================================
//
//  File:       LDrawStepPartListStyle.m
//  Package:    LDrawFeatures
//
//  Purpose:    Works out how the visible step's parts list looks on LPub3D's
//              page, and where it goes.
//
//  Notes:      A file writes lengths in its own unit, radii in dots, and font
//              sizes as dots too. All of them come out of here in page inches.
//
//  Created by Sergey Slobodenyuk on 2026-10-15.
//
//==============================================================================

#import <LDrawFeatures/LDrawStepPartListStyle.h>

#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LPubCalloutBackground.h>
#import <LDrawCore/LPubPlacement.h>

#import "LDrawStepStyleInternal.h"


/// LPub3D's parts list for a file that says nothing: a white fill and a bold
/// count 36 dots high.
static const LPubColorComponents	DEFAULT_FILL		= {1.0, 1.0, 1.0, 1.0};
static const double					DEFAULT_COUNT_SIZE	= 36.0;


@implementation LDrawStepPartListStyle

//---------- styleForVisibleStepOfModel: -----------------------------[static]--
+ (instancetype) styleForVisibleStepOfModel:(nullable LDrawModel *)model
{
	return [[self alloc] initWithModel:model];

}//end styleForVisibleStepOfModel:


//========== initWithModel: ====================================================
- (instancetype) initWithModel:(nullable LDrawModel *)model
{
	self = [super init];
	if (self == nil) {
		return nil;
	}

	LDrawStep	*step		= [model visibleStep];
	double		 unit		= [LDrawStepPartListPolicy inchesPerUnitInModel:model];
	double		 dotInches	= [LDrawStepPartListPolicy inchesPerDotInModel:model];

	LDrawStepStyleLookup lookup = ^id (BOOL (NS_NOESCAPE ^matching)(LDrawDirective *)) {
		return [LDrawStepPartListPolicy directiveInForceForStep:step excluding:nil matching:matching];
	};

	LDrawStepBorderStyle border = LDrawStepReadBorder(lookup, LPubStyleBranchPartsList, unit, dotInches);

	self->_borderShape		= border.shape;
	self->_borderLineStyle	= border.lineStyle;
	self->_borderColor		= border.color;
	self->_borderThickness	= border.thickness;
	self->_cornerRadius		= border.cornerRadius;
	self->_borderMargins	= border.margins;

	// A picture, a gradient or a submodel color cannot be drawn here, and gets
	// LPub3D's white.
	LPubCalloutBackground *fill = LDrawStepReadBackground(lookup, LPubStyleBranchPartsList);

	self->_hasFill		= (fill.kind != LPubCalloutBackgroundKindTransparent);
	self->_fillColor	= (fill.kind == LPubCalloutBackgroundKindColor) ? fill.color : DEFAULT_FILL;

	// Only a color is drawn on the page. Anything else leaves the host's.
	LPubCalloutBackground *page = LDrawStepReadBackground(lookup, LPubStyleBranchPage);

	self->_hasPageColor	= (page.kind == LPubCalloutBackgroundKindColor);
	self->_pageColor	= self->_hasPageColor ? page.color : DEFAULT_FILL;

	self->_margins		= LDrawStepReadMargins(lookup, LPubStyleBranchPartsList, LPubCalloutPartBox, unit);
	self->_pageMargins	= LDrawStepReadMargins(lookup, LPubStyleBranchPage, LPubCalloutPartBox, unit);
	self->_countText	= LDrawStepReadText(lookup, LPubStyleBranchPartsList, LPubCalloutPartInstanceCount,
											DEFAULT_COUNT_SIZE, dotInches);

	// A file with neither line keeps Bricksmith's own badge.
	self->_annotationText		= LDrawStepReadGivenText(lookup, LPubStyleBranchPartsList, LPubCalloutPartAnnotation,
														 dotInches);
	self->_hasAnnotationColor	= LDrawStepReadTextColor(lookup, LPubStyleBranchPartsList, LPubCalloutPartAnnotation,
														 &self->_annotationColor);

	self->_placement = lookup(^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubPlacement class]]
			&& ((LPubPlacement *)directive).branch == LPubPlacementBranchPartsList;
	});

	return self;

}//end initWithModel:


// MARK: - APPLYING -


//========== metricsFromMetrics:pointsPerPageInch: =============================
///
/// @abstract	The padding is the border's margin and line, as LPub3D pads a
/// 			list. The metrics have one padding for both sides, so it is the
/// 			larger of the two.
///
//==============================================================================
- (LDrawStepPartListMetrics) metricsFromMetrics:(LDrawStepPartListMetrics)metrics
							  pointsPerPageInch:(double)pointsPerPageInch
{
	double	padding	= MAX(self.borderMargins.width, self.borderMargins.height) + self.borderThickness;
	Size2	one		= [self.countText sizeForCharacterCount:1];
	Size2	two		= [self.countText sizeForCharacterCount:2];

	// A size badge is written in its own font, or as big as a count, in a pill
	// a little taller.
	LDrawStepCalloutText	*badgeText	= self.annotationText ?: self.countText;
	Size2					 badgeOne	= [badgeText sizeForCharacterCount:1];
	Size2					 badgeTwo	= [badgeText sizeForCharacterCount:2];
	double					 badgeExtra	= metrics.annotationHeight - metrics.labelHeight;

	metrics.framePadding				= padding * pointsPerPageInch;
	metrics.labelHeight					= one.height * pointsPerPageInch;
	metrics.labelCharacterWidth			= (two.width - one.width) * pointsPerPageInch;
	metrics.annotationHeight			= badgeOne.height * pointsPerPageInch + badgeExtra;
	metrics.annotationCharacterWidth	= (badgeTwo.width - badgeOne.width) * pointsPerPageInch;

	return metrics;

}//end metricsFromMetrics:pointsPerPageInch:


//========== chromeFromChrome:pointsPerPageInch: ===============================
- (LDrawStepPartListChrome) chromeFromChrome:(LDrawStepPartListChrome)chrome
						   pointsPerPageInch:(double)pointsPerPageInch
{
	LPubColorComponentsGetRGBA(self.borderColor, chrome.borderRGBA);
	LPubColorComponentsGetRGBA(self.fillColor, chrome.fillRGBA);
	LPubColorComponentsGetRGBA(self.countText.color, chrome.labelRGBA);

	chrome.borderWidth		= self.borderThickness * pointsPerPageInch;
	chrome.cornerRadius		= self.cornerRadius * pointsPerPageInch;
	chrome.borderLineStyle	= self.borderLineStyle;
	chrome.fill				= self.hasFill ? LDrawStepPartListFillColor : LDrawStepPartListFillClear;
	chrome.labelPointSize	= self.countText.fontSize * pointsPerPageInch;

	if (self.annotationText != nil) {
		chrome.annotationPointSize = self.annotationText.fontSize * pointsPerPageInch;
	}
	if (self.hasAnnotationColor) {
		LPubColorComponentsGetRGBA(self.annotationColor, chrome.annotationTextRGBA);
	}

	return chrome;

}//end chromeFromChrome:pointsPerPageInch:

@end
