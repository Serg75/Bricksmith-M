//
//  InspectionLPubCommand.m
//  Bricksmith
//
//  Created by Sergey Slobodenyuk on 2023-02-16.
//

#import "InspectionLPubCommand.h"

#import "LPubCommand.h"

@interface InspectionLPubCommand ()

@property (nonatomic, weak) IBOutlet NSTextField	*commandTextField;
@property (nonatomic, weak) IBOutlet NSTextField	*fullCommandTextField;

@property (nonatomic, strong)		 NSArray		*topLevelObjects;	// holds NIB objects

@end


@implementation InspectionLPubCommand

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
		if ([[NSBundle mainBundle] loadNibNamed:@"InspectorLPubCommand" owner:self topLevelObjects:&nibObjects]) {
			self.topLevelObjects = nibObjects;
		} else {
			NSLog(@"Couldn't load InspectorLPubCommand.nib");
		}
	}
	return self;
	
}//end init


// MARK: - ACTIONS -

//========== commitChanges: ====================================================
///
/// @abstract	Called in response to the conclusion of editing in the palette.
///
//==============================================================================
- (void) commitChanges:(id)sender
{
	LPubCommand *representedObject = self.object;
	
	NSString *newCommand = self.commandTextField.stringValue;

	representedObject.lPubCommandString = newCommand;
	
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
	LPubCommand *representedObject = self.object;

	self.commandTextField.stringValue = representedObject.lPubCommandString;
	self.fullCommandTextField.stringValue = representedObject.commandString;

	[super revert:sender];

}//end revert:


// MARK: - PROTOCOLS -

//========== commandFieldChanged: ==============================================
///
/// @abstract	The user has changed the string that makes up this command.
///
//==============================================================================
- (IBAction) commandFieldChanged:(id)sender
{
	NSString *newCommand	= [self.commandTextField stringValue];
	NSString *oldCommand	= [self.object lPubCommandString];

	//If the values really did change, then update.
	if([newCommand isEqualToString:oldCommand] == NO)
		[self finishedEditing:sender];
		
}//end commandFieldChanged:


#pragma mark -
#pragma mark DESTRUCTOR
#pragma mark -

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
