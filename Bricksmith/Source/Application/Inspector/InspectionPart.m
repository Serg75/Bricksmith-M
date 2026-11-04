//==============================================================================
//
// File:		InspectionPart.m
//
// Purpose:		Inspector Controller for an LDrawPart.
//
//				This inspector panel is loaded by the main Inspector class.
//
//  Created by Allen Smith on 3/26/05.
//  Copyright 2005. All rights reserved.
//==============================================================================
#import "InspectionPart.h"

#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawPartLibrary.h>

#import <LDrawEditing/LDrawInspection.h>
#import <LDrawFeatures/LDrawPartLimitPresentation.h>

#import "LDrawApplication.h"
#import "LDrawColorWell.h"
#import "LDrawDocument.h"
#import "PartReplacementMenu.h"
#import "PartsLimitController.h"
#import "PartsLimitManager.h"

@interface InspectionPart ()

// Top-level objects
@property (nonatomic, weak) IBOutlet				NSNumberFormatter*	formatterBasic;
@property (nonatomic, weak) IBOutlet				NSNumberFormatter*	formatterAngle;
@property (nonatomic, weak) IBOutlet				NSNumberFormatter*	formatterScale;

// Window widgets

@property (nonatomic, weak) IBOutlet	NSTextField*		partDescriptionField;
@property (nonatomic, weak) IBOutlet	NSTextField*		partNameField;
@property (nonatomic, weak) IBOutlet	NSButton*			replaceButton;
@property (nonatomic, weak) IBOutlet	LDrawColorWell*		colorWell;
@property (nonatomic, weak) IBOutlet	NSPopUpButton*		rotationTypePopUp;

@property (nonatomic, weak) IBOutlet	NSTextField*		locationXField;
@property (nonatomic, weak) IBOutlet	NSTextField*		locationYField;
@property (nonatomic, weak) IBOutlet	NSTextField*		locationZField;

@property (nonatomic, weak) IBOutlet	NSTextField*		rotationXField;
@property (nonatomic, weak) IBOutlet	NSTextField*		rotationYField;
@property (nonatomic, weak) IBOutlet	NSTextField*		rotationZField;

@property (nonatomic, weak) IBOutlet	NSTextField*		scaleXField;
@property (nonatomic, weak) IBOutlet	NSTextField*		scaleYField;
@property (nonatomic, weak) IBOutlet	NSTextField*		scaleZField;

@property (nonatomic, weak) IBOutlet	NSTextField*		shearXYField;
@property (nonatomic, weak) IBOutlet	NSTextField*		shearXZField;
@property (nonatomic, weak) IBOutlet	NSTextField*		shearYZField;

@property (nonatomic, strong)			NSArray*			topLevelObjects;	// holds NIB objects

@end

@implementation InspectionPart

//========== init ==============================================================
//
// Purpose:		Load the interface for this inspector.
//
//==============================================================================
- (id) init
{
    self = [super init];
	
    NSArray *nibObjects = nil;
    if ([[NSBundle mainBundle] loadNibNamed:@"InspectorPart" owner:self topLevelObjects:&nibObjects]) {
		self.topLevelObjects = nibObjects;
    } else {
		NSLog(@"Couldn't load InspectorPart.nib");
    }

	// The check runs after the edit, so the limit line is updated when it ends.
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(partsLimitDidCheck:)
												 name:PartsLimitDidCheckNotification
											   object:nil];
	
    return self;
	
}//end init


//========== awakeFromNib ======================================================
//==============================================================================
- (void) awakeFromNib
{
	NSImageSymbolConfiguration	*size	= [NSImageSymbolConfiguration configurationWithPointSize:10
																						  weight:NSFontWeightSemibold];
	NSImage						*arrow	= [NSImage imageWithSystemSymbolName:@"chevron.down"
													accessibilityDescription:NSLocalizedString(@"Replace With", nil)];

	[super awakeFromNib];

	[_replaceButton setImage:[arrow imageWithSymbolConfiguration:size]];
}


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
	LDrawPart			*representedObject	= [self object];
	TransformComponents	 oldComponents		= [representedObject transformComponents];
	Point3				 position			= [self coordinateValueFromFields:@[_locationXField, _locationYField, _locationZField]];
	Vector3				 scaling			= [self coordinateValueFromFields:@[_scaleXField, _scaleYField, _scaleZField]];
	Tuple3				 shear				= [self coordinateValueFromFields:@[_shearXYField, _shearXZField, _shearYZField]];
	
	[representedObject setDisplayName:[_partNameField stringValue]];
	
	[representedObject setTransformComponents:[LDrawInspection inspectorComponentsFromPosition:position
																				scalingPercent:scaling
																						 shear:shear
																				 oldComponents:oldComponents]];
	
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
	LDrawPart			*representedObject	= [self object];
	TransformComponents	 components			= [representedObject transformComponents];
	NSString			*description		= [[LDrawPartLibrary sharedPartLibrary] descriptionForPart:representedObject];
	Point3				 position			= ZeroPoint3;
	Vector3				 scaling			= ZeroPoint3;
	Tuple3				 shear				= ZeroPoint3;
	
	
	[self showDescription:description];
	[_partNameField setStringValue:[representedObject displayName]];
	
	[_colorWell setLDrawColor:[representedObject LDrawColor]];

	[LDrawInspection inspectorFieldsFromComponents:components
										  position:&position
									scalingPercent:&scaling
											 shear:&shear];
	
	[self setCoordinateValue:position onFields:@[_locationXField, _locationYField, _locationZField]];
	[self setCoordinateValue:scaling onFields:@[_scaleXField, _scaleYField, _scaleZField]];
	[self setCoordinateValue:shear onFields:@[_shearXYField, _shearXZField, _shearYZField]];
	
	//Rotation is a bit trickier since we have two different modes for the data 
	// entered. An absolute rotation means that the actual rotation angles for 
	// the part are displayed and edited. A relative rotation means that what-
	// ever we enter in is added to the current angles.
 	[self setRotationAngles];
	
	[super revert:sender];

    // Someone else might care that the part's changed
    [representedObject sendMessageToObservers:LDrawObserverObservedChanged];
	
}//end revert:


//========== setRotationAngles =================================================
//
// Purpose:		Fills in the rotation angles based on the data-entry mode:
//				absolute or relative.
//
//				An absolute rotation means that the actual rotation angles for 
//				the part are displayed and edited. A relative rotation means 
//				that whatever we enter in is *added to* the current angles.
//
//
//==============================================================================
- (void) setRotationAngles
{
	LDrawPart					*representedObject	= [self object];
	TransformComponents			 components			= [representedObject transformComponents];
	LDrawPartInspectorRotationT	 rotationType		= (LDrawPartInspectorRotationT)[[_rotationTypePopUp selectedItem] tag];
	Tuple3						 rotation			= [LDrawInspection partInspectorRotationDegreesForComponents:components
																									rotationType:rotationType];
	
	[_rotationXField setDoubleValue:rotation.x];
	[_rotationYField setDoubleValue:rotation.y];
	[_rotationZField setDoubleValue:rotation.z];
}//end setRotationAngles


#pragma mark -

//========== applyRotationClicked: =============================================
//
// Purpose:		The user has entered new rotation values and now wants them to 
//				take effect. I set up this apply mechanism because it seemed 
//				like it would be odd for the rotations to take effect instantly.
//
//				This method is something like an alternate form of 
//				-finishedEditing: which modifies a different set of values.
//
//==============================================================================
- (IBAction) applyRotationClicked:(id)sender
{
	LDrawPart					*representedObject  = [self object];
	LDrawDocument				*currentDocument    = [[NSDocumentController sharedDocumentController] currentDocument];
	LDrawPartInspectorRotationT	 rotationType       = (LDrawPartInspectorRotationT)[[_rotationTypePopUp selectedItem] tag];
	
	//Save out the current state.
	[currentDocument preserveDirectiveState:representedObject];
	
	if(rotationType == LDrawPartInspectorRotationRelative)
	{
		Tuple3 additiveRotation;
		
		additiveRotation.x = [_rotationXField doubleValue];
		additiveRotation.y = [_rotationYField doubleValue];
		additiveRotation.z = [_rotationZField doubleValue];
		
		[representedObject rotateByDegrees:additiveRotation];
	}
	//An absolute rotation.
	else{
		TransformComponents components = [[self object] transformComponents];
		Tuple3 rotationDegrees = ZeroPoint3;
		rotationDegrees.x = [_rotationXField doubleValue];
		rotationDegrees.y = [_rotationYField doubleValue];
		rotationDegrees.z = [_rotationZField doubleValue];
		
		[representedObject setTransformComponents:[LDrawInspection componentsByApplyingAbsoluteRotationDegrees:rotationDegrees
																								  toComponents:components]];
	}
	
	//Note that the part has changed.
	[representedObject noteNeedsDisplay];
	
	//For a relative rotation, prepare for the next additive rotation by 
	// resetting the rotations values to zero
	[self setRotationAngles];

    // Someone else might care that the part's orientation has changed
    [representedObject sendMessageToObservers:LDrawObserverObservedChanged];
	
}//end applyRotationClicked:


//========== locationEndedEditing: =============================================
//
// Purpose:		The user had been editing the coordinate; now he has stopped. 
//				We need to find out if he actually changed something. If so, 
//				update the object.
//
//==============================================================================
- (IBAction) locationEndedEditing:(id)sender
{
	Point3				formContents	= [self coordinateValueFromFields:@[_locationXField, _locationYField, _locationZField]];
	TransformComponents	components		= [[self object] transformComponents];
	
	//If the values really did change, then update.
	if([LDrawInspection inspectorPoint:formContents differsFromPoint:components.translate])
	{
		[self finishedEditing:sender];
	}
	
}//end locationEndedEditing:


//========== partNameEndedEditing: =============================================
//
// Purpose:		The user had been editing the part name; now he has stopped. 
//				We need to find out if he actually changed something. If so, 
//				update the object.
//
//==============================================================================
- (IBAction) partNameEndedEditing:(id)sender
{
	NSString *newName = [_partNameField stringValue];
	NSString *oldName = [[self object] displayName];
	
	if([oldName isEqualToString:newName] == NO){
		[self finishedEditing:sender];
		[self revert:sender];
	}
	
}//end partNameEndedEditing:


//========== showReplacements: =================================================
//
// Purpose:		Opens the parts that can replace this one just under the part
//				name, lined up with it.
//
//==============================================================================
- (IBAction) showReplacements:(id)sender
{
	NSMenu	*menu	= [[NSMenu alloc] initWithTitle:@""];
	NSRect	 field	= [_partNameField bounds];
	CGFloat	 below	= [_partNameField isFlipped] ? NSMaxY(field) + 2 : NSMinY(field) - 2;

	[[[self documentOfObject] partReplacementMenu] fillMenu:menu forParts:@[[self object]]];
	[menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(NSMinX(field), below) inView:_partNameField];

}//end showReplacements:


//========== rotationTypeChanged: ==============================================
//
// Purpose:		The pop-up menu specifying the rotation type has changed.
//
//==============================================================================
- (IBAction) rotationTypeChanged:(id)sender
{
	
	[self setRotationAngles];
		
}//end rotationTypeChanged:


//========== scalingEndedEditing: ==============================================
//
// Purpose:		The user had been editing the scaling percentages; now he has 
//				stopped. 
//				We need to find out if he actually changed something. If so, 
//				update the object.
//
//==============================================================================
- (IBAction) scalingEndedEditing:(id)sender
{
	Vector3				formContents	= [self coordinateValueFromFields:@[_scaleXField, _scaleYField, _scaleZField]];
	TransformComponents	components		= [[self object] transformComponents];

	//If the values really did change, then update.
	if([LDrawInspection inspectorScalingPercent:formContents differsFromComponents:components])
	{
		[self finishedEditing:sender];
	}
		
}//end scalingEndedEditing:


//========== shearEndedEditing: ================================================
//
// Purpose:		The user had been editing the scaling percentages; now he has 
//				stopped. 
//				We need to find out if he actually changed something. If so, 
//				update the object.
//
//==============================================================================
- (IBAction) shearEndedEditing:(id)sender
{
	Vector3				formContents	= [self coordinateValueFromFields:@[_shearXYField, _shearXZField, _shearYZField]];
	TransformComponents	components		= [[self object] transformComponents];
	
	//If the values really did change, then update.
	// (please disregard the meaningless x, y, and z tags in the formContents.)
	if([LDrawInspection inspectorShear:formContents differsFromComponents:components])
	{
		[self finishedEditing:sender];
	}
		
}//end shearEndedEditing:


#pragma mark -
#pragma mark UTILITIES
#pragma mark -

//========== showDescription: ==================================================
//
// Purpose:		Shows the part's description, and below it how the part breaks
//				the parts limit. The description wraps when both fit in the
//				field, and keeps to one line otherwise.
//
//==============================================================================
- (void) showDescription:(NSString *)description
{
	LDrawDocument				*document	= [self documentOfObject];
	LDrawPart					*part		= [self object];
	NSString					*limitLine	= [[document partsLimitController] limitLineForPart:part];
	NSFont						*font		= [_partDescriptionField font];
	NSMutableParagraphStyle		*oneLine	= [[NSMutableParagraphStyle alloc] init];
	NSDictionary				*plain		= nil;
	NSDictionary				*marked		= nil;
	NSColor						*color		= nil;
	NSAttributedString			*limitText	= nil;
	NSMutableAttributedString	*text		= nil;
	NSCell						*measure	= [[_partDescriptionField cell] copy];
	NSRect						 bounds		= [_partDescriptionField bounds];
	NSSize						 needed		= NSZeroSize;

	if(limitLine == nil)
	{
		[_partDescriptionField setStringValue:description];
		[_partDescriptionField setToolTip:description]; //in case it overflows the field.
		return;
	}

	// The color of the part's badge in File Contents.
	color = [PartsLimitManager colorForBadgeTint:
			 [LDrawPartLimitPresentation badgeTintForStatus:[part limitStatus]]];

	[oneLine setLineBreakMode:NSLineBreakByTruncatingTail];
	plain		= @{NSFontAttributeName: font, NSParagraphStyleAttributeName: oneLine};
	marked		= @{NSFontAttributeName: font, NSParagraphStyleAttributeName: oneLine,
					NSForegroundColorAttributeName: color};
	limitText	= [[NSAttributedString alloc] initWithString:limitLine attributes:marked];
	text		= [[NSMutableAttributedString alloc] initWithString:[description stringByAppendingString:@"\n"]
														 attributes:@{NSFontAttributeName: font}];
	[text appendAttributedString:limitText];

	// A wrapped description that is too long would push the limit line out.
	[measure setAttributedStringValue:text];
	needed = [measure cellSizeForBounds:NSMakeRect(0, 0, NSWidth(bounds), CGFLOAT_MAX)];
	if(needed.height > NSHeight(bounds))
	{
		text = [[NSMutableAttributedString alloc] initWithString:[description stringByAppendingString:@"\n"]
													  attributes:plain];
		[text appendAttributedString:limitText];
	}

	// Without this, selecting the text redraws it without its colors.
	[_partDescriptionField setAllowsEditingTextAttributes:YES];
	[_partDescriptionField setAttributedStringValue:text];
	[_partDescriptionField setToolTip:[NSString stringWithFormat:@"%@\n%@", description, limitLine]];

}//end showDescription:


//========== documentOfObject ==================================================
//
// Purpose:		The document that holds the inspected part.
//
// Notes:		Not the current document: while another app is active or a
//				panel is key, there may be none.
//
//==============================================================================
- (LDrawDocument *) documentOfObject
{
	LDrawFile *file = [[self object] enclosingFile];

	for(NSDocument *document in [[NSDocumentController sharedDocumentController] documents])
	{
		if([document isKindOfClass:[LDrawDocument class]] && [(LDrawDocument *)document documentContents] == file)
			return (LDrawDocument *)document;
	}
	return nil;

}//end documentOfObject


#pragma mark -
#pragma mark NOTIFICATIONS
#pragma mark -

//========== partsLimitDidCheck: ===============================================
//
// Purpose:		Shows how the part stands after the latest check. Only the
//				description changes, so fields being edited keep their text.
//
//==============================================================================
- (void) partsLimitDidCheck:(NSNotification *)notification
{
	LDrawPart *part = [self object];

	if([part isKindOfClass:[LDrawPart class]])
		[self showDescription:[[LDrawPartLibrary sharedPartLibrary] descriptionForPart:part]];
}


#pragma mark -
#pragma mark DESTRUCTOR
#pragma mark -

//========== dealloc ===========================================================
//
// Purpose:		Abandon all hope ye who enter here.
//
//==============================================================================
- (void) dealloc
{
	self.topLevelObjects = nil;
	
}//end dealloc


@end
