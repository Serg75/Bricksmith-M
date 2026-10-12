//==============================================================================
//
//  File:       LPubCalloutAlloc.m
//  Package:    LDrawCore
//
//  Purpose:    Which way the steps in a callout's box run.
//
//              Line format:
//              0 !LPUB CALLOUT ALLOC [GLOBAL|LOCAL] (HORIZONTAL|VERTICAL)
//
//              A parsed line is written back as it was read.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubCalloutAlloc.h>

#import <LDrawCore/LDrawKeywords.h>


@implementation LPubCalloutAlloc


// MARK: - INITIALIZATION -


//========== init ==============================================================
///
/// @abstract	With no line behind it, the steps run downward, as in LPub3D.
///
//==============================================================================
- (id) init
{
	self = [super init];
	if (self) {
		self->_isVertical = YES;
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
		|| [parameters[1] isEqualToString:LPUB_CALLOUT_ALLOC] == NO) {
		return nil;
	}

	NSUInteger		index	= 2;
	LPubMetaScope	scope	= [LPubCommand scopeInParameters:parameters index:&index];

	// The direction is the last token, and there must be nothing after it.
	if (index != parameters.count - 1) {
		return nil;
	}

	BOOL		isVertical	= YES;
	NSString	*token		= parameters[index];

	if ([token isEqualToString:LPUB_CALLOUT_VERTICAL]) {
		isVertical = YES;
	}
	else if ([token isEqualToString:LPUB_CALLOUT_HORIZONTAL]) {
		isVertical = NO;
	}
	else {
		return nil;
	}

	LPubCalloutAlloc *command = [LPubCalloutAlloc new];

	command->_scope			= scope;
	command->_isVertical	= isVertical;
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
	return [NSString stringWithFormat:@"%@ %@ [%@]", LPUB_CALLOUT, LPUB_CALLOUT_ALLOC,
			self.isVertical ? LPUB_CALLOUT_VERTICAL : LPUB_CALLOUT_HORIZONTAL];

}//end browsingDescription


// MARK: - ACCESSORS -


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubCalloutAlloc *other = (LPubCalloutAlloc *)command;

	self->_scope		= other->_scope;
	self->_isVertical	= other->_isVertical;

}//end adoptPropertiesFromCommand:


@end
