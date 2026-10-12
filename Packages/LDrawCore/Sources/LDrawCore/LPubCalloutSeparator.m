//==============================================================================
//
//  File:       LPubCalloutSeparator.m
//  Package:    LDrawCore
//
//  Purpose:    The line between two groups of steps in a callout's box.
//
//              Line format, after 0 !LPUB CALLOUT SEPARATOR [GLOBAL|LOCAL]:
//              [<length>] [THICKNESS] <thickness> <color> [MARGINS] <x> <y>
//
//              where <length> is DEFAULT, PAGE, PAGE_LENGTH, or CUSTOM or
//              CUSTOM_LENGTH followed by a number.
//
//              A line in any other form stays a plain LPubCommand. A parsed
//              line is written back as it was read.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubCalloutSeparator.h>

#import <LDrawCore/LDrawKeywords.h>


static NSString * const LPUB_SEPARATOR_THICKNESS = @"THICKNESS";

/// LPub3D's line when a file says nothing, in inches.
static const double DEFAULT_THICKNESS	= 1.0 / 32.0;
static const double DEFAULT_MARGIN		= 0.05;


@implementation LPubCalloutSeparator


// MARK: - INITIALIZATION -


//========== init ==============================================================
- (id) init
{
	self = [super init];
	if (self) {
		self->_thickness	= DEFAULT_THICKNESS;
		self->_color		= LPubColorBlack;
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
	if (parameters.count < 6
		|| [parameters[0] isEqualToString:LPUB_CALLOUT] == NO
		|| [parameters[1] isEqualToString:LPUB_CALLOUT_SEPARATOR] == NO) {
		return nil;
	}

	NSUInteger		index	= 2;
	LPubMetaScope	scope	= [LPubCommand scopeInParameters:parameters index:&index];
	NSUInteger		count	= parameters.count;
	double			length	= 0.0;

	// How long the line is comes first, when it is there. It is not used.
	if (index < count && [@[@"DEFAULT", @"PAGE", @"PAGE_LENGTH"] containsObject:parameters[index]]) {
		index += 1;
	}
	else if (index < count && [@[@"CUSTOM", @"CUSTOM_LENGTH"] containsObject:parameters[index]]) {
		if (index + 1 >= count || [LPubCommand getNumber:&length fromToken:parameters[index + 1]] == NO) {
			return nil;
		}
		index += 2;
	}

	if (index < count && [parameters[index] isEqualToString:LPUB_SEPARATOR_THICKNESS]) {
		index += 1;
	}

	double				thickness	= 0.0;
	LPubColorComponents	color		= LPubColorBlack;

	if (index + 1 >= count
		|| [LPubCommand getNumber:&thickness fromToken:parameters[index]] == NO
		|| thickness < 0.0) {
		return nil;
	}

	// A color that cannot be read is drawn black, as in LPub3D.
	if (LPubColorComponentsFromString(parameters[index + 1], &color) == NO) {
		color = LPubColorBlack;
	}
	index += 2;

	if (index < count && [parameters[index] isEqualToString:LPUB_CALLOUT_MARGINS]) {
		index += 1;
	}

	double x = 0.0, y = 0.0;

	if (index + 2 != count
		|| [LPubCommand getNumber:&x fromToken:parameters[index]] == NO
		|| [LPubCommand getNumber:&y fromToken:parameters[index + 1]] == NO) {
		return nil;
	}

	LPubCalloutSeparator *command = [LPubCalloutSeparator new];

	command->_scope		= scope;
	command->_thickness	= thickness;
	command->_color		= color;
	command->_margins	= V2MakeSize(x, y);
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
	return [NSString stringWithFormat:@"%@ %@ [%g]", LPUB_CALLOUT, LPUB_CALLOUT_SEPARATOR, self.thickness];

}//end browsingDescription


// MARK: - ACCESSORS -


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubCalloutSeparator *other = (LPubCalloutSeparator *)command;

	self->_scope		= other->_scope;
	self->_thickness	= other->_thickness;
	self->_color		= other->_color;
	self->_margins		= other->_margins;

}//end adoptPropertiesFromCommand:


@end
