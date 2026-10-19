//==============================================================================
//
//  File:       LPubPageNumberDisplay.m
//  Package:    LDrawCore
//
//  Purpose:    Whether LPub3D prints the page's number, and whether an even
//              page puts it on the other side.
//
//              Line format:
//              0 !LPUB PAGE DISPLAY_PAGE_NUMBER [GLOBAL|LOCAL] (TRUE|FALSE)
//              0 !LPUB PAGE TOGGLE_PAGE_NUMBER_PLACEMENT [GLOBAL|LOCAL]
//                  (TRUE|FALSE)
//
//              A parsed line is written back as it was read.
//
//  Created by Sergey Slobodenyuk on 2026-10-18.
//
//==============================================================================

#import <LDrawCore/LPubPageNumberDisplay.h>

#import <LDrawCore/LDrawKeywords.h>


@implementation LPubPageNumberDisplay


// MARK: - INITIALIZATION -


//========== init ==============================================================
///
/// @abstract	With no line behind it, the number is printed, as in LPub3D.
///
//==============================================================================
- (id) init
{
	self = [super init];
	if (self) {
		self->_isOn = YES;
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
	if (parameters.count < 3 || [parameters[0] isEqualToString:LPUB_PAGE] == NO) {
		return nil;
	}

	LPubPageNumberSwitch kind = LPubPageNumberSwitchDisplay;

	if ([parameters[1] isEqualToString:LPUB_PAGE_TOGGLE_NUMBER]) {
		kind = LPubPageNumberSwitchToggle;
	}
	else if ([parameters[1] isEqualToString:LPUB_PAGE_DISPLAY_NUMBER] == NO) {
		return nil;
	}

	NSUInteger		index	= 2;
	LPubMetaScope	scope	= [LPubCommand scopeInParameters:parameters index:&index];

	BOOL isOn = YES;

	if ([LPubCommand getBoolean:&isOn inParameters:parameters atIndex:index] == NO) {
		return nil;
	}

	LPubPageNumberDisplay *command = [LPubPageNumberDisplay new];

	command->_kind	= kind;
	command->_scope	= scope;
	command->_isOn	= isOn;
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
	NSString *name = (self.kind == LPubPageNumberSwitchToggle) ? LPUB_PAGE_TOGGLE_NUMBER : LPUB_PAGE_DISPLAY_NUMBER;

	return [NSString stringWithFormat:@"%@ %@ [%@]", LPUB_PAGE, name,
			self.isOn ? LPUB_BOOLEAN_TRUE : LPUB_BOOLEAN_FALSE];

}//end browsingDescription


// MARK: - ACCESSORS -


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubPageNumberDisplay *other = (LPubPageNumberDisplay *)command;

	self->_kind		= other->_kind;
	self->_scope	= other->_scope;
	self->_isOn		= other->_isOn;

}//end adoptPropertiesFromCommand:


@end
