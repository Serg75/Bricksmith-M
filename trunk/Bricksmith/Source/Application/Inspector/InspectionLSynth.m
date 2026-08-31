//==============================================================================
//
// File:		InspectionLSynth.m
//
// Purpose:		Inspector Controller for an LDraw LSynth block.
//
//				This inspector panel is loaded by the main Inspector class.
//
//  Created by Robin Macharg
//  Copyright 2012. All rights reserved.
//==============================================================================
#import "InspectionLSynth.h"

#import <LDrawCore/LDrawLSynth.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawPartLibrary.h>

#import <LDrawFeatures/LSynthConfiguration.h>

#import "LDrawView.h"

@implementation InspectionLSynth

//@synthesize typePopup;


//========== init ==============================================================
//
// Purpose:		Load the interface for this inspector.
//
//==============================================================================
- (id) init
{
    self = [super init];
	
    NSArray *nibObjects = nil;
    if ([[NSBundle mainBundle] loadNibNamed:@"InspectorLSynth" owner:self topLevelObjects:&nibObjects]) {
		topLevelObjects = nibObjects;
    } else {
		NSLog(@"Couldn't load InspectorLSynth.xib");
    }

    return self;
	
}//end init


#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== commitChanges: ====================================================
//
// Purpose:		Called in response to the conclusion of editing in the palette.
//
//==============================================================================
- (void) commitChanges:(id)sender
{
    LDrawLSynth	*representedObject	= [self object];

    // Update the object
	LSynthClassT	classType	= (LSynthClassT)[[lsynthClassChooserMatrix selectedCell] tag];
	NSArray 		*types		= [[LSynthConfiguration sharedInstance] typesForLSynthClass:classType];

    [representedObject setLsynthClass:(LSynthClassT)[[lsynthClassChooserMatrix selectedCell] tag]];
    [representedObject setLsynthType:[LSynthConfiguration typeNameAtIndex:[typePopup indexOfSelectedItem]
																  inTypes:types]];

    [[LSynthConfiguration sharedInstance] applyDefaultConstraintsToLSynth:representedObject
																classType:(LSynthClassT)[[sender selectedCell] tag]];

    // We've made a change so resynthesis is probably required.
    [representedObject invalCache:ContainerInvalid];

	[super commitChanges:sender];
}//end commitChanges:

//========== setObject: ========================================================
//
// Purpose:		Called as part of the palette initialisation, after we know which
//              object we refer to.
//
//==============================================================================
- (void) setObject:(id)newObject
{
    [super setObject:newObject];

//    // At this point in the inspector initialization we have the object in question
//    // so our delegate and datasource protocol methods can answer questions sensibly
//    [constraintTable setDelegate:self];
//    [constraintTable setDataSource:self];
}


//========== revert ============================================================
//
// Purpose:		Restores the palette to reflect the state of the object.
//				This method is called automatically when the object to inspect
//				is set.
//
//==============================================================================
- (IBAction) revert:(id)sender
{
    LDrawLSynth *representedObject = [self object];
    
    // Set the part label
    [lsynthPartLabel setStringValue:[representedObject browsingDescription]];
    
    // Set the synthesized part count
    [synthesizedPartCount setStringValue:[NSString stringWithFormat:NSLocalizedString([LSynthConfiguration approximatePieceCountFormatKey], nil), [representedObject synthesizedPartsCount]]];
    
    // Set the Type label
    [self updateSynthTypeLabel:[representedObject lsynthClass]];

    // The class selection radio buttons are tagged with values matching the
    // LSynthConfiguration class enumeration - Part=1, Hose=2 and Band=3
    [lsynthClassChooserMatrix selectCellWithTag:[representedObject lsynthClass]];

    // Set the color well
    [colorWell setLDrawColor:[representedObject LDrawColor]];

    // Fill the type dropdown
    [self populateTypes:[representedObject lsynthClass]];

    // Fill the default constraints dropdown
    [self populateDefaultConstraint:[representedObject lsynthClass]];

	[super revert:sender];
}//end revert:

#pragma mark -
#pragma mark UTILITIES
#pragma mark -

//========== populateTypes: ====================================================
//
// Purpose:		Populate the Types dropdown
//
//==============================================================================
- (void) populateTypes:(int)classTag
{
    NSArray *types = [[LSynthConfiguration sharedInstance] typesForLSynthClass:classTag];
    NSArray *titles = [LSynthConfiguration typePopupTitlesFromTypes:types];

    // Populate the dropdown
    [typePopup removeAllItems];
    if (titles != nil) {
        int index = 0;
        for (NSString *title in titles) {

            // Add each entry
            [typePopup addItemWithTitle:title];
            [[typePopup itemAtIndex:index] setTag:index];
            index++;
        }

        NSUInteger selected = [LSynthConfiguration indexOfTypeNamed:[[self object] lsynthType]
                                                            inTypes:types];
        if(selected != NSNotFound)
        {
            [typePopup selectItemAtIndex:selected];
        }
    }
}

//========== populateDefaultConstraint: ========================================
//
// Purpose:		Populate the default-contraint dropdown
//
//==============================================================================

- (void) populateDefaultConstraint:(int)classTag
{
    NSDictionary *selectedType = [LSynthConfiguration selectedTypeForClass:(LSynthClassT)classTag
                                                                   atIndex:[typePopup indexOfSelectedItem]];

    LSynthClassT constraintClass = [LSynthConfiguration constraintClassForSynthClass:(LSynthClassT)classTag
                                                                        selectedType:selectedType];
    NSArray *constraints = [[LSynthConfiguration sharedInstance] constraintsForClass:constraintClass];
    NSString *defaultConstraint = [LSynthConfiguration defaultConstraintForClass:constraintClass];
    NSArray *descriptions = [LSynthConfiguration constraintPopupDescriptionsFromConstraints:constraints];

    [constraintDefaultPopup removeAllItems];

    if (constraints != nil) {
        NSUInteger constraintIndex = 0;
        for (NSString *constraintDescription in descriptions) {

            // Add each entry...
            [constraintDefaultPopup addItemWithTitle:constraintDescription];
            NSMenuItem *menuItem = [constraintDefaultPopup itemAtIndex:([constraintDefaultPopup numberOfItems]-1)];
            // Store the constraint details. Used in makeConstraintsDefaultForClass
            [menuItem setRepresentedObject:[constraints objectAtIndex:constraintIndex]];
            constraintIndex++;
        }

        NSUInteger defaultIndex = [LSynthConfiguration indexOfConstraintNamed:defaultConstraint
                                                                inConstraints:constraints];
        if(defaultIndex != NSNotFound)
        {
            [constraintDefaultPopup selectItemAtIndex:defaultIndex];
        }
    }
}


////========== selectType:fromTypes: =============================================
////
//// Purpose:		Select a specific type
////
////==============================================================================
//-(void) selectType:(NSString *)lsynthType
//{
////    [typePopup selectItemWithTitle:lsynthType];
//}

#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== partClassChanged: =================================================
//
// Purpose:		The user has changed the class of the part.  We only change values
//              in the UI.  The commitChanges method takes care of applying these
//              to the part.
//
//==============================================================================
- (IBAction)partClassChanged:(id)sender
{
    LDrawLSynth *representedObject = [self object];

    // Check that we're actually selecting a different class of synthesized part
    if ([[sender selectedCell] tag] != [representedObject lsynthClass]) {
        
        [self updateSynthTypeLabel:(LSynthClassT)[[sender selectedCell] tag]];

        // Populate the types dropdown correctly
        [self populateTypes:(int)[[sender selectedCell] tag]];

        // Select the default type for the class
        NSString *typeName = [LSynthConfiguration defaultTypeNameForClass:(LSynthClassT)[[sender selectedCell] tag]];
        NSDictionary *type = nil;
        if(typeName != nil)
        {
            type = [[LSynthConfiguration sharedInstance] typeForTypeName:typeName];
        }

        if (type != nil) {
            [typePopup selectItemWithTitle:[type valueForKey:@"title"]];
        }
        else {
            [typePopup selectItemAtIndex:0];
        }

        // Populate the constraints dropdown and select the default
        [self populateDefaultConstraint:(int)[[sender selectedCell] tag]];

        // Finish and invoke redisplay
        [self finishedEditing:sender];
    }
}

//========== makeConstraintsDefaultForClass: ===================================
//
// Purpose:		If the synth class has changed convert the constraints to an
//              appropriate default.  Hoses only work with hose constraints,
//              bands similarly.
//
//              TODO: Our defaults are arbitrary but could be preferences
//
//==============================================================================
- (IBAction)makeConstraintsDefaultForClass:(id)sender {
    LDrawLSynth *representedObject = [self object];
    NSString *partName = [[[constraintDefaultPopup selectedItem] representedObject] valueForKey:@"partName"];

    [[LSynthConfiguration sharedInstance] applyConstraintPartName:partName toLSynth:representedObject];

    // Finish and invoke redisplay
    [self finishedEditing:sender];
    [self revert:sender];
}

//========== partTypeChanged: ==================================================
//
// Purpose:		The user has changed the part type in the dropdown.
//
//==============================================================================
- (IBAction)partTypeChanged:(id)sender
{
    // Finish and invoke redisplay
    [self finishedEditing:sender];
    [self revert:sender];
}

#pragma mark -
#pragma mark UTILITIES
#pragma mark -

//========== updateSynthTypeLabel: =============================================
//
// Purpose:		Show the label type.
//
//==============================================================================
- (void) updateSynthTypeLabel:(LSynthClassT)tag
{
    NSString *label = [LSynthConfiguration typeLabelForClass:tag];
    if(label != nil)
    {
        [SynthTypeLabel setStringValue:label];
    }
}


#pragma mark -
#pragma mark DESTRUCTOR
#pragma mark -

//========== dealloc ============================================================
//
// Purpose:		Cleanup
//
//==============================================================================
- (void) dealloc
{
	topLevelObjects = nil;

}//end dealloc


@end
