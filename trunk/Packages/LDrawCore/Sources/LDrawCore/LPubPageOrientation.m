//==============================================================================
//
//  File:       LPubPageOrientation.m
//  Package:    LDrawCore
//
//  Purpose:    LPub PAGE ORIENTATION command: which way up the page is.
//
//              Line format:
//              0 !LPUB PAGE ORIENTATION [GLOBAL|LOCAL] (PORTRAIT | LANDSCAPE)
//
//              A parsed line is written back as it was read. Any other form
//              stays a plain LPubCommand, which keeps the line verbatim.
//
//  Created by Sergey Slobodenyuk on 2026-09-12.
//
//==============================================================================

#import <LDrawCore/LPubPageOrientation.h>

#import <LDrawCore/LDrawKeywords.h>


@implementation LPubPageOrientation


// MARK: - INITIALIZATION -


//---------- lpubCommandInstance: ------------------------------------[static]--
///
/// @abstract	Makes an instance if the parameters match the command.
///
/// 			Command syntax:
///				0 !LPUB PAGE ORIENTATION [GLOBAL|LOCAL] (PORTRAIT | LANDSCAPE)
///
//------------------------------------------------------------------------------
+ (LPubCommand *) lpubCommandInstance:(NSArray<NSString *> *)parameters
{
	if (parameters.count < 3
		|| [parameters[0] isEqualToString:LPUB_PAGE] == NO
		|| [parameters[1] isEqualToString:LPUB_PAGE_ORIENTATION] == NO) {
		return nil;
	}

	NSUInteger		index	= 2;
	LPubMetaScope	scope	= [LPubCommand scopeInParameters:parameters index:&index];

	if (index != parameters.count - 1) {
		return nil;
	}

	NSString	*keyword	= parameters[index];
	BOOL		 landscape	= NO;

	if ([keyword isEqualToString:LPUB_PAGE_LANDSCAPE]) {
		landscape = YES;
	}
	else if ([keyword isEqualToString:LPUB_PAGE_PORTRAIT] == NO) {
		return nil;
	}

	LPubPageOrientation *command = [LPubPageOrientation new];

	command->_scope			= scope;
	command->_isLandscape	= landscape;
	[command adoptCommandString:[parameters componentsJoinedByString:@" "]];

	return command;

}//end lpubCommandInstance:


// MARK: - DISPLAY -


- (NSString *) browsingDescription
{
	return [NSString stringWithFormat:@"%@ %@ [%@]", LPUB_PAGE, LPUB_PAGE_ORIENTATION,
			self.isLandscape ? LPUB_PAGE_LANDSCAPE : LPUB_PAGE_PORTRAIT];

}//end browsingDescription


// MARK: - ACCESSORS -


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubPageOrientation *other = (LPubPageOrientation *)command;

	self->_scope		= other->_scope;
	self->_isLandscape	= other->_isLandscape;

}//end adoptPropertiesFromCommand:


// MARK: - UTILITIES -


- (NSString *) undoActionKey
{
	return @"UndoAttributesPageOrientation";

}//end undoActionKey


@end
