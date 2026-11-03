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
#import <LDrawFeatures/LDrawColorPanelModel.h>
#import <LDrawFeatures/LDrawPartLimitSession.h>
#import <LDrawInventory/LDrawPartLimit.h>
#import <LDrawInventory/LDrawPartLimitTable.h>

#import "LDrawColorBar.h"
#import "LDrawColorCell.h"
#import "LDrawColorWell.h"
#import "LDrawHostChrome.h"
#import "PartBrowserDataSource.h"
#import "PartsLimitManager.h"

// The separator after the material pop-up's limit items.
static const NSInteger LimitSeparatorTag = 10;


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

	// The panel decides which rows can be picked, and never lets the list
	// pick a color by itself.
	[colorTable setDelegate:self];
	[colorListController setAvoidsEmptySelection:NO];
	[self makeFooter];
	
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

		self->selectedPartNames = @[];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(partsLimitDidChange:)
													 name:LDrawPartLimitDidChangeNotification
												   object:[[PartsLimitManager sharedManager] session]];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(browserSelectionDidChange:)
													 name:PartBrowserSelectionDidChangeNotification
												   object:nil];
		[self updateLimitFilter];
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
	LDrawColor	*selectedColor		= [LDrawColorPanelModel colorFromListSelection:selection
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
	
	// With a limit filter on, a color the list leaves out shows in the bar and
	// is posted, but the selected parts keep their colors.
	if([LDrawColorPanelModel shouldClearColorFilterWhenIndexNotFound:rowToSelect] && [self isLimitFilterOn])
	{
		[self->colorListController setSelectionIndexes:[NSIndexSet indexSet]];
		[colorBar setLDrawColor:newColor];
		if(newColor != nil)
			[[NSNotificationCenter defaultCenter] postNotificationName:LDrawColorDidChangeNotification
																object:newColor];
		return;
	}

	if([LDrawColorPanelModel shouldClearColorFilterWhenIndexNotFound:rowToSelect])
	{
		//It wasn't in the currently-displayed list. Search the master list.
		[self->colorListController setFilterPredicate:nil];
		rowToSelect = [self indexOfColor:newColor];
	}
	
	//We'd better have found it by now!
	if([LDrawColorPanelModel canSelectColorAtRowIndex:rowToSelect])
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

	// A list narrowed by the parts limit applies nothing.
	if(isRefiltering)
		return;

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
	LDrawColor		*objectColor	= [LDrawInspection colorOfLastObjectInSelection:selectedObjects
																	  fallingBackTo:[self LDrawColor]];
	NSArray			*partNames		= [LDrawColorPanelModel partNamesInSelection:selectedObjects];
	BOOL			 hasObjects		= ([selectedObjects count] > 0);

	// The list follows the parts the selection holds.
	if([partNames isEqualToArray:self->selectedPartNames] == NO || hasObjects != self->hasSelection)
	{
		self->selectedPartNames	= partNames;
		self->hasSelection		= hasObjects;
		[self updateLimitFilter];
	}
	
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
	return [LDrawColorPanelModel indexOfColor:colorSought
									 inColors:[self->colorListController arrangedObjects]];
}//end indexOfColor:


//========== colorAtRow: =======================================================
//
// Purpose:		The color listed in the row, or nil when there is no such row.
//
//==============================================================================
- (LDrawColor *) colorAtRow:(NSInteger)row
{
	NSArray *colors = [self->colorListController arrangedObjects];

	if(row < 0 || row >= (NSInteger)[colors count])
		return nil;
	return [colors objectAtIndex:row];

}//end colorAtRow:


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
	savedDescriptorData = [userDefaults objectForKey:[LDrawHostChrome colorTableSortDescriptorsPreferenceKey]];
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
// Purpose:		Filters the color list by the search, the material and the
//				parts limit.
//
// Notes:		When the current color is filtered out, the first color that
//				can be picked is selected, except while the limit refilters the
//				list, which must not change any part.
//
//==============================================================================
- (void) updateColorFilter
{
	NSString			*searchString				= [searchField stringValue];
	LDrawColorFilter	materialType				= (LDrawColorFilter)[[materialPopUpButton selectedItem] tag];
	NSPredicate 		*searchPredicate			= nil;
	LDrawColor			*currentColor				= [self LDrawColor];
	NSInteger			indexOfPreviousSelection	= 0;
	NSArray				*colorCodes					= nil;
	
	if(materialType == LDrawColorFilterSelectedPart)
		colorCodes = self->allowedColorCodes;
	else if(materialType == LDrawColorFilterLimit)
		colorCodes = [[self restrictingTable] everyAllowedColorCode];

	searchPredicate = [LDrawColorPanelModel predicateForSearchString:searchString
															material:materialType
												   allowedColorCodes:colorCodes];
	
	//Update the table with our results.
	[self->colorListController setFilterPredicate:searchPredicate];
	
	// The list keeps the selection while the color is still listed.
	indexOfPreviousSelection = [self indexOfColor:currentColor];
	if(self->isRefiltering)
	{
		// Selects the color again once it is listed. Nothing is applied while
		// refiltering.
		if(indexOfPreviousSelection != NSNotFound && [[self->colorListController selectionIndexes] count] == 0)
			[self->colorListController setSelectionIndex:indexOfPreviousSelection];
	}
	else if([LDrawColorPanelModel shouldSelectFirstColorAfterFilterWhenPreviousIndex:indexOfPreviousSelection])
	{
		// Picks the first color the parts may take.
		NSArray		*colors	= [self->colorListController arrangedObjects];
		NSUInteger	 first	= [colors indexOfObjectPassingTest:^BOOL(LDrawColor *color, NSUInteger index, BOOL *stop) {
			return [self canSelectColor:color];
		}];

		if(first != NSNotFound)
			[self->colorListController setSelectionIndex:first];
	}

}//end updateColorFilter


#pragma mark -
#pragma mark PARTS LIMIT
#pragma mark -

//========== makeFooter ========================================================
//
// Purpose:		Adds the text under the list that says why it is short. It
//				wraps, and takes room from the list only while shown.
//
//==============================================================================
- (void) makeFooter
{
	NSScrollView *scrollView = [self->colorTable enclosingScrollView];

	self->footerField = [NSTextField wrappingLabelWithString:@""];
	[self->footerField setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[self->footerField setTextColor:[NSColor secondaryLabelColor]];
	[self->footerField setSelectable:NO];
	[self->footerField setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
	[self->footerField setHidden:YES];
	[[scrollView superview] addSubview:self->footerField];

	// A new width can change how many lines the text needs.
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(layOutFooter)
												 name:NSViewFrameDidChangeNotification
											   object:scrollView];

}//end makeFooter


//========== setFooterText: ====================================================
//
// Purpose:		Shows the footer with the text, or hides it for nil.
//
//==============================================================================
- (void) setFooterText:(NSString *)text
{
	[self->footerField setStringValue:text ?: @""];
	[self->footerField setHidden:(text == nil)];
	[self layOutFooter];

}//end setFooterText:


//========== layOutFooter ======================================================
//
// Purpose:		Gives the footer the lines its text needs, below the list, and
//				the list the rest.
//
// Notes:		Setting the list's frame posts a frame change, which comes back
//				here with the height already right and stops.
//
//==============================================================================
- (void) layOutFooter
{
	NSScrollView	*scrollView	= [self->colorTable enclosingScrollView];
	NSRect			 list		= [scrollView frame];
	CGFloat			 bottom		= NSMinY(list) - self->footerSpace;
	CGFloat			 height		= 0;

	if([self->footerField isHidden] == NO)
	{
		NSRect bounds = NSMakeRect(0, 0, NSWidth(list), CGFLOAT_MAX);
		height = ceil([[self->footerField cell] cellSizeForBounds:bounds].height);
	}

	[self->footerField setFrame:NSMakeRect(NSMinX(list), bottom, NSWidth(list), height)];
	if(height == self->footerSpace)
		return;

	list.origin.y		= bottom + height;
	list.size.height	+= self->footerSpace - height;
	self->footerSpace	= height;
	[scrollView setFrame:list];

}//end layOutFooter


//========== restrictingTable ==================================================
//==============================================================================
- (LDrawPartLimitTable *) restrictingTable
{
	return [[[PartsLimitManager sharedManager] session] restrictingTable];
}


//========== isLimitFilterOn ===================================================
//
// Purpose:		Whether one of the limit's filters narrows the list.
//
//==============================================================================
- (BOOL) isLimitFilterOn
{
	NSInteger tag = [[materialPopUpButton selectedItem] tag];

	return (		(tag == LDrawColorFilterSelectedPart && self->allowedColorCodes != nil)
			||	tag == LDrawColorFilterLimit );
}


//========== canSelectColor: ===================================================
//
// Purpose:		Whether the user may pick the color for the selected parts.
//
//==============================================================================
- (BOOL) canSelectColor:(LDrawColor *)color
{
	return [LDrawColorPanelModel canSelectColorCode:[color colorCode]
								  allowedColorCodes:self->allowedColorCodes
										  warnsOnly:[[self restrictingTable] limit].warnsOnly];
}


//========== updateLimitFilter =================================================
//
// Purpose:		Narrows the list to the colors the selected parts may take, or
//				with nothing selected, the Part Browser's part. No part changes
//				color.
//
// Notes:		A selection of lines or quads holds no part, so it narrows
//				nothing.
//
//==============================================================================
- (void) updateLimitFilter
{
	LDrawPartLimitTable	*table	= [self restrictingTable];
	NSArray				*names	= [LDrawColorPanelModel limitPartNamesForSelectedPartNames:self->selectedPartNames
																			  hasSelection:self->hasSelection
																		   browserPartName:self->browserPartName];

	self->allowedColorCodes = [LDrawColorPanelModel allowedColorCodesForPartNames:names table:table];

	[self updateLimitMenuItems:table];

	self->isRefiltering = YES;
		[self updateColorFilter];
	self->isRefiltering = NO;

	[self setFooterText:[LDrawColorPanelModel footerForPartNames:names table:table]];
	[self->colorTable setNeedsDisplay:YES];

}//end updateLimitFilter


//========== updateLimitMenuItems: =============================================
//
// Purpose:		While a limit is on, puts For Selected Part and the limit's own
//				item at the top of the material pop-up, and selects For Selected
//				Part. Takes both out when the limit is off.
//
//==============================================================================
- (void) updateLimitMenuItems:(LDrawPartLimitTable *)table
{
	NSMenu				*menu		= [materialPopUpButton menu];
	NSMenuItem			*partItem	= [menu itemWithTag:LDrawColorFilterSelectedPart];
	NSMenuItem			*limitItem	= [menu itemWithTag:LDrawColorFilterLimit];
	NSMenuItem			*separator	= nil;
	LDrawInventoryStore	*store		= [[PartsLimitManager sharedManager] store];

	if(table != nil && partItem == nil)
	{
		partItem	= [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"For Selected Part", nil)
												 action:NULL
										  keyEquivalent:@""];
		limitItem	= [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
		separator	= [NSMenuItem separatorItem];

		[partItem setTag:LDrawColorFilterSelectedPart];
		[limitItem setTag:LDrawColorFilterLimit];
		[separator setTag:LimitSeparatorTag];
		[menu insertItem:partItem atIndex:0];
		[menu insertItem:limitItem atIndex:1];
		[menu insertItem:separator atIndex:2];
		[materialPopUpButton selectItemWithTag:LDrawColorFilterSelectedPart];
	}
	else if(table == nil && partItem != nil)
	{
		BOOL wasOn = ([[materialPopUpButton selectedItem] tag] >= LDrawColorFilterSelectedPart);

		[menu removeItem:partItem];
		[menu removeItem:limitItem];
		[menu removeItem:[menu itemWithTag:LimitSeparatorTag]];
		if(wasOn)
			[materialPopUpButton selectItemWithTag:LDrawColorFilterAll];
	}

	if(table != nil)
		[limitItem setTitle:[LDrawColorPanelModel limitFilterTitleForLimit:table.limit store:store]];

}//end updateLimitMenuItems:


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
		[userDefaults setObject:savedDescriptorData forKey:[LDrawHostChrome colorTableSortDescriptorsPreferenceKey]];
	}
	
}//end observeValueForKeyPath:ofObject:change:context:


//**** NSTableViewDelegate ****
//========== tableView:shouldSelectRow: ========================================
//
// Purpose:		Refuses a color the selected parts are not made in, whether by
//				click or arrow key.
//
//==============================================================================
- (BOOL) tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
	LDrawColor *color = [self colorAtRow:row];

	return (color != nil && [self canSelectColor:color]);

}//end tableView:shouldSelectRow:


//**** NSTableViewDelegate ****
//========== tableView:willDisplayCell:forTableColumn:row: =====================
//
// Purpose:		Fades and crosses out the colors the selected parts are not made
//				in, even when Pick Any Color lets them be picked.
//
//==============================================================================
- (void) tableView:(NSTableView *)tableView
   willDisplayCell:(id)cell
	forTableColumn:(NSTableColumn *)tableColumn
			   row:(NSInteger)row
{
	LDrawColor	*color		= [self colorAtRow:row];
	BOOL		 allowed	= [LDrawColorPanelModel canSelectColorCode:[color colorCode]
													 allowedColorCodes:self->allowedColorCodes
															 warnsOnly:NO];

	if([cell isKindOfClass:[LDrawColorCell class]])
		[(LDrawColorCell *)cell setStruck:(allowed == NO)];
	else if([cell isKindOfClass:[NSTextFieldCell class]])
	{
		// Cells are reused, so every row sets its color. A selected row keeps
		// the selection's.
		BOOL faded = (allowed == NO && [tableView isRowSelected:row] == NO);

		[(NSTextFieldCell *)cell setTextColor:faded ? [NSColor disabledControlTextColor] : [NSColor controlTextColor]];
	}

}//end tableView:willDisplayCell:forTableColumn:row:


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
#pragma mark NOTIFICATIONS
#pragma mark -

//========== partsLimitDidChange: ==============================================
//==============================================================================
- (void) partsLimitDidChange:(NSNotification *)notification
{
	[self updateLimitFilter];
}


//========== browserSelectionDidChange: ========================================
//
// Purpose:		The Part Browser's part counts when the document has no part
//				selected.
//
//==============================================================================
- (void) browserSelectionDidChange:(NSNotification *)notification
{
	NSString *partName = [[notification object] selectedPartName];

	if([partName isEqualToString:self->browserPartName ?: @""])
		return;

	self->browserPartName = partName;
	if(self->hasSelection == NO)
		[self updateLimitFilter];

}//end browserSelectionDidChange:


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
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[colorListController removeObserver:self forKeyPath:@"selectedObjects"];
	[colorListController removeObserver:self forKeyPath:@"sortDescriptors"];
	
}//end dealloc


@end

