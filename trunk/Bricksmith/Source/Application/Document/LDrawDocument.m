//==============================================================================
//
// File:		LDrawDocument.m
//
// Purpose:		Document controller for an LDraw document.
//
//				Opens the document and manages its editor and viewer. This is 
//				the central class of the application's user interface.
//
// Threading:	The LDrawFile encapsulated in this class is a shared resource. 
//				We must take care not to edit it while it is being drawn in 
//				another thread. As such, all the calls in the "Undoable 
//				Activities" section are bracketed with the appropriate locking
//				calls. (ANY edit of the document should be undoable.)
//
//  Created by Allen Smith on 2/14/05.
//  Copyright (c) 2005. All rights reserved.
//==============================================================================
#import "LDrawDocument.h"

#import <AMSProgressBar/AMSProgressBar.h>

#import "DimensionsPanel.h"
#import "DocumentToolbarController.h"
#import "ExtendedSplitView.h"
#import "IconTextCell.h"
#import "Inspector.h"
#import "LDrawApplication.h"
#import <LDrawCore/LDrawColor.h>
#import "LDrawColorPanelController.h"
#import <LDrawCore/LDrawComment.h>
#import <LDrawCore/LDrawConditionalLine.h>
#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawDirective.h>
#import <LDrawEditing/LDrawClipboard.h>
#import <LDrawEditing/LDrawEditorStrings.h>
#import <LDrawEditing/LDrawInsertion.h>
#import <LDrawEditing/LDrawMLCadGroup.h>
#import <LDrawEditing/LDrawOutline.h>
#import <LDrawEditing/LDrawPaste.h>
#import <LDrawEditing/LDrawSearch.h>
#import <LDrawEditing/LDrawSelection.h>
#import <LDrawEditing/LDrawStructure.h>
#import <LDrawEditing/LDrawViewDrop.h>
#import <LDrawEditing/LDrawViewPolicy.h>
#import "LDrawDocumentWindow.h"
#import <LDrawCore/LDrawDragHandle.h>
#import <LDrawCore/LDrawDrawableElement.h>
#import <LDrawCore/LDrawFile.h>
#import "LDrawFileOutlineView.h"
#import <LDrawCore/LDrawHighResPrimitives.h>
#import <LDrawCore/LDrawLine.h>
#import <LDrawCore/LDrawLSynth.h>
#import <LDrawCore/LDrawLSynthDirective.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawQuadrilateral.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LDrawTriangle.h>
#import <LDrawCore/LDrawUtilities.h>
#import "LDrawViewerContainer.h"
#import <LDrawCore/LPubCommand.h>
#import <LDrawCore/LPubRemoveGroup.h>
#import <LDrawFeatures/LDrawGrid.h>
#import <LDrawFeatures/LDrawPreferences.h>
#import <LDrawFeatures/LSynthConfiguration.h>
#import <LDrawCore/MacLDraw.h>
#import "MinifigureDialogController.h"
#import <LDrawCore/ModelManager.h>
#import "MovePanel.h"
#import "PartBrowserDataSource.h"
#import "PartBrowserPanelController.h"
#import <LDrawCore/PartLibrary.h>
#import <LDrawCore/PartReport.h>
#import "PieceCountPanel.h"
#import "RotationPanelController.h"
#import "SearchPanelController.h"
#import "StringUtilities.h"
#import "UserDefaultsCategory.h"
#import "ViewportArranger.h"
#import "WindowCategory.h"
#if WANT_RELATED_PARTS
#import <LDrawFeatures/RelatedParts.h>
#endif


#if WANT_RELATED_PARTS
//---------- AppendChoicesToNewItem --------------------------------------------
//
// Purpose:		Appends related-part choices to a parent menu. The host still
//				builds NSMenuItems.
//
//------------------------------------------------------------------------------
void AppendChoicesToNewItem(
					NSMenu *	parent_menu,	// Menu we append to
					LDrawRelatedPartsMenuGroup * group)
{
	NSUInteger i, counter;
	NSMenuItem * my_item = nil;
	NSMenu * choices_menu = nil;

	if(group.style != LDrawRelatedPartsMenuMerged)
	{
		my_item = [[NSMenuItem alloc] initWithTitle:group.title action:NULL keyEquivalent:@""];
		[parent_menu addItem:my_item];
		
		choices_menu = [[NSMenu alloc] initWithTitle:[RelatedParts relatedPartsChoicesSubmenuTitle]];
		[my_item setSubmenu:choices_menu];
	}
	else
		choices_menu = parent_menu;
		
	counter = [group.choices count];
	for(i = 0; i < counter; ++i)
	{
		RelatedPart * ps = [group.choices objectAtIndex:i];

		NSMenuItem * ps_item = [[NSMenuItem alloc] initWithTitle:[group titleForChoice:ps]
														  action:@selector(addRelatedPartClicked:)
												   keyEquivalent:@""];
		[choices_menu addItem:ps_item];		
		[ps_item setRepresentedObject:ps];
	}
	
}//end AppendChoicesToNewItem
#endif


@implementation LDrawDocument

//========== init ==============================================================
//
// Purpose:		Sets up a new untitled document.
//
//==============================================================================
- (id) init
{
//	[[RelatedParts sharedRelatedParts] dump];
    self = [super init];
    if (self)
	{
		[self setDocumentContents:[LDrawFile file]];
		[self setGridSpacingMode:gridModeMedium];
    }
	markedSelection = NULL;
    return self;
	
}//end init


#pragma mark -
#pragma mark DOCUMENT
#pragma mark -

//========== windowNibName =====================================================
//
// Purpose:		Returns the name of the Nib file used to display this document.
//
//==============================================================================
- (NSString *) windowNibName
{
    // If you need to use a subclass of NSWindowController or if your document 
	// supports multiple NSWindowControllers, you should remove this method and 
	// override -makeWindowControllers instead.
    return @"LDrawDocument";
	
}//end windowNibName


//========== windowControllerDidLoadNib: =======================================
//
// Purpose:		awakeFromNib for document-based programs.
//
//==============================================================================
- (void) windowControllerDidLoadNib:(NSWindowController *) aController
{
	NSNotificationCenter	*notificationCenter 	= [NSNotificationCenter defaultCenter];
	NSUserDefaults			*userDefaults			= [NSUserDefaults standardUserDefaults];
	NSWindow				*window 				= [aController window];
	NSToolbar				*toolbar				= nil;
	NSString				*savedSizeString		= nil;
	NSUInteger				counter 				= 0;
	NSNumberFormatter		*coordinateFormatter	= [[NSNumberFormatter alloc] init];

    [super windowControllerDidLoadNib:aController];
	
	// Create the toolbar.
	toolbar = [[NSToolbar alloc] initWithIdentifier:[LDrawPreferences documentToolbarIdentifier]];
	[toolbar setAutosavesConfiguration:YES];
	[toolbar setAllowsUserCustomization:YES];
	[toolbar setDelegate:self->toolbarController];
	[window setToolbar:toolbar];
	
	
	// Set our size to whatever it was last time. (We don't do the whole frame 
	// because we want the origin to be nicely staggered as documents open; that 
	// normally happens automatically.)
	savedSizeString = [userDefaults objectForKey:DOCUMENT_WINDOW_SIZE];
	if(savedSizeString != nil)
	{
		NSSize	size	= NSSizeFromString(savedSizeString);
		[window resizeToSize:size animate:NO];
	}
	
	
	// File Contents Outline setup
	[fileContentsOutline setDoubleAction:@selector(showInspector:)];
	[fileContentsOutline setVerticalMotionCanBeginDrag:YES];
	[fileContentsOutline registerForDraggedTypes:[LDrawClipboard outlineRegisteredDragTypes]];
	
	
	// We have to do the splitview saving manually. C'mon Apple, get with it!
	// Note: They did in Leopard. These calls will use the system function 
	//		 there. 
	[fileContentsSplitView	setAutosaveName:[LDrawPreferences fileContentsSplitAutosaveName]];
	[viewportArranger		setAutosaveName:[LDrawPreferences documentViewportArrangerAutosaveName]];
	[self updateViewportAutosaveNamesAndRestore:YES];
	
	// Mouse hover coordinates
	[coordinateFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
	[coordinateFormatter setNumberStyle:NSNumberFormatterDecimalStyle];
	[coordinateFormatter setMaximumFractionDigits:0];
	[coordinateFormatter setMinimumFractionDigits:0];
	
	[self->coordinateFieldX setFormatter:coordinateFormatter];
	[self->coordinateFieldY setFormatter:coordinateFormatter];
	[self->coordinateFieldZ setFormatter:coordinateFormatter];
	
	
	// update scope step display controls
	[self setStepDisplay:NO];
	
	//Display our model.
	[self loadDataIntoDocumentUI];
	
	// Set opening zoom percentages
	[[self foremostWindow] layoutIfNeeded]; // zoomToFit needs view sizes
	LDrawView	*mainViewport = [self main3DViewport];
	{
		NSArray<LDrawView*>	*allViewports		= [self all3DViewports];
		LDrawView 			*currentViewport	= nil;

		for(counter = 0; counter < [allViewports count]; counter++)
		{
			currentViewport = [allViewports objectAtIndex:counter];
			
			// For brand new viewports which are not yet displaying a model, set 
			// the default zoom factor. 
			[currentViewport setZoomPercentage:[LDrawViewPolicy openingZoomPercentageForMainViewport:(currentViewport == mainViewport)]];

			// Scrolling to center doesn't seem to work at restoration time, so 
			// do it again here. 
			[currentViewport scrollCenterToModelPoint:ZeroPoint3];

			// For views which are displaying a model, we'll fit the model onscreen
			// (This has no effect for empty models)
			CGFloat unfitZoom	= [currentViewport zoomPercentage];
			CGFloat fitZoom 	= 0.0;

			[currentViewport zoomToFit:nil];
			fitZoom = [currentViewport zoomPercentage];

			// Back out a wee bit so the user has some room to work with his model
			CGFloat adjustedZoom = [LDrawViewPolicy fittedZoomPercentageAfterFit:fitZoom previousZoom:unfitZoom];
			if(adjustedZoom != unfitZoom)
			{
				[currentViewport setZoomPercentage:adjustedZoom];
			}
 		}
	}
	[[self foremostWindow] makeFirstResponder:mainViewport]; //so we can move it immediately.
	
	//Notifications we want.
	[notificationCenter addObserver:self
						   selector:@selector(syntaxColorChanged:)
							   name:LDrawSyntaxColorsDidChangeNotification
							 object:nil ];
	
	[notificationCenter addObserver:self
						   selector:@selector(docChanged:)
							   name:LDrawDirectiveDidChangeNotification
							 object:[self documentContents] ];

	[notificationCenter addObserver:self
						   selector:@selector(partChanged:)
							   name:LDrawDirectiveDidChangeNotification
							 object:nil ];

	[notificationCenter addObserver:self
						   selector:@selector(stepChanged:)
							   name:LDrawStepDidChangeNotification
							 object:nil ];
	
	[notificationCenter addObserver:self
						   selector:@selector(activeModelChanged:)
							   name:LDrawFileActiveModelDidChangeNotification
							 object:[self documentContents] ];
							 
	[notificationCenter addObserver:self
						   selector:@selector(libraryReloaded:)
							   name:LDrawPartLibraryReloaded
							 object:nil];
	
}//end windowControllerDidLoadNib:


#pragma mark -
#pragma mark Reading

//========== readFromURL:ofType:error: =========================================
//
// Purpose:		Reads the file off of disk. We are overriding this NSDocument 
//				method to grab the path; the actual data-collection is done 
//				elsewhere.
//
//==============================================================================
- (BOOL) readFromURL:(NSURL *)absoluteURL
			  ofType:(NSString *)typeName
			   error:(NSError **)outError
{
	AMSProgressPanel    *progressPanel  = [AMSProgressPanel progressPanel];
	NSString            *openMessage    = nil;
	BOOL                success         = NO;
	
	openMessage = [NSString stringWithFormat:	NSLocalizedString([LDrawEditorStrings openingFileFormatKey], nil), 
		[self displayName] ];
	
	//This might take a while. Show that we're doing something!
	[progressPanel setMessage:openMessage];
	[progressPanel setIndeterminate:YES];
	[progressPanel showProgressPanel];

	//do the actual loading.
	success = [super readFromURL:absoluteURL ofType:typeName error:outError];
	
	[progressPanel close];
	
	if(success == YES)
	{
		// Track the path. I'm not sure what a non-file URL means, and I'm basically 
		// hoping we never encounter one. 
		if([absoluteURL isFileURL] == YES)
		{
			[[self documentContents] setPath:[absoluteURL path]];
			[[ModelManager sharedModelManager] documentSignIn:[absoluteURL path] withFile:documentContents];
		}
		else
			[[self documentContents] setPath:nil];

		//Postflight: find missing and moved parts.
		[self doMovedPiecesCheck:self];
		[self doMissingModelnameExtensionCheck:self];
		
		[self doMissingPiecesCheck:self];
		
		// Now that all the parts are at their final name, we can optimize.
//		[[LDrawApplication sharedOpenGLContext] makeCurrentContext];
	}
	
	return success;
	
}//end readFromFile:ofType:


//========== showWindows =======================================================
//
// Purpose:		Overrides NSDocument method to fix a bug whereby the window is 
//				not main once opened. This bug is some sort of odd interplay 
//				with the progress panel; if you don't show the progress panel, 
//				the bug goes away. 
//
//==============================================================================
- (void) showWindows
{
	[super showWindows];
	[[self windowForSheet] makeKeyAndOrderFront:self]; // manually force what is normally automatic behavior.
}


//========== revertToContentsOfURL:ofType:error: ===============================
//
// Purpose:		Called by NSDocument when it reverts the document to its most 
//				recently saved state.
//
//==============================================================================
- (BOOL) revertToContentsOfURL:(NSURL *)absoluteURL
						ofType:(NSString *)typeName
						 error:(NSError **)outError
{
	BOOL success = NO;
	
	//Causes loadDataRepresentation:ofType: to be invoked.
	success = [super revertToContentsOfURL:absoluteURL ofType:typeName error:outError];
	if(success == YES)
	{
		//Display the new document contents. 
		//		(Alas. This doesn't happen automatically.)
		[self loadDataIntoDocumentUI];
	}
	
	return success;
	
}//end revertToSavedFromFile:ofType:


//========== readFromData:ofType:error: ========================================
//
// Purpose:		Read a logical document structure from data. This is the "open" 
//				method.
//
//==============================================================================
- (BOOL) readFromData:(NSData *)data
			   ofType:(NSString *)typeName
				error:(NSError **)outError
{
	NSString    	   *fileContents    = [LDrawUtilities stringFromFileData:data];
	__block	LDrawFile  *newFile         = nil;
	__block	BOOL        success         = NO;
	__block NSError    *blockError      = nil;
	
	//Parse the model.
	// - optimizing models can result in GPU calls, so to be ultra-safe we
	//   set a context and lock on it. We can't use any of the documents GPU
	//   views because the Nib may not have been loaded yet.
	[self lockContextAndExecute:^
	{
		[LDrawApplication makeCurrentSharedContext];

		@try
		{
			CFAbsoluteTime  startTime   = CFAbsoluteTimeGetCurrent();
			CFTimeInterval  parseTime   = 0;
			
			newFile     = [LDrawFile parseFromFileContents:fileContents];
			parseTime   = CFAbsoluteTimeGetCurrent() - startTime;
			
#if DEBUG
			NSLog(@"parse time = %f", parseTime);
#endif
			
			if(newFile != nil)
			{
				[self setDocumentContents:newFile];
				success = YES;
			}
		}
		@catch(NSException * e)
		{
			blockError = [NSError errorWithDomain:NSCocoaErrorDomain
											 code:NSFileReadCorruptFileError
										 userInfo:nil];
		}
	}];

	if (outError != NULL) {
		*outError = blockError;
	}
	
    return success;
	
}//end loadDataRepresentation:ofType:


#pragma mark -
#pragma mark Writing


//========== saveToURL:ofType:forSaveOperation:delegate:didSaveSelector:contextInfo:
//
// Purpose:		Saves the file out. We are overriding this NSDocument method to 
//				grab the path; the actual data-collection is done elsewhere.
//
//==============================================================================
- (void)saveToURL:(NSURL *)absoluteURL 
		   ofType:(NSString *)typeName 
 forSaveOperation:(NSSaveOperationType)saveOperation 
		 delegate:(id)delegate 
  didSaveSelector:(SEL)didSaveSelector 
	  contextInfo:(void *)contextInfo
{
	[super saveToURL:absoluteURL 
			  ofType:typeName 
	forSaveOperation:saveOperation 
			delegate:delegate 
	 didSaveSelector:didSaveSelector 
		 contextInfo:contextInfo];

	//track the path.
	if([absoluteURL isFileURL] == YES)
	{
		[[self documentContents] setPath:[absoluteURL path]];
		[[ModelManager sharedModelManager] documentSignIn:[absoluteURL path] withFile:documentContents];
	}
	else
		[[self documentContents] setPath:nil];
}//end saveToURL:ofType:forSaveOperation:delegate:didSaveSelector:contextInfo:


//========== dataOfType:error: =================================================
//
// Purpose:		Converts this document into a data object that can be written 
//				to disk. This is where a document gets saved.
//
//==============================================================================
- (NSData *)dataOfType:(NSString *)typeName
				 error:(NSError **)outError
{
    NSString *modelOutput = [[self documentContents] write];
	
	return [modelOutput dataUsingEncoding:NSUTF8StringEncoding];
	
}//end dataOfType:error:


#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

//========== documentContents ==================================================
//
// Purpose:		Returns the logical representation of the LDraw file this 
//				document represents.
//
//==============================================================================
- (LDrawFile *) documentContents
{
	return documentContents;
	
}//end documentContents


//========== foremostWindow ====================================================
//
// Purpose:		Returns the main editing window.
//
//==============================================================================
- (NSWindow *) foremostWindow
{
	return [[[self windowControllers] objectAtIndex:0] window];
	
}//end foremostWindow


//========== gridSpacingMode ===================================================
//
// Purpose:		Returns the current granularity of the positioning grid being 
//				used in this document.
//
//==============================================================================
- (gridSpacingModeT) gridSpacingMode
{
	return gridMode;
	
}//end gridSpacingMode


//========== gridOrientationMode ===============================================
//
// Purpose:		Returns the current grid orientation of the positioning grid
//				being used in this document.
//
//==============================================================================
- (gridOrientationModeT) gridOrientationMode
{
	return gridOrientation;
	
}//end gridOrientationMode


//========== viewingAngle ======================================================
//
// Purpose:		Returns the modelview rotation for the focused LDrawView.
//
//==============================================================================
- (Tuple3) viewingAngle
{
	Tuple3	angle	= [self->mostRecentLDrawView viewingAngle];
	
	return angle;
	
}//end viewingAngle


#pragma mark -


//========== setActiveModel: ===================================================
//
// Purpose:		Changes the current active (displayed) submodel, preserving as 
//				much of the viewing state as is appropriate. 
//
// Notes:		You should call this rather than setting the active model 
//				directly on the LDrawFile. 
//
//==============================================================================
- (void) setActiveModel:(LDrawMPDModel *)newActiveModel
{
	LDrawMPDModel	*oldActiveModel		= [[self documentContents] activeModel];
	BOOL			stepDisplayMode		= [oldActiveModel stepDisplay];
	
	if(newActiveModel != oldActiveModel)
	{
		// Allow the old model to draw in its entirety if it is referenced by the 
		// new model. 
		[oldActiveModel setStepDisplay:NO];
		
		// Set the new model and make sure its step display state matches the 
		// previous step display state. 
		[[self documentContents] setActiveModel:newActiveModel];
		[self setStepDisplay:stepDisplayMode];;
		
		//A notification will be generated that updates the models menu.
	}
}//end setActiveModel:


//========== setCurrentStep: ===================================================
//
// Purpose:		Sets the current maximum step displayed in step display mode and 
//				updates the UI. 
//
// Notes:		This does not activate step display if it isn't on.
//				This also does not do anything if the step is not changing.
//
// Parameters:	requestedStep	- the 0-relative step number. Does not do 
//								  bounds-checking. 
//
//==============================================================================
- (void) setCurrentStep:(NSInteger)requestedStepIndex
{
	LDrawMPDModel	*activeModel		= [[self documentContents] activeModel];
	NSInteger		currentStepIndex	= [activeModel maximumStepIndexForStepDisplay];
	LDrawStep		*requestedStep		= [[activeModel steps] objectAtIndex:requestedStepIndex];
	
	if(currentStepIndex != requestedStepIndex)
	{
		[activeModel setMaximumStepIndexForStepDisplay:requestedStepIndex];
		
		// Update UI
		
		[self selectStep:requestedStepIndex];
		
		[self->stepField setIntegerValue:(requestedStepIndex + 1)]; // make 1-relative
		
		if([activeModel stepDisplay] == YES)
		{
			if([requestedStep stepRotationType] != LDrawStepRotationNone)
			{
				[self updateViewingAngleToMatchStep];
			}
				
			[[self documentContents] noteNeedsDisplay];
		}
	}
	
}//end setCurrentStep:


//========== setDocumentContents: ==============================================
//
// Purpose:		Sets the logical representation of the LDraw file this 
//				document represents to newContents. This method should be called 
//				when the document is first created.
//
// Notes:		This method intentionally avoids making the user interface aware 
//				of the new contents. This is because this method is generally 
//				called prior to loading the Nib file. (It also gets called when 
//				reverting.) There is a separate method, -loadDataIntoDocumentUI,
//				to sync the UI.
//
//==============================================================================
- (void) setDocumentContents:(LDrawFile *)newContents
{
	// This is going to be an editable container now, so we need to know when it
	// changes. 
	[newContents setPostsNotifications:YES];
	
	documentContents = newContents;
	
    [LDrawApplication makeCurrentSharedContext];

}//end setDocumentContents:


//========== setGridSpacingMode: ===============================================
//
// Purpose:		Sets the current granularity of the positioning grid being used 
//				in this document. 
//
//==============================================================================
- (void) setGridSpacingMode:(gridSpacingModeT)newMode
{
	NSArray<LDrawView*>*	graphicViews	= [self all3DViewports];
	NSUInteger				counter 		= 0;

	self->gridMode = newMode;
	
	// Update bits of UI
	[self->toolbarController setGridSpacingMode:newMode];
	
	for(counter = 0; counter < [graphicViews count]; counter++)
	{
		[[graphicViews objectAtIndex:counter] setGridSpacingMode:newMode];
	}
	
}//end setGridSpacingMode:


//========== setGridOrientationMode: ===========================================
//
// Purpose:		Sets the current grid orientation of the positioning grid being
//				used in this document.
//
//==============================================================================
- (void) setGridOrientationMode:(gridOrientationModeT)newMode
{
	self->gridOrientation = newMode;
	[self->toolbarController setGridOrientationMode:newMode];
	
}//end setGridOrientationMode:


//========== setLastSelectedPart: ==============================================
//
// Purpose:		The document keeps track of the part most recently selected in 
//				the file contents outline. This method is called each time a new 
//				part is selected. The transformation matrix of the previously 
//				selected part is then used when new parts are added.
//
//==============================================================================
- (void) setLastSelectedPart:(LDrawPart *)newPart
{
	lastSelectedPart = newPart;
	
}//end setLastSelectedPart:


//========== setMostRecentLDrawView: ===========================================
//
// Purpose:		Sets the 3D view with which we interacted the most recently. 
//
// Note:		This accessor method is mainly here to provide KVO compliance so 
//				Cocoa will automatically generate the necessary change messages 
//				for binding which observe the most recent view. 
//
//==============================================================================
- (void) setMostRecentLDrawView:(LDrawView *)viewIn
{
	self->mostRecentLDrawView = viewIn;
	
}//end setMostRecentLDrawView:


//========== setStepDisplay: ===================================================
//
// Purpose:		Turns step display (like Lego instructions) on or off for the 
//				active model.
//
//==============================================================================
- (void) setStepDisplay:(BOOL)showStepsFlag
{
	LDrawMPDModel	*activeModel	= [[self documentContents] activeModel];
	
	if(showStepsFlag != [activeModel stepDisplay])
	{
		if(showStepsFlag == YES)
		{
			[activeModel setStepDisplay:YES];
			[self setCurrentStep:0];
			
			// Force viewing angle update when turning on step display. 
			// -setCurrentStep only does this if the step has actually changed. 
			[self updateViewingAngleToMatchStep];
		}
		else // turn it off now
		{
			[activeModel setStepDisplay:NO];
		}
		
		[[self documentContents] noteNeedsDisplay];
	}
	
	// Set scope button state no matter what. The scope buttons are really 
	// toggle buttons which call this method; if you click "Steps" and step 
	// display is already on, you want the button to *stay* selected. This makes 
	// sure that happens. 
	[self->viewAllButton   setState:(showStepsFlag == NO)];
	[self->viewStepsButton setState:(showStepsFlag == YES)];
	
	[self->scopeStepControlsContainer setHidden:(showStepsFlag == NO)];
	[self->stepField setIntegerValue:[activeModel maximumStepIndexForStepDisplay] + 1];
	
}//end setStepDisplay:


#pragma mark -
#pragma mark ACTIVITIES
#pragma mark -
//These are *high-level* calls to modify the structure of the model. They call 
// down to appropriate low-level calls (in the "Undoable Activities" section).


//========== moveSelectionBy: ==================================================
//
// Purpose:		Moves all selected (and moveable) directives in the direction 
//				indicated by movementVector.
//
//==============================================================================
- (void) moveSelectionBy:(Vector3) movementVector
{
	for(id currentObject in [LDrawSelection movableDirectivesInSelection:[self selectedObjects]])
	{
		[self moveDirective: (LDrawDrawableElement*)currentObject
				inDirection: movementVector];
	}
	
}//end moveSelectionBy:


//========== nudgeSelectionBy: =================================================
//
// Purpose:		Nudges all selected (and nudgeable) directives in the direction 
//				indicated by nudgeVector, which should be normalized. The exact 
//				amount nudged is dependent on the directives themselves, but we 
//				give them our best estimate based on the grid granularity.
//
//==============================================================================
- (void) nudgeSelectionBy:(Vector3)nudgeVector
{
	Vector3 worldNudge = ZeroPoint3;
	if([LDrawSelection worldNudge:&worldNudge
				  fromScreenNudge:nudgeVector
					  gridSpacing:[LDrawGrid spacingForMode:self->gridMode]
						selection:[self selectedObjects]] == NO)
	{
		return;
	}

	[self moveSelectionBy:worldNudge];
}//end nudgeSelectionBy:


//========== rotateSelectionAround:extraFine:aroundOrigin: =====================
//
// Purpose:		Rotates all selected parts in a clockwise direction around the 
//				specified axis. The rotationAxis should be either 
//				+/- i, +/- j or +/- k.
//
//				If extraFine is YES, the rotation angle is reduced in 5 times.
//
//				If aroundOrigin is YES, the rotation center is the origin of
//				the model, otherwize - the center of the selected directives.
//
//				This method is used by the rotate toolbar methods. It chooses
//				the actual number of degrees based on the current grid mode.
//
//==============================================================================
- (void) rotateSelectionAround:(Vector3)rotationAxis
					 extraFine:(BOOL)extraFine
				  aroundOrigin:(BOOL)aroundOrigin
{
	NSArray			*selectedObjects	= [self selectedObjects];
	float			 degreesToRotate	= [LDrawGrid rotationDegreesForMode:[self gridSpacingMode]
																	   kind:LDrawGridRotationAxis
																  extraFine:extraFine];
	Tuple3			 rotation			= [LDrawSelection rotationForAxis:rotationAxis degrees:degreesToRotate];

	rotation = [LDrawSelection partRelativeRotation:rotation
									   forSelection:selectedObjects
									   partRelative:(self->gridOrientation == gridOrientationPart)];

	RotationModeT rotationMode = [LDrawSelection rotationModeForSelectionCount:[selectedObjects count]
																  aroundOrigin:aroundOrigin];
	Point3 origin = {0};
	Point3 *fixedCenter = (rotationMode == RotateAroundFixedPoint) ? &origin : NULL;

	[self rotateSelection:rotation mode:rotationMode fixedCenter:fixedCenter];

}//end rotateSelectionAround:extraFine:aroundOrigin:


//========== rotateSelection:mode:fixedCenter: =================================
//
// Purpose:		Rotates the selected parts according to the specified mode.
//
// Parameters:	rotation	= degrees x,y,z to rotate
//				mode		= how to derive the rotation centerpoint
//				fixedCenter	= explicit centerpoint, or NULL if mode not equal to 
//							  RotateAroundFixedPoint
//
//==============================================================================
- (void) rotateSelection:(Tuple3)rotation
					mode:(RotationModeT)mode
			 fixedCenter:(Point3 *)fixedCenter
{
	NSArray     *selectedObjects    = [self selectedObjects]; //array of LDrawDirectives.
	Point3      rotationCenter      = [LDrawSelection rotationCenterForDirectives:selectedObjects
																			 mode:mode
																	  fixedCenter:fixedCenter];

	//rotate everything that can be rotated. That would be parts and only parts.
	for(LDrawPart *currentObject in [LDrawSelection partsInSelection:selectedObjects])
	{
		Point3 center = rotationCenter;
		if(mode == RotateAroundPartPositions)
			center = [currentObject position];

		[self rotatePart:currentObject
			   byDegrees:rotation
			 aroundPoint:center ];
	}
	
}//end rotateSelection:mode:fixedCenter:


//========== selectDirective:byExtendingSelection:==============================
//
// Purpose:		Selects the specified directive.
//				Pass nil to deselect all.
//
//				If shouldExtend is YES, this method toggles the selection of the 
//				given directive. Otherwise, the given directive is made the 
//				exclusive selection in the document. 
//
//				if withScrolling is true, the outliner is auto-scrolled to 
//				reveal the new selection.  This can be turned off for 
//				performance: when "select-all" is invoked on a huge model,
//				scrolling time can take tens of seconds.
//
//==============================================================================
- (void) selectDirective:(LDrawDirective *) directiveToSelect
    byExtendingSelection:(BOOL) shouldExtend
{
	NSArray     *ancestors      = [directiveToSelect ancestors];
	NSInteger   indexToSelect   = 0;
	NSInteger   counter         = 0;
	
	if(directiveToSelect == nil)
		[fileContentsOutline deselectAll:nil];
	else
	{
		//Expand the hierarchy all the way down to the directive we are about to 
		// select.
		for(counter = 0; counter < [ancestors count]; counter++)
			[fileContentsOutline expandItem:[ancestors objectAtIndex:counter]];
		
		//Now we can safely select the directive. It is guaranteed to be visible, 
		// since we expanded all its ancestors.
		indexToSelect = [fileContentsOutline rowForItem:directiveToSelect];
		
		//If we are doing multiple selection (shift-click), we want to deselect 
		// already-selected parts.
		if(		[[fileContentsOutline selectedRowIndexes] containsIndex:indexToSelect]
			&&	shouldExtend == YES )
		{
			[fileContentsOutline deselectRow:indexToSelect];
		}
		else
		{
			[fileContentsOutline selectRowIndexes:[NSIndexSet indexSetWithIndex:indexToSelect]
							 byExtendingSelection:shouldExtend];
		}
		
		[fileContentsOutline scrollRowToVisible:indexToSelect];
	}
	
}//end selectDirective:byExtendingSelection:

//========== selectDirectives: ================================================
//
// Purpose:		Selects an array of directives.  This function changes the 
//				selection to be these and only these directives, deselecting
//				all others in the process.
//
//				This is used for marquee selection - when changing a lot of
//				selection it's more CPU efficient to change them all at once. 
//
// Notes:		This routine will perform multiple disclosures of items in the
//				hierarchy as needed to make the selection.  It does not attempt
//				to scroll to the selected items, as they could be spread all 
//				over the place.
//
//==============================================================================
- (void) selectDirectives:(NSArray *) directivesToSelect
{
	NSInteger   indexToSelect   = 0;
	NSInteger   counter         = 0;
	NSInteger	d				= 0;
	NSInteger	total			= [directivesToSelect count];
	
	if(total == 0)
		[fileContentsOutline deselectAll:nil];
	else
	{
		// Optimization: Track which ancestors we've already expanded to avoid redundant
		// expansions. With 100,000+ parts, many directives share the same ancestors
		// (e.g., all parts in the same step share that step), so we can expand each
		// ancestor only once. This dramatically reduces the number of expand operations.
		NSMutableSet *expandedAncestors = [NSMutableSet setWithCapacity:total];
		
		for (d = 0; d < total; ++d)
		{
			LDrawDirective 	*directive = [directivesToSelect objectAtIndex:d];
			NSArray 		*ancestors = [directive ancestors];

			//Expand the hierarchy all the way down to the directive we are about to 
			// select. Only expand each ancestor once.
			for (counter = 0; counter < [ancestors count]; counter++)
			{
				LDrawDirective *ancestor = [ancestors objectAtIndex:counter];
				if (![expandedAncestors containsObject:ancestor])
				{
					[fileContentsOutline expandItem:ancestor];
					[expandedAncestors addObject:ancestor];
				}
			}
		}

		NSMutableIndexSet * indices = [NSMutableIndexSet indexSet];
		
		for (d = 0; d < total; ++d)
		{
			LDrawDirective * directive = [directivesToSelect objectAtIndex:d];			
		
			indexToSelect = [fileContentsOutline rowForItem:directive];
			[indices addIndex:indexToSelect];
		}
		[fileContentsOutline selectRowIndexes:indices byExtendingSelection:NO];
	}
	
}//end selectDirectives:


//========== selectStep: =======================================================
//
// Purpose:		Selects the single step. This function deselects all other
//				steps/directives.
//
//==============================================================================
- (void) selectStep:(NSInteger)step
{
	LDrawModel  *activeModel    = [[self documentContents] activeModel];
	NSArray *allSteps = activeModel.subdirectives;
	if (step < allSteps.count)
	{
		LDrawDirective *directiveToSelect = allSteps[step];
		NSInteger indexToSelect = 0;
		
		if(directiveToSelect == nil)
			[fileContentsOutline deselectAll:nil];
		else
		{
			indexToSelect = [fileContentsOutline rowForItem:directiveToSelect];
			
			[fileContentsOutline selectRowIndexes:[NSIndexSet indexSetWithIndex:indexToSelect]
							 byExtendingSelection:NO];
			
			[fileContentsOutline scrollRowToVisible:indexToSelect];
		}
	}
}//end selectStep:


//========== setSelectionToHidden: =============================================
//
// Purpose:		Hides or shows all the hideable selected elements.
//
//==============================================================================
- (void) setSelectionToHidden:(BOOL)hideFlag
{
	for(id currentObject in [LDrawSelection hideableDirectivesInSelection:[self selectedObjects]])
	{
		[self setElement:currentObject toHidden:hideFlag]; //undoable hook.
	}
		
}//end setSelectionToHidden:


//========== setZoomPercentage: ================================================
//
// Purpose:		Zooms the selected LDraw view to the specified percentage.
//
//==============================================================================
- (void) setZoomPercentage:(CGFloat)newPercentage
{
	[self->mostRecentLDrawView setZoomPercentage:newPercentage];
	
}//end setZoomPercentage:


#pragma mark -
#pragma mark ACTIONS
#pragma mark -
//traditional -(void)action:(id)sender type action methods.
// Generally called directly by User Interface controls.


//========== changeLDrawColor: =================================================
//
// Purpose:		Responds to color-change messages sent down the responder chain 
//				by the LDrawColorPanelController. Upon the receipt of this 
//				message, the window should change the color of all the selected 
//				objects to the new color specified in the panel. 
//
//==============================================================================
- (void) changeLDrawColor:(id)sender
{
	NSArray    *selectedObjects = [self selectedObjects];
	LDrawColor *newColor        = [sender LDrawColor];

	for(id currentObject in [LDrawSelection colorableDirectivesInSelection:selectedObjects])
	{
		[self setObject:currentObject toColor:newColor];
	}
	if([selectedObjects count] > 0)
		[[self documentContents] noteNeedsDisplay];
		
}//end changeLDrawColor:




//========== insertLDrawPart: ==================================================
//
// Purpose:		We are being prompted to insert a new part into the model.
//
// Parameters:	sender = PartBrowserDataSource generating the insert request.
//
//==============================================================================
- (void) insertLDrawPart:(id)sender
{
	NSString	*partName	= [sender selectedPartName];
	
	//We got a part; let's add it!
	if(partName != nil)
		[self addPartNamed:partName];
	
	// part-insertion may have been generated by a Part Browser panel which was 
	// in the foreground. Now that the part is inserted, we want the editor 
	// window in the foreground. 
	[[self foremostWindow] makeKeyAndOrderFront:sender];
	
}//end insertLDrawPart:


//========== nudge: ============================================================
//
// Purpose:		Called by LDrawView when it wants to nudge the selection.
//
//==============================================================================
- (void) nudge:(id)sender
{
	LDrawView *glView     = sender;
	Matrix4 xform = [LDrawSelection nudgeOrientationMatrixForSelection:[self selectedObjects]
														  partRelative:(self->gridOrientation == gridOrientationPart)];
	Vector3     nudgeVector = [glView nudgeVectorForMatrix:xform];

	[self nudgeSelectionBy:nudgeVector];
	
}//end nudge:


//========== panelMoveParts: ===================================================
//
// Purpose:		The move panel wants to move parts.
//
// Parameters:	sender = MovePanel generating the move request.
//
//==============================================================================
- (void) panelMoveParts:(id)sender
{
	Vector3			movement		= [sender movementVector];
	
	[self moveSelectionBy:movement];
	
}//end panelMoveParts


//========== panelRotateParts: =================================================
//
// Purpose:		The rotation panel wants to rotate! It's up to us to interrogate 
//				the rotation panel to figure out how exactly this rotation is 
//				supposed to be done.
//
// Parameters:	sender = RotationPanel generating the rotation request.
//
//==============================================================================
- (void) panelRotateParts:(id)sender
{
	Tuple3			angles			= [sender angles];
	RotationModeT	rotationMode	= [sender rotationMode];
	Point3			centerPoint		= [sender fixedPoint];
	
	//the center may not be valid, but that will get taken care of by the 
	// rotation mode.
	
	[self rotateSelection:angles
					 mode:rotationMode
			  fixedCenter:&centerPoint];
	
}//end panelRotateParts


#pragma mark -

//========== doMissingModelnameExtensionCheck: =================================
//
// Purpose:		Ensures that the names of all submodels in the current model end 
//				in a recognized LDraw extension (.ldr, .dat), renaming models 
//				and updating references as needed. 
//
// Notes:		Previous versions of Bricksmith did not force submodel names to 
//				end in a file extension, and this was a seemingly sensible, 
//				Maclike thing to do. Alas, MLCad will NOT RECOGNIZE submodels 
//				whose names do not have an extension. (Why...?!) Furthermore, 
//				according to the LDraw File Specification, a type 1 MUST point 
//				ot a "valid LDraw filename," which MUST include the extension. 
//				http://www.ldraw.org/Article218.html#lt1 Sigh...
//
//				This action is not undoable. Why would you want to?
//
//==============================================================================
- (void) doMissingModelnameExtensionCheck:(id)sender
{
	NSArray *submodels = [[self documentContents] submodels];

	for(LDrawCompliantNameChange *change in [LDrawStructure compliantNameChangesForSubmodels:submodels])
	{
		if(change.renameInPlace)
		{
			[change.model setModelName:change.compliantName];
		}
		else
		{
			[[self documentContents] renameModel:change.model toName:change.compliantName];
			[self updateChangeCount:NSChangeDone];
		}
	}
	
}//end doMissingModelnameExtensionCheck:


//========== doMissingPiecesCheck: =============================================
//
// Purpose:		Searches the current model for any missing parts, and displays a 
//				warning if there are some.
//
//==============================================================================
- (void) doMissingPiecesCheck:(id)sender
{
	CFAbsoluteTime  startTime       = CFAbsoluteTimeGetCurrent();
	CFTimeInterval  partReportTime    = 0;
	
	// Until we load neighbor files as part of the async-GCD-friendly file load, neighboring files show
	// up here - the part report is the first thing that triggers the lazy load.  So until we fix this,
	// "resolve" time contains the time to figure out what each part points to, and the dominant cost 
	// is loading neighbor files when they are in use.
				
	PartReport		*partReport			= [PartReport partReportForContainer:[self documentContents]];
	NSArray			*missingParts		= [partReport missingParts];

	partReportTime = CFAbsoluteTimeGetCurrent() - startTime;
#if DEBUG
	NSLog(@"resolve time = %f", partReportTime);
#endif

	NSString		*missingNames		= nil;
	NSMutableString	*informativeString	= nil;
	
	if([missingParts count] > 0)
	{
		//Build a string listing all the missing parts.
		missingNames = [LDrawSearch newlineSeparatedDisplayNamesFromDirectives:missingParts];
		
		informativeString = [NSMutableString stringWithString:NSLocalizedString([LDrawEditorStrings missingPiecesInformativeKey], nil)];
		[informativeString appendString:@"\n\n"];
		[informativeString appendString:missingNames];
		
		//Alert! Alert!
		NSAlert *alert = [[NSAlert alloc] init];
		
		[alert     setMessageText:NSLocalizedString([LDrawEditorStrings missingPiecesMessageKey], nil)];
		[alert setInformativeText:informativeString];
		[alert addButtonWithTitle:NSLocalizedString([LDrawEditorStrings okButtonNameKey], nil)];
		
		[alert runModal];
		
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			for (LDrawDirective *part in missingParts) {
				[self selectDirective:part byExtendingSelection:YES];
			}
		});
	}
	
}//end doMissingPiecesCheck:


//========== doMovedPiecesCheck: ===============================================
//
// Purpose:		Searches the current model for any ~Moved parts, and displays a 
//				warning if there are some.
//
//==============================================================================
- (void) doMovedPiecesCheck:(id)sender
{
	PartReport	*partReport     = [PartReport partReportForContainer:[self documentContents]];
	NSArray     *movedParts     = [partReport movedParts];
	NSInteger   buttonReturned  = 0;
	
	if([movedParts count] > 0)
	{
		//Alert! Alert! What should we do?
		NSAlert *alert = [[NSAlert alloc] init];
		
		[alert     setMessageText:NSLocalizedString([LDrawEditorStrings movedPiecesMessageKey], nil)];
		[alert setInformativeText:NSLocalizedString([LDrawEditorStrings movedPiecesInformativeKey], nil)];
		[alert addButtonWithTitle:NSLocalizedString([LDrawEditorStrings okButtonNameKey], nil)];
		[alert addButtonWithTitle:NSLocalizedString([LDrawEditorStrings cancelButtonNameKey], nil)];
		
		buttonReturned = [alert runModal];
		
		//They want us to update the ~Moved parts.
		if(buttonReturned == NSAlertFirstButtonReturn)
		{
			[LDrawUtilities updateNamesForMovedParts:movedParts];
			
			//mark document as modified.
			[self updateChangeCount:NSChangeDone];
		}
	}
	
}//end doMovedPiecesCheck:


#pragma mark -
#pragma mark Scope Bar

//========== viewAll: ==========================================================
//
// Purpose:		Turn off Step Display.
//
//==============================================================================
- (IBAction) viewAll:(id)sender
{
	// Call the simple method. This also takes care of button state for us.
	[self setStepDisplay:NO];
	
}//end viewAll:


//========== viewSteps: ========================================================
//
// Purpose:		Turn on Step Display.
//
//==============================================================================
- (IBAction) viewSteps:(id)sender
{
	// Call the simple method. This also takes care of button state for us.
	[self setStepDisplay:YES];

}//end viewSteps:


//========== stepFieldChanged: =================================================
//
// Purpose:		This allows you to type in a specific step and go to it.
//
//==============================================================================
- (IBAction) stepFieldChanged:(id)sender
{
	LDrawMPDModel   *activeModel    = [[self documentContents] activeModel];
	NSInteger       numberSteps     = [[activeModel steps] count];
	NSInteger       requestedStep   = [sender integerValue]; // 1-relative
	NSInteger       actualStep      = 0; // 1-relative
	
	// The user's number may have been out of range.
	actualStep = CLAMP(requestedStep, 1, numberSteps);
	
	[self setCurrentStep:(actualStep - 1)]; // convert to 0-relative
	
	// If we had to clamp, that is a user error. Tell him.
	if(actualStep != requestedStep)
		NSBeep();
		
}//end stepFieldChanged:


//========== stepNavigatorClicked: =============================================
//
// Purpose:		The step navigator is a segmented control that presents a back 
//				and forward button. 
//
//==============================================================================
- (IBAction) stepNavigatorClicked:(id)sender
{
	// Back == 0; Forward == 1
	if([sender selectedSegment] == 0)
		[self backOneStep:sender];
	else
		[self advanceOneStep:sender];
	
}//end stepNavigatorClicked:


#pragma mark -
#pragma mark File Menu

//========== exportSteps: ======================================================
//
// Purpose:		Presents a save dialog allowing the user to export his model 
//				as a series of files, one for each progressive step.
//
//==============================================================================
- (IBAction) exportSteps:(id)sender
{
	NSSavePanel *exportPanel	= [NSSavePanel savePanel];
	NSString	*activeName		= [[[self documentContents] activeModel] modelName];
	NSString	*nameFormat		= NSLocalizedString([LDrawStructure exportedStepsFolderFormatKey], nil);
	
	[exportPanel setDirectoryURL:nil];
	[exportPanel setNameFieldStringValue:[NSString stringWithFormat:nameFormat, activeName]];
	
	[exportPanel beginSheetModalForWindow:[self windowForSheet]
						completionHandler:
	 ^(NSInteger returnCode)
	 {
		 if(returnCode != NSModalResponseOK) return;

		 NSFileManager *fileManager = [[NSFileManager alloc] init];
		 NSURL         *saveURL     = [exportPanel URL];
		 NSString      *saveName    = ([saveURL isFileURL] ? [saveURL path] : nil);

		 // If we got this far, we need to replace any prexisting file.
		 if([fileManager fileExistsAtPath:saveName isDirectory:NULL])
		 {
			 [fileManager removeItemAtPath:saveName error:NULL];
		 }

		 [fileManager createDirectoryAtPath:saveName withIntermediateDirectories:YES attributes:nil error:NULL];

		 NSArray *exports = [LDrawStructure stepExportFilesFromFile:[self documentContents]
												   folderNameFormat:NSLocalizedString([LDrawStructure exportedStepsFolderFormatKey], nil)
													 fileNameFormat:NSLocalizedString([LDrawStructure exportedStepsFileFormatKey], nil)];
		 for(LDrawStepExportFile *item in exports)
		 {
			 NSString *folderName = [saveName stringByAppendingPathComponent:item.folderName];
			 [fileManager createDirectoryAtPath:folderName withIntermediateDirectories:YES attributes:nil error:NULL];

			 NSString *outputPath = [folderName stringByAppendingPathComponent:item.fileName];
			 NSData   *fileOutputData = [item.ldrString dataUsingEncoding:NSUTF8StringEncoding];
			 [fileManager createFileAtPath:outputPath
								  contents:fileOutputData
								attributes:nil];
		 }
	 }];

}//end exportSteps:


//========== revealInFinder: ===================================================
//
// Purpose:             Open a Finder window with the current file selected.
//
//==============================================================================
- (IBAction) revealInFinder:(id)sender
{
    // Cribbed directly from
    // http://stackoverflow.com/questions/7652928/launch-osx-finder-window-with-specific-files-selected
    NSArray *fileURLs = [NSArray arrayWithObjects:[self fileURL], nil];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:fileURLs];
    
}//end revealInFinder:

#pragma mark -
#pragma mark Edit Menu

//========== cut: ==============================================================
//
// Purpose:		Respond to an Edit->Cut action.
//
//==============================================================================
- (IBAction) cut:(id)sender {

	NSUndoManager	*undoManager		= [self undoManager];

	[self copy:sender];
	[self delete:sender]; //that was easy.

	[undoManager setActionName:NSLocalizedString(@"", nil)];
	
}//end cut:


//========== copy: =============================================================
//
// Purpose:		Respond to an Edit->Copy action.
//
//==============================================================================
- (IBAction) copy:(id)sender {

	NSPasteboard	*pasteboard			= [NSPasteboard generalPasteboard];
	NSArray			*selectedObjects	= [self selectedObjects];
	
	[self writeDirectives:selectedObjects
			 toPasteboard:pasteboard];
	
}//end copy:


//========== paste: ============================================================
//
// Purpose:		Respond to an Edit->Paste action, pasting the contents off the 
//				standard copy/paste pasteboard.
//
//==============================================================================
- (IBAction) paste:(id)sender
{
	NSPasteboard	*pasteboard			= [NSPasteboard generalPasteboard];
	NSUndoManager	*undoManager		= [self undoManager];
	
	[self pasteFromPasteboard:pasteboard
		preventNameCollisions:YES
					   parent:[self selectedStep]
						index:NSNotFound
				nextToSimilar:NO];

	[undoManager setActionName:NSLocalizedString(@"", nil)];
	
}//end paste:


//========== delete: ===========================================================
//
// Purpose:		A delete request has arrived from somplace--it could be the 
//				menus, the window, the outline view, etc. Our job is to delete
//				the current selection now.
//
// Notes:		This method conveniently has the same name as one in NSText; 
//				that allows us to use the same menu item for both textual and 
//				part delete.
//
//==============================================================================
- (IBAction) delete:(id)sender
{
	NSArray *selectedObjects = [self selectedObjects];

	// Clear the selection FIRST.  We already have a copy of the doomed objects;
	// if we don't clear the selection, deleting the objs OUT of the selection
	// will cause massive thrash of the outliner.
	[fileContentsOutline deselectAll:sender];
	
	for(LDrawDirective *currentObject in [LDrawStructure directivesInReverseDeletionOrder:selectedObjects])
	{
		if([self canDeleteDirective:currentObject displayErrors:YES] == YES)
		{	//above method will display an error if the directive can't be deleted.
			[self deleteDirective:currentObject];
		}
	}
	
	[[self documentContents] noteNeedsDisplay];
		
}//end delete:


//========== selectAll: ========================================================
//
// Purpose:		Selects all the visible LDraw elements in the active model. This 
//				does not select the steps or model--only the contained elements 
//				themselves. Hidden elements are also ignored.
//
//==============================================================================
- (IBAction) selectAll:(id)sender
{
	LDrawModel *activeModel = [[self documentContents] activeModel];
	NSArray    *visibleElements = [LDrawSelection visibleDirectivesIn:[activeModel allEnclosedElements]];

	// Use bulk directive set rather than calling selectDirective over and over.
	// selectDirective 4000 times is too slow - too much notification traffic.
	[self selectDirectives:visibleElements];
	
}//end selectAll:


//========== duplicate: ========================================================
//
// Purpose:		Makes a copy of the selected object.
//
//==============================================================================
- (IBAction) duplicate:(id)sender
{
	// To take advantage of all the exceptionally cool copy/paste code we 
	// already have, -duplicate: simply "copies" the selection onto a private 
	// pasteboard then "pastes" it right back in. This avoids destroying the 
	// general pasteboard, but allows us some fabulous code reuse. (In case you 
	// haven't noticed, I'm proud of this!) 
	NSPasteboard	*pasteboard			= [NSPasteboard pasteboardWithName:[LDrawClipboard duplicationPasteboardName]];
	NSArray			*selectedObjects	= [self selectedObjects];
	NSUndoManager	*undoManager		= [self undoManager];
	NSInteger 		indexOfObject		= NSNotFound;

	[[undoManager prepareWithInvocationTarget:self] selectDirectives:selectedObjects];

	indexOfObject = [LDrawPaste duplicatePasteIndexForSelection:selectedObjects
										  defaultNextModelIndex:[self nextModelIndex]];
	[self writeDirectives:selectedObjects toPasteboard:pasteboard];
	[self pasteFromPasteboard:pasteboard
		preventNameCollisions:YES
					   parent:nil
						index:indexOfObject
				nextToSimilar:YES];

	[undoManager setActionName:NSLocalizedString([LDrawPaste duplicateUndoActionKey], nil)];
	
}//end duplicate:

//========== find: ========================================================
//
// Purpose:		Opens the Find Parts dialog
//
//==============================================================================
- (IBAction) find:(id)sender
{
    SearchPanelController *searchPanel = [SearchPanelController searchPanel];
    [[searchPanel window] makeKeyAndOrderFront:sender];
} // end find:

//========== splitStep: ========================================================
//
// Purpose:		splitStep splits the selected directives out of their current
//				steps and puts them into a newly created step; the newly 
//				created step is inserted directly BEFORE the last parent step of
//				the selection.  (Users can use this to rapidly 'break down' a
//				monolithic pile of bricks into sane steps.)
//
// Notes:		The function will only move selection directives that are 
//				children of steps from a single model.
//
//==============================================================================
- (IBAction) splitStep:(id)sender
{
	NSUndoManager   *undoManager      = [self undoManager];
	LDrawContainer  *containingModel  = nil;
	LDrawStep       *highestStep      = nil;
	NSInteger        highestIndex     = 0;
	NSArray         *movedDirectives  = [LDrawStructure splitStepDirectivesFromSelection:[self selectedObjects]
																		 containingModel:&containingModel
																			  sourceStep:&highestStep
																			 insertIndex:&highestIndex];

	if([movedDirectives count] == 0)
		return;

	[fileContentsOutline deselectAll:sender];

	for(id child in movedDirectives)
	{
		[self deleteDirective:child];
	}

	LDrawStep *newStep = [LDrawStep emptyStep];

	// Do undo stuff before changing rotation
	[self preserveDirectiveState:highestStep];
	[LDrawStructure transferRotationFromStep:highestStep toStep:newStep];

	[self addDirective:newStep toParent:containingModel atIndex:highestIndex];

	for(id child in movedDirectives)
	{
		[self addDirective:child toParent:newStep];
	}

	[undoManager setActionName:NSLocalizedString([LDrawStructure splitStepUndoActionKey], nil)];

	[self flushDocChangesAndSelect:movedDirectives];

}//end splitStep:


//========== splitModel: =======================================================
//
// Purpose:		Deletes each split-able selected part and inserts the expanded
//				bricks (undo). The host still localizes the undo name.
//
//==============================================================================
- (IBAction) splitModel:(id)sender
{
	NSUndoManager  *undoManager = [self undoManager];
	NSMutableArray *addedParts  = [NSMutableArray arrayWithCapacity:10];

	for(LDrawSplitExpansion *expansion in [LDrawStructure splitExpansionsInSelection:[self selectedObjects]])
	{
		LDrawContainer *anchorParent = [expansion.anchor enclosingDirective];
		[self deleteDirective:expansion.anchor];

		for(LDrawPart *newPart in expansion.expandedParts)
		{
			[self addStepComponent:newPart parent:anchorParent index:NSNotFound];
			[addedParts addObject:newPart];
		}
	}

	[undoManager setActionName:NSLocalizedString([LDrawStructure splitModelUndoActionKey], nil)];

	[self flushDocChangesAndSelect:addedParts];
}//end splitModel:


//========== moveToParentModel: ================================================
//
// Purpose:		Move selected directives from submodel to the parent model(s)
//				where this submodel is inserted as a part.
//				This also works if selected directives are located in different
//				submodels.
//
// Notes:		If we get empty submodels or empty steps after moving stuff then
//				they will be deleted.
//
//==============================================================================
- (IBAction) moveToParentModel:(id)sender
{
	LDrawFile     *docContents = [self documentContents];
	NSUndoManager *undoManager = [self undoManager];
	NSArray       *directives  = [self selectedObjects];

	if (directives.count == 0) {
		return;
	}

	[fileContentsOutline deselectAll:sender];

	NSDictionary<NSString *, NSArray<LDrawDirective *> *> *modelsWithDirectives =
		[LDrawStructure directivesGroupedByEnclosingModelName:directives];

	for (NSString *subModelName in modelsWithDirectives) {
		NSArray<LDrawPart *> *references = [docContents partsWithName:subModelName];
		for (LDrawDirective *directive in modelsWithDirectives[subModelName]) {
			for (LDrawPart *ref in references) {
				LDrawDirective *copy = [LDrawStructure copyOfDirective:directive placedAtReference:ref];
				[self addDirective:copy toParent:ref.enclosingStep];
			}

			LDrawModel *parentModel = directive.enclosingModel;
			LDrawStep  *parentStep  = directive.enclosingStep;
			[self deleteDirective:directive];

			LDrawMoveToParentCleanup cleanup =
				[LDrawStructure cleanupAfterRemovingFromModel:parentModel step:parentStep];
			if (cleanup == LDrawMoveToParentCleanupEmptyModel) {
				[self deleteDirective:parentModel];
				for (LDrawPart *instance in references) {
					[self deleteDirective:instance];
				}
			}
			else if (cleanup == LDrawMoveToParentCleanupEmptyStep) {
				[self deleteDirective:parentStep];
			}
		}
	}

	[undoManager setActionName:NSLocalizedString([LDrawStructure moveToParentModelUndoActionKey], nil)];
	[[self documentContents] noteNeedsDisplay];

}//end moveToParentModel:


//========== orderFrontMovePanel: ==============================================
//
// Purpose:		Opens the advanced rotation panel that provides fine part 
//				rotation controls.
//
//==============================================================================
- (IBAction) orderFrontMovePanel:(id)sender
{
	MovePanel *panel = [MovePanel movePanel];
	
	[panel makeKeyAndOrderFront:self];

}//end orderFrontMovePanel:


//========== orderFrontRotationPanel: ==========================================
//
// Purpose:		Opens the advanced rotation panel that provides fine part 
//				rotation controls.
//
//==============================================================================
- (IBAction) orderFrontRotationPanel:(id)sender
{
	RotationPanelController *rotateController = [RotationPanelController rotationPanel];
	
	[[rotateController window] makeKeyAndOrderFront:self];

}//end openRotationPanel:


#pragma mark -

//========== quickRotateClicked: ===============================================
//
// Purpose:		One of the quick rotation shortcuts was clicked. Build a 
//				rotation in the requested direction (deduced from the sender's 
//				tag). 
//
//==============================================================================
- (IBAction) quickRotateClicked:(id)sender
{
	Vector3 rotation = ZeroPoint3;
	
	if([LDrawSelection quickRotationAxis:&rotation forMenuTag:[sender tag]])
		[self rotateSelectionAround:rotation extraFine:NO aroundOrigin:NO];

}//end quickRotateClicked:


//========== quickRotateFineClicked: ===========================================
//
// Purpose:		One of the quick rotation shortcuts was clicked. Build a
//				rotation in the requested direction (deduced from the sender's
//				tag).
//				Extra fine modification.
//
//==============================================================================
- (IBAction) quickRotateFineClicked:(id)sender
{
	Vector3 rotation = ZeroPoint3;
	
	if([LDrawSelection quickRotationAxis:&rotation forMenuTag:[sender tag]])
		[self rotateSelectionAround:rotation extraFine:YES aroundOrigin:NO];
	
}//end quickRotateFineClicked:


//========== quickRotateAroundOriginClicked: ===================================
//
// Purpose:		One of the quick rotation shortcuts was clicked. Build a
//				rotation in the requested direction (deduced from the sender's
//				tag).
//				Around model origin modification.
//
//==============================================================================
- (IBAction) quickRotateAroundOriginClicked:(id)sender
{
	Vector3 rotation = ZeroPoint3;
	
	if([LDrawSelection quickRotationAxis:&rotation forMenuTag:[sender tag]])
		[self rotateSelectionAround:rotation extraFine:NO aroundOrigin:YES];
	
}//end quickRotateAroundOriginClicked:


//========== quickRotateFineAroundOriginClicked: ===============================
//
// Purpose:		One of the quick rotation shortcuts was clicked. Build a
//				rotation in the requested direction (deduced from the sender's
//				tag).
//				Around model origin with extra fine modification.
//
//==============================================================================
- (IBAction) quickRotateFineAroundOriginClicked:(id)sender
{
	Vector3 rotation = ZeroPoint3;
	
	if([LDrawSelection quickRotationAxis:&rotation forMenuTag:[sender tag]])
		[self rotateSelectionAround:rotation extraFine:YES aroundOrigin:YES];
	
}//end quickRotateFineAroundOriginClicked:


//========== randomizeLDrawColors: =============================================
//
// Purpose:		Randomizes every part in the selection to be one of the parts
//				found in the selection.
//
//				This is meant for a power tool, e.g. if you want to turn a big
//				pile of 1x1 plates into "gravel", you can color the entire set
//				gray and then change a few to the other colors (maybe black,
//				brown, etc.).  randomimzeLDrawColors will randomize the entire
//				set.
//
// Notes:		We try to avoid consecutive colors - if the underlying bricks
//				were built "in order", this gives an author a way to avoid
//				aestheticly ugly blocks of repeating colors that are present
//				in true random distributions.
//
//				This routine depends on LDrawColors hasing into sets with
//				deduplication.  This _does_ work for colors that come from
//				the palettte, but I have not tested it with models that use
//				custom colors in an LDraw directive in their MPD file.
//
//==============================================================================
- (void) randomizeLDrawColors:(id)sender
{
	NSArray *colorable = [LDrawSelection colorableDirectivesInSelection:[self selectedObjects]];
	NSArray *colors    = [LDrawSelection randomizedColorsForDirectives:colorable];

	NSUInteger count = [colors count];
	for(NSUInteger counter = 0; counter < count; ++counter)
	{
		// setObject:toColor builds undo steps; AppKit merges them into one.
		[self setObject:[colorable objectAtIndex:counter]
				toColor:[colors objectAtIndex:counter]];
	}
	if(count > 0)
	{
		[[self documentContents] noteNeedsDisplay];
	}
}//end randomizeLDrawColors:


//========== changeOrigin: =====================================================
//
// Purpose:		Applies origin-change matrices (undo). The host still localizes
//				the undo name and redisplays.
//
//==============================================================================
- (IBAction) changeOrigin:(NSButton *)sender
{
	NSUndoManager         *undoManager = [self undoManager];
	LDrawOriginChangeKind  kind        = LDrawOriginChangeByPosition;

	if([LDrawStructure originChangeKind:&kind forMenuTag:[sender tag]] == NO)
		kind = LDrawOriginChangeByPosition;

	NSArray *updates = [LDrawStructure originPartUpdatesForSelection:[self selectedObjects]
																kind:kind];
	if([updates count] == 0) return;

	for(LDrawOriginPartUpdate *update in updates)
	{
		[[undoManager prepareWithInvocationTarget:self]
			setTransformation:update.previousComponents forPart:update.part];

		Matrix4 matrix = update.matrix;
		[update.part setTransformationMatrix:&matrix];
	}

	[undoManager setActionName:NSLocalizedString([LDrawStructure changeOriginUndoActionKey], nil)];
	[[self documentContents] noteNeedsDisplay];

}//end changeOrigin:


#pragma mark -
#pragma mark Tools Menu

//========== showInspector: ====================================================
//
// Purpose:		Opens the inspector window. It may have something in it; it may 
//				not. That's up to the document.
//
//				I presume this method will take precedence over the one in 
//				LDrawApplication when a document is opened. This is not 
//				necessarily a good thing, but oh well.
//
//==============================================================================
- (IBAction) showInspector:(id)sender
{
	[[LDrawApplication sharedInspector] show:sender];
	
}//end showInspector:


//========== toggleFileContents: ===============================================
//
// Purpose:		Either open or close the file contents outline.
//
// Notes:		Now that the file contents is part of the main window, this has 
//				gotten quite a bit more complicated. 
//
//==============================================================================
- (IBAction) toggleFileContents:(id)sender
{
	NSView	*firstSubview	= [[self->fileContentsSplitView subviews] objectAtIndex:0];
	CGFloat	maxPosition		= 0.0;
	
	// We collapse or un-collapse the split view.
	if([self->fileContentsSplitView isSubviewCollapsed:firstSubview])
	{
		// Un-collapse the view
		maxPosition = [[self->fileContentsSplitView delegate] splitView:self->fileContentsSplitView
												 constrainMinCoordinate:0.0
															ofSubviewAt:0];
															
		[self->fileContentsSplitView setPosition:maxPosition ofDividerAtIndex:0];
	}
	else
	{
		// Collapse the view
		[self->fileContentsSplitView setPosition:0.0 ofDividerAtIndex:0];
	}
	
}//end toggleFileContents:


//========== gridGranularityMenuChanged: =======================================
//
// Purpose:		We just used the menubar to change the granularity of the grid. 
//				This is rather irritating because we need to manage the other 
//				visual indicators of the selection:
//				1) the checkmark in the menu itself
//				2) the selection in the toolbar's grid widget.
//				The menu we will handle in -validateMenuItem:.
//				The toolbar is trickier.
//
//==============================================================================
- (IBAction) gridGranularityMenuChanged:(id)sender
{
	gridSpacingModeT    newGridMode = gridModeFine;

	if([LDrawGrid gridSpacingMode:&newGridMode forMenuTag:[sender tag]] == NO)
		return;
	
	[self setGridSpacingMode:newGridMode];
	
}//end gridGranularityMenuChanged:


//========== gridOrientationModeChanged: =======================================
//
// Purpose:		We just used the menubar to change the orientation of the grid.
//				This is rather irritating because we need to manage the other 
//				visual indicators of the selection:
//				1) the checkmark in the menu itself
//				2) the selection in the toolbar's grid widget.
//				The menu we will handle in -validateMenuItem:.
//				The toolbar is trickier.
//
//==============================================================================
- (IBAction) gridOrientationModeChanged:(id)sender
{
	gridOrientationModeT	newMode		= gridOrientationModel;

	if([LDrawGrid gridOrientationMode:&newMode forMenuTag:[sender tag]] == NO)
		return;
	
	[self setGridOrientationMode:newMode];

}//end gridOrientationModeChanged:


//========== showDimensions: ===================================================
//
// Purpose:		Shows the dimensions window for this model.
//
//==============================================================================
- (IBAction) showDimensions:(id)sender
{
	DimensionsPanel *dimensions = nil;
	
	dimensions = [DimensionsPanel dimensionPanelForFile:[self documentContents]];
	
	[[self windowForSheet] beginSheet:dimensions
					completionHandler:nil];
		  
}//end showDimensions


//========== showPieceCount: ===================================================
//
// Purpose:		Shows the dimensions window for this model.
//
//==============================================================================
- (IBAction) showPieceCount:(id)sender
{
	PieceCountPanel *pieceCount = nil;
	
	pieceCount = [PieceCountPanel pieceCountPanelForFile:[self documentContents]];
	
	[[self windowForSheet] beginSheet:pieceCount
					completionHandler:nil];
		  
}//end showPieceCount:


#pragma mark -
#pragma mark View Menu

//========== zoomActual: =======================================================
//
// Purpose:		Zoom to 100%.
//
//==============================================================================
- (IBAction) zoomActual:(id)sender
{
	[mostRecentLDrawView setZoomPercentage:100];
	
}//end zoomActual:


//========== zoomIn: ===========================================================
//
// Purpose:		Enlarge the scale of the current LDraw view.
//
//==============================================================================
- (IBAction) zoomIn:(id)sender
{
	[mostRecentLDrawView zoomIn:sender];
	
}//end zoomIn:


//========== zoomOut: ==========================================================
//
// Purpose:		Shrink the scale of the current LDraw view.
//
//==============================================================================
- (IBAction) zoomOut:(id)sender
{
	[mostRecentLDrawView zoomOut:sender];
	
}//end zoomOut:


//========== viewOrientationSelected: ==========================================
//
// Purpose:		The user has chosen a new viewing angle from a menu.
//				sender is the menu item, whose tag is the viewing angle. We'll 
//				just pass this off to the appropriate view.
//
// Note:		This method will get skipped entirely if an LDrawView is the
//				first responder; the message will instead go directly there 
//				because this method has the same name as the one in LDrawView.
//
//==============================================================================
- (IBAction) viewOrientationSelected:(id)sender
{
	[self->mostRecentLDrawView viewOrientationSelected:sender];
	
}//end viewOrientationSelected:


//========== toggleStepDisplay: ================================================
//
// Purpose:		Turns step display (like Lego instructions) on or off for the 
//				active model.
//
//==============================================================================
- (IBAction) toggleStepDisplay:(id)sender
{
	LDrawMPDModel	*activeModel	= [[self documentContents] activeModel];
	BOOL			 stepDisplay	= [activeModel stepDisplay];
	
	if(stepDisplay == NO) //was off; so turn it on.
		[self setStepDisplay:YES];
	else //on; turn it off now
		[self setStepDisplay:NO];
	
}//end toggleStepDisplay:


//========== advanceOneStep: ===================================================
//
// Purpose:		Moves the step display forward one step.
//
//==============================================================================
- (IBAction) advanceOneStep:(id)sender
{
	LDrawMPDModel   *activeModel    = [[self documentContents] activeModel];
	NSInteger       currentStep     = [activeModel maximumStepIndexForStepDisplay];
	NSInteger       numberSteps     = [[activeModel steps] count];
	
	[self setCurrentStep:[LDrawStructure wrappedStepIndex:currentStep
												  byDelta:1
												stepCount:numberSteps]];
	
}//end advanceOneStep:


//========== backOneStep: ======================================================
//
// Purpose:		Displays the previous step.
//
//==============================================================================
- (IBAction) backOneStep:(id)sender
{
	LDrawMPDModel   *activeModel    = [[self documentContents] activeModel];
	NSInteger       currentStep     = [activeModel maximumStepIndexForStepDisplay];
	NSInteger       numberSteps     = [[activeModel steps] count];
	
	[self setCurrentStep:[LDrawStructure wrappedStepIndex:currentStep
												  byDelta:-1
												stepCount:numberSteps]];

}//end backOneStep:


//========== useSelectionForRotationCenter: ====================================
//
// Purpose:		Defines the model's rotation center.
//
//==============================================================================
- (IBAction) useSelectionForRotationCenter:(id)sender
{
	NSArray *selectedDrawables = [LDrawViewDrop drawableDirectivesInSelection:self->selectedDirectives];
	Point3   center            = [LDrawSelection rotationCenterFromFirstDrawable:selectedDrawables];

	[[self->documentContents activeModel] setRotationCenter:center];
	
}//end useSelectionForRotationCenter:


//========== clearRotationCenter: ==============================================
//
// Purpose:		Resets rotation center to the origin.
//
//==============================================================================
- (IBAction) clearRotationCenter:(id)sender
{
	[[self->documentContents activeModel] setRotationCenter:ZeroPoint3];
		
}//end clearRotationCenter:


#pragma mark -
#pragma mark Piece Menu

//========== showParts: ========================================================
//
// Purpose:		Un-hides all selected parts.
//
//==============================================================================
- (IBAction) showParts:(id)sender
{
	[self setSelectionToHidden:NO];	//unhide 'em
	
}//end showParts:


//========== hideParts: ========================================================
//
// Purpose:		Hides all selected parts so that they are not drawn.
//
//==============================================================================
- (IBAction) hideParts:(id)sender
{
	[self setSelectionToHidden:YES]; //hide 'em
	
}//end hideParts:


//========== showAllParts: =====================================================
//
// Purpose:		Unhides all hidden parts.
//
//==============================================================================
- (IBAction) showAllParts:(id)sender
{
	LDrawModel *activeModel = [[self documentContents] activeModel];
	NSArray    *hidden      = [LDrawSelection hiddenHideableDirectivesIn:[activeModel allEnclosedElements]];

	for(id currentElement in hidden)
	{
		[self setElement:currentElement toHidden:NO]; //undoable hook.
	}
}//end showAllParts:


//========== gotoModel: ========================================================
//
// Purpose:		If a single part is selected and the part is an MPD sub-model,
//				This changes the current edited submodel to the selected parts'
//				model.
//
//				If a single part is selected and it's a peer file on disk, this
//				opens the .ldr file in a new document.
//
//==============================================================================
- (IBAction) gotoModel:(id)sender
{
	NSArray     *selectedObjects    = [self selectedObjects];
	LDrawMPDModel *mpdModel         = [LDrawStructure mpdSubmodelToActivateFromSelection:selectedObjects];
	NSString    *peerPath           = nil;

	if(mpdModel != nil)
	{
		[self setActiveModel:mpdModel];
	}

	if([LDrawStructure peerFileFromSelection:selectedObjects path:&peerPath])
	{
		[[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[NSURL fileURLWithPath:peerPath  isDirectory:FALSE]
																			   display:YES
																	 completionHandler:^(NSDocument * _Nullable document, BOOL documentWasAlreadyOpen, NSError * _Nullable error) {}];
	}
}//end gotoModel:


//========== snapSelectionToGrid: ==============================================
//
// Purpose:		Aligns all selected parts to the current grid setting.
//
//==============================================================================
- (void) snapSelectionToGrid:(id)sender
{	
	float gridSpacing     = [LDrawGrid spacingForMode:[self gridSpacingMode]];
	float degreesToRotate = [LDrawGrid rotationDegreesForMode:[self gridSpacingMode]
														 kind:LDrawGridRotationSnap];

	for(LDrawPartTransformUpdate *update in [LDrawSelection snappedTransformUpdatesForSelection:[self selectedObjects]
																					gridSpacing:gridSpacing
																				   minimumAngle:degreesToRotate])
	{
		[self setTransformation:update.components forPart:update.part];
	}

	[[self documentContents] noteNeedsDisplay];
		
}//end snapSelectionToGrid


//========== snapSelectionToGridX: =============================================
//
// Purpose:		Aligns by X all selected parts to the current grid setting.
//
//==============================================================================
- (void) snapSelectionToGridX:(id)sender
{
	[self snapSelectionByAxis:V3Make(1.0, 0.0, 0.0)];
}


//========== snapSelectionToGridY: =============================================
//
// Purpose:		Aligns by Y all selected parts to the current grid setting.
//
//==============================================================================
- (void) snapSelectionToGridY:(id)sender
{
	[self snapSelectionByAxis:V3Make(0.0, 1.0, 0.0)];
}


//========== snapSelectionToGridZ: =============================================
//
// Purpose:		Aligns by Z all selected parts to the current grid setting.
//
//==============================================================================
- (void) snapSelectionToGridZ:(id)sender
{
	[self snapSelectionByAxis:V3Make(0.0, 0.0, 1.0)];
}


//========== snapSelectionByAxis: =============================================
//
// Purpose:		Aligns by axis all selected parts to the current grid setting.
//
//==============================================================================
- (void) snapSelectionByAxis:(Vector3)axis
{
	float gridSpacing = [LDrawGrid spacingForMode:[self gridSpacingMode]];

	for(LDrawPartTransformUpdate *update in [LDrawSelection snappedTransformUpdatesForSelection:[self selectedObjects]
																					gridSpacing:gridSpacing
																						   axis:axis])
	{
		[self setTransformation:update.components forPart:update.part];
	}
	
	[[self documentContents] noteNeedsDisplay];
}//end snapSelectionByAxis


//========== mirroredSelectionByX: =============================================
//
// Purpose:		Move all selected parts simmetrically by X.
//
//==============================================================================
- (void) mirroredSelectionByX:(id)sender
{
	[self mirroredSelectionByAxis:V3Make(-1.0, 1.0, 1.0)];
}


//========== mirroredSelectionByAxis: ==========================================
//
// Purpose:		Move all selected parts simmetrically by axis.
//
//==============================================================================
- (void) mirroredSelectionByAxis:(Vector3)axis
{
	for(LDrawPartTransformUpdate *update in [LDrawSelection mirroredTransformUpdatesForSelection:[self selectedObjects]
																							axis:axis])
	{
		[self setTransformation:update.components forPart:update.part];
	}
	
	[[self documentContents] noteNeedsDisplay];

}//end mirroredSelectionByAxis:


//========== setGroup: =========================================================
//
// Purpose:		Set/edit MLCAD group
//
//==============================================================================
- (IBAction) setGroup:(id)sender
{
	NSArray						*selectedObjects		= [self selectedObjects];
	NSSet<NSString *>			*groups					= [LDrawMLCadGroup groupNamesInSelection:selectedObjects];

	if (groups == nil) {
		return;
	}

	NSAlert *alert = [NSAlert new];
	[alert addButtonWithTitle:NSLocalizedString([LDrawMLCadGroup mlcadGroupDialogSetButtonKey], nil)];
	[alert addButtonWithTitle:NSLocalizedString([LDrawMLCadGroup mlcadGroupDialogCancelButtonKey], nil)];
	alert.messageText = NSLocalizedString([LDrawMLCadGroup mlcadGroupDialogMessageKey], nil);
    alert.informativeText = NSLocalizedString([LDrawMLCadGroup mlcadGroupDialogInformativeKey], nil);
	if (groups.count <= 1) {
		NSTextField *txt = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
		txt.stringValue = groups.anyObject;
		alert.accessoryView = txt;
	} else {
		NSComboBox *cmb = [[NSComboBox alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
		[cmb addItemsWithObjectValues:[LDrawMLCadGroup nonEmptyGroupNamesFromSet:groups]];
		alert.accessoryView = cmb;
	}
	NSModalResponse responce = [alert runModal];
	if (responce == NSAlertFirstButtonReturn) {
		NSString *group = [LDrawMLCadGroup normalizedGroupName:[((id)alert.accessoryView) stringValue]];
		[self setGroupForDirectives:[LDrawMLCadGroup groupChangesInSelection:selectedObjects
																 toGroupName:group]];
	}

}//end setGroup:

#pragma mark -
#pragma mark Models Menu

//========== addModelClicked: ==================================================
//
// Purpose:		Create a new model and add it to the current file.
//
//==============================================================================
- (IBAction) addModelClicked:(id)sender
{
	LDrawMPDModel	*newModel		= [LDrawMPDModel model];
	NSInteger 		index	 		= [self nextModelIndex];

	[self addModel:newModel atIndex:index preventNameCollisions:YES];
	[self setActiveModel:newModel];
	
}//end modelSelected


//========== addModelFromSelectionClicked: =====================================
//
// Purpose:		Creates a new sub-model whose contents are the currently
//				selected parts.  Parts are moved to the sub-model, using the
//				first selected part as the origin.
//
//				A new part is placed in the current model referencing the newly
//				made sub-mode.  This means the user sees the same contents, but
//				via a reference.
//
//==============================================================================
- (IBAction) addModelFromSelectionClicked:(id)sender
{
	NSUndoManager *undoManager = [self undoManager];
	NSArray       *directives  = [self selectedObjects];
	LDrawPart     *anchor      = [LDrawStructure anchorPartInSelection:directives];
	Matrix4        anchorMatrix;
	Matrix4        correction;

	if(anchor == nil)
		return;
	if([LDrawStructure modelFromSelectionAnchorMatrix:&anchorMatrix
										   correction:&correction
											forAnchor:anchor] == NO)
		return;

	LDrawContainer *anchorParent = [anchor enclosingDirective];
	[fileContentsOutline deselectAll:sender];

	LDrawMPDModel *newModel = [LDrawMPDModel model];
	[self addModel:newModel atIndex:NSNotFound preventNameCollisions:YES];

	for(LDrawOriginPartUpdate *update in [LDrawStructure rebasedPartUpdatesInSelection:directives
																			correction:correction])
	{
		[[undoManager prepareWithInvocationTarget:self]
			setTransformation:update.previousComponents forPart:update.part];

		Matrix4 matrix = update.matrix;
		[update.part setTransformationMatrix:&matrix];
	}

	LDrawStep *step = [LDrawStructure lastStepOfModel:newModel];
	for(LDrawDirective *d in directives)
	{
		[self deleteDirective:d];
		[self addDirective:d toParent:step atIndex:[[step subdirectives] count]];
	}

	LDrawColor *selectedColor = [[LDrawColorPanelController sharedColorPanel] LDrawColor];
	LDrawPart  *newPart       = [LDrawStructure referencePartForSubmodelName:[newModel modelName]
																anchorMatrix:anchorMatrix
																	   color:selectedColor];
	[self addStepComponent:newPart parent:anchorParent index:NSNotFound];

	[undoManager setActionName:NSLocalizedString([LDrawStructure modelFromSelectionUndoActionKey], nil)];

	[self flushDocChangesAndSelect:[NSArray arrayWithObject:newPart]];

}//end addModelFromSelectionClicked:


//========== addStepClicked: ===================================================
//
// Purpose:		Adds a new step wherever it belongs.
//
//==============================================================================
- (IBAction) addStepClicked:(id)sender
{
	LDrawStep		*newStep		= [LDrawStep emptyStep];
	LDrawMPDModel 	*model 			= [self selectedModel];
	NSInteger 		nextStepIdx 	= [LDrawInsertion indexAfterDirective:[self selectedStep]
																 inParent:model];

	[self addStep:newStep parent:model index:nextStepIdx];

}//end addStepClicked:


//========== addPartClicked: ===================================================
//
// Purpose:		Adds a new step to the currently-displayed model. If a part of 
//				the model is already selected, the step will be added after 
//				selection. Otherwise, the step appears at the end of the list.
//
//==============================================================================
- (IBAction) addPartClicked:(id)sender
{	
	PartBrowserPanelController	*partBrowserController	= nil;
	
	partBrowserController = [PartBrowserPanelController sharedPartBrowserPanel];
	
	//is it open and foremost?
	if([[partBrowserController window] isKeyWindow] == YES)
		[[partBrowserController partBrowser] addPartClicked:sender];
	else
		[[partBrowserController window] makeKeyAndOrderFront:sender];
	
}//end addPartClicked:


//========== addSubmodelReferenceClicked: ======================================
//
// Purpose:		Add a reference in the current model to the MPD submodel 
//				selected.
//
// Parameters:	sender: the NSMenuItem representing the submodel to add.
//
//==============================================================================
- (void) addSubmodelReferenceClicked:(id)sender
{
	NSString		*partName			= [[sender representedObject] modelName];
	LDrawMPDModel	*destinationModel	= [LDrawInsertion destinationModelPreferring:[self selectedModel]
																	   fallingBackTo:[[self documentContents] activeModel]];
	BOOL			circularReference	= [LDrawInsertion insertingSubmodelNamed:partName
																		  inFile:[self documentContents]
													   wouldCycleWithDestination:destinationModel];
	
	//We got a part; let's add it!
	if([LDrawInsertion shouldInsertSubmodelNamed:partName whenCircularReference:circularReference])
	{
		[self addPartNamed:partName];
	}
	
	if(circularReference)
	{
		NSAlert *alert = [[NSAlert alloc] init];
		
		[alert setMessageText:NSLocalizedString([LDrawInsertion circularReferenceMessageKey], nil)];
		[alert setInformativeText:NSLocalizedString([LDrawInsertion circularReferenceInformativeKey], nil)];
		
		NSBeep();
		[alert beginSheetModalForWindow:[self windowForSheet] completionHandler:nil];
	}
}//end addSubmodelReferenceClicked:


//========== addLineClicked: ===================================================
//
// Purpose:		Adds a new line primitive to the currently-displayed model.
//
//==============================================================================
- (IBAction) addLineClicked:(id)sender
{
	LDrawColor      *selectedColor  = [[LDrawColorPanelController sharedColorPanel] LDrawColor];
	LDrawLine       *newLine        = [LDrawInsertion lineAtAnchor:[LDrawInsertion anchorPositionForPart:self->lastSelectedPart]
															 color:selectedColor];
	NSUndoManager   *undoManager    = [self undoManager];
	
	[self addStepComponent:newLine parent:nil index:NSNotFound];
	
	[undoManager setActionName:NSLocalizedString([LDrawInsertion undoActionKeyForInsertKind:LDrawInsertUndoLine], nil)];
	[self flushDocChangesAndSelect:[NSArray arrayWithObject:newLine]];
	
}//end addLineClicked:


//========== addTriangleClicked: ===============================================
//
// Purpose:		Adds a new triangle primitive to the currently-displayed model.
//
//==============================================================================
- (IBAction) addTriangleClicked:(id)sender
{
	LDrawColor      *selectedColor  = [[LDrawColorPanelController sharedColorPanel] LDrawColor];
	LDrawTriangle	*newTriangle	= [LDrawInsertion triangleAtAnchor:[LDrawInsertion anchorPositionForPart:self->lastSelectedPart]
																 color:selectedColor];
	NSUndoManager	*undoManager	= [self undoManager];
	
	[self addStepComponent:newTriangle parent:nil index:NSNotFound];
	
	[undoManager setActionName:NSLocalizedString([LDrawInsertion undoActionKeyForInsertKind:LDrawInsertUndoTriangle], nil)];
	[self flushDocChangesAndSelect:[NSArray arrayWithObject:newTriangle]];
	
}//end addTriangleClicked:


//========== addQuadrilateralClicked: ==========================================
//
// Purpose:		Adds a new quadrilateral primitive to the currently-displayed 
//				model.
//
//==============================================================================
- (IBAction) addQuadrilateralClicked:(id)sender
{
	LDrawColor          *selectedColor      = [[LDrawColorPanelController sharedColorPanel] LDrawColor];
	LDrawQuadrilateral  *newQuadrilateral   = [LDrawInsertion quadrilateralAtAnchor:[LDrawInsertion anchorPositionForPart:self->lastSelectedPart]
																			  color:selectedColor];
	NSUndoManager       *undoManager        = [self undoManager];
	
	[self addStepComponent:newQuadrilateral parent:nil index:NSNotFound];
	
	[undoManager setActionName:NSLocalizedString([LDrawInsertion undoActionKeyForInsertKind:LDrawInsertUndoQuadrilateral], nil)];
	[self flushDocChangesAndSelect:[NSArray arrayWithObject:newQuadrilateral]];
	
}//end addQuadrilateralClicked:


//========== addConditionalClicked: ============================================
//
// Purpose:		Adds a new conditional-line primitive to the currently-displayed 
//				model.
//
//==============================================================================
- (IBAction) addConditionalClicked:(id)sender
{
	LDrawColor              *selectedColor  = [[LDrawColorPanelController sharedColorPanel] LDrawColor];
	LDrawConditionalLine    *newConditional = [LDrawInsertion conditionalLineAtAnchor:[LDrawInsertion anchorPositionForPart:self->lastSelectedPart]
																				color:selectedColor];
	NSUndoManager           *undoManager    = [self undoManager];

	[self addStepComponent:newConditional parent:nil index:NSNotFound];
	
	[undoManager setActionName:NSLocalizedString([LDrawInsertion undoActionKeyForInsertKind:LDrawInsertUndoConditionalLine], nil)];
	[self flushDocChangesAndSelect:[NSArray arrayWithObject:newConditional]];
	
}//end addConditionalClicked:


//========== addCommentClicked: ================================================
//
// Purpose:		Adds a new comment primitive to the currently-displayed model.
//
//==============================================================================
- (IBAction) addCommentClicked:(id)sender
{
	LDrawComment	*newComment		= [LDrawInsertion comment];
	NSUndoManager	*undoManager	= [self undoManager];
	
	[self addStepComponent:newComment parent:nil index:NSNotFound];
	
	[undoManager setActionName:NSLocalizedString([LDrawInsertion undoActionKeyForInsertKind:LDrawInsertUndoComment], nil)];
	[self flushDocChangesAndSelect:[NSArray arrayWithObject:newComment]];
	
}//end addCommentClicked:


//========== addRawCommandClicked: =============================================
//
// Purpose:		Adds a new raw command to the currently-displayed model.
//
//==============================================================================
- (IBAction) addRawCommandClicked:(id)sender
{
	LDrawMetaCommand	*newCommand		= [LDrawInsertion metaCommand];
	NSUndoManager		*undoManager	= [self undoManager];
	
	[self addStepComponent:newCommand parent:nil index:NSNotFound];
	
	[undoManager setActionName:NSLocalizedString([LDrawInsertion undoActionKeyForInsertKind:LDrawInsertUndoMetaCommand], nil)];
	[self flushDocChangesAndSelect:[NSArray arrayWithObject:newCommand]];
	
}//end addCommentClicked:


//========== addLPubCommandClicked: ============================================
//
// Purpose:		Adds a new generic LPub command to the currently-displayed model.
//
//==============================================================================
- (IBAction) addLPubCommandClicked:(id)sender
{
	LPubCommand		*newCommand		= [LDrawInsertion lpubCommand];
	NSUndoManager	*undoManager	= [self undoManager];
	
	[self addStepComponent:newCommand parent:nil index:NSNotFound];
	
	[undoManager setActionName:NSLocalizedString([LDrawInsertion undoActionKeyForInsertKind:LDrawInsertUndoLPubCommand], nil)];
	[self flushDocChangesAndSelect:[NSArray arrayWithObject:newCommand]];
	
}//end addLPubCommandClicked:


//========== addRemoveGroupClicked: ============================================
//
// Purpose:		Adds a new LPub Remove Group command to the currently-displayed
//				model.
//
//==============================================================================
- (IBAction) addRemoveGroupClicked:(id)sender
{
	LPubRemoveGroup	*newCommand		= [LDrawInsertion lpubRemoveGroup];
	NSUndoManager	*undoManager	= [self undoManager];
	
	[self addStepComponent:newCommand parent:nil index:NSNotFound];
	
	[undoManager setActionName:NSLocalizedString([LDrawInsertion undoActionKeyForInsertKind:LDrawInsertUndoRemoveGroup], nil)];
	[self flushDocChangesAndSelect:[NSArray arrayWithObject:newCommand]];
	
}//end addRemoveGroupClicked:


//========== addRelatedPartClicked: ============================================
//
// Purpose:		Adds the related child part for a selected parent part.
//
// Notes:		Right now we use the last selected part as a cheat for the 
//				parent we need to insert.  Someday if I can figure out how to
//				insert multiple parts in a single undo, we can iterate on the 
//				selection and add one part per selection.  This would speed up
//				adding the same glass to a whole pile of windows, for example.
//
//==============================================================================
- (IBAction) addRelatedPartClicked:(id)sender
{
#if WANT_RELATED_PARTS
	RelatedPart   *relatedPart   = [sender representedObject];
	NSUndoManager *undoManager   = [self undoManager];
	LDrawColor    *selectedColor = [[LDrawColorPanelController sharedColorPanel] LDrawColor];

	// Snapshot selection first — inserting parts would change it under us.
	NSArray *parentParts = [NSArray arrayWithArray:selectedDirectives];
	NSArray *newParts    = [relatedPart childPartsForSelection:parentParts color:selectedColor];

	for(LDrawPart *newPart in newParts)
	{
		[self addStepComponent:newPart parent:nil index:NSNotFound];
	}

	[self flushDocChangesAndSelect:newParts];
	[undoManager setActionName:NSLocalizedString([LDrawInsertion undoActionKeyForInsertKind:LDrawInsertUndoRelatedPart], nil)];
#endif	
}//end addRelatedPartClicked


//========== addMinifigure: ====================================================
//
// Purpose:		Create a new minifigure with the amazing Minifigure Generator 
//				and add it to the model.
//
//==============================================================================
- (void) addMinifigure:(id)sender
{
	MinifigureDialogController  *minifigDialog  = [MinifigureDialogController new];
	NSInteger                   result          = NSModalResponseCancel;
	LDrawMPDModel               *minifigure     = nil;
	
	result = [minifigDialog runModal];
	if(result == NSModalResponseOK)
	{
		minifigure = [minifigDialog minifigure];
		[self addModel:minifigure atIndex:NSNotFound preventNameCollisions:YES];
	}
	
}//end addMinifigure:


//========== modelSelected: ====================================================
//
// Purpose:		A new model from the Models menu was chosen to be the active 
//				model.
//
// Parameters:	sender: an NSMenuItem representing the model to make active.
//
//==============================================================================
- (void) modelSelected:(id)sender
{
	LDrawMPDModel	*newActiveModel		= [sender representedObject];

	[self setActiveModel:newActiveModel];
		
}//end modelSelected


#pragma mark Models Menu - LSynth Submenu

//========== insertSynthesizableDirective: =====================================
//
// Purpose:		Insert a synthesizable directive into the model.  This is a
//              hose, band or part.
//
// Parameters:	sender: an NSMenuItem representing the model to make active.
//
//==============================================================================
- (void) insertSynthesizableDirective:(id)sender
{
	NSDictionary	*synthEntry			= [sender representedObject];
	NSString		*type				= [synthEntry objectForKey:@"LSYNTH_TYPE"];
	LDrawColor		*selectedColor		= [[LDrawColorPanelController sharedColorPanel] LDrawColor];
	NSUndoManager	*undoManager		= [self undoManager];
	LDrawLSynth		*synthesizedObject	= [[LSynthConfiguration sharedInstance]
											synthesizableDirectiveWithType:type
																	 color:selectedColor];

	[self addStepComponent:synthesizedObject parent:nil index:NSNotFound];

	[undoManager setActionName:[NSString stringWithFormat:NSLocalizedString([LDrawInsertion undoActionFormatKeyForAddingLSynth], nil),
														  [synthEntry objectForKey:@"title"]]];
	[self flushDocChangesAndSelect:[NSArray arrayWithObject:synthesizedObject]];

}//end insertSynthesizedDirective:


//========== insertLSynthConstraint: =======================================
//
// Purpose:		Insert a synthesizable directive constraint into the model.
//              We don't distinguish between hose or band constraints since
//              both types can be used for either synthesizable type.
//
// Parameters:	sender: an NSMenuItem representing the constraint to insert
//
//==============================================================================
-(void) insertLSynthConstraint:(id)sender
{
	NSUndoManager	*undoManager		= [self undoManager];
	LDrawContainer	*parent				= nil;
	NSInteger		 index				= NSNotFound;

	if(self->lastSelectedPart == nil)
	{
		return;
	}

	if([LDrawStructure lsynthInsertionParent:&parent
									   index:&index
							 forLastSelected:self->lastSelectedPart] == NO)
	{
		NSLog(@"BIG FAT CONSTRAINT ADDING ERROR");
		return;
	}

	LDrawPart *constraint = [LDrawInsertion partNamed:[[sender representedObject] objectForKey:@"partName"]
												color:[[ColorLibrary sharedColorLibrary] colorForCode:LDrawCurrentColor]
								 copyingTransformFrom:lastSelectedPart];

	[self addDirective:constraint toParent:parent atIndex:index];
	[(LDrawLSynth *)parent synthesize];
	[parent noteNeedsDisplay];

	[self flushDocChangesAndSelect:[NSArray arrayWithObject:constraint]];
	[undoManager setActionName:NSLocalizedString([LDrawInsertion undoActionKeyForInsertKind:LDrawInsertUndoLSynthConstraint], nil)];

} // end insertLSynthConstraint

//========== surroundLSynthConstraints: ========================================
//
// Purpose:		Placeholder for a future Model → LSynth → Surround Selection
//				command. Would wrap the current selection in INSIDE/OUTSIDE
//				constraints. Menu wiring is still commented out in
//				-buildMainMenu.
//
//==============================================================================
-(void) surroundLSynthConstraints:(id)sender
{
    NSLog(@"surroundLSynthConstraints");
}

//========== invertLSynthConstraintSelection: ==================================
//
// Purpose:		Placeholder for a future Model → LSynth → Invert Selection
//				command. Would flip INSIDE/OUTSIDE on selected constraints.
//				Menu wiring is still commented out in -buildMainMenu.
//
//==============================================================================
-(void) invertLSynthConstraintSelection:(id)sender
{
    NSLog(@"invertLSynthConstraintSelection");
}

//========== insertINSIDEOUTSIDELSynthDirective: ===============================
//
// Purpose:		Insert an LSynth direction directive, INSIDE or OUTSIDE, which
//              causes a constraint to switch the side the band passes it.
//
//==============================================================================
-(void) insertINSIDEOUTSIDELSynthDirective:(id)sender
{
	NSUndoManager	*undoManager		= [self undoManager];
	LDrawContainer	*parent				= nil;
	NSInteger		 index				= NSNotFound;
	NSString		*command			= [LDrawStructure lsynthDirectionCommandForMenuTag:[(NSMenuItem *)sender tag]];
	NSString		*undoKey			= [LDrawStructure lsynthInsertUndoKeyForMenuTag:[(NSMenuItem *)sender tag]];

	if(self->lastSelectedPart == nil || command == nil)
	{
		return;
	}
	if([LDrawStructure lsynthInsertionParent:&parent
									   index:&index
							 forLastSelected:self->lastSelectedPart] == NO)
	{
		return;
	}

	LDrawLSynthDirective *direction = [[LDrawLSynthDirective alloc] init];
	[direction setCommandString:command];

	[self addDirective:direction toParent:parent atIndex:index];
	[(LDrawLSynth *)parent synthesize];
	[parent noteNeedsDisplay];

	[self flushDocChangesAndSelect:[NSArray arrayWithObject:direction]];
	[[self foremostWindow] makeFirstResponder:mostRecentLDrawView];
	[undoManager setActionName:NSLocalizedString(undoKey, nil)];

}//end insertINSIDEOUTSIDELSynthDirective:


//========== convertToHighResPrimitives: =======================================
//
// Purpose:		Changes low-res directives into high-res quality for "48" folder.
//
// Notes:		If nothing is selected, all directives are converted.
//
//==============================================================================
- (IBAction) convertToHighResPrimitives:(id)sender
{
	NSUndoManager  *undoManager  = [self undoManager];
	NSMutableArray *directives   = [[LDrawStructure highResSourceDirectivesFromSelection:[self selectedObjects]
																			 activeModel:self.documentContents.activeModel] mutableCopy];
	NSMutableArray *unknownLines = [NSMutableArray array];

	[fileContentsOutline deselectAll:sender];

	for(int axis = 0; axis < 3; axis++)
	{
		NSArray<LDrawHighResReplacement *> *replacements =
			[LDrawHighResPrimitives replacementsForDirectives:directives
														 axis:(Axis)axis
												 unknownLines:unknownLines];

		for(LDrawHighResReplacement *replacement in replacements)
		{
			LDrawDirective *originalDirective = replacement.original;
			NSArray        *newDirectives     = replacement.highRes.primitives;
			LDrawContainer *parent            = [originalDirective enclosingDirective];
			if(parent)
			{
				NSInteger index = [parent indexOfDirective:originalDirective];
				[self deleteDirective:originalDirective];
				for(LDrawDirective *directive in newDirectives)
				{
					[self addDirective:directive toParent:parent atIndex:index++];
				}
			}
			[directives removeObjectIdenticalTo:originalDirective];
		}
	}

	[undoManager setActionName:NSLocalizedString([LDrawStructure convertPrimitivesUndoActionKey], nil)];
	[[self documentContents] noteNeedsDisplay];
}//end convertToHighResPrimitives:


#pragma mark -
#pragma mark UNDOABLE ACTIVITIES
#pragma mark -

//these are *low-level* calls which provide support for the Undo architecture.
// all of these are wrapped by high-level calls, which are all application-level 
// code should ever need to use.


//========== addDirective:toParent: ============================================
//
// Purpose:		Undo-aware call to add a directive to the specified parent.
//
//==============================================================================
- (void) addDirective:(LDrawDirective *)newDirective
			 toParent:(LDrawContainer * )parent
{
	NSInteger index = [[parent subdirectives] count];
	
	[self addDirective:newDirective
			  toParent:parent
			   atIndex:index];
			   
}//end addDirective:toParent:


//========== addDirective:toParent:atIndex: ====================================
//
// Purpose:		Undo-aware call to add a directive to the specified parent.
//
//==============================================================================
- (void) addDirective:(LDrawDirective *)newDirective
			 toParent:(LDrawContainer * )parent
			  atIndex:(NSInteger)index
{
	NSUndoManager	*undoManager	= [self undoManager];
	
	{
		[[undoManager prepareWithInvocationTarget:self]
			deleteDirective:newDirective ];
	
		[parent insertDirective:newDirective atIndex:index];
	}
	[self lockContextAndExecute:^
	{
		[LDrawApplication makeCurrentSharedContext];
	}];
	
}//end addDirective:toParent:atIndex:


//========== deleteDirective: ==================================================
//
// Purpose:		Removes the specified doomedDirective from its enclosing 
//				container.
//
// Notes:		If the doomed directive is selected, chaos breaks out.  (The
//				act of removing the directive triggers a rebuilding of the 
//				outliner.  The outliner rebuild triggers a push of the cached
//				selection back to the outliner.  The cached selection will have
//				doomedDirective and the outliner won't, causing the push of the
//				selection to fail with an ObjC exception.
///
//==============================================================================
- (void) deleteDirective:(LDrawDirective *)doomedDirective
{
	NSUndoManager   *undoManager    = [self undoManager];
	LDrawContainer  *parent         = [doomedDirective enclosingDirective];
	NSInteger       index           = [[parent subdirectives] indexOfObject:doomedDirective];
	
	{
		[[undoManager prepareWithInvocationTarget:self]
				addDirective:doomedDirective
					toParent:parent
					 atIndex:index ];
		
		[parent removeDirective:doomedDirective];
	}

	// After a directive is deleted, we need to resynchronize our step field - maybe the current step changed.
	// There may be other places where we need this too.
	[self->stepField setIntegerValue:[[[self documentContents] activeModel] maximumStepIndexForStepDisplay] + 1];

}//end deleteDirective:


//========== moveDirective:inDirection: ========================================
//
// Purpose:		Undo-aware call to move the object in the direction indicated. 
//				The vector here should indicate the exact amount to move. It 
//				should be adjusted to the grid mode already).
//
//==============================================================================
- (void) moveDirective:(LDrawDrawableElement *)object
		   inDirection:(Vector3)moveVector
{
	NSUndoManager	*undoManager	= [self undoManager];
	Vector3			 opposite		= V3Negate(moveVector);
	
	{
			[[undoManager prepareWithInvocationTarget:self]
				moveDirective: object
				  inDirection: opposite ];
		[undoManager setActionName:NSLocalizedString([LDrawSelection moveUndoActionKey], nil)];
		
		//Do the move.
		[object moveBy:moveVector];
	}
	
	//our part changed; notify!
	[object noteNeedsDisplay];
								  
}//end moveDirective:inDirection:


//========== preserveDirectiveState: ===========================================
//
// Purpose:		Records the entire state of the object with the undo manager. 
//
// Note:		Undo operations are stored on a *stack*, so the order of undo 
//				registration in the code is the opposite from the order in 
//				which the undo operations are executed.
//
//==============================================================================
- (void) preserveDirectiveState:(LDrawDirective *)directive
{
	NSUndoManager	*undoManager	= [self undoManager];

	{
		// ** Read code bottom-to-top ** //

		[[undoManager prepareWithInvocationTarget:directive] noteNeedsDisplay];
		[directive registerUndoActions:undoManager];
		
		[[undoManager prepareWithInvocationTarget:self]
								preserveDirectiveState:directive ];
	}
	
}//end preserveDirectiveState:


//========== rotatePart:onAxis:byDegrees: ======================================
//
// Purpose:		Undo-aware call to rotate the object in the direction indicated. 
//
// Notes:		This gets a little tricky because there is more than one way 
//				to represent a single rotation when using three rotation angles. 
//				Since we don't really know which one was intended, we can't just 
//				blithely manipulate the rotation components.
//
//				Instead, we must generate a new transformation matrix that 
//				rotates by degreesToRotate in the desired direction. Then we 
//				multiply that matrix by the part's current transformation. This 
//				way, we can rest assured that we rotated the part exactly the 
//				direction the user intended, no matter what goofy representation
//				the components came up with.
//
//				Caveat: We have to zero out the translation components of the 
//				part's transformation before we append our new rotation. Thus 
//				the part will be rotated in place.
//
//==============================================================================
- (void) rotatePart:(LDrawPart *)part
		  byDegrees:(Tuple3)rotationDegrees
		aroundPoint:(Point3)rotationCenter
{

	NSUndoManager	*undoManager		= [self undoManager];
	Tuple3			 oppositeRotation	= V3AntiEuler(rotationDegrees);
	
	[[undoManager prepareWithInvocationTarget:self]
			rotatePart: part
			 byDegrees: oppositeRotation
		   aroundPoint: rotationCenter  ]; //undo: rotate backwards
	[undoManager setActionName:NSLocalizedString([LDrawSelection rotateUndoActionKey], nil)];
	
	
	{
		[part rotateByDegrees:rotationDegrees centerPoint:rotationCenter];
	}
	
	[part noteNeedsDisplay];
	
} //rotatePart:onAxis:byDegrees:


//========== setElement:toHidden: ==============================================
//
// Purpose:		Undo-aware call to change the visibility attribute of an element.
//
//==============================================================================
- (void) setElement:(LDrawDrawableElement *)element toHidden:(BOOL)hideFlag
{
	NSUndoManager	*undoManager	= [self undoManager];
	NSString		*actionName		= [LDrawSelection hideShowUndoActionKeyForHidden:hideFlag];
	
	{
			[[undoManager prepareWithInvocationTarget:self]
			setElement:element
			  toHidden:(!hideFlag) ];
		[undoManager setActionName:NSLocalizedString(actionName, nil)];
		
		[element setHidden:hideFlag];
	}
	[element noteNeedsDisplay];

}//end setElement:toHidden:


//========== setObject:toColor: ================================================
//
// Purpose:		Undo-aware call to change the color of an object.
//
//==============================================================================
- (void) setObject:(LDrawDirective <LDrawColorable>* )object toColor:(LDrawColor *)newColor
{
	NSUndoManager *undoManager = [self undoManager];
	
	[[undoManager prepareWithInvocationTarget:self]
												setObject:object
												  toColor:[object LDrawColor] ];
	[undoManager setActionName:NSLocalizedString([LDrawSelection colorUndoActionKey], nil)];
	
	{
		[object setLDrawColor:newColor];
	}
	[object noteNeedsDisplay];

}//end setObject:toColor:


//========== setTransformation:forPart: ========================================
//
// Purpose:		Undo-aware call to set the entire transformation for a part. 
//				This is an important step in snapping a part to the grid.
//
//==============================================================================
- (void) setTransformation:(TransformComponents)newComponents
				   forPart:(LDrawPart *)part
{
	NSUndoManager		*undoManager		= [self undoManager];
	TransformComponents	 currentComponents	= [part transformComponents];
	
	{
		[part setTransformComponents:newComponents];
		
		//Be ready to restore the old components.
		[[undoManager prepareWithInvocationTarget:self]
				setTransformation:currentComponents
						  forPart:part ];
		
		[undoManager setActionName:NSLocalizedString([LDrawSelection snapToGridUndoActionKey], nil)];
	}
	[part noteNeedsDisplay];
	
}//end setTransformation:forPart:


//========== setGroupForDirectives: ============================================
//
// Purpose:		Undo-aware call to set the MLCAD group.
//
//==============================================================================
- (void) setGroupForDirectives:(NSArray *)directivesAndGroups
{
	NSUndoManager *undoManager = [self undoManager];

	if (directivesAndGroups.count == 0) {
		return;
	}

	NSArray *directivesAndOldGroups = [LDrawMLCadGroup invertedGroupChanges:directivesAndGroups];
	[LDrawMLCadGroup applyGroupChanges:directivesAndGroups];

	[[undoManager prepareWithInvocationTarget:self] setGroupForDirectives:directivesAndOldGroups];
	[[undoManager prepareWithInvocationTarget:fileContentsOutline] reloadData];
	[undoManager setActionName:NSLocalizedString([LDrawSelection setGroupUndoActionKey], nil)];
	
}//end setGroupForDirectives:


#pragma mark -
#pragma mark OUTLINE VIEW
#pragma mark -

#pragma mark Data Source

//**** NSOutlineViewDataSource ****
//========== outlineView:numberOfChildrenOfItem: ===============================
//
// Purpose:		Returns the number of items which should be displayed under an 
//				expanded item.
//
//==============================================================================
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	return [LDrawOutline outlineChildCountOfItem:item file:documentContents];
	
}//end outlineView:numberOfChildrenOfItem:


//**** NSOutlineViewDataSource ****
//========== outlineView:isItemExpandable: =====================================
//
// Purpose:		Returns the number of items which should be displayed under an 
//				expanded item.
//
//==============================================================================
- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return [LDrawOutline outlineItemIsExpandable:item];
	
}//end outlineView:isItemExpandable:


//**** NSOutlineViewDataSource ****
//========== outlineView:child:ofItem: =========================================
//
// Purpose:		Returns the child of item at the position index.
//
//==============================================================================
- (id)outlineView:(NSOutlineView *)outlineView
			child:(NSInteger)index
		   ofItem:(id)item
{
	return [LDrawOutline outlineChild:index ofItem:item file:documentContents];
	
}//end outlineView:child:ofItem:


//**** NSOutlineViewDataSource ****
//========== outlineView:objectValueForTableColumn:byItem: =====================
//
// Purpose:		Returns the representation of item given for the given table 
//				column.
//
//==============================================================================
- (id)			outlineView:(NSOutlineView *)outlineView
  objectValueForTableColumn:(NSTableColumn *)tableColumn
					 byItem:(id)item
{
	id representation = [LDrawOutline outlineDescriptionForItem:item];
	
	if([item isKindOfClass:[LDrawDirective class]]) {
		//Apply formatting to our little string.
		representation = [self formatDirective:item
					  withStringRepresentation:representation];
    }

	return representation;

}//end outlineView:objectValueForTableColumn:byItem:


#pragma mark -
#pragma mark Drag and Drop

//**** NSOutlineViewDataSource ****
//========== outlineView:writeItems:toPasteboard: ==============================
//
// Purpose:		Initiates a drag. We drag directives by copying them at the 
//				outset. Upon the successful completion of the drag, we "paste" 
//				the copied directives wherever they landed, then delete the 
//				original objects.
//
//				We also drag a string representation of the objects for the 
//				benefit of other applications.
//
//==============================================================================
- (BOOL)outlineView:(NSOutlineView *)outlineView
		 writeItems:(NSArray *)items
	   toPasteboard:(NSPasteboard *)pboard
{
	BOOL			disallow	= [LDrawOutline shouldDisallowDraggingItems:items];
	NSArray         *rowIndexes = nil;
	
	//Write the objects as data.
	[self writeDirectives:items toPasteboard:pboard];
	
	//Now write the row indexes out. We'll use them to delete the original 
	// objects in the event of a successful drag.
	rowIndexes = [LDrawClipboard outlineDragSourceRowIndexesForItems:items
													rowForItemTarget:outlineView];
	[pboard addTypes:[LDrawClipboard outlineDragSourcePasteboardTypes]
			   owner:nil];
	[pboard setPropertyList:rowIndexes forType:LDrawDragSourceRowsPboardType];
	
	[pboard setPropertyList:[LDrawClipboard outlineDragDisallowPropertyListForDisallow:disallow]
					forType:LDrawDisallowDragToSourcePboardType];
	
	return YES;
	
}//end outlineView:writeItems:toPasteboard:


//**** NSOutlineViewDataSource ****
//========== outlineView:validateDrop:proposedItem:proposedChildIndex: =========
//
// Purpose:		Returns the representation of item given for the given table 
//				column.
//
//==============================================================================
- (NSDragOperation) outlineView:(NSOutlineView *)outlineView
				   validateDrop:(id <NSDraggingInfo>)info
				   proposedItem:(id)newParent
			 proposedChildIndex:(NSInteger)index
{
	NSPasteboard		*pasteboard		= [info draggingPasteboard];
	NSOutlineView		*sourceView		= [info draggingSource];
	NSArray             *types          = [pasteboard types];
	BOOL                 disallow       = [LDrawClipboard outlinePasteboardDisallowsDragToSourceFromTypes:types
																					 disallowPropertyList:
																			 [pasteboard propertyListForType:LDrawDisallowDragToSourcePboardType]];

	//Fix our logic for handling drags to the root of the outline.
	newParent = [LDrawOutline outlineDropParent:newParent file:[self documentContents]];

	NSArray *archivedObjects = nil;
	if(index != NSOutlineViewDropOnItemIndex
	   && [types containsObject:LDrawDirectivePboardType])
	{
		archivedObjects = [pasteboard propertyListForType:LDrawDirectivePboardType];
	}

	LDrawOutlineDropKind kind = [LDrawOutline outlineDropKindForValidateDropWithProposedParent:newParent
																						  file:[self documentContents]
																					dropOnItem:(index == NSOutlineViewDropOnItemIndex)
																			   pasteboardTypes:types
																		  disallowDragToSource:disallow
																				   sameOutline:(sourceView == outlineView)
																	  archivedDirectiveObjects:archivedObjects];
	if(kind == LDrawOutlineDropMove)
	{
		return NSDragOperationMove;
	}
	if(kind == LDrawOutlineDropCopy)
	{
		return NSDragOperationCopy;
	}
	return NSDragOperationNone;

}//end outlineView:validateDrop:proposedItem:proposedChildIndex:


//**** NSOutlineViewDataSource ****
//========== outlineView:acceptDrop:item:childIndex: ===========================
//
// Purpose:		Finishes the current drop, depositing as near as possible to 
//				the specified item.
//
// Notes:		Complexities lie within. Note them carefully.
//
//==============================================================================
- (BOOL)outlineView:(NSOutlineView *)outlineView
		 acceptDrop:(id <NSDraggingInfo>)info
			   item:(id)newParent
		 childIndex:(NSInteger)dropIndex
{
	//Identify the root object if needed.
	newParent = [LDrawOutline outlineDropParent:newParent file:[self documentContents]];
	
	NSPasteboard    *pasteboard             = [info draggingPasteboard];
	NSUndoManager   *undoManager            = [self undoManager];
	NSOutlineView   *sourceView             = [info draggingSource];
	BOOL            sameOutline             = (sourceView == outlineView);
	NSArray         *doomedObjects          = [NSArray array];
	NSArray         *pastedObjects          = nil;
	BOOL            renameDuplicateModels   = (sameOutline == NO);
	NSInteger       counter                 = 0;
	
	if(sameOutline)
	{
		//We dragged within the same table. That means we expect the original 
		// objects dragged to "move" to the new position. Well, we can't 
		// actually *move* them, since our drag is implemented as a copy-and-paste.
		// However, we can simply delete the original objects, which will 
		// look the same anyway.
		//
		// Note we're doing this *before* moving, so that the indexes are 
		// still correct.
		doomedObjects = [LDrawClipboard outlineItemsAtRowIndexes:outlineView.selectedRowIndexes
												 itemAtRowTarget:outlineView];
	}

	NSSet *donatingParents = [LDrawOutline donatingParentsFromMovedDirectives:doomedObjects];

    // Do The Move.
	pastedObjects = [self pasteFromPasteboard:pasteboard
						preventNameCollisions:renameDuplicateModels
									   parent:newParent
										index:dropIndex
								nextToSimilar:NO];

	if(sameOutline)
	{
		//Now that we've inserted the new objects, we need to delete the 
		// old ones.
		for(counter = 0; counter < [doomedObjects count]; counter++)
			[self deleteDirective:[doomedObjects objectAtIndex:counter]];
		
		NSString *undoKey = [LDrawOutline outlineDropUndoActionKeyForSameOutline:sameOutline];
		if(undoKey != nil)
			[undoManager setActionName:NSLocalizedString(undoKey, nil)];
	}

	[LDrawOutline cleanupAfterOutlineDropDonors:donatingParents destination:newParent];

    //And lastly, select the dragged objects.
	[(LDrawFileOutlineView*)outlineView selectObjects:pastedObjects];

	return YES;
	
}//end outlineView:acceptDrop:item:childIndex:



#pragma mark -
#pragma mark Delegate

//**** NSOutlineView ****
//========== outlineView:willDisplayCell:forTableColumn:item: ==================
//
// Purpose:		Returns the representation of item given for the given table 
//				column.
//
//==============================================================================
- (void) outlineView:(NSOutlineView *)outlineView
	 willDisplayCell:(id)cell
	  forTableColumn:(NSTableColumn *)tableColumn
				item:(id)item
{
	NSString	*imageName = [LDrawOutline outlineIconNameForItem:item];
	NSImage		*theImage  = nil;
		
	if(imageName != nil)
	{
		theImage = [NSImage imageNamed:imageName];
	}
		
	[(IconTextCell *)cell setImage:theImage];
	
}//end outlineView:willDisplayCell:forTableColumn:item:


#pragma mark -
#pragma mark MOUSE COORDINATES
#pragma mark -

//========== LDrawView:mouseIsOverPoint:confidence: ============================
//
// Purpose:		Display the 3D world coordinates of the mouse as it hovers over 
//				the model. 
//
//==============================================================================
- (void) LDrawView:(LDrawView *)glView mouseIsOverPoint:(Point3)modelPoint confidence:(Tuple3)confidence
{
	[self->coordinateFieldX setFloatValue:modelPoint.x];
	[self->coordinateFieldY setFloatValue:modelPoint.y];
	[self->coordinateFieldZ setFloatValue:modelPoint.z];
	
	NSColor *questionableColor	= [NSColor colorWithCalibratedWhite:0.3 alpha:1.0];
	NSColor *confidentColor 	= [NSColor colorWithCalibratedWhite:0.1 alpha:1.0];
	
	[self->coordinateFieldX setTextColor:[LDrawUtilities hoverCoordinateAxisIsQuestionable:confidence.x] ? questionableColor : confidentColor];
	[self->coordinateFieldY setTextColor:[LDrawUtilities hoverCoordinateAxisIsQuestionable:confidence.y] ? questionableColor : confidentColor];
	[self->coordinateFieldZ setTextColor:[LDrawUtilities hoverCoordinateAxisIsQuestionable:confidence.z] ? questionableColor : confidentColor];
	[self->coordinateLabelX setTextColor:[LDrawUtilities hoverCoordinateAxisIsQuestionable:confidence.x] ? questionableColor : confidentColor];
	[self->coordinateLabelY setTextColor:[LDrawUtilities hoverCoordinateAxisIsQuestionable:confidence.y] ? questionableColor : confidentColor];
	[self->coordinateLabelZ setTextColor:[LDrawUtilities hoverCoordinateAxisIsQuestionable:confidence.z] ? questionableColor : confidentColor];
	
	[self->coordinateFieldX setHidden:NO];
	[self->coordinateFieldY setHidden:NO];
	[self->coordinateFieldZ setHidden:NO];
	[self->coordinateLabelX setHidden:NO];
	[self->coordinateLabelY setHidden:NO];
	[self->coordinateLabelZ setHidden:NO];
}


//========== LDrawViewMouseExited: =============================================
//
// Purpose:		The mouse location is no longer relevant to coordinate display. 
//				This could be because the mouse exited the view, or because it 
//				is controlling a tool which is not coordinate sensitive. 
//
//==============================================================================
- (void) LDrawViewMouseNotPositioning:(LDrawView *)glView
{
	[self->coordinateFieldX setHidden:YES];
	[self->coordinateFieldY setHidden:YES];
	[self->coordinateFieldZ setHidden:YES];
	[self->coordinateLabelX setHidden:YES];
	[self->coordinateLabelY setHidden:YES];
	[self->coordinateLabelZ setHidden:YES];
}


#pragma mark -
#pragma mark LDRAW GL VIEW
#pragma mark -

//**** LDrawView ****
//========== LDrawView:acceptDrop: =============================================
//
// Purpose:		The user has deposited some drag-anddrop parts into an 
//			    LDrawView. Now they need to be imported into the model.
//
// Notes:		Just like in -duplicate: and 
//				-outlineView:acceptDrop:item:childIndex:, we appropriate the 
//				pasting architecture to simplify importing the parts.
//
//==============================================================================
- (void) LDrawView:(LDrawView *)glView
		acceptDrop:(id < NSDraggingInfo >)info
		directives:(NSArray *)directives
{
	NSPasteboard    *pasteboard         = [NSPasteboard pasteboardWithName:[LDrawClipboard viewDropPasteboardName]];
	NSUndoManager   *undoManager        = [self undoManager];
	id               sourceFile         = nil;

	if([[info draggingSource] respondsToSelector:@selector(LDrawDirective)])
		sourceFile = [[info draggingSource] LDrawDirective];

	if([LDrawViewDrop viewDropIsSameDocumentMoveFromSource:sourceFile
												toDocument:[self documentContents]
											selectionCount:[self->selectedDirectives count]])
	{
		NSArray *moves = [LDrawViewDrop viewDropMovesForSelection:self->selectedDirectives
													droppedCopies:directives];

		for(LDrawViewDropMove *move in moves)
		{
			[self moveDirective:move.directive inDirection:move.displacement];
		}
		[LDrawViewDrop unhideDirectivesInViewDropMoves:moves];
	}
	else
	{
		[self writeDirectives:directives toPasteboard:pasteboard];
		[self pasteFromPasteboard:pasteboard
			preventNameCollisions:YES
						   parent:nil
							index:NSNotFound
					nextToSimilar:NO];

		[undoManager setActionName:NSLocalizedString([LDrawViewDrop viewDropPasteUndoActionKey], nil)];
	}
	
}//end LDrawView:acceptDrop:


//**** LDrawView ****
//========== LDrawViewBecameFirstResponder: ====================================
//
// Purpose:		One of our model views just became active, so we need to update 
//				our display to represent that view's characteristics.
//
//==============================================================================
- (void) LDrawViewBecameFirstResponder:(LDrawView *)glView
{
	// We used bindings to sync up the ever-in-limbo zoom control.
	[self setMostRecentLDrawView:glView];

}//end LDrawViewBecameFirstResponder:


//========== LDrawView:dragHandleDidMove: ======================================
//
// Purpose:		A primitive's geometry is being directly manipulated.
//
//==============================================================================
- (void) LDrawView:(LDrawView *)glView dragHandleDidMove:(LDrawDragHandle *)dragHandle
{
	// Ben says: this call is unnecessary for now because the GL renderer tickles the document
	// too.  Some day ideally directives would signal their change to their parents and observers;
	// if we're looking at a triangle, the drag handles would single through the drag handle.
	[self updateInspector];
}


//========== LDrawViewPartDragEnded: ===========================================
//
// Purpose:		Part drag has ended, successfully or unsuccessfully. This is our 
//				opportunity to clean up.
//
//==============================================================================
- (void) LDrawViewPartDragEnded:(LDrawView*)glView
{
	self->selectedDirectivesBeforeCopyDrag = nil;
}


//========== LDrawViewPartsWereDraggedIntoOblivion: ============================
//
// Purpose:		The parts which originated the most recent drag operation have 
//				apparently been dragged clear out of the document. Maybe they 
//				went into another document. Maybe they got dragged into empty 
//				space. Whereever they went, they are gone now. 
//
//				The trouble is that when we started dragging them, we just *hid* 
//				them, in anticipation of their landing back within the document. 
//				(It was too much trouble to delete them at the beginning, 
//				because then we might have to reconstruct where they were in the 
//				model hierarchy if they did stay in the same document.) Now that 
//				we know they are really truly gone, we need to delete their 
//				hidden ghosts. 
//
//==============================================================================
- (void) LDrawViewPartsWereDraggedIntoOblivion:(LDrawView *)glView
{
	NSArray *directivesToDelete = [LDrawViewDrop viewDragOblivionDirectivesFromSelection:self->selectedDirectives];

	[LDrawViewDrop restoreVisibilityBeforeDeletingViewDragOblivionDirectives:directivesToDelete];

	for(id currentDirective in directivesToDelete)
	{
		[self deleteDirective:currentDirective];
	}
	
}//end LDrawViewPartsWereDraggedIntoOblivion:


//========== LDrawViewPreferredPartTransform: ==================================
//
// Purpose:		Returns the part transform which would be nice applied to new 
//			    parts. This is used during Drag-and-Drop to unpack directives 
//			    and show them in the right place. 
//
//==============================================================================
- (TransformComponents) LDrawViewPreferredPartTransform:(LDrawView *)glView
{
	return [LDrawInsertion preferredPartTransformFromPart:self->lastSelectedPart];
	
}//end LDrawViewPreferredPartTransform:


//**** LDrawView ****

//============ markPreviousSelection ============================================
//
// Purpose:		This function marks the current selection - each time 
//				wantsToSelectDirectives is called the new selection is calculated
//				relative to this marked one.  This sets the baseline for when the
//				marquee constantly rebuilds the selection.
//
//==============================================================================
- (void) markPreviousSelection
{
	if(self->markedSelection)
	{
		markedSelection = NULL;
	}
	
	markedSelection = [self selectedObjects];
}//end markPreviousSelection


//============ unmarkPreviousSelection ============================================
//
// Purpose:		This function purges the saved selection - it is called when the
//				marquee drag finishes to save memory.
//
//==============================================================================
- (void) unmarkPreviousSelection
{
	if(markedSelection)
	{
		markedSelection = NULL;
	}
}//end unmarkPreviousSelection


//========== LDrawView:wantsToSelectDirectives:selectionMode: ========
//
// Purpose:		The given LDrawView has decided some directives should be 
//				selected, probably because the user marquee selected.
//				If the array is empty, the old selection is still preserved if
//				"extension" is used.
//
//==============================================================================
- (void)	   LDrawView:(LDrawView *)glView
 wantsToSelectDirectives:(NSArray *)directivesToSelect
		   selectionMode:(SelectionModeT) selectionMode
 {
	if(markedSelection)
	{
		NSArray *sel = [LDrawSelection mergedSelectionWithMarked:markedSelection
												   newDirectives:directivesToSelect
															mode:selectionMode];
		
		if([sel count])		
		{
			[self selectDirectives:sel];
		}
		else 
		{
			[self selectDirective:nil byExtendingSelection:NO];
		}
		
	}
	
}//end LDrawView:wantsToSelectDirectives:selectionMode:


//========== LDrawView:wantsToSelectDirective:byExtendingSelection: ============
//
// Purpose:		The given LDrawView has decided some directive should be 
//				selected, probably because the user clicked on it.
//				Pass nil to mean deselect.
//
//==============================================================================
- (void)	  LDrawView:(LDrawView *)glView
 wantsToSelectDirective:(LDrawDirective *)directiveToSelect
   byExtendingSelection:(BOOL) shouldExtend
{
	[self selectDirective:directiveToSelect byExtendingSelection:shouldExtend];
	
}//end LDrawView:wantsToSelectDirective:byExtendingSelection:


//========== LDrawView:willBeginDraggingHandle: ================================
//
// Purpose:		The view is about to begin direct primitive geometry 
//				manipulation. We need to record the object state for undo. 
//
//==============================================================================
- (void) LDrawView:(LDrawView *)glView willBeginDraggingHandle:(LDrawDragHandle *)dragHandle
{
	LDrawDirective *primitive = [dragHandle target];
	
	[self preserveDirectiveState:primitive];
}


//========== LDrawView:writeDirectivesToPasteboard:asCopy: =====================
//
// Purpose:		Begin a drag-and-drop part insertion initiated in the directive 
//				view. 
//
// Notes:		The parts you see being dragged around are always copies of the 
//				originals. When we aren't actually doing a copy drag, we just 
//				hide the originals. At the end of the drag, we update the 
//				originals with the new dragged positions, unhide them, and 
//				discard the stuff on the pasteboard. This frees us from having 
//				to remember what step each dragged element belonged to. 
//
//==============================================================================
- (BOOL)		   LDrawView:(LDrawView *)glView
 writeDirectivesToPasteboard:(NSPasteboard *)pasteboard
					  asCopy:(BOOL)copyFlag
{
	NSArray *drawables     = nil;
	NSArray *archivedParts = [LDrawClipboard archivedDraggingDataFromSelection:self->selectedDirectives
															 drawableOriginals:&drawables];

	[LDrawSelection prepareViewDragOriginals:drawables asCopy:copyFlag];
	if(copyFlag)
	{
		// If copying, DESELECT all current directives as a visual indicator that
		// the originals will stay put.
		self->selectedDirectivesBeforeCopyDrag = [self->selectedDirectives copy];
		[self selectDirective:nil byExtendingSelection:NO];
	}

	// Set up pasteboard
	if([archivedParts count] > 0)
	{
		[pasteboard declareTypes:[LDrawClipboard viewRegisteredDragTypes] owner:self];
		[pasteboard setPropertyList:archivedParts forType:LDrawDraggingPboardType];
		return YES;
	}

	return NO;
	
}//end LDrawView:writeDirectivesToPasteboard:asCopy:


#pragma mark -
#pragma mark SPLIT VIEW
#pragma mark -

//**** NSSplitView ****
//========== splitView:canCollapseSubview: =====================================
//
// Purpose:		Collapsing is good if we don't like this multipane view deal.
//
//==============================================================================
- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview
{
	return YES;
	
}//end splitView:canCollapseSubview:


//**** NSSplitView ****
//========== splitView:shouldCollapseSubview:forDoubleClickOnDividerAtIndex: ===
//
// Purpose:		Allow split views to collapse when their divider is 
//				double-clicked. 
//
//==============================================================================
- (BOOL)				splitView:(NSSplitView *)splitView
			shouldCollapseSubview:(NSView *)subview
   forDoubleClickOnDividerAtIndex:(NSInteger)dividerIndex
{
	return YES;
	
}//end splitView:shouldCollapseSubview:forDoubleClickOnDividerAtIndex:


//**** NSSplitView ****
//========== splitView:constrainMinCoordinate:ofSubviewAt: =====================
//
// Purpose:		Allow the file Contents split view to collapse by giving it a 
//				minimum size. 
//
//==============================================================================
- (CGFloat)   splitView:(NSSplitView *)sender
 constrainMinCoordinate:(CGFloat)proposedMin
			ofSubviewAt:(NSInteger)offset
{
	return [LDrawPreferences constrainedSplitMinCoordinate:proposedMin
										   forFileContents:(sender == self->fileContentsSplitView)
											 subviewOffset:offset];
	
}//end splitView:constrainMinCoordinate:ofSubviewAt:


//**** NSSplitView ****
//========== splitView:constrainMaxCoordinate:ofSubviewAt: =====================
//
// Purpose:		Allow the graphics detail view to collapse by defining a maximum 
//				extent for the the main graphic view. (It's counter-intuitive!)
//
//==============================================================================
- (CGFloat)   splitView:(NSSplitView *)sender
 constrainMaxCoordinate:(CGFloat)proposedMax
			ofSubviewAt:(NSInteger)offset
{
	return [LDrawPreferences constrainedSplitMaxCoordinate:proposedMax
									   forViewportArranger:(sender == self->viewportArranger)
											 subviewOffset:offset
											 containerMaxX:NSMaxX([sender frame])];
	
}//end splitView:constrainMinCoordinate:ofSubviewAt:


//**** NSSplitView ****
//========== splitView:resizeSubviewsWithOldSize: ==============================
//
// Purpose:		Do yucky MANUAL resizing of the split view subviews.
//
//				We use this method to make sure that the size of the File 
//				Contents sidebar remains CONSTANT while the window is being 
//				resized. This is how all Apple applications with sidebars 
//				behave, and it is good. 
//
//==============================================================================
- (void) splitView:(NSSplitView *)sender resizeSubviewsWithOldSize:(NSSize)oldSize
{
	BOOL inLiveResize = [[[sender window] contentView] inLiveResize];

	// Make sure the width of the File Contents column remains constant during 
	// live window resize. 
	if(		sender == self->fileContentsSplitView
		&&	inLiveResize )
	{
		NSView	*fileContentsPane	= [[sender subviews] objectAtIndex:0];
		NSView	*graphicPane		= [[sender subviews] objectAtIndex:1];
		NSSize	totalSize			= [sender frame].size;
		NSSize	graphicPaneSize		= [graphicPane frame].size;
		
		// The graphic pane absorbs ALL width changes.
		graphicPaneSize.width		=	totalSize.width 
									 -	[sender dividerThickness]
									 -	NSWidth([fileContentsPane frame]);
		
		[graphicPane setFrameSize:graphicPaneSize];
	}
	
	// If there are only two view columns configured, make sure the rightmost 
	// column remains constant during live window resize. This fit's Allen's 
	// Preferred Viewport Layout, in which there is a set of detail views on the 
	// right. People who prefer otherwise are up a creek.
	if(		sender == self->viewportArranger
		&&	inLiveResize
		&&	[[sender subviews] count] == 2 )
	{
		NSView	*mainViewPane		= [[sender subviews] objectAtIndex:0];
		NSView	*detailViewsPane	= [[sender subviews] objectAtIndex:1];
		NSSize	totalSize			= [sender frame].size;
		NSSize	mainViewPaneSize	= [mainViewPane frame].size;
		
		// The graphic pane absorbs ALL width changes.
		mainViewPaneSize.width		=	totalSize.width 
									 -	[sender dividerThickness]
									 -	NSWidth([detailViewsPane frame]);
		
		[mainViewPane setFrameSize:mainViewPaneSize];
	}
	
	// Allow the split view to finish normal calculations. For the File Contents 
	// split view, this does height resizing for us. For all other split views, 
	// it just does behavior as normal. 
	[sender adjustSubviews];
	
}//end splitView:resizeSubviewsWithOldSize:


#pragma mark -
#pragma mark NOTIFICATIONS
#pragma mark -


//========== libraryReloaded: ==================================================
//
// Purpose:		The library has been reloaded.  We need to notify our entire
//				set of directives that the library parts might have changed.
//				The directives don't do this themselves to avoid overhead.
//
//==============================================================================
- (void)libraryReloaded:(NSNotification *)notification
{
	[LDrawUtilities unresolveLibraryParts:documentContents];
}//end libraryReloaded


//========== activeModelChanged: ===============================================
//
// Purpose:		The file we are displaying has changed its active model.
//
//==============================================================================
- (void)activeModelChanged:(NSNotification *)notification
{
	//[fileContentsOutline reloadData];
	
	//Update the models menu.
	[self addModelsToMenus];
	
	[self setLastSelectedPart:nil];
	
}//end activeModelDidChange:


//========== partChanged: ======================================================
//
// Purpose:		Somewhere, somehow, a part (or some other LDrawDirective) was 
//				changed.  This method handles updating the UI.
//
// Notes:		partChanged is called for -any- part being changed; as a result
//				it gets called a lot.  To keep things fast, partChanged does
//				basically no work directly.  Instead it reposts a notification
//				on the top level LDrawFile for this document.  
//
//				The reposted notification is queued and coalesced with 
//				NSNotificationQueue; the result is that we get one big change
//				notification on our document after many change notifications
//				on parts.  See docChanged for more.
//
//==============================================================================
- (void) partChanged:(NSNotification *)notification
{
	LDrawDirective *changedDirective = [notification object];
	LDrawFile *docContents = [self documentContents];

	// Since the document sends out part changes too, make sure it isn't the doc
	// itself sending - if it is, we'd get into an endless loop.  (Because we 
	// listen to ALL LDrawDirectiveDidChangeNotification notifications, posting
	// calls us again, with changedDirective == docContents).
	if(changedDirective != docContents)
	{	
		// Since we listen to all parts, we have to check whether this part is
		// from our document or some other document.
		if([[changedDirective ancestors] containsObject:docContents])		
		{
			// Post a notification that our doc changed; LDrawView needs this
			// to refresh drawing, and we ned it to redo our menus.
			NSNotification * doc_notification = 
				[NSNotification notificationWithName:LDrawDirectiveDidChangeNotification 
											  object:docContents];
		
			// Notification is queued and coalesced; 
			[[NSNotificationQueue defaultQueue] 
				   enqueueNotification:doc_notification 
						  postingStyle:NSPostASAP 
						  coalesceMask:NSNotificationCoalescingOnName|NSNotificationCoalescingOnSender
							  forModes:NULL];
		}
	}
}//end partChanged:


//========== docChanged: =======================================================
//
// Purpose:		This notification is sent to us when something in our document
//				has changed; it's the asynchronous coalesced result of
//				partChanged being called within our document.
//
// Notes:		This notification is always asynchronous and coalesced; the 
//				result is that it happens about once for an entire edit or undo
//				operation.  This is where we do the expensive stuff like
//				resync the hierarchy and update the menus.
//
//==============================================================================
- (void)docChanged:(NSNotification *)notification
{
	// This functionality was in partChanged through Bricksmith 3.0.
	[fileContentsOutline selectObjects:selectedDirectives];
	[fileContentsOutline reloadData];

	[self updateInspector];

	// Technically we don't need to redo the model menu on every UI edit.  In the
	// future we should add specific notifications or directive observations to
	// detect this case. But 3.0 and earlier ran this once for every edit (when
	// part changes were escalated to doc changes) and then twice on real model
	// changes (because we'd hit the case on the model and again on the doc).
	//
	// In practice it doesn't matter - for now, for the test cases we have,
	// rebuilding the menus is relatively cheap.  A user can only add so many
	// MPD parts to a file without going completely insane.
	[self addModelsToMenus];

}//end docChanged:


//========== stepChanged: ======================================================
//
// Purpose:		A step changed its numeric attributes, e.g. the viewing angle,
//				typically by the inspector editing.  We get a direct 
//				notification from the step and can resync our viewing angles
//				if needed.
//
//==============================================================================
- (void)stepChanged:(NSNotification *)notification
{
	LDrawDirective *changedDirective = [notification object];
	LDrawFile *docContents = [self documentContents];

	if([[changedDirective ancestors] containsObject:docContents])		
	if([[docContents activeModel] stepDisplay] == YES)
	{
		// TODO: new notification for this to get out of hot path?!?
		[self updateViewingAngleToMatchStep];
	}
}//end stepChanged:


//========== syntaxColorChanged: ===============================================
//
// Purpose:		The preferences have been updated; we need to refresh our data 
//				display.
//
//==============================================================================
- (void) syntaxColorChanged:(NSNotification *)notification
{
	[fileContentsOutline reloadData];
	
}//end syntaxColorChanged:


//**** NSWindow ****
//========== windowDidBecomeMain: ==============================================
//
// Purpose:		The window has come to the foreground.
//
//==============================================================================
- (void) windowDidBecomeMain:(NSNotification *)aNotification
{
	[self updateInspector];

	[self addModelsToMenus];
	[self buildRelatedPartsMenus];
	
}//end windowDidBecomeMain:


//**** NSWindow ****
//========== windowDidResize: ==================================================
//
// Purpose:		As the window changes size, we must record the new dimensions 
//				for autosaving purposes. 
//
// Notes:		Snow Leopard adds windowDidEndLiveResize which may be more 
//				appropriate. 
//
//==============================================================================
- (void) windowDidResize:(NSNotification *)notification
{
	NSUserDefaults	*userDefaults	= [NSUserDefaults standardUserDefaults];
	NSWindow		*window			= [notification object];
	
	// Don't do anything for the resizing that happens during awakeFromNib.
	if([window isVisible])
	{
		// In Leopard, we don't have any control over split view autosaving. It 
		// is saved every time the split view resizes. Since the split view size 
		// is dependent on the window size, we must save it at the same time. 
		// Otherwise, we could open a new document after resizing another one 
		// and the split views would not match the window size. 
	
		[userDefaults setObject:NSStringFromSize([window frame].size)
						 forKey:DOCUMENT_WINDOW_SIZE];
	}
	
}//end windowDidResize:


//**** NSWindow ****
//========== windowWillClose: ==================================================
//
// Purpose:		The window is about to close; let's save some state info.
//
//==============================================================================
- (void) windowWillClose:(NSNotification *)notification
{
	NSWindow		*window			= [notification object];
	
	//Un-inspect everything
	[[LDrawApplication sharedInspector] inspectObjects:nil];
	
	// Bug: if this document isn't the foremost window, this will botch up the 
	//		menu! Remember, we can close windows in the background. 
	if([window isMainWindow] == YES){
		[self clearModelMenus];
	}
	
	[self->bindingsController setContent:nil];
	
}//end windowWillClose:


//**** NSFilePresenter ****
//========== presentedItemDidChange ============================================
//
// Purpose:		Tells that the presented item’s contents or attributes changed.
//				Use this to inform user that someone ouside Bricksmith changed
//				the opened file.
//
//==============================================================================
- (void)presentedItemDidChange
{
	static BOOL alertIsPresenting = NO;
	
	if (alertIsPresenting) {
		return;
	}
	
	// last known by this app modification date
	NSDate *innerDate = self.fileModificationDate;
	
	// file's real modification date
	NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.fileURL.path error:nil];
	NSDate *outerDate = attributes.fileModificationDate;
	
	if ([outerDate compare:innerDate] == NSOrderedDescending) {
		BOOL fileNewer = YES;

		if ([LDrawEditorStrings shouldPromptUnsavedExternalChangeWhenDocumentEdited:self.isDocumentEdited
																 fileNewerThanKnown:fileNewer]) {
			alertIsPresenting = YES;
			dispatch_async(dispatch_get_main_queue(), ^{
				NSAlert *alert = [NSAlert new];
				alert.messageText = [NSString stringWithFormat:NSLocalizedString([LDrawEditorStrings unsavedDocumentMessageFormatKey], nil), [self displayName]];
				alert.informativeText = NSLocalizedString([LDrawEditorStrings unsavedDocumentInformativeKey], nil);
				[alert addButtonWithTitle:NSLocalizedString([LDrawEditorStrings unsavedDocumentRevertButtonKey], nil)];
				[alert addButtonWithTitle:NSLocalizedString([LDrawEditorStrings unsavedDocumentKeepButtonKey], nil)];

				NSInteger buttonReturned = [alert runModal];
				if (buttonReturned == NSAlertFirstButtonReturn)
				{
					[self revertToContentsOfURL:self.fileURL ofType:self.fileType error:nil];
				}
				alertIsPresenting = NO;
			});
		} else if ([LDrawEditorStrings shouldSilentRevertExternalChangeWhenDocumentEdited:self.isDocumentEdited
																	   fileNewerThanKnown:fileNewer]) {
			// reload without any prompt
			dispatch_async(dispatch_get_main_queue(), ^{
				[self revertToContentsOfURL:self.fileURL ofType:self.fileType error:nil];
			});
		}
	}
}//end presentedItemDidChange


#pragma mark -
#pragma mark MENUS
#pragma mark -

//========== validateMenuItem: =================================================
//
// Purpose:		Determines whether the given menu item should be available.
//				This method is called automatically each time a menu is opened.
//				We identify the menu item by its tag, which is defined in 
//				MacLDraw.h.
//
//==============================================================================
- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
	NSInteger       tag             = [menuItem tag];
	NSArray         *selectedItems  = [self selectedObjects];
	LDrawPart       *selectedPart   = [self selectedPart];
	NSPasteboard    *pasteboard     = [NSPasteboard generalPasteboard];
	LDrawMPDModel   *activeModel    = [[self documentContents] activeModel];
	BOOL            enable          = NO;
	
	switch(tag)
	{
        ////////////////////////////////////////
        //
        // File Menu
        //
        ////////////////////////////////////////

        case revealInFinderTag:
            enable = ([self fileURL] != nil);
            break;

		////////////////////////////////////////
		//
		// Edit Menu
		//
		////////////////////////////////////////

		case cutMenuTag:
		case copyMenuTag:
		case deleteMenuTag:
		case duplicateMenuTag:
		case rotatePositiveXTag:
		case rotateNegativeXTag:
		case rotatePositiveYTag:
		case rotateNegativeYTag:
		case rotatePositiveZTag:
		case rotateNegativeZTag:
			enable = [selectedItems count] > 0;
			break;
		
		case changeOriginMenuTag:
		case axesByPartRotationMenuTag:
			enable = [LDrawStructure selectionCanChangeOrigin:selectedItems];
			break;
		
		case changeOriginByRotationMenuTag:
			enable = [LDrawStructure selectionCanChangeOriginByRotation:selectedItems];
			break;
		
		case splitModelMenuTag:
			enable = [LDrawStructure selectionCanSplitModel:selectedItems];
			break;
			
		case moveToParentMenuTag:
			enable = [LDrawStructure selectionCanMoveToParentModel:selectedItems];
			break;
		
		case splitStepMenuTag:
			// Direct children of steps, all from the same model.
			enable = [LDrawStructure selectionCanSplitStep:selectedItems];
			break;
			
		
		case pasteMenuTag:
			enable = [[pasteboard types] containsObject:LDrawDirectivePboardType];
			break;
		
		
		////////////////////////////////////////
		//
		// Tools Menu
		//
		////////////////////////////////////////
		
		//The grid menus are always enabled, but this is a fine place to keep 
		// track of their state.
		case gridFineMenuTag:
		case gridMediumMenuTag:
		case gridCoarseMenuTag:
			[menuItem setState:[LDrawGrid menuItemShouldBeSelectedForGridModeTag:tag
																	 currentMode:self->gridMode]];
			enable = YES;
			break;
		
		case coordModelMenuTag:
		case coordPartMenuTag:
			[menuItem setState:[LDrawGrid menuItemShouldBeSelectedForGridOrientationTag:tag
																	 currentOrientation:self->gridOrientation]];
			enable = YES;
			break;
			
		////////////////////////////////////////
		//
		// View Menu
		//
		////////////////////////////////////////
		
		case useSelectionForSpinCenterMenuTag:
			enable = [selectedItems count] > 0;
			break;
		
		case resetSpinCenterMenuTag:
			enable = (V3EqualPoints(ZeroPoint3, [[self->documentContents activeModel] rotationCenter]) == NO);
			break;

		case stepDisplayMenuTag:
			[menuItem setState:([activeModel stepDisplay])];
			enable = YES;
			break;
			
		case nextStepMenuTag:
		case previousStepMenuTag:
			enable = [activeModel stepDisplay];
			break;
		
		
		////////////////////////////////////////
		//
		// Piece Menu
		//
		////////////////////////////////////////
			
		case hidePieceMenuTag:
			enable = [LDrawSelection selection:selectedItems containsVisibility:YES];
			break;
			
		case showPieceMenuTag:
			enable = [LDrawSelection selection:selectedItems containsVisibility:NO];
			break;
			
		case snapToGridMenuTag:
			enable = (selectedPart != nil);
			break;
		
		case gotoModelMenuTag:
			enable = (selectedPart != nil && [selectedItems count] == 1);
			break;		
			
		case setGroupMenuTag:
			enable = [LDrawMLCadGroup selectionCanSetGroup:selectedItems];
			break;

		////////////////////////////////////////
		//
		// Model Menu
		//
		////////////////////////////////////////
		
		case addModelSelectionMenuTag:
			enable = [LDrawStructure selectionCanSplitModel:selectedItems];
			break;
		
		case submodelReferenceMenuTag:
			//we can't insert a reference to the active model into itself.
			// That would be an inifinite loop.
			enable = [LDrawInsertion canInsertSubmodel:[menuItem representedObject]
									   intoActiveModel:activeModel];
			break;

		case relatedPartMenuTag:
			enable = [menuItem submenu] != nil;
			break;

		case lsynthHoseMenuTag:
		case lsynthBandMenuTag:
            // This is just like inserting a part
			enable = YES;
            break;

        case lsynthHoseConstraintMenuTag:
		case lsynthBandConstraintMenuTag:
            // We can only insert a constraint into an LDrawLSynth part.
            // Ensure it (or a constraint) is selected
            enable = [LDrawInsertion canInsertLSynthConstraintForPart:selectedPart];
            break;

// TODO: add these in later
//        case lsynthSurroundINSIDEOUTSIDETag:
//            // INSIDE/OUTSIDE pairs can only surround constraints under a single LSynth part
//            // Valid selections are therefore an LSynth part, a single constraint or multiple
//            // contiguous constraints.
//            enable = NO;
//
//            // Single object selected, and is constraint or LSynth part
//            if ([selectedItems count] == 1) {
//                if ([[selectedItems objectAtIndex:0] isKindOfClass:[LDrawLSynth class]] ||
//                    [[fileContentsOutline parentForItem:[selectedItems objectAtIndex:0]] isKindOfClass:[LDrawLSynth class]]) {
//                    enable = YES;
//                }
//            }
//
//            // More than one thing selected.  Check they are direct siblings and contiguous
//            else {
//                NSMutableSet *parents = [[NSMutableSet alloc] init];
//                for (LDrawDirective *directive in selectedItems) {
//                    [parents addObject:[fileContentsOutline parent]];
//
//                }
//            }
//
//            break;
//
//        case lsynthInvertINSIDEOUTSIDETag:
//            enable = YES;
//            break;

        case lsynthInsertINSIDETag:
            enable = YES;
            break;

        case lsynthInsertOUTSIDETag:
            enable = YES;
            break;



		////////////////////////////////////////
		//
		// Something else.
		//
		////////////////////////////////////////
		
		default:
			//We are an NSDocument; it has its own validator to track certain 
			// items.
			enable = [super validateMenuItem:menuItem];
			break;
	}
	
	return enable;
	
}//end validateMenuItem:


//========== validateToolbarItem: ==============================================
//
// Purpose:		Toolbar validation: eye candy that probably slows everything to 
//				a crawl.
//
//==============================================================================
- (BOOL)validateToolbarItem:(NSToolbarItem *)item
{
	LDrawPart		*selectedPart	= [self selectedPart];
//	NSArray			*selectedItems	= [self selectedObjects];
	NSString		*identifier		= [item itemIdentifier];
	BOOL			 enabled		= NO;
	
	//Must have something selected.
	//Must have a part selected.
	if([identifier isEqualToString:TOOLBAR_SNAP_TO_GRID]  )
	{
		enabled = (selectedPart != nil);
	}
	
	//We don't have special conditions for it; give it a pass.
	else
		enabled = YES;

	return enabled;
	
}//end validateToolbarItem:


#pragma mark -

//========== addModelsToMenus ==================================================
//
// Purpose:		Creates a menu used to switch the active model. A list of all 
//				the models in the document is inserted into the Models menu in 
//				the application's menu bar; the active model gets a check next 
//				to it.
//
//				We also regenerate the Insert Reference submenu (for inserting 
//				MPD submodels as parts in a different model). They require 
//				additional validation which occurs in validateMenuItem.
//
//==============================================================================
- (void) addModelsToMenus
{
	NSMenu          *mainMenu           = [NSApp mainMenu];
	NSMenu          *modelMenu          = [[mainMenu itemWithTag:modelsMenuTag] submenu];
	NSMenu          *referenceMenu      = [[modelMenu itemWithTag:insertReferenceMenuTag] submenu];
	NSInteger       separatorIndex      = [modelMenu indexOfItemWithTag:modelsSeparatorMenuTag];
	NSMenuItem      *modelItem          = nil;
	NSMenuItem      *referenceItem      = nil;
	NSArray         *models             = [[self documentContents] submodels];
	LDrawMPDModel   *currentModel       = nil;
	NSString        *modelDescription   = nil;
	NSInteger       counter             = 0;
	
	[self clearModelMenus];
	
	//Create menu items for each model.
	for(counter = 0; counter < [models count]; counter++)
	{
		currentModel		= [models objectAtIndex:counter];
		modelDescription	= [currentModel browsingDescription];
		
		//
		// Active Model menu items
		//
		modelItem = [[NSMenuItem alloc] init];
		[modelItem setTitle:modelDescription];
		[modelItem setRepresentedObject:currentModel];
		[modelItem setTarget:self];
		[modelItem setAction:@selector(modelSelected:)];
		
		//
		// MPD reference menu items
		//
		referenceItem = [[NSMenuItem alloc] init];
		[referenceItem setTitle:modelDescription];
		[referenceItem setRepresentedObject:currentModel];
		//We set the same tag for all items in the reference menu.
		// Validation will distinguish them with their represented objects.
		[referenceItem setTag:submodelReferenceMenuTag];
		[referenceItem setTarget:self];
		[referenceItem setAction:@selector(addSubmodelReferenceClicked:)];
		
		//
		// Insert the new item at the end.
		//
		[modelMenu insertItem:modelItem atIndex:separatorIndex+counter+1];
		[referenceMenu addItem:referenceItem];
		[[addReferenceButton menu] addItem:[referenceItem copy]];
		[[self->submodelPopUpMenu menu] addItem:[modelItem copy]];
		
		//
		// Set (or re-set) the selected state
		//
		if([[self documentContents] activeModel] == currentModel)
		{
			[modelItem setState:NSControlStateValueOn];
			[self->submodelPopUpMenu selectItemAtIndex:counter];
		}
	}
	
}//end addModelsToMenus


//========== clearModelMenus ===================================================
//
// Purpose:		Removes all submodels from the menus. There are two places we 
//				track the submodels: in the Model menu (for selecting the active 
//				model, and in the references submenu (for inserting submodels as 
//				parts).
//
//==============================================================================
- (void) clearModelMenus
{
	NSMenu      *mainMenu       = [NSApp mainMenu];
	NSMenu      *modelMenu      = [[mainMenu itemWithTag:modelsMenuTag] submenu];
	NSMenu      *referenceMenu  = [[modelMenu itemWithTag:insertReferenceMenuTag] submenu];
	NSInteger   separatorIndex  = [modelMenu indexOfItemWithTag:modelsSeparatorMenuTag];
	NSInteger   counter         = 0;
	
	//Kill all model menu items.
	for(counter = [modelMenu numberOfItems]-1; counter > separatorIndex; counter--)
		[modelMenu removeItemAtIndex: counter];
	
	for(counter = [referenceMenu numberOfItems]-1; counter >= 0; counter--)
		[referenceMenu removeItemAtIndex:counter];
		
	for(counter = [addReferenceButton numberOfItems]-1; counter > 0; counter--)
		[self->addReferenceButton removeItemAtIndex:counter];
		
	[self->submodelPopUpMenu removeAllItems];
	
}//end clearModelMenus


//========== buildRelatedPartsMenus ============================================
//
// Purpose:		This kills and rebuilds the related-parts menu.
//
//==============================================================================
- (void) buildRelatedPartsMenus
{
	NSMenu      *mainMenu       = [NSApp mainMenu];
	NSMenu      *modelMenu      = [[mainMenu itemWithTag:modelsMenuTag] submenu];
	NSMenuItem	*relatedItem	= [modelMenu itemWithTag:relatedPartMenuTag];

#if WANT_RELATED_PARTS

	if ([relatedItem hasSubmenu])
	{
		[relatedItem setSubmenu:nil];
	}
	
	// Shared part-type among selected parts, or nil if none or mixed types.
	NSString *parentName = [LDrawSelection sharedReferenceNameInSelection:selectedDirectives];
	
	if(parentName != nil)
	{
		LDrawRelatedPartsMenuPlan *plan = [[RelatedParts sharedRelatedParts] menuPlanForParentName:parentName];

		if(plan != nil)
		{
			NSMenu * kids_and_roles = [[NSMenu alloc] initWithTitle:[RelatedParts relatedPartsMenuTitle]];

			[relatedItem setSubmenu:kids_and_roles];
			[relatedItem setEnabled:TRUE];

			for(LDrawRelatedPartsMenuGroup *group in plan.childGroups)
			{
				AppendChoicesToNewItem(kids_and_roles, group);
			}

			if([plan.roleGroups count] > 0)
			{
				[kids_and_roles addItem:[NSMenuItem separatorItem]];

				for(LDrawRelatedPartsMenuGroup *group in plan.roleGroups)
				{
					AppendChoicesToNewItem(kids_and_roles, group);
				}
			}
		}
	}
	
#else /* WANT_RELATED_PARTS */

	// We can't (as faras I know) use macros to remove UI.  So instead we simply delete our menu item the first time we find
	// it if the related parts UI is disabled.

	if(relatedItem != nil)
	{
		[modelMenu removeItem:relatedItem];
	}

#endif	/* WANT_RELATED_PARTS */
	
}//end buildRelatedPartsMenus



#pragma mark -
#pragma mark VIEWPORT MANAGEMENT
#pragma mark -

//========== all3DViewports ====================================================
//
// Purpose:		Returns an array of all the LDrawViews managed by the
//				document and displaying the document contents. 
//
//==============================================================================
- (NSArray<LDrawView*> *) all3DViewports
{
	NSArray<LDrawViewerContainer*>* viewerContainers	= [self->viewportArranger allViewports];
	NSMutableArray<LDrawView*>*	viewports			= [NSMutableArray array];

	// Count up all the GL views in each column
	for(LDrawViewerContainer* currentViewer in viewerContainers)
	{
		LDrawView* currentGLView = currentViewer.glView;
		
		[viewports addObject:currentGLView];
	}
	
	return viewports;
	
}//end all3DViewports


//========== connectLDrawView: =================================================
//
// Purpose:		Associates the given LDrawView with this document.
//
//==============================================================================
- (void) connectLDrawView:(LDrawView *)glView
{
	[glView setLDrawDelegate:self];

	[glView setTarget:self];
	[glView setForwardAction:@selector(advanceOneStep:)];
	[glView setBackAction:@selector(backOneStep:)];
	[glView setNudgeAction:@selector(nudge:)];
	
	[glView setGridSpacingMode:[self gridSpacingMode]];
	
}//end connectLDrawView:


//========== main3DViewport ====================================================
//
// Purpose:		This is the viewport anointed "main", where we reflect things 
//				like the current step orientation. 
//
//==============================================================================
- (LDrawView *) main3DViewport
{
	NSArray<LDrawView*>*	allViewports	= [self all3DViewports];
	NSMutableArray			*areas			= [NSMutableArray arrayWithCapacity:[allViewports count]];

	// Find the largest viewport. We'll assume that's the one the user wants to 
	// be the main one. 
	for(LDrawView *currentViewport in allViewports)
	{
		NSSize currentSize = currentViewport.frame.size;
		[areas addObject:[NSNumber numberWithDouble:currentSize.width * currentSize.height]];
	}

	NSUInteger largestIndex = [LDrawViewPolicy indexOfLargestViewportAmongAreas:areas];
	if(largestIndex == NSNotFound)
		return nil;
	return [allViewports objectAtIndex:largestIndex];
	
}//end main3DViewport


//========== updateViewportAutosaveNamesAndRestore: ============================
//
// Purpose:		Sets the autosave names for all the viewports. Call this after 
//				the viewport configuration changes. 
//
// Parameters:	shouldRestore	- pass YES to also read settings from prefs.
//
//==============================================================================
- (void) updateViewportAutosaveNamesAndRestore:(BOOL)shouldRestore
{
	NSArray<LDrawView*>*	viewports		= [self all3DViewports];
	LDrawView*				glView			= nil;
	NSUInteger				viewportCount	= [viewports count];
	NSUInteger				counter 		= 0;

	// Recreate whatever was in use last
	for(counter = 0; counter < viewportCount; counter++)
	{
		glView          = [viewports objectAtIndex:counter];
		
		[glView setAutosaveName:[LDrawPreferences documentViewportAutosaveNameAtIndex:counter]];
		
		if(shouldRestore == YES)
			[glView restoreConfiguration];
	}

}//end updateViewportAutosaveNamesAndRestore:


#pragma mark -

//========== viewportArranger:didAddViewport: ==================================
//
// Purpose:		A new viewport has been added. Time to update the world!
//
// Parameters:	sourceView	- the view the newViewport is being split from. Will 
//				be nil if this is called during restoring the viewports from 
//				preferences. 
//
//==============================================================================
- (void) viewportArranger:(ViewportArranger *)viewportArrangerIn
		   didAddViewport:(LDrawViewerContainer *)newViewport
		   sourceViewport:(LDrawViewerContainer *)sourceView
{
	LDrawView *glView         = newViewport.glView;
	LDrawView *sourceGLView   = nil;
	
	[self connectLDrawView:glView];
	
	[self loadDataIntoDocumentUI];
	
	// This doesn't work during viewport restoration. Didn't attempt to debug 
	// it; just moved the code to -windowControllerDidLoadNib: 
//	[glView scrollCenterToPoint:NSMakePoint( NSMidX([glView frame]), NSMidY([glView frame]) )];
	
	// Opening zoom level
	// Note: The zoom level when first opening the document is set to default 
	//		 values. But we aren't able to determine which views get what values 
	//		 until *all* the views have been fully restored. So we can't do it 
	//		 here. 
	if(sourceView != nil)
	{
		// Make the new view look like the old one.
		sourceGLView = [sourceView glView];
		
		[glView setViewOrientation:[sourceGLView viewOrientation]];
		[glView setProjectionMode:[sourceGLView projectionMode]];
		[glView setZoomPercentage:[sourceGLView zoomPercentage]];
		[glView setLocationMode:[sourceGLView locationMode]];
	}
	
	[self updateViewportAutosaveNamesAndRestore:NO];


}//end viewportArranger:didAddViewport:


//========== viewportArranger:willRemoveViewports: =============================
//
// Purpose:		3D viewports are about to be removed (but they haven't been 
//				quite yet). 
//
//==============================================================================
- (void) viewportArranger:(ViewportArranger *)viewportArranger
	  willRemoveViewports:(NSSet<LDrawViewerContainer*> *)removingViewports
{
	NSArray<LDrawViewerContainer*>* allViewports			= [self->viewportArranger allViewports];
	BOOL							removingMostRecentView	= NO;

	// Are we removing the most recently-used view?
	for(LDrawViewerContainer* container in removingViewports)
	{
		if(container.glView == self->mostRecentLDrawView)
		{
			removingMostRecentView = YES;
			break;
		}
	}

	// If the current most-recent viewport is being removed, we need to make a 
	// new viewport "most-recent." That's because we have bindings observers 
	// watching the most recent view, and we'll crash if they're still observing 
	// when the view deallocates. 
	if(removingMostRecentView)
	{
		// Make the first viewport not being removed the most recent.
		for(LDrawViewerContainer* container in allViewports)
		{
			if([removingViewports containsObject:container] == NO)
			{
				[self setMostRecentLDrawView:[container glView]];
				break;
			}
		}
	}
	
}//end viewportArranger:willRemoveViewports:


//========== viewportArrangerDidRemoveViewports: ===============================
//
// Purpose:		A viewport (or maybe a whole bunch of them) has been removed. We 
//				don't get told which one, but that's because we don't need to 
//				know. 
//
//==============================================================================
- (void) viewportArrangerDidRemoveViewports:(ViewportArranger *)viewportArranger
{
	[self updateViewportAutosaveNamesAndRestore:NO];
	
}//end viewportArrangerDidRemoveViewports:


#pragma mark -
#pragma mark UTILITIES
#pragma mark -

//========== addModel: =========================================================
//
// Purpose:		Add newModel to the current file.
//
// Notes:		Duplicate model names are verboten if renameModels is true, so 
//				if newModel's name matches an existing model name, an approriate 
//				"copy X" will be appended automatically. 
//
//				There is a bug here in that if several models having references 
//				to one another are pasted at once into a file with name 
//				conflicts, the file reference structure of the pasted models 
//				will point to the wrong names once this method does its renaming 
//				magic. To this I respond, "don't do that."
//
//==============================================================================
- (void) addModel:(LDrawMPDModel *)newModel atIndex:(NSInteger)insertAtIndex preventNameCollisions:(BOOL)renameModels
{
	NSString        *proposedModelName  = [newModel modelName];
	NSUndoManager   *undoManager        = [self undoManager];
	NSInteger       rowForItem          = 0;
	
	// Derive a non-duplicating name for this new model
	if(renameModels == YES)
	{
		while([[self documentContents] modelWithName:proposedModelName] != nil)
		{
			proposedModelName = [StringUtilities nextCopyPathForFilePath:proposedModelName];
		}
		[newModel setModelName:proposedModelName];
	}
	
	// Insert
	if(insertAtIndex == NSNotFound)
	{
		[self addDirective:newModel toParent:[self documentContents]];
	}
	else
	{
		[self addDirective:newModel toParent:[self documentContents] atIndex:insertAtIndex];
	}
	
	// Select the new model.
	// Ben says: why is it legal for us to directly synchronously select the mode? (This is one of the 
	// only cases where we do?)  Adding a directive to the parent file (which is what adding a model
	// does) causes us to get a notification _directly_ off of the doc's file. Notifications off of 
	// the doc's file are handled synchronously, so by the time we get here, we are totally UI-synced.
	//
	// This is good because we are also going to hierarchy-expand our new model to reveal its first
	// step, so we this code is going to have to talk to the outliner no matter what.
	[fileContentsOutline expandItem:newModel];
	rowForItem = [fileContentsOutline rowForItem:newModel];
	[fileContentsOutline selectRowIndexes:[NSIndexSet indexSetWithIndex:rowForItem]
					 byExtendingSelection:NO];
	
	[undoManager setActionName:NSLocalizedString([LDrawInsertion undoActionKeyForInsertKind:LDrawInsertUndoModel], nil)];
	
}//end addModel:


//========== addStep:parent:index: =============================================
//
// Purpose:		Adds newStep to the currently-displayed model. If you specify an 
//				index, it will be inserted there. Otherwise, the step appears at 
//				the end of the list. 
//
//==============================================================================
- (void) addStep:(LDrawStep *)newStep parent:(LDrawMPDModel*)selectedModel index:(NSInteger)insertAtIndex
{
	NSUndoManager	*undoManager	= [self undoManager];
	
	// Synchronize our addition with the model currently active.
	if(selectedModel == nil)
		selectedModel = [[self documentContents] activeModel];
	else
		[[self documentContents] setActiveModel:selectedModel];
	
	// Insert
	if(insertAtIndex == NSNotFound)
	{
		[self addDirective:newStep toParent:selectedModel];
	}
	else
	{
		[self addDirective:newStep toParent:selectedModel atIndex:insertAtIndex];
	}
	
	[undoManager setActionName:NSLocalizedString([LDrawInsertion undoActionKeyForInsertKind:LDrawInsertUndoStep], nil)];	
	[self flushDocChangesAndSelect:[NSArray arrayWithObject:newStep]];
	
}//end addStep:


//========== addPartNamed: =====================================================
//
// Purpose:		Adds a part with the given name to the current step in the 
//				currently-displayed model.
//
//==============================================================================
- (void) addPartNamed:(NSString *)partName
{
	NSUndoManager       *undoManager    = [self undoManager];
	LDrawColor          *selectedColor  = [[LDrawColorPanelController sharedColorPanel] LDrawColor];
	LDrawPart           *newPart        = nil;
	
	//We got a part; let's add it!
	if(partName != nil)
	{
		newPart = [LDrawInsertion partNamed:partName
									  color:selectedColor
					   copyingTransformFrom:self->lastSelectedPart];
		
		[self addStepComponent:newPart parent:nil index:NSNotFound];
		
		[undoManager setActionName:NSLocalizedString([LDrawInsertion undoActionKeyForInsertKind:LDrawInsertUndoPart], nil)];
		[self flushDocChangesAndSelect:[NSArray arrayWithObject:newPart]];
	}
}//end addPartNamed:


//========== addStepComponent: =================================================
//
// Purpose:		Adds newDirective to the bottom of the current step, or after 
//				the currently-selected element in the step if there is one.
//
// Parameters:	newDirective: a directive which can be added to a step. These 
//						include parts, geometric primitives, and comments.
//				parent - requested target step; if nil, uses the default behavior
//				insertAtIndex - index in parent.
//
// Note:			This routine _no longer_ selects the added step component!  All
//				code that calls addStepComponent must manage selection on its
//				own.  Selection has been pulled out of addStepComponent because
//				many operations involve a large number of step components;
//				editing the selection per directive turns into a huge
//				performance problem.
//
//==============================================================================
- (void) addStepComponent:(LDrawDirective *)newDirective
				   parent:(LDrawContainer*)parent
					index:(NSInteger)insertAtIndex
{
	LDrawContainer	*targetContainer	= parent;
	LDrawMPDModel	*selectedModel		= [self selectedModel];

	// Synchronize our addition with the model currently active.
	if(selectedModel == nil)
		selectedModel = [[self documentContents] activeModel];
	else
		[[self documentContents] setActiveModel:selectedModel];
	
	// We may have the model itself selected, in which case we will add this new 
	// element to the very bottom of the model.
	if(targetContainer == nil)
	{
		targetContainer = [LDrawStructure insertionParentForDirective:newDirective
													selectedContainer:[self selectedContainer]
														  visibleStep:[selectedModel visibleStep]];
	}
	if(insertAtIndex == NSNotFound)
	{
		// At a user's request, all new components are inserted in the last 
		// visible step. That's how duplicating drag-and-drops work anyway. 
		[self addDirective:newDirective toParent:targetContainer ];
	}
	else
	{
		[self addDirective:newDirective toParent:targetContainer atIndex:insertAtIndex ];
	}

	// This code used to do a synchronous doc update and select the part right here.
	// This has been removed and hoisted out to the calling code - pretty much anyone
	// calling this should call flushDocChangesAndSelect.

	// Allow us to immediately use the keyboard to move the new part.
	[[self foremostWindow] makeFirstResponder:mostRecentLDrawView];
	
}//end addStepComponent:


#pragma mark -

//========== canDeleteDirective:displayErrors: =================================
//
// Purpose:		Tests whether the specified directive should be allowed to be 
//				deleted. If errorFlag is YES, also displays an appropriate error 
//				sheet explaining the reasons why directive cannot be deleted.
//
//==============================================================================
- (BOOL) canDeleteDirective:(LDrawDirective *)directive
			  displayErrors:(BOOL)errorFlag
{
	LDrawDeleteRefusal	refusal			= [LDrawStructure deleteRefusalForDirective:directive];
	BOOL				 canDelete		= (refusal == LDrawDeleteAllowed);
	NSString			*informativeKey	= [LDrawStructure deleteRefusalInformativeKey:refusal];
	NSAlert				*alert			= nil;
	NSString			*message		= nil;
	NSString			*informative	= nil;

	if(informativeKey != nil && errorFlag == YES)
	{
		informative = NSLocalizedString(informativeKey, nil);

		message = NSLocalizedString([LDrawStructure deleteDirectiveErrorMessageKey], nil);
		message = [NSString stringWithFormat:message, [directive browsingDescription]];
		
		alert = [[NSAlert alloc] init];		
		[alert setMessageText:message];
		[alert setInformativeText:informative];
		
		[alert addButtonWithTitle:NSLocalizedString([LDrawEditorStrings okButtonNameKey], nil)];
		
		[alert beginSheetModalForWindow:[self windowForSheet]
					  completionHandler:nil];
	}
	
	
	return canDelete;
	
}//end canDeleteDirective:displayErrors:


//========== formatDirective:withStringRepresentation: =========================
//
// Purpose:		Applies syntax coloring to the specified directive, which will 
//				be displayed with the text representation.
//
//==============================================================================
- (NSAttributedString *) formatDirective:(LDrawDirective *)item
				withStringRepresentation:(NSString *)representation
{
	NSUserDefaults			*userDefaults	= [NSUserDefaults standardUserDefaults];
	NSString				*colorKey		= [LDrawOutline outlineSyntaxColorKeyForDirective:item];
	NSColor					*syntaxColor	= nil;
	NSNumber				*obliqueness	= [NSNumber numberWithDouble:[LDrawOutline outlineObliquenessForDirective:item]];
	NSAttributedString		*styledString	= nil;
	NSMutableDictionary		*attributes		= [NSMutableDictionary dictionary];
	NSMutableParagraphStyle	*paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
	
	//We want the text to appear nicely truncated in its column.
	// By setting the column to wrap and then setting the paragraph wrapping to 
	// truncate, we achieve the desired effect.
	[paragraphStyle setLineBreakMode:NSLineBreakByTruncatingTail];
	
	//We have the syntax coloring we want.
	syntaxColor = [userDefaults colorForKey:colorKey];
	
	if (syntaxColor == nil) {
		switch([LDrawOutline outlineSyntaxFallbackColorForKey:colorKey])
		{
			case LDrawOutlineSyntaxFallbackSystemGreen:
				syntaxColor = [NSColor systemGreenColor];
				break;
			case LDrawOutlineSyntaxFallbackSystemBlue:
				syntaxColor = [NSColor systemBlueColor];
				break;
			case LDrawOutlineSyntaxFallbackSystemOrange:
				syntaxColor = [NSColor systemOrangeColor];
				break;
			case LDrawOutlineSyntaxFallbackSystemPurple:
				syntaxColor = [NSColor systemPurpleColor];
				break;
			case LDrawOutlineSyntaxFallbackSystemYellow:
				syntaxColor = [NSColor systemYellowColor];
				break;
			case LDrawOutlineSyntaxFallbackSystemPink:
				syntaxColor = [NSColor systemPinkColor];
				break;
			case LDrawOutlineSyntaxFallbackSystemRed:
				syntaxColor = [NSColor systemRedColor];
				break;
			case LDrawOutlineSyntaxFallbackLabel:
				syntaxColor = [NSColor labelColor];
				break;
		}
	}
	
	//Assemble the attributes dictionary.
	[attributes setObject:paragraphStyle	forKey:NSParagraphStyleAttributeName];
	[attributes setObject:syntaxColor		forKey:NSForegroundColorAttributeName];
	[attributes setObject:obliqueness		forKey:NSObliquenessAttributeName];
	
	//Create the attributed string.
    styledString = [[NSAttributedString alloc]
							initWithString:representation
								attributes:attributes ];
	
	return styledString;

}//end formatDirective:withStringRepresentation:


//========== loadDataIntoDocumentUI ============================================
//
// Purpose:		Informs the document's user interface widgets about the contents 
//				of the document they are supposed to be representing.
//
//				There are two occasions when this method must be called:
//					1) immediately after the document UI has first been loaded
//						(in windowControllerDidLoadNib:)
//					2) when reverting the document.
//						(in revertToSavedFromFile:ofType:)
//
//==============================================================================
- (void) loadDataIntoDocumentUI
{
	NSArray<LDrawView*>*	graphicViews	= [self all3DViewports];
	NSUInteger				counter 		= 0;

	for(counter = 0; counter < [graphicViews count]; counter++)
	{
		[[graphicViews objectAtIndex:counter] setLDrawDirective:[self documentContents]];
	}
	[self->fileContentsOutline	reloadData];
	
	[self addModelsToMenus];
	
	[self buildRelatedPartsMenus];

}//end loadDataIntoDocumentUI


//========== selectedContainer =================================================
//
// Purpose:		Returns the step that encloses (or is) the current selection, or
//				nil if there is no step in the selection chain.
//
//==============================================================================
- (LDrawContainer *) selectedContainer
{
	NSInteger		selectedRow 		= [fileContentsOutline selectedRow];
	id				selectedItem		= [fileContentsOutline itemAtRow:selectedRow];
	
	// Hack alert!
	// If we are doing a copy-drag operation, remember the original selection 
	// and use it. (We can't use the current selection during copy drag because 
	// we clear it when the drag begins.)
	selectedItem = [LDrawSelection outlineItemForCopyDragContainerLookupWithCurrentItem:selectedItem
																 selectedBeforeCopyDrag:self->selectedDirectivesBeforeCopyDrag];
	
	return [LDrawOutline containerEnclosingOutlineItem:selectedItem];
	
}//end selectedContainer


//========== selectedObjects ===================================================
//
// Purpose:		Returns the LDraw objects currently selected in the file.
//
//==============================================================================
- (NSArray *) selectedObjects
{
	NSIndexSet      *selectedIndexes    = [fileContentsOutline selectedRowIndexes];
	NSUInteger      currentIndex        = [selectedIndexes firstIndex];
	NSMutableArray  *selectedObjects    = [NSMutableArray arrayWithCapacity:[selectedIndexes count]];
	id              currentObject       = nil;
	
	//Search through all the indexes and get the objects associated with them.
	while(currentIndex != NSNotFound){
	
		currentObject = [fileContentsOutline itemAtRow:currentIndex];
		if (currentObject != nil) {
			[selectedObjects addObject:currentObject];
		}
		
		currentIndex = [selectedIndexes indexGreaterThanIndex:currentIndex];
	}
	
	return selectedObjects;
	
}//end selectedObjects


//========== selectedModel =====================================================
//
// Purpose:		Returns the model that encloses the current selection, or nil 
//				if there is no selection.
//
// Note:		If you intend to use this method's output to figure out which 
//				model to display, then you need to convert a nil case into the 
//				active model.
//
//==============================================================================
- (LDrawMPDModel *) selectedModel
{
	NSInteger   selectedRow     = [fileContentsOutline selectedRow];
	id          selectedItem    = [fileContentsOutline itemAtRow:selectedRow];
	
	return (LDrawMPDModel*)[selectedItem enclosingModel];

}//end selectedModel


//========== selectedModel =====================================================
//
// Purpose:		Returns the step that encloses (or is) the current selection, or  
//				nil if there is no step in the selection chain.
//
//==============================================================================
- (LDrawStep *) selectedStep
{
	NSInteger   selectedRow     = [fileContentsOutline selectedRow];
	id          selectedItem    = [fileContentsOutline itemAtRow:selectedRow];
	
	return [selectedItem enclosingStep];

}//end selectedStep


//========== selectedStepComponent =============================================
//
// Purpose:		Returns the drawable LDraw element that is currently selected.
//				(e.g., Part, Quadrilateral, Triangle, etc.)
//
//				Returns nil if the selection is not one of these atomic LDraw
//				commands.
//
//==============================================================================
- (LDrawDirective *) selectedStepComponent
{
	NSInteger   selectedRow     = [fileContentsOutline selectedRow];
	id          selectedItem    = [fileContentsOutline itemAtRow:selectedRow];
	
	return [LDrawOutline stepComponentFromOutlineItem:selectedItem];
}//end selectedStep


//========== selectedPart ======================================================
//
// Purpose:		Returns the first part that is currently selected, or nil if no 
//				part is selected.
//
//==============================================================================
- (LDrawPart *) selectedPart
{
	return [LDrawSelection firstPartInSelection:[self selectedObjects]];
}//end 


//========== nextModelIndex =====================================================
//
// Purpose:		Returns index of the next model that follows another one, which
//				encloses the current selection, or NSNotFound if there is no
//				selection.
//
//==============================================================================
- (NSInteger) nextModelIndex
{
	return [LDrawPaste insertIndexAfterModel:self.selectedModel inFile:self.documentContents];
	
}//end nextModelIndex


//========== updateInspector ===================================================
//
// Purpose:		Updates the Inspector to display the currently-selected objects.
//				This should be called in response to any potentially state-
//				changing actions on a directive.
//
//==============================================================================
- (void) updateInspector
{
	NSArray *selectedObjects = [self selectedObjects];
	
	[[LDrawApplication sharedInspector] inspectObjects:selectedObjects];
	[[LDrawColorPanelController sharedColorPanel] updateSelectionWithObjects:selectedObjects];
	
}//end updateInspector


//========== updateViewingAngleToMatchStep =====================================
//
// Purpose:		Sets the viewing angle of the main viewport to the angle 
//				requested by the current step for Step Display mode. 
//
//==============================================================================
- (void) updateViewingAngleToMatchStep
{
	LDrawMPDModel       *activeModel        = [[self documentContents] activeModel];
	NSInteger           requestedStep       = [activeModel maximumStepIndexForStepDisplay];
	Tuple3              viewingAngle        = [activeModel rotationAngleForStepAtIndex:requestedStep];
	ViewOrientationT    viewOrientation     = [LDrawUtilities viewOrientationForAngle:viewingAngle];
	LDrawView           *affectedViewport   = [self main3DViewport];
	
	// Set the Viewing angle
	[affectedViewport setProjectionMode:[LDrawViewPolicy projectionModeForViewOrientation:viewOrientation]];
	
	[affectedViewport setViewOrientation:viewOrientation];
	[affectedViewport setViewingAngle:viewingAngle];
	[affectedViewport setLocationMode:LocationModeModel];
	
}//end updateViewingAngleToMatchStep


//========== writeDirectives:toPasteboard: =====================================
//
// Purpose:		Writes objects to the given pasteboard, ensuring that each 
//				directive is written only once.
//
//				This method places two arrays on the pasteboard for these types:
//				* LDrawDirectivePboardType: array of LDrawDirectives converted 
//							to NSData objects.
//				* NSStringPboardType: array of strings representing the objects 
//							in the format written to an LDraw file.
//
// Notes:		This method will clear the contents of the pasteboard.
//
//==============================================================================
- (void) writeDirectives:(NSArray *)directives
			toPasteboard:(NSPasteboard *)pasteboard
{
	//Pasteboard types.
	NSArray			*pboardTypes		= [LDrawClipboard copyPasteboardTypesIncludingStringType:NSPasteboardTypeString];
	NSArray			*archivedObjects	= nil;
	NSString		*stringedObjects	= nil;

	[LDrawClipboard copyPayloadFromDirectives:directives
								 archivedData:&archivedObjects
									ldrString:&stringedObjects];
	
	//Set up our pasteboard.
	[pasteboard declareTypes:pboardTypes owner:nil];
	
	//Internally, Bricksmith uses archived LDrawDirectives to copy/paste.
	[pasteboard setPropertyList:archivedObjects forType:LDrawDirectivePboardType];
	
	//For other applications, however, we provide the LDraw file contents for 
	// the objects. Note that these strings cannot be pasted back into the 
	// program. (Not using CRLF here because any Mac program that knows enough
	// to do DOS line-endings will automatically add them to pasted content.)
	[pasteboard setString:stringedObjects forType:NSPasteboardTypeString];
	
}//end writeDirectives:toPasteboard:


//========== pasteFromPasteboard: ==============================================
//
// Purpose:		Paste the directives on the given pasteboard into the document.
//				The pasteboard must contain LDrawDirectivePboardType.
//
//				By generalizing the method in this way, we allow pasting off 
//				private internal pasteboards too. This method is used by 
//				-duplicate: in order to leverage the existing copy/paste code 
//				without wantonly destroying the contents of the General 
//				Pasteboard.
//
// Returns:		The objects added, or nil if nothing was on the pasteboard.
//
// Parameters:	pasteboard		- where the archived directives live
//				renameModels	- add "copy X" suffixes to pasted models as needed. 
//				parent			- add objects to this component (pass nil for default behavior)
//				insertAtIndex	- child index within parent (pass NSNotFound for default behavior)
//				nextToSimilar	- for part duplication: if true, paste duplicated parts next to originals
//
//==============================================================================
- (NSArray *) pasteFromPasteboard:(NSPasteboard *) pasteboard
			preventNameCollisions:(BOOL)renameModels
						   parent:(LDrawContainer*)parent
							index:(NSInteger)insertAtIndex
					nextToSimilar:(BOOL)nextToSimilar
{
	NSArray				*objects			= nil;
	NSMutableArray		*addedObjects		= [NSMutableArray array];
	NSMutableArray		*models				= [NSMutableArray array];
	NSMutableArray		*steps				= [NSMutableArray array];
	NSMutableArray		*directives			= [NSMutableArray array];
	LDrawContainer		*parentStep			= nil;
	NSInteger			 real_index			= NSNotFound;
	NSArray				*selectedObjects	= self.selectedObjects; // initial selection

	//We must make sure we have the proper pasteboard type available.
 	if([[pasteboard types] containsObject:LDrawDirectivePboardType])
	{
		//Unarchived everything and dump it into our file.
		objects = [LDrawClipboard unarchivedDirectivesFromDataArray:
				   [pasteboard propertyListForType:LDrawDirectivePboardType]];
		[LDrawPaste partitionPastedObjects:objects
									models:models
									 steps:steps
								directives:directives];
		
		//Now pop the data into our file.
		if (directives.count > 0) {
			real_index = insertAtIndex;
			for (LDrawDirective *directive in directives) {
				[LDrawPaste resolveStepPasteParent:&parentStep
											 index:&real_index
									  forDirective:directive
											parent:parent
									 insertAtIndex:insertAtIndex
									 nextToSimilar:nextToSimilar
									   inSelection:selectedObjects
								fallbackParentStep:[self selectedStep]];
				[self addStepComponent:directive parent:parentStep index:real_index];
				[addedObjects addObject:directive];
			}
		} else if (steps.count > 0) {
			for (LDrawStep *step in steps) {
				LDrawMPDModel * parentModel = [LDrawPaste pasteModelParentFromParent:parent];
				[self addStep:step parent:parentModel index:insertAtIndex];
				[addedObjects addObject:step];
			}
		} else {
			real_index = [LDrawPaste modelPasteStartIndexForInsertAtIndex:insertAtIndex
															 defaultIndex:[self nextModelIndex]];
			for (LDrawMPDModel *model in models) {
				[self addModel:model atIndex:real_index preventNameCollisions:renameModels];
				real_index = [LDrawPaste nextSequentialModelInsertIndexAfter:real_index];
				[addedObjects addObject:model];
			}
		}

		[self flushDocChangesAndSelect:addedObjects];

	}
	
	return addedObjects;
	
}//end pasteFromPasteboard:


//========== flushDocChangesAndSelect: =========================================
//
// Purpose:		This routine does two tasks that are almost always done 
//				together in most UI code:
//
//				(1) it "flushes" pending asynchronous UI updates by
//					directly posting a directive change (on our doc's file)
//					synchronously with coalescing. When this finishes, the 
//					outliner, model menu, etc. are all "synced up".
//
//				(2) it then completely changes the selection to a new set
//					of directives.  That could be 0, 1 or many directives.
//
// Notes:		This routine should be done once at the end of an editing
//				function; the sync and selection change are quite affordable
//				performance wise if they are done once per user edit.
//
//				This function should _not_ be done in lower level utility 
//				functions, undoable methods, or inside an iteration loop.
//
//				Typical use will be to make a series of low level directive
//				changes (all which post async doc updates) and then flush and
//				select once when all editing work is finished.
//==============================================================================
- (void) flushDocChangesAndSelect:(NSArray*)directives
{
	LDrawFile *docContents = [self documentContents];

	// Post a notification that our doc changed; LDrawView needs this
	// to refresh drawing, and we ned it to redo our menus.
	NSNotification * doc_notification = 
		[NSNotification notificationWithName:LDrawDirectiveDidChangeNotification 
									  object:docContents];

	// Notification is queued and coalesced; 
	[[NSNotificationQueue defaultQueue] 
			enqueueNotification:doc_notification 
				   postingStyle:NSPostNow 
				   coalesceMask:NSNotificationCoalescingOnName|NSNotificationCoalescingOnSender
					   forModes:NULL];
					
	[self selectDirectives:directives];
}//end flushDocChangesAndSelect:


#pragma mark -
#pragma mark DESTRUCTOR
#pragma mark -

//========== dealloc ===========================================================
//
// Purpose:		We're crossing over Jordan; we're heading to that mansion just 
//				over the hilltop (the gold one that's silver-lined).
//
// Note:		We DO NOT RELEASE TOP-LEVEL NIB OBJECTS HERE! NSWindowController 
//				does that automagically.
//
//==============================================================================
- (void) dealloc
{
	if ([NSThread isMainThread])
	{
		[[ModelManager sharedModelManager] documentSignOut:documentContents];
	}
	else
	{
		// This punt to the main thread tries to ensure that in the case when
		// our doc is dropped from a worker dispatch Q.  This happens on Sierra
		// and newer when we quit and save during the quit.
	
		// I think if we use documentContents we capture self - which takes a ref
		// from inside dealloc which blows up the obj-C runtime.
		LDrawFile * doc = documentContents;
		dispatch_async(dispatch_get_main_queue(),^{
			[[ModelManager sharedModelManager] documentSignOut:doc];
		});
	}

	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
}//end dealloc

@end
