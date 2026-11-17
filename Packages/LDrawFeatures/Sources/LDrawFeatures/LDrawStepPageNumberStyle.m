//==============================================================================
//
//  File:       LDrawStepPageNumberStyle.m
//  Package:    LDrawFeatures
//
//  Purpose:    Reads how the page's number looks on LPub3D's page, and where
//              it goes.
//
//  Created by Sergey Slobodenyuk on 2026-10-19.
//
//==============================================================================

#import <LDrawFeatures/LDrawStepPageNumberStyle.h>

#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LPubPageNumberDisplay.h>
#import <LDrawCore/LPubPlacement.h>
#import <LDrawFeatures/LDrawStepPartListPolicy.h>

#import "LDrawStepCalloutContent.h"
#import "LDrawStepStyleInternal.h"


/// LPub3D's page number for a file that says nothing: bold, 24 dots high.
static const double DEFAULT_SIZE = 24.0;


//========== FindSwitch() ======================================================
///
/// @abstract	The PAGE line of one kind that turns the number on or off, or
/// 			nil for none.
///
//==============================================================================
static LPubPageNumberDisplay *FindSwitch(LDrawStepStyleLookup lookup, LPubPageNumberSwitch kind)
{
	return lookup(^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubPageNumberDisplay class]]
			&& ((LPubPageNumberDisplay *)directive).kind == kind;
	});

}//end FindSwitch


//========== MirroredPosition() ================================================
///
/// @abstract	The place on the other side of the page, left for right. LPub3D
/// 			puts the number of an even page there when the file asks.
///
//==============================================================================
static LPubPlacementPosition MirroredPosition(LPubPlacementPosition position)
{
	switch (position) {
		case LPubPlacementPositionTopLeft:		return LPubPlacementPositionTopRight;
		case LPubPlacementPositionTopRight:		return LPubPlacementPositionTopLeft;
		case LPubPlacementPositionLeft:			return LPubPlacementPositionRight;
		case LPubPlacementPositionRight:		return LPubPlacementPositionLeft;
		case LPubPlacementPositionBottomLeft:	return LPubPlacementPositionBottomRight;
		case LPubPlacementPositionBottomRight:	return LPubPlacementPositionBottomLeft;
		default:								return position;
	}

}//end MirroredPosition


@implementation LDrawStepPageNumberStyle

//---------- styleForVisibleStepOfModel: -----------------------------[static]--
+ (nullable instancetype) styleForVisibleStepOfModel:(LDrawModel *)model
{
	LDrawStep *step = [model visibleStep];

	LDrawStepStyleLookup lookup = ^id (BOOL (NS_NOESCAPE ^matching)(LDrawDirective *)) {
		return [LDrawStepPartListPolicy directiveInForceForStep:step excluding:nil matching:matching];
	};

	LPubPageNumberDisplay *display = FindSwitch(lookup, LPubPageNumberSwitchDisplay);

	if (display != nil && display.isOn == NO) {
		return nil;
	}

	return [[self alloc] initWithLookup:lookup model:model];

}//end styleForVisibleStepOfModel:


//========== initWithLookup:model: =============================================
- (instancetype) initWithLookup:(LDrawStepStyleLookup)lookup model:(LDrawModel *)model
{
	self = [super init];
	if (self == nil) {
		return nil;
	}

	double unit			= [LDrawStepPartListPolicy inchesPerUnitInModel:model];
	double dotInches	= [LDrawStepPartListPolicy inchesPerDotInModel:model];

	self->_text			= LDrawStepReadText(lookup, LPubStyleBranchPage, LPubCalloutPartPageNumber, DEFAULT_SIZE,
											dotInches);
	self->_margins		= LDrawStepReadMargins(lookup, LPubStyleBranchPage, LPubCalloutPartPageNumber, unit);
	self->_pageMargins	= LDrawStepReadMargins(lookup, LPubStyleBranchPage, LPubCalloutPartBox, unit);
	self->_togglesSides	= FindSwitch(lookup, LPubPageNumberSwitchToggle).isOn;

	self->_placement = lookup(^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubPlacement class]]
			&& ((LPubPlacement *)directive).branch == LPubPlacementBranchPageNumber;
	});

	return self;

}//end initWithLookup:model:


//========== rectForSize:pageNumber:onPage:pointsPerInch: ======================
- (Box2) rectForSize:(Size2)size
		  pageNumber:(NSUInteger)pageNumber
			  onPage:(Box2)pageRect
	   pointsPerInch:(double)pointsPerInch
{
	LPubPlacement			*placement	= self.placement;
	LPubPlacementPosition	 position	= LPubPlacementPositionBottomRight;
	Point2					 offset		= ZeroPoint2;
	Size2					 margin		= V2MakeSize(MAX(self.pageMargins.width, self.margins.width) * pointsPerInch,
													 MAX(self.pageMargins.height, self.margins.height) * pointsPerInch);

	if (placement.isInsidePage) {
		position	= placement.position;
		offset		= placement.offset;
	}

	if (self.togglesSides && pageNumber % 2 == 0) {
		position = MirroredPosition(position);
	}

	Point2 origin = [LDrawStepCalloutBox originForSize:size
											  position:position
										 justification:LPubPlacementPositionCenter
											  isInside:YES
												anchor:pageRect
												margin:margin];

	origin.x += V2BoxWidth(pageRect) * offset.x;
	origin.y += V2BoxHeight(pageRect) * offset.y;

	return V2MakeBox(origin.x, origin.y, size.width, size.height);

}//end rectForSize:pageNumber:onPage:pointsPerInch:

@end
