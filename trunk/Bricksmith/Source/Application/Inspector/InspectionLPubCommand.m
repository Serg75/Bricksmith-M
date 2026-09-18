//
//  InspectionLPubCommand.m
//  Bricksmith
//
//  Created by Sergey Slobodenyuk on 2023-02-16.
//

#import "InspectionLPubCommand.h"

#import <LDrawCore/LPubCommand.h>
#import "LDrawDocument.h"

@interface InspectionLPubCommand ()

@property (nonatomic, weak) IBOutlet NSTextField	*commandTextField;
@property (nonatomic, weak) IBOutlet NSTextField	*fullCommandTextField;

@property (nonatomic, strong)		 NSArray		*topLevelObjects;	// holds NIB objects

// The swap ends editing again, which must not queue a second swap.
@property (nonatomic, assign)		 BOOL			swapQueued;

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
	LPubCommand	*command		= self.object;
	NSString	*newCommand		= [self.commandTextField stringValue];
	LPubCommand	*replacement	= nil;

	if(self.swapQueued || [newCommand isEqualToString:[command lPubCommandString]])
		return;

	// Text of another class swaps the directive. Otherwise it is edited in place.
	replacement = [command replacementForText:newCommand];
	if(replacement == nil)
	{
		[self finishedEditing:sender];
		return;
	}

	// Next turn: the swap replaces this inspector while its field is still
	// ending editing.
	self.swapQueued = YES;
	dispatch_async(dispatch_get_main_queue(), ^{
		// The open document that holds the command. There is none once the
		// document is closed or the command was already swapped.
		for(NSDocument *document in [[NSDocumentController sharedDocumentController] documents])
		{
			if(		[document isKindOfClass:[LDrawDocument class]]
			   &&	[(LDrawDocument *)document replaceDirective:command withDirective:replacement])
			{
				[[document undoManager] setActionName:NSLocalizedString([replacement undoActionKey], nil)];
				break;
			}
		}
	});

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
