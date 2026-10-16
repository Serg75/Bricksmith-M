//==============================================================================
//
//  File:       LPubCalloutBackground.m
//  Package:    LDrawCore
//
//  Purpose:    What a callout's box, a parts list or the page is filled with.
//
//              Line format, after 0 !LPUB (CALLOUT|PLI|PAGE) BACKGROUND
//              [GLOBAL|LOCAL]:
//              TRANSPARENT | TRANS
//              SUBMODEL_BACKGROUND_COLOR
//              COLOR <color>
//              PICTURE <file> [STRETCH]
//              GRADIENT <mode> <spread> <type> <width> <height> <angle>
//                  <points> <stops>
//
//              A line in any other form stays a plain LPubCommand. A parsed
//              line is written back as it was read.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubCalloutBackground.h>

#import <LDrawCore/LDrawKeywords.h>


static NSString * const LPUB_BACKGROUND_TRANSPARENT	= @"TRANSPARENT";
static NSString * const LPUB_BACKGROUND_TRANS		= @"TRANS";
static NSString * const LPUB_BACKGROUND_COLOR		= @"COLOR";
static NSString * const LPUB_BACKGROUND_PICTURE		= @"PICTURE";
static NSString * const LPUB_BACKGROUND_STRETCH		= @"STRETCH";
static NSString * const LPUB_BACKGROUND_GRADIENT	= @"GRADIENT";

/// How many values follow GRADIENT.
static const NSUInteger GRADIENT_VALUE_COUNT = 8;


@implementation LPubCalloutBackground


// MARK: - INITIALIZATION -


//========== init ==============================================================
- (id) init
{
	self = [super init];
	if (self) {
		self->_kind		= LPubCalloutBackgroundKindSubmodelColor;
		self->_color	= LPubColorBlack;
	}
	return self;

}//end init


//---------- lpubCommandInstance: ------------------------------------[static]--
///
/// @abstract	Builds the command from the line's words, or nil if the
/// 			line is not this command.
///
//------------------------------------------------------------------------------
+ (LPubCommand *) lpubCommandInstance:(NSArray<NSString *> *)parameters
{
	LPubStyleBranch branch = LPubStyleBranchCallout;

	if (parameters.count < 3
		|| [LPubCommand getStyleBranch:&branch fromToken:parameters[0]] == NO
		|| [parameters[1] isEqualToString:LPUB_CALLOUT_BACKGROUND] == NO) {
		return nil;
	}

	NSUInteger		index	= 2;
	LPubMetaScope	scope	= [LPubCommand scopeInParameters:parameters index:&index];

	if (index >= parameters.count) {
		return nil;
	}

	NSString					*word	= parameters[index];
	NSUInteger					 count	= parameters.count - index;
	LPubCalloutBackgroundKind	 kind	= LPubCalloutBackgroundKindPicture;
	LPubColorComponents			 color	= LPubColorBlack;

	if (count == 1 && ([word isEqualToString:LPUB_BACKGROUND_TRANSPARENT]
					   || [word isEqualToString:LPUB_BACKGROUND_TRANS])) {
		kind = LPubCalloutBackgroundKindTransparent;
	}
	else if (count == 1 && [word isEqualToString:LPUB_CALLOUT_SUBMODEL_COLOR]) {
		kind = LPubCalloutBackgroundKindSubmodelColor;
	}
	else if (count == 2 && [word isEqualToString:LPUB_BACKGROUND_COLOR]) {
		kind = LPubCalloutBackgroundKindColor;

		if (LPubColorComponentsFromString(parameters[index + 1], &color) == NO) {
			color = LPubColorBlack;
		}
	}
	else if (count == 1 + GRADIENT_VALUE_COUNT && [word isEqualToString:LPUB_BACKGROUND_GRADIENT]) {
		kind = LPubCalloutBackgroundKindGradient;
	}
	else if (count == 1) {
		// One other word is the name of a picture. A keyword with its value
		// missing is not.
		if ([@[LPUB_BACKGROUND_COLOR, LPUB_BACKGROUND_PICTURE, LPUB_BACKGROUND_GRADIENT] containsObject:word]) {
			return nil;
		}
		kind = LPubCalloutBackgroundKindPicture;
	}
	else if ([word isEqualToString:LPUB_BACKGROUND_PICTURE] == NO
			 || count > 3
			 || (count == 3 && [parameters[index + 2] isEqualToString:LPUB_BACKGROUND_STRETCH] == NO)) {
		return nil;
	}

	LPubCalloutBackground *command = [LPubCalloutBackground new];

	command->_branch	= branch;
	command->_scope		= scope;
	command->_kind		= kind;
	command->_color		= color;
	[command adoptCommandString:[parameters componentsJoinedByString:@" "]];

	return command;

}//end lpubCommandInstance:


// MARK: - DISPLAY -


//========== browsingDescription ===============================================
///
/// @abstract	A short description of the line, shown to the user.
///
//==============================================================================
- (NSString *) browsingDescription
{
	NSArray<NSString *> *kinds = @[LPUB_CALLOUT_SUBMODEL_COLOR, LPUB_BACKGROUND_TRANSPARENT, LPUB_BACKGROUND_COLOR,
								   LPUB_BACKGROUND_PICTURE, LPUB_BACKGROUND_GRADIENT];

	return [NSString stringWithFormat:@"%@ %@ [%@]", [LPubCommand keywordForStyleBranch:self.branch],
			LPUB_CALLOUT_BACKGROUND, kinds[self.kind]];

}//end browsingDescription


// MARK: - ACCESSORS -


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubCalloutBackground *other = (LPubCalloutBackground *)command;

	self->_branch	= other->_branch;
	self->_scope	= other->_scope;
	self->_kind		= other->_kind;
	self->_color	= other->_color;

}//end adoptPropertiesFromCommand:


@end
