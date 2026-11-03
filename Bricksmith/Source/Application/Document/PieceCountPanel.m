//==============================================================================
//
// File:		PieceCountPanel.m
//
// Purpose:		Dialog to display the dimensions for a model.
//
//  Created by Allen Smith on 8/21/05.
//  Copyright 2005. All rights reserved.
//==============================================================================
#import "PieceCountPanel.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawCore/LDrawPartReport.h>
#import <LDrawFeatures/LDrawPartLimitCheck.h>
#import <LDrawFeatures/LDrawPartLimitPresentation.h>
#import <LDrawInventory/LDrawPartLimit.h>
#import <LDrawInventory/LDrawPartLimitTable.h>

#import "LDrawApplication.h"
#import "LDrawColorCell.h"
#import "LDrawView.h"
#import "LDrawViewerContainer.h"

@interface PieceCountPanel ()

@property (nonatomic, weak) IBOutlet NSTableView			*pieceCountTable;
@property (nonatomic, weak) IBOutlet LDrawViewerContainer	*partPreview;

@end


// Keys the limit adds to a row, and the columns that show them.
static NSString * const LimitOwnedKey		= @"LimitOwned";		// text: a count, or a dash
static NSString * const LimitOwnedCountKey	= @"LimitOwnedCount";	// for sorting
static NSString * const LimitStatusKey		= @"LimitStatus";		// LDrawPartLimitStatus, for sorting
static NSString * const LimitStatusTextKey	= @"LimitStatusText";


@implementation PieceCountPanel

//========== awakeFromNib ======================================================
//
// Purpose:		Readies things that need to be readied. 
//
//==============================================================================
- (void) awakeFromNib
{
	LDrawColorCell  *colorCell      = [[LDrawColorCell alloc] init];
	NSTableColumn   *colorColumn    = [_pieceCountTable tableColumnWithIdentifier:PART_REPORT_LDRAW_COLOR];
	
	[colorColumn setDataCell:colorCell];
	
	[_partPreview.glView setAcceptsFirstResponder:NO];
	
	//Remember, this method is called twice for an LDrawColorPanelController; the first time 
	// is for the File's Owner, which is promptly overwritten.
	
}//end awakeFromNib


#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//---------- pieceCountPanelForFile: ---------------------------------[static]--
//
// Purpose:		Creates a panel which displays the dimensions for the specified 
//				file. 
//
//------------------------------------------------------------------------------
+ (PieceCountPanel *) pieceCountPanelForFile:(LDrawFile *)fileIn
{
	PieceCountPanel *panel = nil;
	
	panel = [[PieceCountPanel alloc] initWithFile:fileIn];
	
	return panel;
	
}//end pieceCountPanelForFile:


//========== initWithFile: =====================================================
//
// Purpose:		Make us an object. The superclass loads us our window.
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


//========== container =========================================================
//
// Purpose:		Returns the container whose dimensions we are analyzing.
//
//==============================================================================
- (LDrawFile *) file
{
	return self->file;
	
}//end file


//========== panelNibName ======================================================
//
// Purpose:		Returns the name of the Nib which contains the desired panel.
//				Called by our superclass.
//
//==============================================================================
- (NSString *) panelNibName
{
	return @"PieceCountPanel";
	
}//end panelNibName


//========== partReport: =======================================================
//
// Purpose:		Sets the name of the submodel in the file whose dimensions we 
//				are currently analyzing and updates the data view.
//
//==============================================================================
- (LDrawPartReport *) partReport
{
	return self->partReport;
	
}//end partReport


#pragma mark -

//========== setActiveModel: ===================================================
//
// Purpose:		Sets the name of the submodel in the file whose dimensions we 
//				are currently analyzing, and also updates the data view.
//
//==============================================================================
- (void) setActiveModel:(LDrawMPDModel *)newModel
{
	LDrawPartReport		*modelReport	= nil;
	
	//Update the model name.
	self->activeModel = newModel;
	
	//Get the report for the new model.
	modelReport = [LDrawPartReport partReportForContainer:self->activeModel];
	[modelReport getPieceCountReport];
	
	[self setPartReport:modelReport];
	
}//end setActiveModel:


//========== setFile: ==========================================================
//
// Purpose:		Sets the file we are reporting on.
//
//==============================================================================
- (void) setFile:(LDrawFile *)newFile
{
	file = newFile;
	[self setActiveModel:[newFile activeModel]];
	
}//end setFile:


//========== setPartReport: ====================================================
//
// Purpose:		Sets the part report (containing all piece/color/quantity info)
//				that we are displaying.
//
// Notes:		You should never call this method directly.
//
//==============================================================================
- (void) setPartReport:(LDrawPartReport *)newPartReport
{
	NSMutableArray *flattened = nil;
	
	//Update the part report
	partReport = newPartReport;
	
	//Prepare some new data for the table view:
	flattened = [NSMutableArray arrayWithArray:[partReport flattenedReport]];
	if(self->limitReport != nil)
		flattened = [self rowsWithLimit:flattened];
	[self setTableDataSource:flattened];
	
	[_pieceCountTable reloadData];
	
}//end setPartReport:


//========== setTableDataSource: ===============================================
//
// Purpose:		The table displays a list of the parts in a category. The array
//				here is an array of part records containg names and 
//				descriptions.
//
//				The new parts are then displayed in the table.
//
//==============================================================================
- (void) setTableDataSource:(NSMutableArray *) newReport
{	
	//Sort the parts based on whatever the current sort order is for the table.
	[newReport sortUsingDescriptors:[_pieceCountTable sortDescriptors]];
	
	//Swap out the variable
	flattenedReport = newReport;
	
	//Update the table
	[_pieceCountTable reloadData];
	[self syncSelectionAndPartDisplayed];
	
}//end setTableDataSource


//========== setLimitReport: ===================================================
//
// Purpose:		Adds what the parts limit says of each row: how many the
//				inventory holds and the row's problem. Nothing without a limit.
//
//==============================================================================
- (void) setLimitReport:(LDrawPartLimitReport *)report
{
	NSView *content = [self contentView];

	if(report == nil || [[report table] limit].isRestricting == NO)
		return;

	self->limitReport = report;

	if([_pieceCountTable tableColumnWithIdentifier:LimitStatusTextKey] == nil)
	{
		NSTableColumn *owned	= [[NSTableColumn alloc] initWithIdentifier:LimitOwnedKey];
		NSTableColumn *status	= [[NSTableColumn alloc] initWithIdentifier:LimitStatusTextKey];

		[[owned headerCell] setStringValue:NSLocalizedString(@"Owned", nil)];
		[[owned dataCell] setAlignment:NSTextAlignmentRight];
		[owned setWidth:50];
		[owned setSortDescriptorPrototype:[NSSortDescriptor sortDescriptorWithKey:LimitOwnedCountKey ascending:YES]];
		[[status headerCell] setStringValue:NSLocalizedString(@"Status", nil)];
		[status setWidth:100];
		[status setSortDescriptorPrototype:[NSSortDescriptor sortDescriptorWithKey:LimitStatusKey ascending:NO]];
		[_pieceCountTable addTableColumn:owned];
		[_pieceCountTable addTableColumn:status];

		// Shrinks the description column so the two new columns fit.
		NSTableColumn	*name		= [_pieceCountTable tableColumnWithIdentifier:PART_REPORT_NAME_KEY];
		CGFloat			 needed		= 0.0;
		CGFloat			 spacing	= [_pieceCountTable intercellSpacing].width;

		for(NSTableColumn *column in [_pieceCountTable tableColumns])
			needed += [column width] + spacing;
		needed -= NSWidth([[_pieceCountTable enclosingScrollView] documentVisibleRect]);
		if(needed > 0)
			[name setWidth:MAX([name width] - needed, 120)];

		// The problems first.
		[_pieceCountTable setSortDescriptors:[@[[status sortDescriptorPrototype]]
											  arrayByAddingObjectsFromArray:[_pieceCountTable sortDescriptors]]];

		self->problemsOnlyCheckbox = [NSButton checkboxWithTitle:NSLocalizedString(@"Problems only", nil)
														  target:self
														  action:@selector(problemsOnlyChanged:)];
		[self->problemsOnlyCheckbox setFrameOrigin:NSMakePoint(176, 20)];
		[self->problemsOnlyCheckbox setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
		[content addSubview:self->problemsOnlyCheckbox];
	}

	[self setPartReport:self->partReport];

}//end setLimitReport:


// MARK: - ACTIONS -

//========== zoomIn: ===========================================================
///
/// @abstract	Forward zoom to the 3D view
///
//==============================================================================
- (IBAction) zoomIn:(id)sender
{
	[_partPreview.glView zoomIn:sender];
}

//========== zoomOut: ==========================================================
///
/// @abstract	Forward zoom to the 3D view
///
//==============================================================================
- (IBAction) zoomOut:(id)sender
{
	[_partPreview.glView zoomOut:sender];
}


//========== problemsOnlyChanged: ==============================================
//==============================================================================
- (IBAction) problemsOnlyChanged:(id)sender
{
	[self setPartReport:self->partReport];
}

#pragma mark -
#pragma mark TABLE VIEW
#pragma mark -

//========== exportButtonClicked: ==============================================
//
// Purpose:		Export a tab-delimited text file of the part list.
//
//==============================================================================
- (IBAction) exportButtonClicked:(id)sender
{
	NSSavePanel *savePanel          = [NSSavePanel savePanel];
	NSURL       *savePath           = nil;
	NSString    *exported           = nil;
	NSArray     *sortDescriptors    = [_pieceCountTable sortDescriptors];
	NSInteger   result              = 0;
	
	//set up the save panel
	[savePanel setAllowedContentTypes:@[UTTypePlainText]];
	[savePanel setCanSelectHiddenExtension:YES];
	[savePanel setTitle:NSLocalizedString([LDrawPartReport pieceCountSaveDialogTitleKey], nil)];
	[savePanel setMessage:NSLocalizedString([LDrawPartReport pieceCountSaveDialogMessageKey], nil)];
	[savePanel setNameFieldStringValue:NSLocalizedString([LDrawPartReport untitledLocalizationKey], nil)];
	
	//run it and export the file if needed
	result = [savePanel runModal];
	if(result == NSModalResponseOK)
	{
		savePath	= [savePanel URL];
		exported	= [self->partReport textualRepresentationWithSortDescriptors:sortDescriptors];
		
		[exported writeToURL:savePath
				  atomically:YES
					encoding:NSUTF8StringEncoding
					   error:NULL ];
	}

}//end exportButtonClicked:


#pragma mark -
#pragma mark TABLE VIEW
#pragma mark -

//**** NSTableDataSource ****
//========== numberOfRowsInTableView: ==========================================
//
// Purpose:		How many parts?
//
//==============================================================================
- (NSInteger) numberOfRowsInTableView:(NSTableView *)aTableView
{
	return [flattenedReport count];
	
}//end numberOfRowsInTableView:


//**** NSTableDataSource ****
//========== tableView:objectValueForTableColumn:row: ==========================
//
// Purpose:		Provide the information for each part row.
//
//==============================================================================
- (id)				tableView:(NSTableView *)tableView
	objectValueForTableColumn:(NSTableColumn *)tableColumn
						  row:(NSInteger)rowIndex
{
	NSString		*identifier	= [tableColumn identifier];
	NSDictionary	*partRecord	= [flattenedReport objectAtIndex:rowIndex];
	id				 object		= nil;
	
	object = [partRecord objectForKey:identifier];
	
//	if(		[identifier isEqualToString:PART_NUMBER_KEY]
//		||	[identifier isEqualToString:PART_QUANTITY]
//		||	[identifier isEqualToString:LDRAW_COLOR] )
//	{
//		object = [partRecord objectForKey:identifier];
//	}
//	
//	else if([identifier isEqualToString:PART_NAME_KEY])
//		object = [[LDrawPartLibrary sharedPartLibrary] descriptionForPartName:[partRecord objectForKey:PART_NUMBER_KEY]];
//	
//	else if([identifier isEqualToString:COLOR_NAME])
//		object = [LDrawColor nameForLDrawColor:[[partRecord objectForKey:LDRAW_COLOR] intValue]];
	
	return object;
	
}//end tableView:objectValueForTableColumn:row:


//**** NSTableDataSource ****
//========== tableView:sortDescriptorsDidChange: ===============================
//
// Purpose:		Resort the table elements.
//
//==============================================================================
- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
	NSArray *newDescriptors = [tableView sortDescriptors];
	
	[flattenedReport sortUsingDescriptors:newDescriptors];
	[tableView reloadData];
	
}//end tableView:sortDescriptorsDidChange:


//**** NSTableDataSource ****
//========== tableViewSelectionDidChange: ======================================
//
// Purpose:		A new selection! Update the part preview accordingly.
//
//==============================================================================
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	[self syncSelectionAndPartDisplayed];
	
}//end tableViewSelectionDidChange:


#pragma mark -
#pragma mark UTILITIES
#pragma mark -

//========== syncSelectionAndPartDisplayed =====================================
//
// Purpose:		Makes the current part displayed match the part selected in the 
//				table.
//
//==============================================================================
- (void) syncSelectionAndPartDisplayed
{
	NSDictionary   *partRecord    = nil;
	LDrawColor     *partColor     = nil;
	LDrawPart      *newPart       = nil;
	NSInteger      rowIndex       = [_pieceCountTable selectedRow];
	
	if(rowIndex >= 0)
	{
		partRecord	= [flattenedReport objectAtIndex:rowIndex];
		newPart		= [LDrawPartReport previewPartFromRecord:partRecord];
		partColor	= [partRecord objectForKey:PART_REPORT_LDRAW_COLOR];

		[LDrawApplication makeCurrentSharedContext];

		[_partPreview.glView setLDrawDirective:newPart];
		[_partPreview.glView setLDrawColor:partColor];
	}
	
}//end syncSelectionAndPartDisplayed


//========== rowsWithLimit: ====================================================
//
// Purpose:		Copies each row with the limit's keys. With Problems Only on,
//				keeps only the rows with a problem.
//
//==============================================================================
- (NSMutableArray *) rowsWithLimit:(NSArray *)rows
{
	LDrawPartLimitTable	*table		= [self->limitReport table];
	NSMutableArray		*result		= [NSMutableArray arrayWithCapacity:[rows count]];
	BOOL				 onlyBad	= ([self->problemsOnlyCheckbox state] == NSControlStateValueOn);

	for(NSDictionary *row in rows)
	{
		NSMutableDictionary		*copy		= [row mutableCopy];
		NSString				*partName	= [row objectForKey:PART_REPORT_NUMBER_KEY];
		LDrawColorT				 colorCode	= [[row objectForKey:PART_REPORT_LDRAW_COLOR] colorCode];
		LDrawPartLimitStatus	 status		= [self->limitReport statusForPartNamed:partName colorCode:colorCode];
		NSUInteger				 owned		= [table ownedCountForPartNamed:partName colorCode:colorCode];

		if(onlyBad && LDrawPartLimitStatusIsProblem(status) == NO)
			continue;

		copy[LimitStatusKey]		= @(status);
		copy[LimitStatusTextKey]	= [LDrawPartLimitPresentation titleForStatus:status];
		copy[LimitOwnedCountKey]	= @((owned == NSNotFound) ? -1 : (NSInteger)owned);
		copy[LimitOwnedKey]			= (owned == NSNotFound) ? @"—"
															: [NSString stringWithFormat:@"%lu", (unsigned long)owned];
		[result addObject:copy];
	}
	return result;

}//end rowsWithLimit:


@end
