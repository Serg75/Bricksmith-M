//==============================================================================
//
//  File:       LPubCalloutMargins.m
//  Package:    LDrawCore
//
//  Purpose:    The room kept around a callout or something in it.
//
//              Line format:
//              0 !LPUB CALLOUT [ASSEM | PLI | STEP_NUMBER | INSTANCE_COUNT]
//                  MARGINS [GLOBAL|LOCAL] <x> <y>
//
//              A parsed line is written back as it was read.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubCalloutMargins.h>

#import <LDrawCore/LDrawKeywords.h>


/// LPub3D's margin when a file says nothing, in inches.
static const double DEFAULT_MARGIN = 0.05;


//========== PartNames() =======================================================
///
/// @abstract	The keyword of each thing inside a callout, by its part.
///
//==============================================================================
static NSDictionary<NSNumber *, NSString *> *PartNames(void)
{
	return @{
		@(LPubCalloutPartAssembly):			LPUB_ASSEM,
		@(LPubCalloutPartPartsList):		LPUB_PLI,
		@(LPubCalloutPartStepNumber):		LPUB_CALLOUT_STEP_NUMBER,
		@(LPubCalloutPartInstanceCount):	LPUB_CALLOUT_INSTANCE_COUNT,
	};

}//end PartNames


@implementation LPubCalloutMargins


// MARK: - INITIALIZATION -


//========== init ==============================================================
- (id) init
{
	self = [super init];
	if (self) {
		self->_margins = V2MakeSize(DEFAULT_MARGIN, DEFAULT_MARGIN);
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
	if (parameters.count < 4 || [parameters[0] isEqualToString:LPUB_CALLOUT] == NO) {
		return nil;
	}

	NSUInteger		index	= 1;
	LPubCalloutPart	part	= LPubCalloutPartBox;

	if ([self getPart:&part fromToken:parameters[index]]) {
		index += 1;
	}

	if ([parameters[index] isEqualToString:LPUB_CALLOUT_MARGINS] == NO) {
		return nil;
	}
	index += 1;

	LPubMetaScope	scope	= [LPubCommand scopeInParameters:parameters index:&index];
	double			x		= 0.0;
	double			y		= 0.0;

	// The two numbers are the last tokens, and there must be nothing after.
	if (index + 2 != parameters.count
		|| [LPubCommand getNumber:&x fromToken:parameters[index]] == NO
		|| [LPubCommand getNumber:&y fromToken:parameters[index + 1]] == NO) {
		return nil;
	}

	LPubCalloutMargins *command = [LPubCalloutMargins new];

	command->_scope		= scope;
	command->_part		= part;
	command->_margins	= V2MakeSize(x, y);
	[command adoptCommandString:[parameters componentsJoinedByString:@" "]];

	return command;

}//end lpubCommandInstance:


//---------- getPart:fromToken: --------------------------------------[static]--
+ (BOOL) getPart:(LPubCalloutPart *)outPart fromToken:(NSString *)token
{
	NSNumber *part = [[PartNames() allKeysForObject:token] firstObject];

	if (part == nil) {
		return NO;
	}

	*outPart = part.integerValue;
	return YES;

}//end getPart:fromToken:


//---------- nameForPart: --------------------------------------------[static]--
+ (nullable NSString *) nameForPart:(LPubCalloutPart)part
{
	return PartNames()[@(part)];

}//end nameForPart:


// MARK: - DISPLAY -


//========== browsingDescription ===============================================
///
/// @abstract	A short description of the line, shown to the user.
///
//==============================================================================
- (NSString *) browsingDescription
{
	NSString *name		= [LPubCalloutMargins nameForPart:self.part];
	NSString *subject	= (name != nil) ? [NSString stringWithFormat:@"%@ %@", LPUB_CALLOUT, name] : LPUB_CALLOUT;

	return [NSString stringWithFormat:@"%@ %@ [%g %g]", subject, LPUB_CALLOUT_MARGINS,
			self.margins.width, self.margins.height];

}//end browsingDescription


// MARK: - ACCESSORS -


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubCalloutMargins *other = (LPubCalloutMargins *)command;

	self->_scope	= other->_scope;
	self->_part		= other->_part;
	self->_margins	= other->_margins;

}//end adoptPropertiesFromCommand:


@end
