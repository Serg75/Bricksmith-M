//==============================================================================
//
//  File:       LPubPliShow.m
//  Package:    LDrawCore
//
//  Purpose:    LPub PLI SHOW command: whether the parts list is displayed.
//
//              Line format:
//              0 !LPUB PLI SHOW [GLOBAL|LOCAL] (TRUE|FALSE)
//
//              GLOBAL and no keyword hold from the line on, LOCAL for the rest
//              of its step.
//
//              A parsed line is written back as it was read. A line in any
//              other form is left to the generic LPubCommand, which writes it
//              back unchanged.
//
//  Created by Sergey Slobodenyuk on 2026-09-09.
//
//==============================================================================

#import <LDrawCore/LPubPliShow.h>

#import <LDrawCore/LDrawKeywords.h>


@implementation LPubPliShow


// MARK: - INITIALIZATION -


//---------- lpubCommandInstance: ------------------------------------[static]--
///
/// @abstract	Builds the command from the line's words, or nil if the
/// 			line is not this command.
///
/// 			Command syntax:
///				0 !LPUB PLI SHOW [GLOBAL|LOCAL] (TRUE|FALSE)
///
//------------------------------------------------------------------------------
+ (LPubCommand *) lpubCommandInstance:(NSArray<NSString *> *)parameters
{
	if (parameters.count < 3
		|| [parameters[0] isEqualToString:LPUB_PLI] == NO
		|| [parameters[1] isEqualToString:LPUB_PLI_SHOW] == NO) {
		return nil;
	}

	NSUInteger		index	= 2;
	LPubMetaScope	scope	= [LPubCommand scopeInParameters:parameters index:&index];

	// The boolean is the last token, and there must be nothing after it.
	if (index != parameters.count - 1) {
		return nil;
	}

	BOOL		isShown	= YES;
	NSString	*token	= parameters[index];

	if ([token isEqualToString:LPUB_BOOLEAN_TRUE]) {
		isShown = YES;
	}
	else if ([token isEqualToString:LPUB_BOOLEAN_FALSE]) {
		isShown = NO;
	}
	else {
		return nil;
	}

	LPubPliShow *command = [LPubPliShow new];

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
	return [NSString stringWithFormat:@"%@ %@ [%@]", LPUB_PLI, LPUB_PLI_SHOW,
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
	LPubPliShow *other = (LPubPliShow *)command;

	self->_scope	= other->_scope;
	self->_isShown	= other->_isShown;

}//end adoptPropertiesFromCommand:


// MARK: - UTILITIES -


//========== undoActionKey =====================================================
- (NSString *) undoActionKey
{
	return @"UndoAttributesPliShow";

}//end undoActionKey


@end
