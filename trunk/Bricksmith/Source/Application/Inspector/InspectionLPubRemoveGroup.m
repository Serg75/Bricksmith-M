//
//  InspectionLPubRemoveGroup.m
//  Bricksmith
//
//  Created by Sergey Slobodenyuk on 2023-02-04.
//

#import "InspectionLPubRemoveGroup.h"

#import "LDrawDocumentTree.h"
#import "LPubRemoveGroup.h"

@interface InspectionLPubRemoveGroup ()

@property (nonatomic, weak) IBOutlet NSComboBox		*groupNamesComboBox;
@property (nonatomic, weak) IBOutlet NSTextField	*fullCommandTextField;

@property (nonatomic, strong) NSArray				*topLevelObjects;	// holds NIB objects

@property (nonatomic, strong) NSSet<NSString *>		*groupNames;

@end


@implementation InspectionLPubRemoveGroup

// MARK: - INITIALIZATION -

//========== init ==============================================================
///
/// @abstract	Load the interface for this inspector.
///
//==============================================================================
- (instancetype) init
{
	self = [super init];
	if (self) {
		NSArray *nibObjects = nil;
		if ([[NSBundle mainBundle] loadNibNamed:@"InspectorRemoveGroup" owner:self topLevelObjects:&nibObjects]) {
			self.topLevelObjects = nibObjects;
		} else {
			NSLog(@"Couldn't load InspectorRemoveGroup.nib");
		}
	}
	return self;
	
}//end init


// MARK: - ACCESSORS -

//========== setObject =========================================================
///
/// @abstract	Sets up the object to edit. This is called when creating the
///				class.
///
//==============================================================================
- (void) setObject:(id)newObject
{
	LPubRemoveGroup *command = newObject;
	_groupNames = [LDrawDocumentTree groupsBeforeStep:command.enclosingStep];

	[super setObject:newObject];
	
}//end setObject:


// MARK: - ACTIONS -

//========== commitChanges: ====================================================
///
/// @abstract	Called in response to the conclusion of editing in the palette.
///
//==============================================================================
- (void) commitChanges:(id)sender
{
	LPubRemoveGroup *representedObject = self.object;
	
	NSString *newName = self.groupNamesComboBox.stringValue;
	
	representedObject.groupName = newName;
	
	[super commitChanges:sender];
	
}//end commitChanges:


//========== revert ============================================================
///
/// @abstract	Restores the palette to reflect the state of the object.
///				This method is called automatically when the object to inspect
///				is set. Subclasses should override this method to populate
///				the data in their inspector palettes.
///
//==============================================================================
- (IBAction) revert:(id)sender
{
	LPubRemoveGroup *representedObject = self.object;

	// Fill the type dropdown
	[self populateGroupNames];
	
	self.groupNamesComboBox.stringValue = representedObject.groupName;
	self.fullCommandTextField.stringValue = representedObject.commandString;

	[super revert:sender];

}//end revert:


// MARK: - UTILITIES -

//========== populateGroupNames ================================================
///
/// @abstract	Populate the Group Names dropdown
///
//==============================================================================
- (void) populateGroupNames
{
	[self.groupNamesComboBox removeAllItems];
	if (_groupNames != nil) {
		for (NSString *name in _groupNames) {
			[self.groupNamesComboBox addItemWithObjectValue:name];
		}
	}
	
}//end populateGroupNames


// MARK: - PROTOCOLS -

//========== groupNamesComboBoxChanged: ========================================
///
/// @abstract	The user has changed the group name.
///
//==============================================================================
- (IBAction) groupNamesComboBoxChanged:(id)sender
{
	NSString *newName	= [self.groupNamesComboBox stringValue];
	NSString *oldName	= [self.object groupName];

	//If the values really did change, then update.
	if([newName isEqualToString:oldName] == NO)
		[self finishedEditing:sender];
		
}//end groupNamesComboBoxChanged:


// MARK: - DESTRUCTOR -

//========== dealloc ============================================================
///
/// @abstract	Cleanup
///
//==============================================================================
- (void) dealloc
{
	self.topLevelObjects = nil;

}//end dealloc


@end
