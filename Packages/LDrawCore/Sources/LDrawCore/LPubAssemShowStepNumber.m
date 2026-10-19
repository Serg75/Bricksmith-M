//==============================================================================
//
//  File:       LPubAssemShowStepNumber.m
//  Package:    LDrawCore
//
//  Purpose:    Whether LPub3D prints step numbers.
//
//              Line format:
//              0 !LPUB ASSEM SHOW_STEP_NUMBER [GLOBAL|LOCAL] (TRUE|FALSE)
//
//              A parsed line is written back as it was read.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubAssemShowStepNumber.h>

#import <LDrawCore/LDrawKeywords.h>


@implementation LPubAssemShowStepNumber


// MARK: - INITIALIZATION -


//========== init ==============================================================
///
/// @abstract	With no line behind it, step numbers are printed, as in LPub3D.
///
//==============================================================================
- (id) init
{
	self = [super init];
	if (self) {
		self->_isShown = YES;
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
		|| [parameters[0] isEqualToString:LPUB_ASSEM] == NO
		|| [parameters[1] isEqualToString:LPUB_SHOW_STEP_NUMBER] == NO) {
		return nil;
	}

	NSUInteger		index	= 2;
	LPubMetaScope	scope	= [LPubCommand scopeInParameters:parameters index:&index];

	BOOL isShown = YES;

	if ([LPubCommand getBoolean:&isShown inParameters:parameters atIndex:index] == NO) {
		return nil;
	}

	LPubAssemShowStepNumber *command = [LPubAssemShowStepNumber new];

	command->_scope		= scope;
	command->_isShown	= isShown;
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
	return [NSString stringWithFormat:@"%@ %@ [%@]", LPUB_ASSEM, LPUB_SHOW_STEP_NUMBER,
			self.isShown ? LPUB_BOOLEAN_TRUE : LPUB_BOOLEAN_FALSE];

}//end browsingDescription


// MARK: - ACCESSORS -


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubAssemShowStepNumber *other = (LPubAssemShowStepNumber *)command;

	self->_scope	= other->_scope;
	self->_isShown	= other->_isShown;

}//end adoptPropertiesFromCommand:


@end
