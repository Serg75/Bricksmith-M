//==============================================================================
//
// File:		PieceCountPanel.h
//
// Purpose:		Dialog to display the dimensions for a model.
//
//  Created by Allen Smith on 8/21/05.
//  Copyright 2005. All rights reserved.
//==============================================================================
#import <Cocoa/Cocoa.h>

#import "DialogPanel.h"

@class LDrawFile;
@class LDrawMPDModel;
@class LDrawPartReport;

@interface PieceCountPanel : DialogPanel
{
	__weak LDrawFile		*file;
	__weak LDrawMPDModel	*activeModel;
	LDrawPartReport			*partReport;
	NSMutableArray			*flattenedReport;
}

//Initialization
+ (PieceCountPanel *) pieceCountPanelForFile:(LDrawFile *)fileIn;
- (id) initWithFile:(LDrawFile *)file;

//Accessors
- (LDrawMPDModel *) activeModel;
- (LDrawFile *) file;
- (LDrawPartReport *) partReport;

- (void) setActiveModel:(LDrawMPDModel *)newModel;
- (void) setFile:(LDrawFile *)newFile;
- (void) setPartReport:(LDrawPartReport *)newPartReport;
- (void) setTableDataSource:(NSMutableArray *) newReport;

//Actions
- (IBAction) exportButtonClicked:(id)sender;

//Utilities
- (void) syncSelectionAndPartDisplayed;

@end
