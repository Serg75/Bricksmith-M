//==============================================================================
//
// File:		LDrawColorPanelController.m
//
// Purpose:		Color-picker for Bricksmith. The color panel is used to browse, 
//				select, and apply LDraw colors. The colors are presented by 
//				both swatch and name.
//
//  Created by Allen Smith on 2/26/05.
//  Copyright 2005. All rights reserved.
//==============================================================================
#import "LDrawColorPanelController.h"

#import <LDrawCore/LDrawColorLibrary.h>
#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/NSString+LDraw.h>

#import <LDrawEditing/LDrawInspection.h>
#import <LDrawFeatures/LDrawPreferences.h>

#import "LDrawColorBar.h"
#import "LDrawColorCell.h"
#import "LDrawColorWell.h"

@implementation LDrawColorPanelController

//There is supposed to be only one of these.
LDrawColorPanelController *sharedColorPanel = nil;


//========== windowDidLoad =====================================================
//
// Purpose:		Brings the LDraw color panel to life.
//
// Note:		Please note that this method is called BEFORE most class
//				initialization code. For instance, awake is called before the 
//				table's data is even loaded, so you can't sort the data here.
//
//==============================================================================
- (void) windowDidLoad
{
	LDrawColorCell	*colorCell		= [[LDrawColorCell alloc] init];
	NSTableColumn	*colorColumn	= [colorTable tableColumnWithIdentifier:@"colorCode"];
	
	[colorColumn setDataCell:colorCell];
	
	[materialPopUpButton selectItemWithTag:LDrawColorFilterAll];
	
	[(NSPanel*)[self window] setWorksWhenModal:YES];
	[(NSPanel*)[self window] setLevel:NSStatusWindowLevel];
	[(NSPanel*)[self window] setBecomesKeyOnlyIfNeeded:YES];
	
}//end awakeFromNib


#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//---------- sharedColorPanel ----------------------------------------[static]--
//
// Purpose:		Returns the global instance of the color panel.
//
//------------------------------------------------------------------------------
+ (LDrawColorPanelController *) sharedColorPanel
{
	if(sharedColorPanel == nil)
		sharedColorPanel = [[LDrawColorPanelController alloc] init];
	
	return sharedColorPanel;
	
}//end sharedColorPanel


//========== init ==============================================================
//
// Purpose:		Brings the LDraw color panel to life.
//
//==============================================================================
- (id) init
{
	self = [super initWithWindowNibName:@"ColorPanel"];
	if(self)
	{
		LDrawColorLibrary  *colorLibrary   = [LDrawColorLibrary sharedColorLibrary];
		NSArray            *colorList      = [colorLibrary colors];
		
		//While the data is being loaded in the table, a color will automatically
		// be selected. We do not want this color-selection to generate a
		// changeColor: message, so we turn on this flag.
		updatingToReflectFile = YES;
		
		// The application's selected color state is stored in an 
		// NSArrayController that is instantiated by the nib. So no lazy loading 
		// for us. Force nib to load now.
		[self window];
		
		// Set the list of colors to display.
		[self->colorListController setContent:colorList];
		[self->colorListController addObserver:self forKeyPath:@"selectedObjects" options:kNilOptions context:NULL];
		[self->colorListController addObserver:self forKeyPath:@"sortDescriptors" options:kNilOptions context:NULL];
		
		[self loadInitialSortDescriptors];
		
		[self setLDrawColor:[colorLibrary colorForCode:LDrawRed]];
		updatingToReflectFile = NO;
	}
	return self;
	
}//end init


#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

//========== LDrawColor ========================================================
//
// Purpose:		Returns the color code of the panel's currently-selected color.
//
//==============================================================================
- (LDrawColor *) LDrawColor
{
	NSArray		*selection			= [self->colorListController selectedObjects];
	LDrawColor	*selectedColor		= [LDrawColorLibrary colorFromListSelection:selection
															 fallbackColor:[colorBar LDrawColor]];
	
	return selectedColor;
	
}//end LDrawColor


//========== setLDrawColor: ====================================================
//
// Purpose:		Chooses newColor in the color table. As long as newColor is a 
//				valid color, this method will select it, even if it has to 
//				change the found set.
//
//==============================================================================
- (void) setLDrawColor:(LDrawColor *)newColor
{
	//Try to find the color we are after in the current list.
	NSInteger rowToSelect = [self indexOfColor:newColor]; //will be the row index for the color we want.
	
	if([LDrawColorLibrary shouldClearColorFilterWhenIndexNotFound:rowToSelect])
	{
		//It wasn't in the currently-displayed list. Search the master list.
		[self->colorListController setFilterPredicate:nil];
		rowToSelect = [self indexOfColor:newColor];
	}
	
	//We'd better have found it by now!
	if([LDrawColorLibrary canSelectColorAtRowIndex:rowToSelect])
	{
		[self->colorListController setSelectionIndex:rowToSelect];
		[colorBar setLDrawColor:newColor];
	}
	
}//end setLDrawColor:

#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== focusSearchField: =================================================
//
// Purpose:		Makes the search field the first responder.
//
// Notes:		This is to pacify those who wish to type in color codes rather 
//				than clicking them. Once the search field is made key by some 
//				keyboard combination, the color code can be typed in. 
//
//==============================================================================
- (void) focusSearchField:(id)sender
{
	[[self window] makeFirstResponder:self->searchField];
	
}//end focusSearchField:


//========== materialPopUpButtonChanged: =======================================
//
// Purpose:		Chose a different material filter for the color search.
//
//==============================================================================
- (void) materialPopUpButtonChanged:(id)sender
{
	[self updateColorFilter];
}

//========== sendAction ========================================================
//
// Purpose:		Dispatches the change-color action as appropriate. If there is 
//				an active color well, it will be the sole recipient of the color 
//				change. Otherwise, a nil-targeted -changeLDrawColor: message 
//				will be dispatched.
//
//==============================================================================
- (void) sendAction
{
	LDrawColorWell *activeColorWell = [LDrawColorWell activeColorWell];

	if(activeColorWell != nil)
	{
		//we have an active color well, so it is the only one whose color should 
		// change.
		[activeColorWell changeLDrawColorWell:self];
	}
	else
	{
		//Well, our color has changed. Presumably, somebody wants to update a 
		// part color in response to this momentous event. But who knows who? So 
		// we just send this message toddling along, and let whoever want it get 
		// it.
		//
		//But--if this notification is coming in response to selecting a 
		// different part in the file, then our color did not *really* change; 
		// we are just displaying a new one. In that case, we don't want any 
		// parts changing colors.
		if(updatingToReflectFile == NO)
		{
			[NSApp sendAction:@selector(changeLDrawColor:)
						   to:nil //just send it somewhere!
						 from:self]; //it's from us (we'll be the sender)
			
		}
		
		//Clients that are tracking the global color state always need to know 
		// about the current color, though!
		[[NSNotificationCenter defaultCenter]
							postNotificationName:LDrawColorDidChangeNotification
										  object:[self LDrawColor] ];
	}

}//end sendAction


//========== searchFieldChanged: ===============================================
//
// Purpose:		The user has changed the search string. We need to research 
//				the list of colors for those whose names match the new string.
//
// Notes:		For the sake of concise code, I do not bother to optimize this 
//				search. After all, we only have 64 colors; that's no time.
//
//==============================================================================
- (IBAction) searchFieldChanged:(id)sender
{
	[self updateColorFilter];
	
}//end searchFieldChanged:


//========== updateSelectionWithObjects: =======================================
//
// Purpose:		Updates the selected color based on the colors in 
//				selectedObjects, which should be a list of LDrawDirectives 
//				which have been selected in a document window.
//
//				If two or more directives have different colors, then the color 
//				of the last object selected is displayed.
//
//				If there are no colorable directives in selectedObjects, then 
//				the color selection remains unchanged.
//
//==============================================================================
- (void) updateSelectionWithObjects:(NSArray *)selectedObjects
{
	LDrawColor *objectColor = [LDrawInspection colorOfLastObjectInSelection:selectedObjects
															  fallingBackTo:[self LDrawColor]];
	
	updatingToReflectFile = YES;
		[self setLDrawColor:objectColor];
	updatingToReflectFile = NO;
	
}//end updateSelectionWithObjects:


#pragma mark -
#pragma mark UTILITIES
#pragma mark -

//========== indexOfColor: =================================================
//
// Purpose:		Row of the sought color in the panel's table. The host still
//				uses arrangedObjects.
//
//==============================================================================
- (NSInteger) indexOfColor:(LDrawColor *)colorSought
{
	return [LDrawColorLibrary indexOfColor:colorSought
								  inColors:[self->colorListController arrangedObjects]];
}//end indexOfColor:


//========== loadInitialSortDescriptors ========================================
//
// Purpose:		Reads the last-used sort descriptors from preferences and 
//				applies them to the color list. 
//
// Notes:		Once moved entirely to Leopard, we can dispense with some of 
//				this and bind directly to the data using 
//				NSKeyedUnarchiveFromData. That would also be an easy class to 
//				replicate on Tiger, but I'm not feeling like I need it all that 
//				much. 
//
//==============================================================================
- (void) loadInitialSortDescriptors
{
	NSData				*savedDescriptorData	= nil;
	NSArray				*savedDescriptors		= nil;
	NSSortDescriptor	*initialDescriptor		= nil;
	NSUserDefaults		*userDefaults			= [NSUserDefaults standardUserDefaults];
	
	// Get the object from preferences.
	savedDescriptorData = [userDefaults objectForKey:[LDrawPreferences colorTableSortDescriptorsPreferenceKey]];
	if(savedDescriptorData != nil) {
		NSError *unarchiveError = nil;
		NSSet *allowedClasses = [NSSet setWithObjects:[NSArray class], [NSSortDescriptor class], nil];
		savedDescriptors = [NSKeyedUnarchiver unarchivedObjectOfClasses:allowedClasses fromData:savedDescriptorData error:&unarchiveError];
		if (unarchiveError != nil) {
			NSLog(@"Failed to unarchive color sort descriptors: %@", unarchiveError);
		}
	}
	
	// Regenerate them if needed
	if(savedDescriptors == nil)
	{
		initialDescriptor	= [[self->colorTable tableColumnWithIdentifier:@"colorCode"] sortDescriptorPrototype];
		savedDescriptors	= [NSArray arrayWithObject:initialDescriptor];
	}
	
	// and sort.
	[self->colorListController setSortDescriptors:savedDescriptors];

}//end loadInitialSortDescriptors


//========== updateColorFilter =================================================
//
// Purpose:		Searches the global color list for colors matching the selected 
//				parameters.
//
//==============================================================================
- (void) updateColorFilter
{
	NSString			*searchString				= [searchField stringValue];
	LDrawColorFilter	materialType				= (LDrawColorFilter)[[materialPopUpButton selectedItem] tag];
	NSPredicate 		*searchPredicate			= nil;
	LDrawColor			*currentColor				= [self LDrawColor];
	NSInteger			indexOfPreviousSelection	= 0;
	
	searchPredicate = [LDrawColorLibrary predicateForSearchString:searchString material:materialType];
	
	//Update the table with our results.
	[self->colorListController setFilterPredicate:searchPredicate];
	
	// The array controller will automatically maintain the selection if it can.
	// But if it can't, we need to come up a reasonable new answer.
	indexOfPreviousSelection = [self indexOfColor:currentColor];
	if([LDrawColorLibrary shouldSelectFirstColorAfterFilterWhenPreviousIndex:indexOfPreviousSelection])
	{
		[self->colorListController setSelectionIndex:0];
	}
}//end updateColorFilter


#pragma mark -
#pragma mark DELEGATES
#pragma mark -

//========== observeValueForKeyPath:ofObject:change:context: ===================
//
// Purpose:		We need to know when our color selection changes, so we use 
//				Key-Value Observing. 
//
//==============================================================================
- (void)observeValueForKeyPath:(NSString *)keyPath
					  ofObject:(id)object
						change:(NSDictionary *)change
					   context:(void *)context
{
	// Selected color has changed. Need to update everything to indicate that a 
	// new color was selected. 
	if([keyPath isEqualToString:@"selectedObjects"])
	{
		if([[self->colorListController selectedObjects] count] > 0)
		{
			//Update internal information.
			[self->colorBar setLDrawColor:[self LDrawColor]];
			
			[self sendAction];
		}
	}
	
	// Sort descriptors changed; save in preferences.
	// Once we are Leopard-only, we can dispense with this and just use the 
	// NSKeyedUnarchiveFromData transformer. 
	else if([keyPath isEqualToString:@"sortDescriptors"])
	{
		NSArray			*newDescriptors			= [self->colorListController sortDescriptors];;
		NSData			*savedDescriptorData	= [NSKeyedArchiver archivedDataWithRootObject:newDescriptors requiringSecureCoding:NO error:nil];
		NSUserDefaults	*userDefaults			= [NSUserDefaults standardUserDefaults];
		
		// Set the object in preferences.
		[userDefaults setObject:savedDescriptorData forKey:[LDrawPreferences colorTableSortDescriptorsPreferenceKey]];
	}
	
}//end observeValueForKeyPath:ofObject:change:context:

#pragma mark - NSWindow -

//========== windowWillClose: ==================================================
//
// Purpose:		The color panel is being closed. If there is an active color
//				well, it needs to deactivate.
//
//==============================================================================
- (void) windowWillClose:(NSNotification *)notification
{
	//deactivate active color well.
	if([LDrawColorWell activeColorWell] != nil)
		[LDrawColorWell setActiveColorWell:nil];
	
}//end orderOut:


//========== windowWillReturnUndoManager: ======================================
//
// Purpose:		Allows Undo to keep working transparently through this window by 
//				allowing the undo request to forward on to the active document.
//
//==============================================================================
- (NSUndoManager *) windowWillReturnUndoManager:(NSWindow *)sender
{
	NSDocument *currentDocument = [[NSDocumentController sharedDocumentController] currentDocument];
	
	return [currentDocument undoManager];
	
}//end windowWillReturnUndoManager:


#pragma mark -
#pragma mark DESTRUCTOR
#pragma mark -

//========== dealloc ===========================================================
//
// Purpose:		The Roll has been called up Yonder, and we will be there.
//
//==============================================================================
- (void) dealloc
{
	[colorListController removeObserver:self forKeyPath:@"selectedObjects"];
	[colorListController removeObserver:self forKeyPath:@"sortDescriptors"];
	
}//end dealloc


@end

