//==============================================================================
//
// File:		DimensionsPanel.m
//
// Purpose:		Dialog to display the dimensions for a model.
//
//  Created by Allen Smith on 8/21/05.
//  Copyright 2005. All rights reserved.
//==============================================================================
#import "DimensionsPanel.h"

#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawUtilities.h>
#import <math.h>

@implementation DimensionsPanel

#define UNITS_COLUMN		@"UnitsIdentifier"
#define WIDTH_COLUMN		@"WidthIdentifier"
#define LENGTH_COLUMN		@"LengthIdentifier"
#define HEIGHT_COLUMN		@"HeightIdentifier"


#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//---------- dimensionPanelForFile: ----------------------------------[static]--
//
// Purpose:		Creates a panel which displays the dimensions for the specified 
//				file. 
//
//------------------------------------------------------------------------------
+ (DimensionsPanel *) dimensionPanelForFile:(LDrawFile *)fileIn
{
	DimensionsPanel *dimensions = nil;
	
	dimensions = [[DimensionsPanel alloc] initWithFile:fileIn];
	
	return dimensions;
	
}//end dimensionPanelForFile:


//========== initWithFile: =====================================================
//
// Purpose:		Make us an object. Load us our window.
//
// Notes:		Memory management is a bit tricky here. The receiver here is a 
//				throwaway object that exists soley to load a Nib file. We then 
//				junk the receiver and return a reference to the panel it loaded 
//				in the Nib. Tricky, huh?
//
//==============================================================================
- (id) initWithFile:(LDrawFile *)fileIn
{
	self = [super init];
	
	[self setFile:fileIn];
	
	return self;
	
}//end initWithFile:


#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

//========== activeModel =======================================================
//
// Purpose:		Returns the name of the submodel in the file whose dimensions we 
//				are currently analyzing.
//
//==============================================================================
- (LDrawMPDModel *) activeModel
{
	return self->activeModel;
	
}//end activeModel


//========== file ==============================================================
//
// Purpose:		Returns the file whose dimensions we are analyzing.
//
//==============================================================================
- (LDrawFile *) file
{
	return self->file;
	
}//end file


//========== panelNibName ======================================================
//
// Purpose:		For the benefit of our superclass, we need to identify the name 
//				of the Nib where my dialog comes from.
//
//==============================================================================
- (NSString *) panelNibName
{
	return @"Dimensions";
	
}//end panelNibName


#pragma mark -

//========== setActiveModel: ===================================================
//
// Purpose:		Sets the name of the submodel in the file whose dimensions we 
//				are currently analyzing and updates the data view.
//
//==============================================================================
- (void) setActiveModel:(LDrawMPDModel *)newModel
{
	self->activeModel = newModel;
	
	[dimensionsTable reloadData];
	
}//end setActiveModel:


//========== setFile: ==========================================================
//
// Purpose:		Sets the file whose dimensions we are analyzing.
//
//==============================================================================
- (void) setFile:(LDrawFile *)newFile
{
	file = newFile;
	[self setActiveModel:[newFile activeModel]];
	
}//end setFile:


#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== legonianRulerButtonClicked: =======================================
//
// Purpose:		Explain those Legonian units!
//
//==============================================================================
- (IBAction) legonianRulerButtonClicked:(id)sender
{
	NSString *path = [[NSBundle mainBundle] pathForResource:@"Legonian Ruler" ofType:@"pdf"];
	
	[[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}


#pragma mark -
#pragma mark DELEGATES

#pragma mark -
#pragma mark NSTableDataSource

//**** NSTableDataSource ****
//========== numberOfRowsInTableView: ==========================================
//
// Purpose:		End the sheet (we are the sheet!)
//
//==============================================================================
- (NSInteger) numberOfRowsInTableView:(NSTableView *)aTableView
{
	return LDrawDimensionUnitCount;
	
}//end numberOfRowsInTableView:


//**** NSTableDataSource ****
//========== tableView:objectValueForTableColumn:row: ==========================
//
// Purpose:		Return the appropriate dimensions.
//
//				This is downright ugly. Studs are different depending on whether 
//				they are horizontal or vertical. Oh yeah, and we want to display 
//				integers, floats, and strings in one table.
//
//==============================================================================
- (id)				tableView:(NSTableView *)tableView
	objectValueForTableColumn:(NSTableColumn *)tableColumn
						  row:(NSInteger)rowIndex
{
	id                  object          = nil;
	Box3                bounds          = [self->activeModel boundingBox3];
	double              width           = 0;
	double              height          = 0;
	double              length          = 0;
	double              value           = 0;
	LDrawDimensionUnitT unit            = (LDrawDimensionUnitT)rowIndex;
	BOOL                isHeight        = [[tableColumn identifier] isEqualToString:HEIGHT_COLUMN];
	
	//If we got valid bounds, analyze them.
	if(V3EqualBoxes(bounds, InvalidBox) == NO)
	{
		width	= bounds.max.x - bounds.min.x;
		height	= bounds.max.y - bounds.min.y;
		length	= bounds.max.z - bounds.min.z;
	}

	//Units Label?
	if([[tableColumn identifier] isEqualToString:UNITS_COLUMN])
	{
		NSString *unitKey = [LDrawUtilities dimensionUnitNameKey:unit];
		object = unitKey != nil ? NSLocalizedString(unitKey, nil) : nil;
	}
	//Dimension value, then.
	else
	{
		// Width, Height, or Length?
		if([[tableColumn identifier] isEqualToString:WIDTH_COLUMN])
			value = width;
		else if([[tableColumn identifier] isEqualToString:LENGTH_COLUMN])
			value = length;
		else if([[tableColumn identifier] isEqualToString:HEIGHT_COLUMN])
			value = height;
			
		object = [LDrawUtilities formattedDimensionDisplayFromLDU:value
															 unit:unit
														 isHeight:isHeight
										feetAndInchesFormatString:NSLocalizedString([LDrawUtilities feetAndInchesFormatKey], nil)];
	}
		
	return object;
	
}//end tableView:objectValueForTableColumn:row:


@end
