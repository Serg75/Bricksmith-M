//==============================================================================
//
//  File:       LPubPliIgnore.m
//  Package:    LDrawCore
//
//  Purpose:    The bracket that keeps a range of parts out of the parts list.
//
//              Line format:
//              0 !LPUB (PLI | PART) BEGIN IGN
//              0 !LPUB (PLI | PART) END
//
//              A parsed line is written back as it was read.
//
//  Created by Sergey Slobodenyuk on 2026-09-09.
//
//==============================================================================

#import <LDrawCore/LPubPliIgnore.h>

#import <LDrawCore/LDrawKeywords.h>


//========== KeywordForBranch() ================================================
static NSString *KeywordForBranch(LPubPliIgnoreBranch branch)
{
	switch (branch) {
		case LPubPliIgnoreBranchPli:	return LPUB_PLI;
		case LPubPliIgnoreBranchPart:	return LPUB_PART;
		default:						return LPUB_PLI;
	}

}//end KeywordForBranch


@implementation LPubPliIgnore


// MARK: - INITIALIZATION -


//---------- lpubCommandInstance: ------------------------------------[static]--
///
/// @abstract	Builds the command from the line's words, or nil if the
/// 			line is not this command.
///
/// 			Command syntax:
///				0 !LPUB (PLI | PART) BEGIN IGN
///				0 !LPUB (PLI | PART) END
///
//------------------------------------------------------------------------------
+ (LPubCommand *) lpubCommandInstance:(NSArray<NSString *> *)parameters
{
	if (parameters.count < 2) {
		return nil;
	}

	LPubPliIgnoreBranch branch = LPubPliIgnoreBranchPli;

	if ([parameters[0] isEqualToString:LPUB_PLI]) {
		branch = LPubPliIgnoreBranchPli;
	}
	else if ([parameters[0] isEqualToString:LPUB_PART]) {
		branch = LPubPliIgnoreBranchPart;
	}
	else {
		return nil;
	}

	BOOL beginsRange = NO;

	if (parameters.count == 3
		&& [parameters[1] isEqualToString:LPUB_PLI_BEGIN]
		&& [parameters[2] isEqualToString:LPUB_PLI_IGNORE]) {
		beginsRange = YES;
	}
	else if (parameters.count == 2 && [parameters[1] isEqualToString:LPUB_PLI_END]) {
		beginsRange = NO;
	}
	else {
		return nil;
	}

	LPubPliIgnore *command = [LPubPliIgnore new];

	command->_beginsRange	= beginsRange;
	command->_branch		= branch;
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
	return [NSString stringWithFormat:@"%@ [%@]", KeywordForBranch(self.branch),
			self.beginsRange ? [NSString stringWithFormat:@"%@ %@", LPUB_PLI_BEGIN, LPUB_PLI_IGNORE]
							 : LPUB_PLI_END];
}//end browsingDescription


// MARK: - ACCESSORS -


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubPliIgnore *other = (LPubPliIgnore *)command;

	self->_beginsRange	= other->_beginsRange;
	self->_branch		= other->_branch;

}//end adoptPropertiesFromCommand:


// MARK: - UTILITIES -


//========== undoActionKey =====================================================
- (NSString *) undoActionKey
{
	return @"UndoAttributesPliIgnore";

}//end undoActionKey


@end
