//==============================================================================
//
//  File:       LPubCommand.m
//  Package:    LDrawCore
//
//  Purpose:    A generic LPub command.
//
//              Line format:
//              0 !LPUB command parameter-1 parameter-2 ...
//
//              where
//
//              * command is a command itself
//              * parameter-1, parameter-2 etc. are optional command parameters
//
//  Created by Sergey Slobodenyuk on 2023-02-08.
//
//==============================================================================

#import <LDrawCore/LDrawKeywords.h>
#import <LDrawCore/LDrawLocalization.h>
#import <LDrawCore/LDrawUtilities.h>
#import <LDrawCore/LPubCommand.h>
#import <LDrawCore/NSScanner+LDraw.h>

#import "LDrawClassInspector.h"


static NSString * const		LPUB_COMMAND_STRING_KEY = @"lpubCommandString";
static NSArray<Class>		*subclasses;


//========== ScopeForKeyword() =================================================
///
/// @abstract	Reads a token as a scope. Returns Unspecified when the token is
/// 			not a scope keyword.
///
//==============================================================================
static LPubMetaScope ScopeForKeyword(NSString *keyword)
{
	if ([keyword isEqualToString:LPUB_SCOPE_GLOBAL]) {
		return LPubMetaScopeGlobal;
	}
	if ([keyword isEqualToString:LPUB_SCOPE_LOCAL]) {
		return LPubMetaScopeLocal;
	}
	return LPubMetaScopeUnspecified;

}//end ScopeForKeyword


@implementation LPubCommand

// MARK: - INITIALIZATION -


//---------- initialize ----------------------------------------------[static]--
///
/// @abstract	Bulds subclasses tree to delegate them lpubCommandInstance:
///				method.
///
//------------------------------------------------------------------------------
+ (void)initialize
{
	if (self == [LPubCommand class]) {
		subclasses = [LDrawClassInspector firstLevelSubclassesFor:[self class]];
	}
	
}//end initialize


//========== init ==============================================================
///
/// @abstract	Initialize an empty command.
///
//==============================================================================
- (id) init
{
	self = [super init];
	if (self) {
		[self setLPubCommandString:@""];
	}
	return self;
	
}//end init


//========== initWithCoder: ====================================================
///
/// @abstract	Reads a representation of this object from the given coder,
///				which is assumed to always be a keyed decoder. This allows us to
///				read and write LDraw objects as NSData.
///
//==============================================================================
- (id)initWithCoder:(NSCoder *)decoder
{
	self = [super initWithCoder:decoder];
	
	// Go through the setter so a subclass re-derives its properties from the
	// text. Subclasses that archive properties decode them after this.
	[self setLPubCommandString:[decoder decodeObjectForKey:LPUB_COMMAND_STRING_KEY] ?: @""];
	
	return self;
	
}//end initWithCoder:


//========== encodeWithCoder: ==================================================
//
// Purpose:		Writes a representation of this object to the given coder,
//				which is assumed to always be a keyed decoder. This allows us to
//				read and write LDraw objects as NSData.
//
//==============================================================================
- (void) encodeWithCoder:(NSCoder *)encoder
{
	[super encodeWithCoder:encoder];
	
	[encoder encodeObject:_lPubCommandString forKey:LPUB_COMMAND_STRING_KEY];
	
}//end encodeWithCoder:


//========== copyWithZone: =====================================================
//
// Purpose:		Returns a duplicate of this file.
//
//==============================================================================
- (id) copyWithZone:(NSZone *)zone
{
	LPubCommand *copied = (LPubCommand *)[super copyWithZone:zone];

	// Text last, as typed: rebuilding it from the properties would lose a
	// line that no longer parses.
	[copied adoptPropertiesFromCommand:self];
	[copied adoptCommandString:self.lPubCommandString];

	return copied;

}//end copyWithZone:


//---------- metaCommandInstanceByMarker:scanner: --------------------[static]--
///
/// @abstract	Here we parse the command marker and create proper subclass
/// 			instance of LDrawMetaCommand.
///
/// 			Command syntax:
///				0 !LPUB <param1> {<param2> <param3>}
///
/// @discussion	LPUB command may be extracted to its own class, like
/// 			LPubRemoveGroup.
///
//------------------------------------------------------------------------------
+ (LDrawMetaCommand *) metaCommandInstanceByMarker:(NSString *)ldrawMarker scanner:(NSScanner *)scanner
{
	LPubCommand			*command = nil;
	NSArray<NSString *>	*parameters;

	if ([ldrawMarker isEqualToString:LPUB_COMMAND])
	{
		parameters = [scanner scanSubstringsWithQuotations];

		for (Class subclass in subclasses) {
			command = [subclass lpubCommandInstance:parameters];
			if (command) {
				return command;
			}
		}

		return [LPubCommand new];
	}
	return nil;
}


//---------- lpubCommandInstance: ------------------------------------[static]--
///
/// @abstract	If LPub command is in a separate subclass, it should override
/// 			this method to create its own instance.
///
//------------------------------------------------------------------------------
+ (LPubCommand *) lpubCommandInstance:(NSArray<NSString *> *)parameters
{
	return nil;
}


//========== finishParsing: ====================================================
///
/// @abstract	metaCommandInstanceByMarker:remainder: is responsible for
/// 			parsing out the line code and LPub command (i.e., "0 !LPUB");
/// 			now we just have to finish the LPub-command specific syntax.
/// 			As it happens, that is everything after the LPub command.
///
//==============================================================================
- (BOOL) finishParsing:(NSScanner *)scanner
{
	// The line as typed, the same as an edit in the inspector. The setter
	// parses it again, so CONSTRAIN still writes its own form.
	self.lPubCommandString = [[scanner string] substringFromIndex:[scanner scanLocation]];

	return YES;
	
}//end lineWithDirectiveText


// MARK: - DISPLAY -

//========== browsingDescription ===============================================
///
/// @abstract	Returns a representation of the directive as a short string
///				which can be presented to the user.
///
//==============================================================================
- (NSString *) browsingDescription
{
	return self.lPubCommandString;
	
}//end browsingDescription


//========== iconName ==========================================================
///
/// @abstract	Returns the name of image file used to display this kind of
///				object, or nil if there is no icon.
///
//==============================================================================
- (NSString *) iconName
{
	return @"LPub";
	
}//end iconName


// MARK: - ACCESSORS -


//---------- scopeInParameters:index: -------------------------------[static]--
///
/// @abstract	Reads the scope keyword at *index, if there is one, and moves
/// 			*index past it.
///
//------------------------------------------------------------------------------
+ (LPubMetaScope) scopeInParameters:(NSArray<NSString *> *)parameters index:(NSUInteger *)index
{
	if (*index >= parameters.count) {
		return LPubMetaScopeUnspecified;
	}

	LPubMetaScope scope = ScopeForKeyword(parameters[*index]);

	if (scope != LPubMetaScopeUnspecified) {
		*index += 1;
	}
	return scope;

}//end scopeInParameters:index:


//---------- subclassNames--------------------------------------------[static]--
///
/// @abstract	Convenient method for debugging and testsing.
///
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)subclassNames
{
	NSMutableArray<NSString *> *result = [NSMutableArray array];
	[subclasses enumerateObjectsUsingBlock:^(Class  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
			[result addObject:NSStringFromClass(obj)];
	}];
	return result;
	
}//end subclassNames


//---------- getNumber:fromToken: ------------------------------------[static]--
+ (BOOL) getNumber:(double *)outValue fromToken:(NSString *)token
{
	NSScanner	*scanner	= [NSScanner scannerWithString:token];
	double		 parsed		= 0.0;

	if ([scanner scanDouble:&parsed] == NO || scanner.isAtEnd == NO || isfinite(parsed) == NO) {
		return NO;
	}

	*outValue = parsed;
	return YES;

}//end getNumber:fromToken:


//---------- getPositiveNumber:fromToken: ----------------------------[static]--
+ (BOOL) getPositiveNumber:(double *)outValue fromToken:(NSString *)token
{
	double parsed = 0.0;

	if ([self getNumber:&parsed fromToken:token] == NO || parsed <= 0.0) {
		return NO;
	}

	*outValue = parsed;
	return YES;

}//end getPositiveNumber:fromToken:


//---------- getInteger:fromToken:atLeast: --------------------------[static]--
+ (BOOL) getInteger:(NSInteger *)outValue fromToken:(NSString *)token atLeast:(NSInteger)minimum
{
	NSScanner	*scanner	= [NSScanner scannerWithString:token];
	NSInteger	 parsed		= 0;

	if ([scanner scanInteger:&parsed] == NO || scanner.isAtEnd == NO || parsed < minimum) {
		return NO;
	}

	*outValue = parsed;
	return YES;

}//end getInteger:fromToken:atLeast:


//========== setLPubCommandString: =============================================
///
/// @abstract	Updates the command string, and the properties a subclass
/// 			derives from it.
///
/// @discussion	The text is parsed again so the properties match it. Text
/// 			that no longer parses leaves the properties as they were.
///
//==============================================================================
-(void) setLPubCommandString:(NSString *)newString
{
	[self adoptCommandString:newString];

	// Split the text the way the file parser does, so a quoted name stays whole.
	NSScanner			*scanner	= [NSScanner scannerWithString:newString ?: @""];
	NSArray<NSString *>	*tokens		= [scanner scanSubstringsWithQuotations];
	LPubCommand			*reparsed	= [[self class] lpubCommandInstance:tokens];

	if (reparsed != nil) {
		[self adoptPropertiesFromCommand:reparsed];
	}

}//end setLPubCommandString:


//========== adoptCommandString: ===============================================
///
/// @abstract	Stores the text without re-deriving anything from it.
///
//==============================================================================
- (void) adoptCommandString:(NSString *)commandString
{
	_lPubCommandString = [commandString copy];
	super.commandString = [NSString stringWithFormat:@"%@ %@", LPUB_COMMAND, commandString];

}//end adoptCommandString:


//========== adoptPropertiesFromCommand: ======================================
///
/// @abstract	A plain command has no properties beyond its text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	// Nothing to take.

}//end adoptPropertiesFromCommand:


// MARK: - UTILITIES -

//========== registerUndoActions ===============================================
///
/// @abstract	Registers the undo actions that are unique to this subclass,
///				not to any superclass.
///
//==============================================================================
- (void) registerUndoActions:(NSUndoManager *)undoManager
{
	[super registerUndoActions:undoManager];
	
	// Setting the text parses it again, which restores a subclass's properties.
	[[undoManager prepareWithInvocationTarget:self] setLPubCommandString:self.lPubCommandString];
	
	[undoManager setActionName:[LDrawLocalization stringForKey:[self undoActionKey]]];
	
}//end registerUndoActions:


//========== undoActionKey =====================================================
///
/// @abstract	The localization key for the undo action name. Subclasses
/// 			return their own.
///
//==============================================================================
- (NSString *) undoActionKey
{
	return @"UndoAttributesLPubCommand";

}//end undoActionKey


//========== replacementForText: ===============================================
///
/// @abstract	Parses the text as a whole line, the way opening the file does.
/// 			Returns nil when that gives the receiver's class, because the
/// 			setter can take the text then.
///
//==============================================================================
- (nullable LPubCommand *) replacementForText:(NSString *)text
{
	NSString	*line	= [NSString stringWithFormat:@"0 %@ %@", LPUB_COMMAND, text ?: @""];
	id			 parsed	= [[LDrawMetaCommand alloc] initWithLines:@[line]
														  inRange:NSMakeRange(0, 1)
													  parentGroup:NULL];

	// It is not an LPubCommand only when the parser failed.
	if ([parsed isKindOfClass:[LPubCommand class]] == NO || [parsed class] == [self class]) {
		return nil;
	}
	return parsed;

}//end replacementForText:


@end
