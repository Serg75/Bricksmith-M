//==============================================================================
//
//  File:       LPubCalloutSubmodelColor.m
//  Package:    LDrawCore
//
//  Purpose:    The fill of a callout's box at each depth of submodel.
//
//              Line format:
//              0 !LPUB CALLOUT SUBMODEL_BACKGROUND_COLOR [GLOBAL|LOCAL]
//                  <color> [<color> ...]
//
//              A parsed line is written back as it was read.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubCalloutSubmodelColor.h>

#import <LDrawCore/LDrawKeywords.h>


@implementation LPubCalloutSubmodelColor
{
	/// The colors, as LPubColorComponents values.
	NSData *_colors;
}


// MARK: - INITIALIZATION -


//========== init ==============================================================
///
/// @abstract	With no line behind it, LPub3D's four colors.
///
//==============================================================================
- (id) init
{
	self = [super init];
	if (self) {
		self->_colors = [LPubCalloutSubmodelColor colorsFromNames:@[@"#FFFFFF", @"#FFFFCC", @"#FFCCCC", @"#CCCCFF"]];
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
	if (parameters.count < 3
		|| [parameters[0] isEqualToString:LPUB_CALLOUT] == NO
		|| [parameters[1] isEqualToString:LPUB_CALLOUT_SUBMODEL_COLOR] == NO) {
		return nil;
	}

	NSUInteger		index	= 2;
	LPubMetaScope	scope	= [LPubCommand scopeInParameters:parameters index:&index];

	if (index >= parameters.count) {
		return nil;
	}

	NSRange						 range		= NSMakeRange(index, parameters.count - index);
	LPubCalloutSubmodelColor	*command	= [LPubCalloutSubmodelColor new];

	command->_scope		= scope;
	command->_colors	= [self colorsFromNames:[parameters subarrayWithRange:range]];
	[command adoptCommandString:[parameters componentsJoinedByString:@" "]];

	return command;

}//end lpubCommandInstance:


//---------- colorsFromNames: ----------------------------------------[static]--
///
/// @abstract	Reads each name. One that cannot be read is black, as in LPub3D.
///
//------------------------------------------------------------------------------
+ (NSData *) colorsFromNames:(NSArray<NSString *> *)names
{
	NSMutableData *colors = [NSMutableData dataWithCapacity:names.count * sizeof(LPubColorComponents)];

	for (NSString *name in names) {
		LPubColorComponents color = LPubColorBlack;

		if (LPubColorComponentsFromString(name, &color) == NO) {
			color = LPubColorBlack;
		}
		[colors appendBytes:&color length:sizeof(LPubColorComponents)];
	}

	return colors;

}//end colorsFromNames:


// MARK: - DISPLAY -


//========== browsingDescription ===============================================
///
/// @abstract	A short description of the line, shown to the user.
///
//==============================================================================
- (NSString *) browsingDescription
{
	return [NSString stringWithFormat:@"%@ %@ [%lu]", LPUB_CALLOUT, LPUB_CALLOUT_SUBMODEL_COLOR,
			(unsigned long)self.colorCount];

}//end browsingDescription


// MARK: - ACCESSORS -


- (NSUInteger) colorCount
{
	return self->_colors.length / sizeof(LPubColorComponents);
}


//========== colorAtLevel: =====================================================
- (LPubColorComponents) colorAtLevel:(NSUInteger)level
{
	NSUInteger count = self.colorCount;

	if (count == 0) {
		return LPubColorBlack;
	}

	return ((const LPubColorComponents *)self->_colors.bytes)[MIN(level, count - 1)];

}//end colorAtLevel:


//---------- defaultColorAtLevel: ------------------------------------[static]--
+ (LPubColorComponents) defaultColorAtLevel:(NSUInteger)level
{
	return [[LPubCalloutSubmodelColor new] colorAtLevel:level];

}//end defaultColorAtLevel:


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubCalloutSubmodelColor *other = (LPubCalloutSubmodelColor *)command;

	self->_scope	= other->_scope;
	self->_colors	= other->_colors;

}//end adoptPropertiesFromCommand:


@end
