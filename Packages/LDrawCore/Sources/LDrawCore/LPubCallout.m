//==============================================================================
//
//  File:       LPubCallout.m
//  Package:    LDrawCore
//
//  Purpose:    The lines that mark out a callout.
//
//              Line format:
//              0 !LPUB CALLOUT BEGIN [ASSEMBLED|ROTATED]
//              0 !LPUB CALLOUT DIVIDER
//              0 !LPUB CALLOUT END
//
//              A parsed line is written back as it was read.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubCallout.h>

#import <LDrawCore/LDrawKeywords.h>


@implementation LPubCallout


// MARK: - INITIALIZATION -


//---------- lpubCommandInstance: ------------------------------------[static]--
///
/// @abstract	Builds the command from the line's words, or nil if the
/// 			line is not this command.
///
/// 			Command syntax:
///				0 !LPUB CALLOUT BEGIN [ASSEMBLED|ROTATED]
///				0 !LPUB CALLOUT DIVIDER
///				0 !LPUB CALLOUT END
///
//------------------------------------------------------------------------------
+ (LPubCommand *) lpubCommandInstance:(NSArray<NSString *> *)parameters
{
	if (parameters.count < 2 || [parameters[0] isEqualToString:LPUB_CALLOUT] == NO) {
		return nil;
	}

	NSString		*keyword	= parameters[1];
	NSString		*argument	= (parameters.count == 3) ? parameters[2] : nil;
	LPubCalloutLine	 line		= LPubCalloutLineBegin;
	LPubCalloutMode	 mode		= LPubCalloutModeUnassembled;

	if (parameters.count > 3) {
		return nil;
	}

	if ([keyword isEqualToString:LPUB_CALLOUT_BEGIN]) {
		line = LPubCalloutLineBegin;

		if ([argument isEqualToString:LPUB_CALLOUT_ASSEMBLED]) {
			mode = LPubCalloutModeAssembled;
		}
		else if ([argument isEqualToString:LPUB_CALLOUT_ROTATED]) {
			mode = LPubCalloutModeRotated;
		}
		else if (argument != nil) {
			return nil;
		}
	}
	else if (argument == nil && [keyword isEqualToString:LPUB_CALLOUT_DIVIDER]) {
		line = LPubCalloutLineDivider;
	}
	else if (argument == nil && [keyword isEqualToString:LPUB_CALLOUT_END]) {
		line = LPubCalloutLineEnd;
	}
	else {
		return nil;
	}

	LPubCallout *command = [LPubCallout new];

	command->_line	= line;
	command->_mode	= mode;
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
	NSString *keyword = LPUB_CALLOUT_BEGIN;

	switch (self.line) {
		case LPubCalloutLineBegin:
			if (self.mode == LPubCalloutModeAssembled) {
				keyword = [NSString stringWithFormat:@"%@ %@", LPUB_CALLOUT_BEGIN, LPUB_CALLOUT_ASSEMBLED];
			}
			else if (self.mode == LPubCalloutModeRotated) {
				keyword = [NSString stringWithFormat:@"%@ %@", LPUB_CALLOUT_BEGIN, LPUB_CALLOUT_ROTATED];
			}
			break;

		case LPubCalloutLineDivider:
			keyword = LPUB_CALLOUT_DIVIDER;
			break;

		case LPubCalloutLineEnd:
			keyword = LPUB_CALLOUT_END;
			break;
	}

	return [NSString stringWithFormat:@"%@ [%@]", LPUB_CALLOUT, keyword];

}//end browsingDescription


// MARK: - ACCESSORS -


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubCallout *other = (LPubCallout *)command;

	self->_line	= other->_line;
	self->_mode	= other->_mode;

}//end adoptPropertiesFromCommand:


@end
