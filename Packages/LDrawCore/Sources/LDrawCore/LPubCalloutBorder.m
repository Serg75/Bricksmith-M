//==============================================================================
//
//  File:       LPubCalloutBorder.m
//  Package:    LDrawCore
//
//  Purpose:    The outline of a callout's box.
//
//              Line format, after 0 !LPUB CALLOUT BORDER [GLOBAL|LOCAL]:
//              NONE [<line>] [MARGINS <x> <y>]
//              (SQUARE|HIDDEN) [<line>] <color> <thickness> [MARGINS <x> <y>]
//              ROUND [<line>] <color> <thickness> <radius> [MARGINS <x> <y>]
//
//              A line in any other form stays a plain LPubCommand. A parsed
//              line is written back as it was read.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubCalloutBorder.h>

#import <LDrawCore/LDrawKeywords.h>


static NSString * const LPUB_BORDER_NONE	= @"NONE";
static NSString * const LPUB_BORDER_SQUARE	= @"SQUARE";
static NSString * const LPUB_BORDER_HIDDEN	= @"HIDDEN";
static NSString * const LPUB_BORDER_ROUND	= @"ROUND";

/// LPub3D's outline for a callout when a file says nothing, in inches.
static const double DEFAULT_THICKNESS	= 1.0 / 32.0;
static const double DEFAULT_RADIUS		= 15.0;
static const double DEFAULT_MARGIN		= 0.05;


@implementation LPubCalloutBorder


// MARK: - INITIALIZATION -


//========== init ==============================================================
///
/// @abstract	With no line behind it, LPub3D's outline: square, solid and
/// 			black.
///
//==============================================================================
- (id) init
{
	self = [super init];
	if (self) {
		self->_shape		= LPubBorderShapeSquare;
		self->_lineStyle	= LPubLineStyleSolid;
		self->_color		= LPubColorBlack;
		self->_thickness	= DEFAULT_THICKNESS;
		self->_radius		= DEFAULT_RADIUS;
		self->_margins		= V2MakeSize(DEFAULT_MARGIN, DEFAULT_MARGIN);
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
	if (parameters.count < 3
		|| [parameters[0] isEqualToString:LPUB_CALLOUT] == NO
		|| [parameters[1] isEqualToString:LPUB_CALLOUT_BORDER] == NO) {
		return nil;
	}

	NSUInteger			 index		= 2;
	LPubMetaScope		 scope		= [LPubCommand scopeInParameters:parameters index:&index];
	LPubCalloutBorder	*command	= [LPubCalloutBorder new];

	if (index >= parameters.count) {
		return nil;
	}

	NSString *shape = parameters[index];

	index += 1;

	if ([shape isEqualToString:LPUB_BORDER_NONE]) {
		command->_shape = LPubBorderShapeNone;
	}
	else if ([shape isEqualToString:LPUB_BORDER_ROUND]) {
		command->_shape = LPubBorderShapeRound;
	}
	else if ([shape isEqualToString:LPUB_BORDER_SQUARE] || [shape isEqualToString:LPUB_BORDER_HIDDEN]) {
		command->_shape				= LPubBorderShapeSquare;
		command->_hidesArrowTips	= [shape isEqualToString:LPUB_BORDER_HIDDEN];
	}
	else {
		return nil;
	}

	// A whole number here is the line style. Older files have none.
	NSInteger lineStyle = LPubLineStyleSolid;

	if (index < parameters.count
		&& [LPubCommand getInteger:&lineStyle fromToken:parameters[index] atLeast:LPubLineStyleNone]) {

		if (lineStyle > LPubLineStyleDashDotDot) {
			return nil;
		}
		command->_lineStyle = lineStyle;
		index += 1;
	}

	if (command->_shape != LPubBorderShapeNone) {
		NSUInteger numberCount = (command->_shape == LPubBorderShapeRound) ? 2 : 1;

		if (index + numberCount >= parameters.count) {
			return nil;
		}

		// A color that cannot be read is drawn black, as in LPub3D.
		if (LPubColorComponentsFromString(parameters[index], &command->_color) == NO) {
			command->_color = LPubColorBlack;
		}

		if ([LPubCommand getNumber:&command->_thickness fromToken:parameters[index + 1]] == NO
			|| command->_thickness < 0.0) {
			return nil;
		}

		if (numberCount == 2
			&& ([LPubCommand getNumber:&command->_radius fromToken:parameters[index + 2]] == NO
				|| command->_radius < 0.0)) {
			return nil;
		}

		index += 1 + numberCount;
	}

	if (index < parameters.count) {
		double x = 0.0, y = 0.0;

		if (parameters.count - index != 3
			|| [parameters[index] isEqualToString:LPUB_CALLOUT_MARGINS] == NO
			|| [LPubCommand getNumber:&x fromToken:parameters[index + 1]] == NO
			|| [LPubCommand getNumber:&y fromToken:parameters[index + 2]] == NO) {
			return nil;
		}

		command->_hasMargins	= YES;
		command->_margins		= V2MakeSize(x, y);
	}

	command->_scope = scope;
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
	NSString *shape = LPUB_BORDER_NONE;

	if (self.shape == LPubBorderShapeRound) {
		shape = LPUB_BORDER_ROUND;
	}
	else if (self.shape == LPubBorderShapeSquare) {
		shape = self.hidesArrowTips ? LPUB_BORDER_HIDDEN : LPUB_BORDER_SQUARE;
	}

	return [NSString stringWithFormat:@"%@ %@ [%@]", LPUB_CALLOUT, LPUB_CALLOUT_BORDER, shape];

}//end browsingDescription


// MARK: - ACCESSORS -


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubCalloutBorder *other = (LPubCalloutBorder *)command;

	self->_scope			= other->_scope;
	self->_shape			= other->_shape;
	self->_hidesArrowTips	= other->_hidesArrowTips;
	self->_lineStyle		= other->_lineStyle;
	self->_color			= other->_color;
	self->_thickness		= other->_thickness;
	self->_radius			= other->_radius;
	self->_hasMargins		= other->_hasMargins;
	self->_margins			= other->_margins;

}//end adoptPropertiesFromCommand:


@end
