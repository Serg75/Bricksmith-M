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

#import "LDrawStepPageNumberStyle.h"

#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LPubPageNumberDisplay.h>
#import <LDrawCore/LPubPlacement.h>
#import <LDrawFeatures/LDrawStepPartListPolicy.h>

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
	self->_togglesSides	= FindSwitch(lookup, LPubPageNumberSwitchToggle).isOn;

	self->_placement = lookup(^BOOL(LDrawDirective *directive) {
		return [directive isKindOfClass:[LPubPlacement class]]
			&& ((LPubPlacement *)directive).branch == LPubPlacementBranchPageNumber;
	});

	return self;

}//end initWithLookup:model:

@end
