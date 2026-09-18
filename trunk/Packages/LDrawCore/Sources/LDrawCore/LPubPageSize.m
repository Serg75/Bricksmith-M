//==============================================================================
//
//  File:       LPubPageSize.m
//  Package:    LDrawCore
//
//  Purpose:    LPub PAGE SIZE command: how big the printed page is.
//
//              Line format:
//              0 !LPUB PAGE SIZE [GLOBAL|LOCAL] <width> <height> [<name>]
//
//              The measurements are in the unit the document's RESOLUTION
//              names, and describe the page before ORIENTATION turns it.
//
//              A line that names the page instead of measuring it stays a
//              plain LPubCommand. A parsed line is written back as it was read.
//
//  Created by Sergey Slobodenyuk on 2026-09-12.
//
//==============================================================================

#import <LDrawCore/LPubPageSize.h>

#import <LDrawCore/LDrawKeywords.h>


@implementation LPubPageSize


// MARK: - INITIALIZATION -


//---------- lpubCommandInstance: ------------------------------------[static]--
///
/// @abstract	Makes an instance if the parameters match the command.
///
/// 			Command syntax:
///				0 !LPUB PAGE SIZE [GLOBAL|LOCAL] <width> <height> [<name>]
///
//------------------------------------------------------------------------------
+ (LPubCommand *) lpubCommandInstance:(NSArray<NSString *> *)parameters
{
	if (parameters.count < 4
		|| [parameters[0] isEqualToString:LPUB_PAGE] == NO
		|| [parameters[1] isEqualToString:LPUB_PAGE_SIZE] == NO) {
		return nil;
	}

	NSUInteger		index	= 2;
	LPubMetaScope	scope	= [LPubCommand scopeInParameters:parameters index:&index];

	NSUInteger	remaining	= parameters.count - index;
	double		width		= 0.0;
	double		height		= 0.0;

	if (remaining != 2 && remaining != 3) {
		return nil;
	}
	if ([LPubCommand getPositiveNumber:&width fromToken:parameters[index]] == NO
		|| [LPubCommand getPositiveNumber:&height fromToken:parameters[index + 1]] == NO) {
		return nil;
	}

	LPubPageSize *command = [LPubPageSize new];

	command->_scope		= scope;
	command->_width		= width;
	command->_height	= height;
	command->_pageName	= (remaining == 3) ? [parameters[index + 2] copy] : nil;
	[command adoptCommandString:[parameters componentsJoinedByString:@" "]];

	return command;

}//end lpubCommandInstance:


// MARK: - DISPLAY -


- (NSString *) browsingDescription
{
	NSString *name = (self.pageName.length > 0) ? [@" " stringByAppendingString:self.pageName] : @"";

	return [NSString stringWithFormat:@"%@ %@ [%g %g%@]", LPUB_PAGE, LPUB_PAGE_SIZE, self.width, self.height, name];

}//end browsingDescription


// MARK: - ACCESSORS -


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubPageSize *other = (LPubPageSize *)command;

	self->_scope	= other->_scope;
	self->_width	= other->_width;
	self->_height	= other->_height;
	self->_pageName	= [other->_pageName copy];

}//end adoptPropertiesFromCommand:


// MARK: - UTILITIES -


- (NSString *) undoActionKey
{
	return @"UndoAttributesPageSize";

}//end undoActionKey


@end
