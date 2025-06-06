//==============================================================================
//
// File:		LDrawDocument.h
//
// Purpose:		Document controller for an LDraw document.
//
//				Opens the document and manages its editor and viewer.
//
//              To use elsewhere, do something like:
//
//                   #import "LDrawDocument.h"
//                   NSDocumentController *documentController = [NSDocumentController sharedDocumentController];
//                   LDrawDocument *currentDocument = [documentController currentDocument];
//
//  Created by Allen Smith on 2/14/05.
//  Copyright (c) 2005. All rights reserved.
//==============================================================================
#import <Cocoa/Cocoa.h>

#import "BricksmithUtilities.h"
#import "ColorLibrary.h"
#import "LDrawUtilities.h"
#import "MatrixMath.h"
#import "RotationPanelController.h"
#import "ViewportArranger.h"

@class DocumentToolbarController;
@class ExtendedSplitView;
@class LDrawContainer;
@class LDrawDirective;
@class LDrawDrawableElement;
@class LDrawFile;
@class LDrawFileOutlineView;
@class LDrawView;
@class LDrawModel;
@class LDrawMPDModel;
@class LDrawStep;
@class LDrawPart;
@class PartBrowserDataSource;


////////////////////////////////////////////////////////////////////////////////
//
// class LDrawDocument
//
////////////////////////////////////////////////////////////////////////////////
@interface LDrawDocument : NSDocument <ViewportArrangerDelegate>
{
	__weak IBOutlet DocumentToolbarController	*toolbarController;
	__weak IBOutlet NSObjectController			*bindingsController;
	
	// Window satellites
	__weak IBOutlet NSDrawer					*partBrowserDrawer;
	__weak IBOutlet PartBrowserDataSource		*partsBrowser;
	
	// Scope bar
	__weak IBOutlet NSButton					*viewAllButton;
	__weak IBOutlet NSButton					*viewStepsButton;
	__weak IBOutlet NSPopUpButton				*submodelPopUpMenu;
	__weak IBOutlet NSView						*scopeStepControlsContainer;
	__weak IBOutlet NSTextField					*stepField;
	__weak IBOutlet NSSegmentedControl			*stepNavigator;
	
	// Window contents
	__weak IBOutlet ExtendedSplitView			*fileContentsSplitView;
	__weak IBOutlet LDrawFileOutlineView		*fileContentsOutline;
	__weak IBOutlet NSPopUpButton				*addReferenceButton;
	
	// LDraw graphic view
	__weak IBOutlet ViewportArranger			*viewportArranger;
	__weak IBOutlet NSTextField					*coordinateLabelX;
	__weak IBOutlet NSTextField					*coordinateLabelY;
	__weak IBOutlet NSTextField					*coordinateLabelZ;
	__weak IBOutlet NSTextField					*coordinateFieldX;
	__weak IBOutlet NSTextField					*coordinateFieldY;
	__weak IBOutlet NSTextField					*coordinateFieldZ;
	
	@private
		LDrawFile		*documentContents;
		LDrawPart		*lastSelectedPart; //the part in the file which was most recently selected in the contents. (retained)
		NSArray			*selectedDirectives; //mirrors the selection of the file contents outline.
		NSArray			*selectedDirectivesBeforeCopyDrag;
		gridSpacingModeT gridMode;
		gridOrientationModeT gridOrientation;
		LDrawView		*mostRecentLDrawView; //file graphic view which most recently had focus. Weak link.
		NSArray		*	markedSelection;		// if we are mid-marquee selection, this is an array of the previously selected directives before drag started
}

// Accessors
- (LDrawFile *) documentContents;
- (NSWindow *)foremostWindow;
- (gridSpacingModeT) gridSpacingMode;
- (gridOrientationModeT) gridOrientationMode;
- (NSDrawer *) partBrowserDrawer;
- (Tuple3) viewingAngle;

- (void) setActiveModel:(LDrawMPDModel *)newActiveModel;
- (void) setCurrentStep:(NSInteger)requestedStep;
- (void) setDocumentContents:(LDrawFile *)newContents;
- (void) setGridSpacingMode:(gridSpacingModeT)newMode;
- (void) setGridOrientationMode:(gridOrientationModeT)newMode;
- (void) setLastSelectedPart:(LDrawPart *)newPart;
- (void) setMostRecentLDrawView:(LDrawView *)viewIn;
- (void) setStepDisplay:(BOOL)showStepsFlag;

// Activities
- (void) moveSelectionBy:(Vector3) movementVector;
- (void) nudgeSelectionBy:(Vector3) nudgeVector;
- (void) rotateSelectionAround:(Vector3)rotationAxis extraFine:(BOOL)extraFine aroundOrigin:(BOOL)aroundOrigin;
- (void) rotateSelection:(Tuple3)rotation mode:(RotationModeT)mode fixedCenter:(Point3 *)fixedCenter;
- (void) selectDirective:(LDrawDirective *)directiveToSelect byExtendingSelection:(BOOL)shouldExtend;
- (void) selectDirectives:(NSArray *)directivesToSelect;
- (void) setSelectionToHidden:(BOOL)hideFlag;
- (void) setZoomPercentage:(CGFloat)newPercentage;

// Actions
- (void) changeLDrawColor:(id)sender;
- (void) insertLDrawPart:(id)sender;
- (void) panelMoveParts:(id)sender;
- (void) panelRotateParts:(id)sender;

// - miscellaneous
- (void) doMissingModelnameExtensionCheck:(id)sender;
- (void) doMissingPiecesCheck:(id)sender;
- (void) doMovedPiecesCheck:(id)sender;

// - Scope bar
- (IBAction) viewAll:(id)sender;
- (IBAction) viewSteps:(id)sender;
- (IBAction) stepFieldChanged:(id)sender;
- (IBAction) stepNavigatorClicked:(id)sender;

// - File menu
- (IBAction) exportSteps:(id)sender;
- (IBAction) revealInFinder:(id)sender;

// - Edit menu
- (IBAction) copy:(id)sender;
- (IBAction) paste:(id)sender;
- (IBAction) delete:(id)sender;
- (IBAction) duplicate:(id)sender;
- (IBAction) splitStep:(id)sender;
- (IBAction) splitModel:(id)sender;
- (IBAction) orderFrontRotationPanel:(id)sender;
- (IBAction) quickRotateClicked:(id)sender;
- (IBAction) quickRotateFineClicked:(id)sender;
- (IBAction) quickRotateAroundOriginClicked:(id)sender;
- (IBAction) quickRotateFineAroundOriginClicked:(id)sender;
- (IBAction) randomizeLDrawColors:(id)sender;
- (IBAction) find:(id)sender;
- (IBAction) changeOrigin:(id)sender;

// - Tools menu
- (IBAction) showInspector:(id)sender;
- (IBAction) toggleFileContentsDrawer:(id)sender;
- (IBAction) gridGranularityMenuChanged:(id)sender;
- (IBAction) gridOrientationModeChanged:(id)sender;
- (IBAction) showDimensions:(id)sender;
- (IBAction) showPieceCount:(id)sender;

// - View menu
- (IBAction) zoomActual:(id)sender;
- (IBAction) zoomIn:(id)sender;
- (IBAction) zoomOut:(id)sender;
- (IBAction) toggleStepDisplay:(id)sender;
- (IBAction) advanceOneStep:(id)sender;
- (IBAction) backOneStep:(id)sender;
- (IBAction) useSelectionForRotationCenter:(id)sender;
- (IBAction) clearRotationCenter:(id)sender;

// - Piece menu
- (IBAction) showParts:(id)sender;
- (IBAction) hideParts:(id)sender;
- (IBAction) showAllParts:(id)sender;
- (IBAction) gotoModel:(id)sender;
- (IBAction) snapSelectionToGrid:(id)sender;
- (IBAction) snapSelectionToGridX:(id)sender;
- (IBAction) snapSelectionToGridY:(id)sender;
- (IBAction) snapSelectionToGridZ:(id)sender;
- (IBAction) mirroredSelectionByX:(id)sender;
- (IBAction) setGroup:(id)sender;

// - Models menu
- (IBAction) addModelClicked:(id)sender;
- (IBAction) addStepClicked:(id)sender;
- (IBAction) addPartClicked:(id)sender;
- (void) addSubmodelReferenceClicked:(id)sender;
- (IBAction) addLineClicked:(id)sender;
- (IBAction) addTriangleClicked:(id)sender;
- (IBAction) addQuadrilateralClicked:(id)sender;
- (IBAction) addConditionalClicked:(id)sender;
- (IBAction) addCommentClicked:(id)sender;
- (IBAction) addRawCommandClicked:(id)sender;
- (IBAction) addRelatedPartClicked:(id)sender;
- (void) modelSelected:(id)sender;

// Undoable Activities
- (void) addDirective:(LDrawDirective *)newDirective toParent:(LDrawContainer * )parent;
- (void) addDirective:(LDrawDirective *)newDirective toParent:(LDrawContainer * )parent atIndex:(NSInteger)index;
- (void) deleteDirective:(LDrawDirective *)doomedDirective;
- (void) moveDirective:(LDrawDrawableElement *)object inDirection:(Vector3)moveVector;
- (void) preserveDirectiveState:(LDrawDirective *)directive;
- (void) rotatePart:(LDrawPart *)part byDegrees:(Tuple3)rotationDegrees aroundPoint:(Point3)rotationCenter;
- (void) setElement:(LDrawDrawableElement *)element toHidden:(BOOL)hideFlag;
- (void) setObject:(LDrawDirective <LDrawColorable>* )object toColor:(LDrawColor *)newColor;
- (void) setTransformation:(TransformComponents)newComponents forPart:(LDrawPart *)part;

//Notifications
- (void)partChanged:(NSNotification *)notification;
- (void)docChanged:(NSNotification *)notification;
- (void)stepChanged:(NSNotification *)notification;
- (void)syntaxColorChanged:(NSNotification *)notification;

//Menus
- (void) addModelsToMenus;
- (void) clearModelMenus;
- (void) buildRelatedPartsMenus;

// Viewport Management
- (void) connectLDrawView:(LDrawView *)view;
- (LDrawView *) main3DViewport;
- (void) updateViewportAutosaveNamesAndRestore:(BOOL)shouldRestore;

// Utilities
- (void) addModel:(LDrawMPDModel *)newModel atIndex:(NSInteger)insertAtIndex preventNameCollisions:(BOOL)renameModels;
- (void) addStep:(LDrawStep *)newStep parent:(LDrawMPDModel*)selectedModel index:(NSInteger)insertAtIndex;
- (void) addPartNamed:(NSString *)partName;
- (void) addStepComponent:(LDrawDirective *)newDirective parent:(LDrawContainer*)parent index:(NSInteger)insertAtIndex;

- (BOOL) canDeleteDirective:(LDrawDirective *)directive displayErrors:(BOOL)errorFlag;
- (BOOL) elementsAreSelectedOfVisibility:(BOOL)visibleFlag;
- (NSAttributedString *) formatDirective:(LDrawDirective *)item withStringRepresentation:(NSString *)representation;
- (void) loadDataIntoDocumentUI;
- (LDrawContainer *) selectedContainer;
- (NSArray *) selectedObjects;
- (LDrawMPDModel *) selectedModel;
- (LDrawStep *) selectedStep;
- (LDrawDirective *) selectedStepComponent;
- (LDrawPart *) selectedPart;
- (void) updateInspector;
- (void) updateViewingAngleToMatchStep;
- (void) writeDirectives:(NSArray *)directives toPasteboard:(NSPasteboard *)pasteboard;
- (NSArray *) pasteFromPasteboard:(NSPasteboard *) pasteboard preventNameCollisions:(BOOL)renameModels parent:(LDrawContainer*)parent index:(NSInteger)insertAtIndex;

- (void) flushDocChangesAndSelect:(NSArray*)directives;

@end
