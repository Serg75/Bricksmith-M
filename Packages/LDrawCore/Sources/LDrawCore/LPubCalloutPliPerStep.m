//==============================================================================
//
//  File:       LPubCalloutPliPerStep.m
//  Package:    LDrawCore
//
//  Purpose:    Where the parts of a called-out submodel are listed.
//
//              Line format:
//              0 !LPUB CALLOUT PLI PER_STEP [GLOBAL|LOCAL] (TRUE|FALSE)
//
//              A parsed line is written back as it was read.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubCalloutPliPerStep.h>

#import <LDrawCore/LDrawKeywords.h>


@implementation LPubCalloutPliPerStep


// MARK: - INITIALIZATION -


//========== init ==============================================================
///
/// @abstract	With no line behind it, each step lists its own parts, as in
///				LPub3D.
///
//==============================================================================
- (id) init
{
	self = [super init];
	if (self) {
		self->_isPerStep = YES;
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
	if (parameters.count < 4
		|| [parameters[0] isEqualToString:LPUB_CALLOUT] == NO
		|| [parameters[1] isEqualToString:LPUB_PLI] == NO
		|| [parameters[2] isEqualToString:LPUB_CALLOUT_PER_STEP] == NO) {
		return nil;
	}

	NSUInteger		index	= 3;
	LPubMetaScope	scope	= [LPubCommand scopeInParameters:parameters index:&index];

	BOOL isPerStep = YES;

	if ([LPubCommand getBoolean:&isPerStep inParameters:parameters atIndex:index] == NO) {
		return nil;
	}

	LPubCalloutPliPerStep *command = [LPubCalloutPliPerStep new];

	command->_scope		= scope;
	command->_isPerStep	= isPerStep;
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
	return [NSString stringWithFormat:@"%@ %@ %@ [%@]", LPUB_CALLOUT, LPUB_PLI, LPUB_CALLOUT_PER_STEP,
			self.isPerStep ? LPUB_BOOLEAN_TRUE : LPUB_BOOLEAN_FALSE];

}//end browsingDescription


// MARK: - ACCESSORS -


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubCalloutPliPerStep *other = (LPubCalloutPliPerStep *)command;

	self->_scope		= other->_scope;
	self->_isPerStep	= other->_isPerStep;

}//end adoptPropertiesFromCommand:


@end
