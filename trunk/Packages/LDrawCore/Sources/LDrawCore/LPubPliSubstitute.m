//==============================================================================
//
//  File:       LPubPliSubstitute.m
//  Package:    LDrawCore
//
//  Purpose:    Lists one part in place of a range of parts.
//
//              Line format:
//              0 !LPUB PLI BEGIN SUB <part> [<color> [<anything else>]]
//              0 !LPUB PLI END
//
//              The END is parsed as an LPubPliIgnore. A BEGIN SUB with no
//              part stays a plain LPubCommand. A parsed line is written back
//              as it was read.
//
//  Created by Sergey Slobodenyuk on 2026-09-13.
//
//==============================================================================

#import <LDrawCore/LPubPliSubstitute.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawKeywords.h>


static NSString * const		LPUB_PLI_SUBSTITUTE	= @"SUB";


@implementation LPubPliSubstitute


// MARK: - INITIALIZATION -


//========== init ==============================================================
///
/// @abstract	Makes an empty substitute that names no part yet.
///
//==============================================================================
- (id) init
{
	self = [super init];
	if (self) {
		self->_partName			= @"";
		self->_partColorCode	= LDrawColorBogus;
		self->_trailingTokens	= @[];
	}
	return self;

}//end init


//---------- lpubCommandInstance: ------------------------------------[static]--
///
/// @abstract	Makes an instance if the parameters match the command.
///
/// 			Command syntax:
///				0 !LPUB PLI BEGIN SUB <part> [<color> [<anything else>]]
///
//------------------------------------------------------------------------------
+ (LPubCommand *) lpubCommandInstance:(NSArray<NSString *> *)parameters
{
	if (parameters.count < 4
		|| [parameters[0] isEqualToString:LPUB_PLI] == NO
		|| [parameters[1] isEqualToString:LPUB_PLI_BEGIN] == NO
		|| [parameters[2] isEqualToString:LPUB_PLI_SUBSTITUTE] == NO) {
		return nil;
	}

	LPubPliSubstitute	*command	= [LPubPliSubstitute new];
	NSUInteger			 next		= 4;
	NSInteger			 code		= LDrawColorBogus;

	command->_partName = [parameters[3] copy];

	// A negative code is not a color, so it stays with the tokens after it.
	if (parameters.count > 4 && [LPubCommand getInteger:&code fromToken:parameters[4] atLeast:0]) {
		command->_partColorCode = code;
		next = 5;
	}

	command->_trailingTokens = [parameters subarrayWithRange:NSMakeRange(next, parameters.count - next)];
	[command adoptCommandString:[parameters componentsJoinedByString:@" "]];

	return command;

}//end lpubCommandInstance:


// MARK: - DISPLAY -


//========== browsingDescription ===============================================
- (NSString *) browsingDescription
{
	NSString *color = (self.partColorCode != LDrawColorBogus)
					 ? [NSString stringWithFormat:@" %ld", (long)self.partColorCode]
					 : @"";

	return [NSString stringWithFormat:@"%@ %@ %@ [%@%@]",
			LPUB_PLI, LPUB_PLI_BEGIN, LPUB_PLI_SUBSTITUTE, self.partName, color];
}//end browsingDescription


// MARK: - ACCESSORS -


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubPliSubstitute *other = (LPubPliSubstitute *)command;

	self->_partName			= other->_partName;
	self->_partColorCode	= other->_partColorCode;
	self->_trailingTokens	= other->_trailingTokens;

}//end adoptPropertiesFromCommand:


// MARK: - UTILITIES -


//========== undoActionKey =====================================================
- (NSString *) undoActionKey
{
	return @"UndoAttributesPliSubstitute";

}//end undoActionKey


@end
