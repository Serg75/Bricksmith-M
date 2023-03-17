//==============================================================================
//
//  LPubCommand.m
//  Bricksmith
//
//  Purpose:	A generic LPub command.
//
//				Line format:
//				0 !LPUB command parameter-1 parameter-2 ...
//
//				where
//
//				* command is a command itself
//				* parameter-1, parameter-2 etc. are optional command parameters
//
//  Created by Sergey Slobodenyuk on 2023-02-08.
//
//==============================================================================

#import "LPubCommand.h"

#import "ClassInspector.h"
#import "LDrawKeywords.h"
#import "LDrawUtilities.h"
#import "ScannerCategory.h"


static NSString * const		LPUB_COMMAND_STRING_KEY = @"lpubCommandString";
static NSArray<Class>		*subclasses;


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
		subclasses = [ClassInspector firstLevelSubclassesFor:[self class]];
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
	
	_lPubCommandString	= [decoder decodeObjectForKey:LPUB_COMMAND_STRING_KEY];
	
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
	
	copied.lPubCommandString = self.lPubCommandString;

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
	NSString	*remainder	= nil;
	
	remainder = [[scanner string] substringFromIndex:[scanner scanLocation]];
	self.lPubCommandString = remainder;
	
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


//========== inspectorClassName ================================================
///
/// @abstract	Returns the name of the class used to inspect this one.
///
//==============================================================================
- (NSString *) inspectorClassName
{
	return @"InspectionLPubCommand";
	
}//end inspectorClassName


// MARK: - ACCESSORS -


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


//========== setLPubCommandString: =============================================
///
/// @abstract	Updates the command string.
///
//==============================================================================
-(void) setLPubCommandString:(NSString *)newString
{
	_lPubCommandString = [newString copy];
	super.commandString = [NSString stringWithFormat:@"%@ %@", LPUB_COMMAND, newString];

}//end setLPubCommandString:


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
	
	[[undoManager prepareWithInvocationTarget:self] setLPubCommandString:self.lPubCommandString];
	
	[undoManager setActionName:NSLocalizedString(@"UndoAttributesLPubCommand", nil)];
	
}//end registerUndoActions:


@end
