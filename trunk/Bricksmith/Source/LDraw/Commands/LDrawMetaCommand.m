//==============================================================================
//
// File:		LDrawMetaCommand.m
//
// Purpose:		Meta-command holder.
//				Could do just about anything, but only in subclasses!
//
//				Line format:
//				0 command... 
//
//				where
//
//				* command is a string; it could mean anything. We have specific 
//				subclasses to deal with recognized meta-commands. This class is 
//				the fallback class for unrecognized commands. 
//
//  Created by Allen Smith on 2/21/05.
//  Copyright (c) 2005. All rights reserved.
//==============================================================================
#import "LDrawMetaCommand.h"

#import "ClassInspector.h"
#import "LDrawColor.h"
#import "LDrawUtilities.h"


static NSArray<Class>	*subclasses;


@implementation LDrawMetaCommand


#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//---------- initialize ----------------------------------------------[static]--
///
/// @abstract	Gets knowledge about subclasses.
///
//------------------------------------------------------------------------------
+ (void)initialize
{
	if (self == [LDrawMetaCommand class]) {
		subclasses = [ClassInspector firstLevelSubclassesFor:[self class]];
	}
}


//========== init ==============================================================
//
// Purpose:		Initialize an empty command.
//
//==============================================================================
- (id) init
{
	self = [super init];
	if (self) {
		[self setCommandString:@""];
	}
	return self;
	
}//end init


//========== initWithLines:inRange:parentGroup: ================================
//
// Purpose:		Returns the LDraw directive based on lineFromFile, a single line 
//				of LDraw code from a file.
//
//				directive should have the format:
//
//				0 command... 
//
//				This method determines and returns a subclass instance for known 
//				meta-commands. As such, the instance returned will always be of 
//				a different class, and thus will always be a different instance 
//				than the receiver. 
//
//==============================================================================
- (id) initWithLines:(NSArray *)lines
			 inRange:(NSRange)range
		 parentGroup:(dispatch_group_t)parentGroup
{
	self = [super init];

	LDrawMetaCommand	*directive		= nil;
	NSString			*parsedField	= nil;
	NSString			*firstLine		= [lines objectAtIndex:range.location];
	NSScanner			*scanner		= [NSScanner scannerWithString:firstLine];
	int 				lineCode		= 0;
	BOOL				gotLineCode 	= 0;
	NSUInteger			metaLineStart	= 0;
	NSUInteger			remainderStart	= 0;
	
	[scanner setCharactersToBeSkipped:nil];
	
	//A malformed part could easily cause a string indexing error, which would 
	// raise an exception. We don't want this to happen here.
	@try
	{
		// skip leading whitespace
		[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:nil];
		
		//Read in the line code and advance past it.
		gotLineCode = [scanner scanInt:&lineCode];
		
		if(gotLineCode == YES && lineCode == 0)
		{
			// The first word of a meta-command should indicate the command 
			// itself, and thus the syntax of the rest of the line. However, the 
			// first word might not be a recognized command. It might not even 
			// be anything. "0\n" is perfectly valid LDraw.
			[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:nil];
			metaLineStart = scanner.scanLocation;
			
			[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&parsedField];

			// skip whitespace
			[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:nil];

			remainderStart = scanner.scanLocation;
		
			for (Class subclass in subclasses) {
				directive = [subclass metaCommandInstanceByMarker:parsedField scanner:scanner];
				scanner.scanLocation = remainderStart;
				if (directive) {
					break;
				}
			}
			
			// If we recognized the metacommand, use the subclass to finish 
			// parsing. 
			if(directive != nil)
			{
				[directive finishParsing:scanner]; // throws exceptions on error
			}
			else
			{
				// Didn't specifically recognize this metacommand. Create a 
				// non-functional generic command to record its existence. 
				directive = self;
				NSString *command = [[scanner string] substringFromIndex:metaLineStart];
		
				directive.commandString = command;
			}
		}
		else if(gotLineCode == NO)
		{
			// This is presumably an empty line, and the following will 
			// incorrectly add a 0 linetype to it. 
			directive = self;
			NSString *command = [scanner string];
	
			directive.commandString = command;
		}
		else
		{
			// nonzero linetype!
			@throw [NSException exceptionWithName:@"BricksmithParseException" reason:@"Bad metacommand syntax" userInfo:nil];
		}
	}		
	@catch(NSException *exception)
	{
		NSLog(@"the meta-command %@ was fatally invalid", [lines objectAtIndex:range.location]);
		NSLog(@" raised exception %@", [exception name]);
	}
	
	// The new directive should replace the receiver!
	self = nil;
	
	return directive;
	
}//end initWithLines:inRange:


//========== initWithCoder: ====================================================
//
// Purpose:		Reads a representation of this object from the given coder,
//				which is assumed to always be a keyed decoder. This allows us to 
//				read and write LDraw objects as NSData.
//
//==============================================================================
- (id)initWithCoder:(NSCoder *)decoder
{
	self = [super initWithCoder:decoder];
	
	_commandString	= [decoder decodeObjectForKey:@"commandString"];
	
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
	
	[encoder encodeObject:_commandString forKey:@"commandString"];
	
}//end encodeWithCoder:


//========== copyWithZone: =====================================================
//
// Purpose:		Returns a duplicate of this file.
//
//==============================================================================
- (id) copyWithZone:(NSZone *)zone
{
	LDrawMetaCommand *copied = (LDrawMetaCommand *)[super copyWithZone:zone];
	
	copied.commandString = self.commandString;
	
	return copied;
	
}//end copyWithZone:


//========== metaCommandInstanceByMarker:scanner: ==============================
///
/// @abstract	Subclasses override this method to create their own instance.
///
//==============================================================================
+ (LDrawMetaCommand *) metaCommandInstanceByMarker:(NSString *)ldrawMarker scanner:(NSScanner *)scanner
{
	return nil;
}


//========== finishParsing: ====================================================
//
// Purpose:		Subclasses override this method to finish parsing their specific 
//				syntax once -[LDrawMetaCommand initWithLines:inRange:] 
//				has determined which subclass to instantiate. 
//
// Returns:		YES on success; NO on a syntax error.
//
//==============================================================================
- (BOOL) finishParsing:(NSScanner *)scanner
{
	// LDrawMetaCommand itself doesn't have any special syntax, so we shouldn't 
	// be getting any in this method. 
	return NO;
	
}//end finishParsing:


#pragma mark -
#pragma mark DIRECTIVES
#pragma mark -

//========== draw:viewScale:parentColor: =======================================
//
// Purpose:		Draws the part.
//
//==============================================================================
- (void) draw:(NSUInteger)optionsMask viewScale:(float)scaleFactor parentColor:(LDrawColor *)parentColor

{
	// Nothing to do here.
	
}//end draw:viewScale:parentColor:


//========== write =============================================================
//
// Purpose:		Returns a line that can be written out to a file.
//				Line format:
//				0 command... 
//
//==============================================================================
- (NSString *) write
{
	return [NSString stringWithFormat: @"0 %@", self.commandString];
	
}//end write

#pragma mark -
#pragma mark DISPLAY
#pragma mark -

//========== browsingDescription ===============================================
//
// Purpose:		Returns a representation of the directive as a short string 
//				which can be presented to the user.
//
//==============================================================================
- (NSString *) browsingDescription
{
	return _commandString;
	
}//end browsingDescription


//========== iconName ==========================================================
//
// Purpose:		Returns the name of image file used to display this kind of 
//				object, or nil if there is no icon.
//
//==============================================================================
- (NSString *) iconName
{
	return @"Unknown";
	
}//end iconName


//========== inspectorClassName ================================================
//
// Purpose:		Returns the name of the class used to inspect this one.
//
//==============================================================================
- (NSString *) inspectorClassName
{
	return @"InspectionUnknownCommand";
	
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


#pragma mark -
#pragma mark UTILITIES
#pragma mark -

//========== registerUndoActions ===============================================
//
// Purpose:		Registers the undo actions that are unique to this subclass, 
//				not to any superclass.
//
//==============================================================================
- (void) registerUndoActions:(NSUndoManager *)undoManager
{
	[super registerUndoActions:undoManager];
	
	[[undoManager prepareWithInvocationTarget:self] setCommandString:[self commandString]];
	
	//[undoManager setActionName:NSLocalizedString(@"UndoAttributesLine", nil)];
	// (unused for this class; a plain "Undo" will probably be less confusing.)
	
}//end registerUndoActions:


@end
