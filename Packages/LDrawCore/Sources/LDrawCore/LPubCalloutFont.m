//==============================================================================
//
//  File:       LPubCalloutFont.m
//  Package:    LDrawCore
//
//  Purpose:    The font or the color of the text in a callout's box.
//
//              Line format:
//              0 !LPUB CALLOUT (STEP_NUMBER | INSTANCE_COUNT) FONT
//                  [GLOBAL|LOCAL] "<family>,<point size>,<pixel size>,
//                  <style hint>,<weight>,<slant>,..."
//              0 !LPUB CALLOUT (STEP_NUMBER | INSTANCE_COUNT) FONT_COLOR
//                  [GLOBAL|LOCAL] <color>
//
//              A parsed line is written back as it was read.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubCalloutFont.h>

#import <LDrawCore/LDrawKeywords.h>


/// Where each value sits in a font's description.
static const NSUInteger FONT_FAMILY_FIELD		= 0;
static const NSUInteger FONT_POINT_SIZE_FIELD	= 1;
static const NSUInteger FONT_PIXEL_SIZE_FIELD	= 2;
static const NSUInteger FONT_WEIGHT_FIELD		= 4;
static const NSUInteger FONT_SLANT_FIELD		= 5;

/// A description from Qt 5 has this many values, and weighs a font from 0 to
/// 99. Qt 6 writes more values, and weighs from 1 to 1000.
static const NSUInteger	QT5_FIELD_COUNT			= 10;
static const double		QT5_BOLD_WEIGHT			= 63.0;
static const double		QT6_BOLD_WEIGHT			= 600.0;


@implementation LPubCalloutFont


// MARK: - INITIALIZATION -


//========== init ==============================================================
- (id) init
{
	self = [super init];
	if (self) {
		self->_part		= LPubCalloutPartStepNumber;
		self->_color	= LPubColorBlack;
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
	if (parameters.count < 4 || [parameters[0] isEqualToString:LPUB_CALLOUT] == NO) {
		return nil;
	}

	LPubCalloutPart	part	= LPubCalloutPartStepNumber;
	BOOL			isColor	= [parameters[2] isEqualToString:LPUB_CALLOUT_FONT_COLOR];

	if ([LPubCalloutMargins getPart:&part fromToken:parameters[1]] == NO
		|| (part != LPubCalloutPartStepNumber && part != LPubCalloutPartInstanceCount)
		|| (isColor == NO && [parameters[2] isEqualToString:LPUB_CALLOUT_FONT] == NO)) {
		return nil;
	}

	NSUInteger		index	= 3;
	LPubMetaScope	scope	= [LPubCommand scopeInParameters:parameters index:&index];

	// The value is the last token, and there must be nothing after it.
	if (index != parameters.count - 1) {
		return nil;
	}

	LPubCalloutFont *command = [LPubCalloutFont new];

	command->_scope		= scope;
	command->_part		= part;
	command->_isColor	= isColor;

	if (isColor) {
		// A color that cannot be read is drawn black, as in LPub3D.
		if (LPubColorComponentsFromString(parameters[index], &command->_color) == NO) {
			command->_color = LPubColorBlack;
		}
	}
	else if ([command readDescription:parameters[index]] == NO) {
		return nil;
	}

	[command adoptCommandString:[parameters componentsJoinedByString:@" "]];

	return command;

}//end lpubCommandInstance:


//========== readDescription: ==================================================
///
/// @abstract	Reads a font as Qt describes one. NO without a family and a
/// 			size.
///
/// @discussion	A size in points of -1 means the size is given in pixels.
///
//==============================================================================
- (BOOL) readDescription:(NSString *)description
{
	NSCharacterSet		*quotes	= [NSCharacterSet characterSetWithCharactersInString:@"\""];
	NSString			*text	= [description stringByTrimmingCharactersInSet:quotes];
	NSArray<NSString *>	*fields	= [text componentsSeparatedByString:@","];
	double				 size	= 0.0;
	double				 weight	= 0.0;
	double				 slant	= 0.0;

	if (fields.count <= FONT_POINT_SIZE_FIELD || fields[FONT_FAMILY_FIELD].length == 0) {
		return NO;
	}

	if ([LPubCommand getPositiveNumber:&size fromToken:fields[FONT_POINT_SIZE_FIELD]] == NO
		&& (fields.count <= FONT_PIXEL_SIZE_FIELD
			|| [LPubCommand getPositiveNumber:&size fromToken:fields[FONT_PIXEL_SIZE_FIELD]] == NO)) {
		return NO;
	}

	if (fields.count > FONT_WEIGHT_FIELD) {
		[LPubCommand getNumber:&weight fromToken:fields[FONT_WEIGHT_FIELD]];
	}
	if (fields.count > FONT_SLANT_FIELD) {
		[LPubCommand getNumber:&slant fromToken:fields[FONT_SLANT_FIELD]];
	}

	self->_family	= [fields[FONT_FAMILY_FIELD] copy];
	self->_size		= size;
	self->_isBold	= weight >= ((fields.count > QT5_FIELD_COUNT) ? QT6_BOLD_WEIGHT : QT5_BOLD_WEIGHT);
	self->_isItalic	= slant > 0.0;

	return YES;

}//end readDescription:


// MARK: - DISPLAY -


//========== browsingDescription ===============================================
///
/// @abstract	A short description of the line, shown to the user.
///
//==============================================================================
- (NSString *) browsingDescription
{
	NSString *name = [LPubCalloutMargins nameForPart:self.part];

	if (self.isColor) {
		return [NSString stringWithFormat:@"%@ %@ %@", LPUB_CALLOUT, name, LPUB_CALLOUT_FONT_COLOR];
	}

	return [NSString stringWithFormat:@"%@ %@ %@ [%@ %g]", LPUB_CALLOUT, name, LPUB_CALLOUT_FONT,
			self.family, self.size];

}//end browsingDescription


// MARK: - ACCESSORS -


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubCalloutFont *other = (LPubCalloutFont *)command;

	self->_scope	= other->_scope;
	self->_part		= other->_part;
	self->_isColor	= other->_isColor;
	self->_family	= [other->_family copy];
	self->_size		= other->_size;
	self->_isBold	= other->_isBold;
	self->_isItalic	= other->_isItalic;
	self->_color	= other->_color;

}//end adoptPropertiesFromCommand:


@end
