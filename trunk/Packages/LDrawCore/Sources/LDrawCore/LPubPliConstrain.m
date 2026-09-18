//==============================================================================
//
//  File:       LPubPliConstrain.m
//  Package:    LDrawCore
//
//  Purpose:    LPub PLI CONSTRAIN command: how the parts list box is packed.
//
//              Line format:
//              0 !LPUB PLI CONSTRAIN [GLOBAL|LOCAL] AREA
//              0 !LPUB PLI CONSTRAIN [GLOBAL|LOCAL] SQUARE
//              0 !LPUB PLI CONSTRAIN [GLOBAL|LOCAL] WIDTH <double>
//              0 !LPUB PLI CONSTRAIN [GLOBAL|LOCAL] HEIGHT <double>
//              0 !LPUB PLI CONSTRAIN [GLOBAL|LOCAL] COLS <int>
//
//              GLOBAL and no keyword hold from the line on, LOCAL for the rest
//              of its step. WIDTH and HEIGHT are inches on the printed page.
//
//              A line in any other form is left to the generic LPubCommand,
//              which writes it back unchanged.
//
//  Created by Sergey Slobodenyuk on 2026-09-09.
//
//==============================================================================

#import <LDrawCore/LPubPliConstrain.h>

#import <LDrawCore/LDrawKeywords.h>


static NSString * const		SCOPE_KEY	= @"scope";
static NSString * const		MODE_KEY	= @"mode";
static NSString * const		VALUE_KEY	= @"value";
static NSString * const		COLUMNS_KEY	= @"columns";

@implementation LPubPliConstrain


// MARK: - INITIALIZATION -


//========== init ==============================================================
///
/// @abstract	A constraint with no line behind it is the default, AREA.
///
//==============================================================================
- (id) init
{
	self = [super init];
	if (self) {
		[self updateCommandString];
	}
	return self;

}//end init


//========== initWithCoder: ====================================================
///
/// @abstract	Reads this object back from a keyed coder.
///
//==============================================================================
- (id) initWithCoder:(NSCoder *)decoder
{
	self = [super initWithCoder:decoder];

	self->_scope	= [decoder decodeIntegerForKey:SCOPE_KEY];
	self->_mode		= [decoder decodeIntegerForKey:MODE_KEY];
	self->_inches	= [decoder decodeDoubleForKey:VALUE_KEY];
	self->_columns	= [decoder decodeIntegerForKey:COLUMNS_KEY];

	return self;

}//end initWithCoder:


//========== encodeWithCoder: ==================================================
//
// Purpose:		Writes this object to a keyed coder.
//
//==============================================================================
- (void) encodeWithCoder:(NSCoder *)encoder
{
	[super encodeWithCoder:encoder];

	[encoder encodeInteger:self->_scope forKey:SCOPE_KEY];
	[encoder encodeInteger:self->_mode forKey:MODE_KEY];
	[encoder encodeDouble:self->_inches forKey:VALUE_KEY];
	[encoder encodeInteger:self->_columns forKey:COLUMNS_KEY];

}//end encodeWithCoder:


//---------- lpubCommandInstance: ------------------------------------[static]--
///
/// @abstract	Builds the command from the line's words, or nil if the
/// 			line is not this command.
///
/// 			Command syntax:
///				0 !LPUB PLI CONSTRAIN [GLOBAL|LOCAL] (AREA | SQUARE |
///					WIDTH <double> | HEIGHT <double> | COLS <int>)
///
//------------------------------------------------------------------------------
+ (LPubCommand *) lpubCommandInstance:(NSArray<NSString *> *)parameters
{
	if (parameters.count < 3
		|| [parameters[0] isEqualToString:LPUB_PLI] == NO
		|| [parameters[1] isEqualToString:LPUB_PLI_CONSTRAIN] == NO) {
		return nil;
	}

	NSUInteger		index	= 2;
	LPubMetaScope	scope	= [LPubCommand scopeInParameters:parameters index:&index];

	if (index >= parameters.count) {
		return nil;
	}

	NSString	*modeKeyword	= parameters[index];
	NSUInteger	argumentCount	= parameters.count - (index + 1);
	NSString	*argument		= (argumentCount == 1) ? parameters[index + 1] : nil;

	LPubPliConstrainMode	mode	= LPubPliConstrainModeArea;
	double					inches	= 0.0;
	NSInteger				columns	= 0;

	if (argumentCount == 0 && [modeKeyword isEqualToString:LPUB_PLI_CONSTRAIN_AREA]) {
		mode = LPubPliConstrainModeArea;
	}
	else if (argumentCount == 0 && [modeKeyword isEqualToString:LPUB_PLI_CONSTRAIN_SQUARE]) {
		mode = LPubPliConstrainModeSquare;
	}
	else if (argument != nil && [modeKeyword isEqualToString:LPUB_PLI_CONSTRAIN_WIDTH]) {
		if ([LPubCommand getPositiveNumber:&inches fromToken:argument] == NO) {
			return nil;
		}
		mode = LPubPliConstrainModeWidth;
	}
	else if (argument != nil && [modeKeyword isEqualToString:LPUB_PLI_CONSTRAIN_HEIGHT]) {
		if ([LPubCommand getPositiveNumber:&inches fromToken:argument] == NO) {
			return nil;
		}
		mode = LPubPliConstrainModeHeight;
	}
	else if (argument != nil && [modeKeyword isEqualToString:LPUB_PLI_CONSTRAIN_COLS]) {
		if ([LPubCommand getInteger:&columns fromToken:argument atLeast:1] == NO) {
			return nil;
		}
		mode = LPubPliConstrainModeColumns;
	}
	else {
		return nil;
	}

	LPubPliConstrain *command = [LPubPliConstrain new];

	command->_scope		= scope;
	command->_mode		= mode;
	command->_inches	= inches;
	command->_columns	= columns;
	[command updateCommandString];

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
	return [NSString stringWithFormat:@"%@ %@ [%@]", LPUB_PLI, LPUB_PLI_CONSTRAIN, [self constraintDescription]];

}//end browsingDescription


// MARK: - ACCESSORS -


- (void) setScope:(LPubMetaScope)newScope
{
	self->_scope	= newScope;
	[self updateCommandString];
}

- (void) setMode:(LPubPliConstrainMode)newMode
{
	self->_mode	= newMode;
	[self updateCommandString];
}

- (void) setInches:(double)newInches
{
	self->_inches	= newInches;
	[self updateCommandString];
}

- (void) setColumns:(NSInteger)newColumns
{
	self->_columns	= newColumns;
	[self updateCommandString];
}


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubPliConstrain *other = (LPubPliConstrain *)command;

	self->_scope	= other->_scope;
	self->_mode		= other->_mode;
	self->_inches	= other->_inches;
	self->_columns	= other->_columns;

	// Then the text, in the form LPub3D writes.
	[self updateCommandString];

}//end adoptPropertiesFromCommand:


// MARK: - UTILITIES -


//========== constraintDescription =============================================
///
/// @abstract	The mode and its argument, as they are written into the file.
///
/// @discussion	Four decimals, matching LPub3D's page-size precision.
///
//==============================================================================
- (NSString *) constraintDescription
{
	switch (self.mode) {
		case LPubPliConstrainModeArea:
			return LPUB_PLI_CONSTRAIN_AREA;

		case LPubPliConstrainModeSquare:
			return LPUB_PLI_CONSTRAIN_SQUARE;

		case LPubPliConstrainModeWidth:
			return [NSString stringWithFormat:@"%@ %.4f", LPUB_PLI_CONSTRAIN_WIDTH, self.inches];

		case LPubPliConstrainModeHeight:
			return [NSString stringWithFormat:@"%@ %.4f", LPUB_PLI_CONSTRAIN_HEIGHT, self.inches];

		case LPubPliConstrainModeColumns:
			return [NSString stringWithFormat:@"%@ %ld", LPUB_PLI_CONSTRAIN_COLS, (long)self.columns];

		// Reached only from a damaged archive. AREA is the default mode.
		default:
			return LPUB_PLI_CONSTRAIN_AREA;
	}

}//end constraintDescription


//========== updateCommandString ===============================================
///
/// @abstract	Rebuilds the line from the properties, in the form LPub3D
/// 			writes.
///
//==============================================================================
- (void) updateCommandString
{
	NSMutableArray<NSString *> *tokens = [NSMutableArray arrayWithObjects:LPUB_PLI, LPUB_PLI_CONSTRAIN, nil];

	switch (self.scope) {
		case LPubMetaScopeGlobal:		[tokens addObject:LPUB_SCOPE_GLOBAL];	break;
		case LPubMetaScopeLocal:		[tokens addObject:LPUB_SCOPE_LOCAL];	break;
		case LPubMetaScopeUnspecified:	break;
	}

	[tokens addObject:[self constraintDescription]];

	[self adoptCommandString:[tokens componentsJoinedByString:@" "]];

}//end updateCommandString


//========== undoActionKey =====================================================
- (NSString *) undoActionKey
{
	return @"UndoAttributesPliConstrain";

}//end undoActionKey


@end
