//==============================================================================
//
// File:		InspectionStep.m
//
// Purpose:		Inspector controller for LDrawSteps. Allows selection of a step 
//				rotatation angle (MLCad ROTSTEP). 
//
//				The UI is prettified to make ROTSTEP configuration easier. For 
//				each rotation type, we present a pop-up menu of common viewing 
//				angles appropriate for that rotation (such as Upside-down for 
//				Relative). In so doing, we aim to make it easier for users to 
//				select the correct rotation type for their viewing angle, which 
//				is traditionally very difficult for new users to figure out. 
//
//				If they don't want a preset, they can always choose custom. 
//				Under the hood, of course, everything is just an angle. But for 
//				"magic" recognized angles (like upside-down) we disable the 
//				custom fields and show the popup-menu item. 
//
// Modified:	9/7/08 Allen Smith. Creation date.
//
//==============================================================================
#import "InspectionStep.h"

#import "LDrawApplication.h"
#import "LDrawDocument.h"
#import "LDrawView.h"
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LDrawUtilities.h>
#import <LDrawEditing/LDrawSelectionOps.h>


@implementation InspectionStep

#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//========== init ==============================================================
//
// Purpose:		Load the interface for this inspector.
//
//==============================================================================
- (id) init
{
    self = [super init];
	
    NSArray *nibObjects = nil;
    if ([[NSBundle mainBundle] loadNibNamed:@"InspectorStep" owner:self topLevelObjects:&nibObjects]) {
		topLevelObjects = nibObjects;
    } else {
		NSLog(@"Couldn't load InspectorStep.nib");
    }
	
    return self;
	
}//end init


#pragma mark -
#pragma mark CONSTRAINTS
#pragma mark -

//========== updateConstraints =================================================
//
// Purpose:		Enables what should be enabled, and disables what should not be 
//				enabled. 
//
//==============================================================================
- (void) updateConstraints
{
	LDrawStep						*representedObject		= [self object];
	LDrawStepRotationT				 stepRotationType		= [representedObject stepRotationType];
	LDrawStepInspectorConstraints	 constraints			=
		[LDrawSelectionOps stepInspectorConstraintsForRotationType:stepRotationType
											  relativeShortcutTag:[self->relativeRotationPopUpMenu selectedTag]
											  absoluteShortcutTag:[self->absoluteRotationPopUpMenu selectedTag]];
	
	[self->relativeRotationPopUpMenu	setEnabled:constraints.relativePopupEnabled];
	[self->absoluteRotationPopUpMenu	setEnabled:constraints.absolutePopupEnabled];
	
	[self->rotationXField				setEnabled:constraints.angleFieldsEnabled];
	[self->rotationYField				setEnabled:constraints.angleFieldsEnabled];
	[self->rotationZField				setEnabled:constraints.angleFieldsEnabled];
	
	[self->useCurrentAngleButton		setHidden:(constraints.viewAngleButtonVisible == NO)];
	
}//end updateConstraints


#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== finishedEditing: ==================================================
//
// Purpose:		Called in response to the conclusion of editing in the palette.
//
//==============================================================================
- (void) commitChanges:(id)sender
{
	LDrawStep *representedObject = [self object];
	
	LDrawStepRotationT	stepRotationType	= (LDrawStepRotationT)[[self->rotationTypeRadioButtons selectedCell] tag];
	Tuple3				rotationAngle		= ZeroPoint3;
	
	rotationAngle.x = [self->rotationXField doubleValue];
	rotationAngle.y = [self->rotationYField doubleValue];
	rotationAngle.z = [self->rotationZField doubleValue];
	
	[representedObject setStepRotationType:stepRotationType];
	[representedObject setRotationAngle:rotationAngle];
	
	[super commitChanges:sender];
	
}//end commitChanges:


//========== revert ============================================================
//
// Purpose:		Restores the palette to reflect the state of the object.
//				This method is called automatically when the object to inspect 
//				is set. Subclasses should override this method to populate 
//				the data in their inspector palettes.
//
//==============================================================================
- (IBAction) revert:(id)sender
{
	LDrawStep			*representedObject	= [self object];
	
	LDrawStepRotationT	stepRotationType	= [representedObject stepRotationType];
	Tuple3				rotationAngle		= [representedObject rotationAngle];
	
	[self->rotationTypeRadioButtons selectCellWithTag:stepRotationType];
	[self->rotationXField setDoubleValue:rotationAngle.x];
	[self->rotationYField setDoubleValue:rotationAngle.y];
	[self->rotationZField setDoubleValue:rotationAngle.z];
	
	if(stepRotationType == LDrawStepRotationRelative)
	{
		NSInteger tag = [LDrawSelectionOps relativeRotationShortcutTagForAngle:rotationAngle
																	currentTag:[self->relativeRotationPopUpMenu selectedTag]];
		[self->relativeRotationPopUpMenu selectItemWithTag:tag];
	}
	else if(stepRotationType == LDrawStepRotationAbsolute)
	{
		NSInteger tag = [LDrawSelectionOps absoluteRotationShortcutTagForAngle:rotationAngle
																	currentTag:[self->absoluteRotationPopUpMenu selectedTag]];
		[self->absoluteRotationPopUpMenu selectItemWithTag:tag];
	}
	
	
	[super revert:sender];
	[self updateConstraints];
	
}//end revert:


#pragma mark -

//========== rotationTypeRadioButtonsClicked: ==================================
//
// Purpose:		Master rotation type has changed.
//
//==============================================================================
- (void) rotationTypeRadioButtonsClicked:(id)sender
{
	// Apply current step rotation automatically when absolute rotation is selected
	LDrawStepRotationT	stepRotationType	= (LDrawStepRotationT)[[self->rotationTypeRadioButtons selectedCell] tag];
	if (stepRotationType == LDrawStepRotationAbsolute) {
		[self->absoluteRotationPopUpMenu selectItemWithTag:LDrawStepInspectorRotationShortcutCustom];
		[self useCurrentViewingAngleClicked:sender];
	}

	[self setAngleUIAccordingToPopUp];
	
	[self finishedEditing:sender];
	[self updateConstraints];
	
}//end rotationTypeRadioButtonsClicked:


//========== relativeRotationPopUpMenuChanged: =================================
//
// Purpose:		User has chosen a new shortcut from the relative rotation menu.
//
//==============================================================================
- (void) relativeRotationPopUpMenuChanged:(id)sender
{
	// set the angle values in the UI.
	[self setAngleUIAccordingToPopUp];
	
	[self finishedEditing:sender];
	[self updateConstraints];
	
}//end relativeRotationPopUpMenuChanged:


//========== absoluteRotationPopUpMenuChanged: =================================
//
// Purpose:		User has chosen a new shortcut from the relative rotation menu.
//
//==============================================================================
- (void) absoluteRotationPopUpMenuChanged:(id)sender
{
	// set the angle values in the UI.
	[self setAngleUIAccordingToPopUp];
	
	[self finishedEditing:sender];
	[self updateConstraints];
	
}//end absoluteRotationPopUpMenuChanged:


//========== useCurrentViewingAngleClicked: ====================================
//
// Purpose:		Grab the viewing angle of the currently-focused LDrawView and 
//				use that for the step's rotation angle. 
//
// Notes:		Only applicable to absolute rotations.
//
//==============================================================================
- (IBAction) useCurrentViewingAngleClicked:(id)sender
{
	LDrawDocument	*currentDocument	= [[NSDocumentController sharedDocumentController] currentDocument];
	Tuple3			viewingAngle		= [LDrawSelectionOps displayViewingAngleFromAngle:[currentDocument viewingAngle]];
	
	// set the values in the UI.
	[self->rotationXField setDoubleValue:viewingAngle.x];
	[self->rotationYField setDoubleValue:viewingAngle.y];
	[self->rotationZField setDoubleValue:viewingAngle.z];
	
	[self finishedEditing:sender];
	
}//end useCurrentViewingAngleClicked:


//========== doHelp: ===========================================================
//
// Purpose:		Requests help for the Step inspector, and boy will my poor users 
//				need it. The help page will explicate in great detail just what 
//				in the heck all this stuff does. 
//
//==============================================================================
- (void) doHelp:(id)sender
{
	LDrawApplication *application = [LDrawApplication shared];
	
	[application openHelpAnchor:@"Steps"];

}//end doHelp:


#pragma mark -
#pragma mark UTILITIES
#pragma mark -

//========== setAngleUIAccordingToPopUp ========================================
//
// Purpose:		Sets the xyz values of the angle field according to the 
//				selection in the pop-up menu. 
//
//==============================================================================
- (void) setAngleUIAccordingToPopUp
{
	LDrawStepRotationT  stepRotationType    = (LDrawStepRotationT)[self->rotationTypeRadioButtons selectedTag];
	NSInteger           shortcut            = 0;
	Tuple3              customAbsolute      = ZeroPoint3;
	Tuple3              newAngle            = ZeroPoint3;
	
	if(stepRotationType == LDrawStepRotationRelative)
		shortcut = [self->relativeRotationPopUpMenu selectedTag];
	else if(stepRotationType == LDrawStepRotationAbsolute)
	{
		shortcut = [self->absoluteRotationPopUpMenu selectedTag];
		LDrawDocument *currentDocument = [[NSDocumentController sharedDocumentController] currentDocument];
		customAbsolute = [currentDocument viewingAngle];
	}

	newAngle = [LDrawSelectionOps stepInspectorAngleForRotationType:stepRotationType
														shortcutTag:shortcut
											   customAbsoluteAngle:customAbsolute];
	
	// set the values in the UI.
	[self->rotationXField setDoubleValue:newAngle.x];
	[self->rotationYField setDoubleValue:newAngle.y];
	[self->rotationZField setDoubleValue:newAngle.z];
	
}//end setAngleUIAccordingToPopUp


#pragma mark -
#pragma mark DESTRUCTOR
#pragma mark -

//========== dealloc ===========================================================
//
// Purpose:		Clean up memory.
//
//==============================================================================
- (void) dealloc
{
	topLevelObjects = nil;

}//end dealloc


@end

