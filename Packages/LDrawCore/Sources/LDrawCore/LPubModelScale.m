//==============================================================================
//
//  File:       LPubModelScale.m
//  Package:    LDrawCore
//
//  Purpose:    LPub MODEL_SCALE command: how big a picture is drawn.
//
//              Line format:
//              0 !LPUB (PLI | ASSEM | BOM) MODEL_SCALE [GLOBAL|LOCAL] <double>
//
//              PLI sizes the parts list icons, ASSEM the step picture, BOM
//              the bill of materials. GLOBAL and no keyword hold from the line
//              on, LOCAL for the rest of its step. The value multiplies life
//              size, 1/64 inch per LDU.
//
//              A parsed line is written back as it was read. A line in any
//              other form is left to the generic LPubCommand, which writes it
//              back unchanged.
//
//  Created by Sergey Slobodenyuk on 2026-09-12.
//
//==============================================================================

#import <LDrawCore/LPubModelScale.h>

#import <LDrawCore/LDrawKeywords.h>


//========== BranchForKeyword() ================================================
static BOOL BranchForKeyword(NSString *keyword, LPubModelScaleBranch *outBranch)
{
	if ([keyword isEqualToString:LPUB_PLI]) {
		*outBranch = LPubModelScaleBranchPli;
	}
	else if ([keyword isEqualToString:LPUB_ASSEM]) {
		*outBranch = LPubModelScaleBranchAssembly;
	}
	else if ([keyword isEqualToString:LPUB_BOM]) {
		*outBranch = LPubModelScaleBranchBom;
	}
	else {
		return NO;
	}

	return YES;

}//end BranchForKeyword


//========== KeywordForBranch() ================================================
static NSString *KeywordForBranch(LPubModelScaleBranch branch)
{
	switch (branch) {
		case LPubModelScaleBranchPli:	return LPUB_PLI;
		case LPubModelScaleBranchAssembly:	return LPUB_ASSEM;
		case LPubModelScaleBranchBom:	return LPUB_BOM;
		default:						return LPUB_PLI;
	}

}//end KeywordForBranch


@implementation LPubModelScale


// MARK: - INITIALIZATION -


//---------- lpubCommandInstance: ------------------------------------[static]--
///
/// @abstract	Builds the command from the line's words, or nil if the
/// 			line is not this command.
///
/// 			Command syntax:
///				0 !LPUB (PLI | ASSEM | BOM) MODEL_SCALE [GLOBAL|LOCAL] <double>
///
//------------------------------------------------------------------------------
+ (LPubCommand *) lpubCommandInstance:(NSArray<NSString *> *)parameters
{
	LPubModelScaleBranch branch = LPubModelScaleBranchPli;

	if (parameters.count < 3
		|| BranchForKeyword(parameters[0], &branch) == NO
		|| [parameters[1] isEqualToString:LPUB_MODEL_SCALE] == NO) {
		return nil;
	}

	NSUInteger		index	= 2;
	LPubMetaScope	scope	= [LPubCommand scopeInParameters:parameters index:&index];

	if (index != parameters.count - 1) {
		return nil;
	}

	double scale = 0.0;

	if ([LPubCommand getPositiveNumber:&scale fromToken:parameters[index]] == NO) {
		return nil;
	}

	LPubModelScale *command = [LPubModelScale new];

	command->_branch	= branch;
	command->_scope		= scope;
	command->_scale		= scale;
	[command adoptCommandString:[parameters componentsJoinedByString:@" "]];

	return command;

}//end lpubCommandInstance:


// MARK: - DISPLAY -


//========== browsingDescription ===============================================
- (NSString *) browsingDescription
{
	return [NSString stringWithFormat:@"%@ %@ [%.4f]", KeywordForBranch(self.branch), LPUB_MODEL_SCALE, self.scale];

}//end browsingDescription


// MARK: - ACCESSORS -


//---------- inchesPerLDU --------------------------------------------[static]--
///
/// @abstract	Inches one LDU covers at a scale of 1.0.
///
/// @discussion	An LDU is 0.4 mm, or 1/63.5 inch. We round to 1/64 as LPub3D
/// 			does, so both draw a part the same size.
///
//------------------------------------------------------------------------------
+ (double) inchesPerLDU
{
	return 1.0 / 64.0;

}//end inchesPerLDU


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubModelScale *other = (LPubModelScale *)command;

	self->_branch	= other->_branch;
	self->_scope	= other->_scope;
	self->_scale	= other->_scale;

}//end adoptPropertiesFromCommand:


// MARK: - UTILITIES -


//========== undoActionKey =====================================================
- (NSString *) undoActionKey
{
	return @"UndoAttributesModelScale";

}//end undoActionKey


@end
