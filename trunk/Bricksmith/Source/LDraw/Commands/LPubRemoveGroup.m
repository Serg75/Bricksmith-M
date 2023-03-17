//==============================================================================
//
//  LPubRemoveGroup.m
//  Bricksmith
//
//  Purpose:	LPub Remove Group command.
//
//				Line format:
//				0 !LPUB REMOVE GROUP "group-name"
//
//				where
//
//				* group-name is a name for the group to be removed.
//
//  Created by Sergey Slobodenyuk on 2023-02-07.
//
//==============================================================================

#import "LPubRemoveGroup.h"

#import "LDrawKeywords.h"
#import "LDrawUtilities.h"
#import "LPubCommand.h"


static NSString * const		GROUP_NAME_KEY = @"groupName";


@implementation LPubRemoveGroup

// MARK: - INITIALIZATION -

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
	
	_groupName	= [decoder decodeObjectForKey:GROUP_NAME_KEY];
	
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
	
	[encoder encodeObject:_groupName forKey:GROUP_NAME_KEY];
	
}//end encodeWithCoder:


//========== copyWithZone: =====================================================
//
// Purpose:		Returns a duplicate of this file.
//
//==============================================================================
- (id) copyWithZone:(NSZone *)zone
{
	LPubRemoveGroup *copied = (LPubRemoveGroup *)[super copyWithZone:zone];
	
	copied.groupName = self.groupName;

	return copied;
	
}//end copyWithZone:


//---------- lpubCommandInstance: ------------------------------------[static]--
///
/// @abstract	Here we create LPubRemoveGroup instance if parsing succeeded.
///
/// 			Command syntax:
///				0 !LPUB REMOVE GROUP "group name"
///
//------------------------------------------------------------------------------
+ (LPubCommand *) lpubCommandInstance:(NSArray<NSString *> *)parameters
{
	if (parameters.count == 3
		&& [parameters[0] isEqualToString:LPUB_REMOVE_GROUP_1]
		&& [parameters[1] isEqualToString:LPUB_REMOVE_GROUP_2]) {

		LPubRemoveGroup *command = [LPubRemoveGroup new];
		
		// remove quotes around group name
		NSCharacterSet *quoteCharset = [NSCharacterSet characterSetWithCharactersInString:@"\""];
		command.groupName = [parameters[2] stringByTrimmingCharactersInSet:quoteCharset];
		command.lPubCommandString = [parameters componentsJoinedByString:@" "];
		
		return command;
	}
	return nil;
	
}//end lpubCommandInstance:


//========== finishParsing: ====================================================
///
/// @abstract	Because everything has done in lpubCommandInstance: method,
///				here we do nothing.
///
//==============================================================================
- (BOOL) finishParsing:(NSScanner *)scanner
{
	return YES;
	
}//end finishParsing


// MARK: - DISPLAY -

//========== browsingDescription ===============================================
///
/// @abstract	Returns a representation of the directive as a short string
///				which can be presented to the user.
///
//==============================================================================
- (NSString *) browsingDescription
{
	return [NSString stringWithFormat:@"REMOVE [%@]", self.groupName];
	
}//end browsingDescription


//========== iconName ==========================================================
///
/// @abstract	Returns the name of image file used to display this kind of
///				object, or nil if there is no icon.
///
//==============================================================================
- (NSString *) iconName
{
	return @"RemoveGroup";
	
}//end iconName


//========== inspectorClassName ================================================
///
/// @abstract	Returns the name of the class used to inspect this one.
///
//==============================================================================
- (NSString *) inspectorClassName
{
	return @"InspectionLPubRemoveGroup";
	
}//end inspectorClassName


// MARK: - ACCESSORS -

//========== setGroupName: =====================================================
///
/// @abstract	Updates the command's group name.
///
//==============================================================================
-(void) setGroupName:(NSString *)newName
{
	_groupName = [newName copy];
	super.lPubCommandString = [NSString stringWithFormat:@"%@ %@ \"%@\"", LPUB_REMOVE_GROUP_1, LPUB_REMOVE_GROUP_2, newName];
	
}//end setGroupName:


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
	
	[[undoManager prepareWithInvocationTarget:self] setGroupName:self.groupName];
	
	[undoManager setActionName:NSLocalizedString(@"UndoAttributesRemoveGroup", nil)];
	
}//end registerUndoActions:


@end
