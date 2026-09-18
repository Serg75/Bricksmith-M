//==============================================================================
//
//  File:       LPubResolution.m
//  Package:    LDrawCore
//
//  Purpose:    LPub RESOLUTION command: the printed page's dots per unit.
//
//              Line format:
//              0 !LPUB RESOLUTION [GLOBAL|LOCAL] <double> (DPI | DPCM)
//
//              LPub3D keeps one resolution, so LOCAL does not end with the
//              step. The keyword may be left out.
//
//              A parsed line is written back as it was read. A line in any
//              other form is left to the generic LPubCommand, which writes it
//              back unchanged.
//
//  Created by Sergey Slobodenyuk on 2026-09-12.
//
//==============================================================================

#import <LDrawCore/LPubResolution.h>

#import <LDrawCore/LDrawKeywords.h>


static const double			CENTIMETERS_PER_INCH = 2.54;


//========== KeywordForUnit() ==================================================
static NSString *KeywordForUnit(LPubResolutionUnit unit)
{
	switch (unit) {
		case LPubResolutionUnitDotsPerInch:			return LPUB_RESOLUTION_DPI;
		case LPubResolutionUnitDotsPerCentimeter:	return LPUB_RESOLUTION_DPCM;
		default:									return LPUB_RESOLUTION_DPI;
	}

}//end KeywordForUnit


@implementation LPubResolution


// MARK: - INITIALIZATION -


//---------- lpubCommandInstance: ------------------------------------[static]--
///
/// @abstract	Builds the command from the line's words, or nil if the
/// 			line is not this command.
///
/// 			Command syntax:
///				0 !LPUB RESOLUTION [GLOBAL|LOCAL] <double> (DPI | DPCM)
///
//------------------------------------------------------------------------------
+ (LPubCommand *) lpubCommandInstance:(NSArray<NSString *> *)parameters
{
	if (parameters.count < 3 || [parameters[0] isEqualToString:LPUB_RESOLUTION] == NO) {
		return nil;
	}

	NSUInteger		index	= 1;
	LPubMetaScope	scope	= [LPubCommand scopeInParameters:parameters index:&index];

	if (index != parameters.count - 2) {
		return nil;
	}

	double				dotsPerUnit	= 0.0;
	LPubResolutionUnit	unit		= LPubResolutionUnitDotsPerInch;
	NSString			*keyword	= parameters[index + 1];

	if ([LPubCommand getPositiveNumber:&dotsPerUnit fromToken:parameters[index]] == NO) {
		return nil;
	}

	if ([keyword isEqualToString:LPUB_RESOLUTION_DPI]) {
		unit = LPubResolutionUnitDotsPerInch;
	}
	else if ([keyword isEqualToString:LPUB_RESOLUTION_DPCM]) {
		unit = LPubResolutionUnitDotsPerCentimeter;
	}
	else {
		return nil;
	}

	LPubResolution *command = [LPubResolution new];

	command->_scope			= scope;
	command->_dotsPerUnit	= dotsPerUnit;
	command->_unit			= unit;
	[command adoptCommandString:[parameters componentsJoinedByString:@" "]];

	return command;

}//end lpubCommandInstance:


// MARK: - DISPLAY -


//========== browsingDescription ===============================================
- (NSString *) browsingDescription
{
	return [NSString stringWithFormat:@"%@ [%g %@]", LPUB_RESOLUTION, self.dotsPerUnit, KeywordForUnit(self.unit)];

}//end browsingDescription


// MARK: - ACCESSORS -


//========== inchesPerUnit =====================================================
///
/// @abstract	Inches in one unit of the page: 1 for DPI, 1/2.54 for DPCM.
///
//==============================================================================
- (double) inchesPerUnit
{
	if (self.unit == LPubResolutionUnitDotsPerCentimeter) {
		return 1.0 / CENTIMETERS_PER_INCH;
	}

	return 1.0;

}//end inchesPerUnit


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubResolution *other = (LPubResolution *)command;

	self->_scope		= other->_scope;
	self->_dotsPerUnit	= other->_dotsPerUnit;
	self->_unit			= other->_unit;

}//end adoptPropertiesFromCommand:


// MARK: - UTILITIES -


//========== undoActionKey =====================================================
- (NSString *) undoActionKey
{
	return @"UndoAttributesResolution";

}//end undoActionKey


@end
