//==============================================================================
//
// File:		MinifigureDialogController.m
//
// Purpose:		Handles the Minifigure Generator dialog.
//
//  Created by Allen Smith on 7/2/06.
//  Copyright 2006. All rights reserved.
//==============================================================================
#import "MinifigureDialogController.h"

#import <LDrawCore/LDrawColorLibrary.h>
#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawPart.h>

#import <LDrawFeatures/LDrawMinifigureAssembler.h>
#import <LDrawFeatures/LDrawMinifigureSnapshot.h>
#import <LDrawFeatures/LDrawMLCadIni.h>

#import "LDrawColorWell.h"
#import "LDrawView.h"
#import "LDrawViewerContainer.h"

@interface MinifigureDialogController ()
{
	LDrawMLCadIni	*iniFile;
	NSString		*minifigureName;
	LDrawMPDModel	*minifigure;
	NSArray			*topLevelObjects;	// holds NIB objects
	
	BOOL		hasHat;
	BOOL		hasNeckAccessory;
	BOOL		hasHips;
	BOOL		hasRightArm;
	BOOL		hasRightHand;
	BOOL		hasRightHandAccessory;
	BOOL		hasRightLeg;
	BOOL		hasRightLegAccessory;
	BOOL		hasLeftArm;
	BOOL		hasLeftHand;
	BOOL		hasLeftHandAccessory;
	BOOL		hasLeftLeg;
	BOOL		hasLeftLegAccessory;
	
	float		headElevation;
	
	float		angleOfHat;
	float		angleOfHead;
	float		angleOfNeck;
	float		angleOfRightArm;
	float		angleOfRightHand;
	float		angleOfRightHandAccessory;
	float		angleOfRightLeg;
	float		angleOfRightLegAccessory;
	float		angleOfLeftArm;
	float		angleOfLeftHand;
	float		angleOfLeftHandAccessory;
	float		angleOfLeftLeg;
	float		angleOfLeftLegAccessory;
}

//top-level objects

@property (nonatomic, strong) IBOutlet NSObjectController* 		objectController;
@property (nonatomic, weak)   IBOutlet NSNumberFormatter*		degreesFormatter;
@property (nonatomic, strong) IBOutlet NSArrayController* 		hatsController;
@property (nonatomic, strong) IBOutlet NSArrayController* 		headsController;
@property (nonatomic, strong) IBOutlet NSArrayController* 		necksController;
@property (nonatomic, strong) IBOutlet NSArrayController* 		torsosController;
@property (nonatomic, strong) IBOutlet NSArrayController* 		rightArmsController;
@property (nonatomic, strong) IBOutlet NSArrayController* 		rightHandsController;
@property (nonatomic, strong) IBOutlet NSArrayController* 		rightHandAccessoriesController;
@property (nonatomic, strong) IBOutlet NSArrayController* 		leftArmsController;
@property (nonatomic, strong) IBOutlet NSArrayController* 		leftHandsController;
@property (nonatomic, strong) IBOutlet NSArrayController* 		leftHandAccessoriesController;
@property (nonatomic, strong) IBOutlet NSArrayController* 		hipsController;
@property (nonatomic, strong) IBOutlet NSArrayController* 		rightLegsController;
@property (nonatomic, strong) IBOutlet NSArrayController* 		rightLegAccessoriesController;
@property (nonatomic, strong) IBOutlet NSArrayController* 		leftLegsController;
@property (nonatomic, strong) IBOutlet NSArrayController* 		leftLegAccessoriesController;

@property (nonatomic, strong) IBOutlet NSPanel*					minifigureGeneratorPanel;

// Panel widgets

@property (nonatomic, weak) IBOutlet LDrawViewerContainer*	minifigurePreview;
@property (nonatomic, weak) IBOutlet LDrawColorWell*		hatsColorWell;
@property (nonatomic, weak) IBOutlet LDrawColorWell*		headsColorWell;
@property (nonatomic, weak) IBOutlet LDrawColorWell*		necksColorWell;
@property (nonatomic, weak) IBOutlet LDrawColorWell*		torsosColorWell;
@property (nonatomic, weak) IBOutlet LDrawColorWell*		rightArmsColorWell;
@property (nonatomic, weak) IBOutlet LDrawColorWell*		rightHandsColorWell;
@property (nonatomic, weak) IBOutlet LDrawColorWell*		rightHandAccessoriesColorWell;
@property (nonatomic, weak) IBOutlet LDrawColorWell*		leftArmsColorWell;
@property (nonatomic, weak) IBOutlet LDrawColorWell*		leftHandsColorWell;
@property (nonatomic, weak) IBOutlet LDrawColorWell*		leftHandAccessoriesColorWell;
@property (nonatomic, weak) IBOutlet LDrawColorWell*		hipsColorWell;
@property (nonatomic, weak) IBOutlet LDrawColorWell*		rightLegsColorWell;
@property (nonatomic, weak) IBOutlet LDrawColorWell*		rightLegAccessoriesColorWell;
@property (nonatomic, weak) IBOutlet LDrawColorWell*		leftLegsColorWell;
@property (nonatomic, weak) IBOutlet LDrawColorWell*		leftLegAccessoriesColorWell;

@end

@implementation MinifigureDialogController

//========== awakeFromNib ======================================================
//
// Purpose:		Brings the Minifigure Generator dialog onscreen.
//
//==============================================================================
- (void) awakeFromNib
{
	[_minifigurePreview.glView setAcceptsFirstResponder:NO];
	[_minifigurePreview.glView setZoomPercentage:[LDrawMinifigureAssembler generatorPreviewDefaultZoomPercentage]];
	
	[_minifigurePreview.glView	setAutosaveName:[LDrawMinifigureAssembler generatorPreviewAutosaveName]];
	[_minifigurePreview.glView	restoreConfiguration];
	
}//end awakeFromNib


#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//========== init ==============================================================
//
// Purpose:		Creates the Minifigure Generator dialog.
//
//==============================================================================
- (id) init
{
	self = [super init];
	
	iniFile = [LDrawMLCadIni iniFile]; // KVC: XIB binds array controllers to iniFile.minifigure*
	[self setMinifigureName:NSLocalizedString([LDrawMinifigureAssembler untitledMinifigureLocalizationKey], nil)];
	
	//we'll call -generateMinifigure: when the dialog is ready and loaded with 
	// all its values.
	
	NSArray *nibObjects = nil;
	[[NSBundle mainBundle] loadNibNamed:@"MinifigureGenerator" owner:self topLevelObjects:&nibObjects];
	topLevelObjects = nibObjects;
	
	return self;
	
}//end init


#pragma mark -
#pragma mark ACCESSORS
#pragma mark -
//this is all to appease bindings. Hey, at least I wrote the code with grep!

//========== minifigure ========================================================
//
// Purpose:		Returns the minifigure we generated!
//
//==============================================================================
- (LDrawMPDModel *) minifigure
{
	return minifigure;
	
}//end minifigure


//========== setMinifigure: ====================================================
//
// Purpose:		Updates the generated minifigure and redisplays him.
//
//==============================================================================
- (void) setMinifigure:(LDrawMPDModel *)newMinifigure
{
	self->minifigure = newMinifigure;
	
	[_minifigurePreview.glView setLDrawDirective:newMinifigure];
	
}//end setMinifigure:


//========== setHas<PartX> =====================================================
//
// Purpose:		Set accessors for whether the given part is included in the 
//				minifigure.
//
//==============================================================================
- (void) setHasHat:(BOOL)flag						{hasHat = flag;						}
- (void) setHasNeckAccessory:(BOOL)flag				{hasNeckAccessory = flag;			}
- (void) setHasHips:(BOOL)flag						{hasHips = flag;					}
- (void) setHasRightArm:(BOOL)flag					{hasRightArm = flag;				}
- (void) setHasRightHand:(BOOL)flag					{hasRightHand = flag;				}
- (void) setHasRightHandAccessory:(BOOL)flag		{hasRightHandAccessory = flag;		}
- (void) setHasRightLeg:(BOOL)flag					{hasRightLeg = flag;				}
- (void) setHasRightLegAccessory:(BOOL)flag			{hasRightLegAccessory = flag;		}
- (void) setHasLeftArm:(BOOL)flag					{hasLeftArm = flag;					}
- (void) setHasLeftHand:(BOOL)flag					{hasLeftHand = flag;				}
- (void) setHasLeftHandAccessory:(BOOL)flag			{hasLeftHandAccessory = flag;		}
- (void) setHasLeftLeg:(BOOL)flag					{hasLeftLeg = flag;					}
- (void) setHasLeftLegAccessory:(BOOL)flag			{hasLeftLegAccessory = flag;		}

//========== setHeadElevation: =================================================
//
// Purpose:		Whether the neck piece causes the head to be elevated a few 
//				units.
//
//==============================================================================
- (void) setHeadElevation:(float)newElevation		{headElevation = newElevation;		}


//========== setAngleOf<PartX>: ================================================
//
// Purpose:		Set the angle of the given part.
//
//==============================================================================
- (void) setAngleOfHat:(float)angle					{angleOfHat					= angle; }
- (void) setAngleOfHead:(float)angle				{angleOfHead				= angle; }
- (void) setAngleOfNeck:(float)angle				{angleOfNeck				= angle; }
- (void) setAngleOfRightArm:(float)angle			{angleOfRightArm			= angle; }
- (void) setAngleOfRightHand:(float)angle			{angleOfRightHand			= angle; }
- (void) setAngleOfRightHandAccessory:(float)angle	{angleOfRightHandAccessory	= angle; }
- (void) setAngleOfRightLeg:(float)angle			{angleOfRightLeg			= angle; }
- (void) setAngleOfRightLegAccessory:(float)angle	{angleOfRightLegAccessory	= angle; }
- (void) setAngleOfLeftArm:(float)angle				{angleOfLeftArm				= angle; }
- (void) setAngleOfLeftHand:(float)angle			{angleOfLeftHand			= angle; }
- (void) setAngleOfLeftHandAccessory:(float)angle	{angleOfLeftHandAccessory	= angle; }
- (void) setAngleOfLeftLeg:(float)angle				{angleOfLeftLeg				= angle; }
- (void) setAngleOfLeftLegAccessory:(float)angle	{angleOfLeftLegAccessory	= angle; }


//========== setMinifigureName: ================================================
//
// Purpose:		Sets the name which will be given to the new minifigure model.
//
//==============================================================================
- (void) setMinifigureName:(NSString *)newName
{
	minifigureName = newName;
	
	[self->minifigure setModelDisplayName:newName];
	
}//end setMinifigureName:


#pragma mark -
#pragma mark ACTIONS
#pragma mark -


//========== runModal ==========================================================
//
// Purpose:		Displays the dialog, returing NSModalResponseOK or NSModalResponseCancel as 
//				appropriate.
//
//==============================================================================
- (NSInteger) runModal
{
	NSInteger		returnCode	= NSModalResponseCancel;
	
	//set the values
	[self restoreFromPreferences];
	[self generateMinifigure:self];
	
	//Run the dialog.
	returnCode = [NSApp runModalForWindow:self.minifigureGeneratorPanel];
	
	// break retain cycle--NSObjectController retains its content (us!)
	[_objectController setContent:nil];
	
	return returnCode;
	
}//end runModal


//========== okButtonClicked ===================================================
//
// Purpose:		OK clicked, dismiss dialog.
//
//==============================================================================
- (IBAction) okButtonClicked:(id)sender
{
	[NSApp stopModalWithCode:NSModalResponseOK];
	[self.minifigureGeneratorPanel close];
}//end okButtonClicked


//========== cancelButtonClicked ===============================================
//
// Purpose:		Cancel clicked, dismiss the dialog.
//
//==============================================================================
- (IBAction) cancelButtonClicked:(id)sender
{
	[self.minifigureGeneratorPanel close];
	[NSApp stopModalWithCode:NSModalResponseCancel];
}//end cancelButtonClicked


#pragma mark -

//========== colorWellChanged: =================================================
//
// Purpose:		One of the color wells controlling part colors has changed. We 
//				need to regenerate the minifigure.
//
// Notes:		Since the LDrawColorWell is a custom widget, I haven't bothered 
//				implementing bindings on it. Sigh...
//
//==============================================================================
- (IBAction) colorWellChanged:(id)sender
{
	[self generateMinifigure:sender];
	
}//end colorWellChanged:


//========== generateMinifigure ================================================
//
// Purpose:		This is it! It's time to manufacure the minifigure!
//
//==============================================================================
- (IBAction) generateMinifigure:(id)sender
{
	if (_objectController.content == nil) {
		return;
	}

	LDrawMinifigureSpec *spec = [LDrawMinifigureSpec new];
	spec.modelName = self->minifigureName;

	[spec setPartsInSlotOrder:[LDrawMinifigureSpec copiedPartsFromSlotSelections:@[
		[_hatsController					selectedObjects],
		[_headsController					selectedObjects],
		[_necksController					selectedObjects],
		[_torsosController					selectedObjects],
		[_leftArmsController				selectedObjects],
		[_leftHandsController				selectedObjects],
		[_leftHandAccessoriesController		selectedObjects],
		[_rightArmsController				selectedObjects],
		[_rightHandsController				selectedObjects],
		[_rightHandAccessoriesController	selectedObjects],
		[_hipsController					selectedObjects],
		[_leftLegsController				selectedObjects],
		[_leftLegAccessoriesController		selectedObjects],
		[_rightLegsController				selectedObjects],
		[_rightLegAccessoriesController		selectedObjects],
	]]];
	[spec applyColorsInSlotOrder:@[
		[_hatsColorWell					LDrawColor],
		[_headsColorWell				LDrawColor],
		[_necksColorWell				LDrawColor],
		[_torsosColorWell				LDrawColor],
		[_leftArmsColorWell				LDrawColor],
		[_leftHandsColorWell			LDrawColor],
		[_leftHandAccessoriesColorWell	LDrawColor],
		[_rightArmsColorWell			LDrawColor],
		[_rightHandsColorWell			LDrawColor],
		[_rightHandAccessoriesColorWell	LDrawColor],
		[_hipsColorWell					LDrawColor],
		[_leftLegsColorWell				LDrawColor],
		[_leftLegAccessoriesColorWell	LDrawColor],
		[_rightLegsColorWell			LDrawColor],
		[_rightLegAccessoriesColorWell	LDrawColor],
	]];
	[spec takeInclusionAndAnglesFromTarget:self];

	[self setMinifigure:[LDrawMinifigureAssembler assembleSpec:spec]];

}//end generateMinifigure


#pragma mark -
#pragma mark DELEGATES
#pragma mark -

//========== windowWillClose: ==================================================
//
// Purpose:		Dialog is closing; save valuse.
//
//==============================================================================
- (void)windowWillClose:(NSNotification *)aNotification
{
	[self saveToPreferences];
	
}//end windowWillClose:


#pragma mark -
#pragma mark PERSISTENCE
#pragma mark -

//========== restoreFromPreferences ============================================
//
// Purpose:		Reads previous values out of preferences.
//
// Notes:		Wow what a horrific method.
//
//==============================================================================
- (void) restoreFromPreferences
{
	NSUserDefaults            *userDefaults = [NSUserDefaults standardUserDefaults];
	LDrawColorLibrary         *colorLibrary = [LDrawColorLibrary sharedColorLibrary];
	LDrawMinifigureSnapshot   *snap         = [LDrawMinifigureSnapshot snapshotFromUserDefaults:userDefaults];

	[snap applyInclusionAndAnglesToTarget:self];

	NSArray *wells = @[
		_hatsColorWell,
		_headsColorWell,
		_necksColorWell,
		_torsosColorWell,
		_rightArmsColorWell,
		_rightHandsColorWell,
		_rightHandAccessoriesColorWell,
		_leftArmsColorWell,
		_leftHandsColorWell,
		_leftHandAccessoriesColorWell,
		_hipsColorWell,
		_rightLegsColorWell,
		_rightLegAccessoriesColorWell,
		_leftLegsColorWell,
		_leftLegAccessoriesColorWell,
	];
	NSArray *codes = [snap colorCodesInSlotOrder];
	NSUInteger i;
	NSUInteger wellCount = MIN([wells count], [codes count]);
	for(i = 0; i < wellCount; i++)
	{
		[[wells objectAtIndex:i] setLDrawColor:
			[colorLibrary colorForCode:(LDrawColorT)[[codes objectAtIndex:i] integerValue]]];
	}

	NSArray *controllers = @[
		_hatsController,
		_headsController,
		_necksController,
		_torsosController,
		_rightArmsController,
		_rightHandsController,
		_rightHandAccessoriesController,
		_leftArmsController,
		_leftHandsController,
		_leftHandAccessoriesController,
		_hipsController,
		_rightLegsController,
		_rightLegAccessoriesController,
		_leftLegsController,
		_leftLegAccessoriesController,
	];
	NSArray *names = [snap partNamesInSlotOrder];
	NSUInteger nameCount = MIN([controllers count], [names count]);
	for(i = 0; i < nameCount; i++)
	{
		[self selectPartWithName:[names objectAtIndex:i]
					inController:[controllers objectAtIndex:i]];
	}

}//end restoreFromPreferences


//========== saveToPreferences =================================================
//
// Purpose:		Writes current values out of preferences.
//
// Notes:		Wow what a horrific method.
//
//==============================================================================
- (void) saveToPreferences
{
	NSUserDefaults          *userDefaults = [NSUserDefaults standardUserDefaults];
	LDrawMinifigureSnapshot *snap         = [LDrawMinifigureSnapshot new];

	[snap takeInclusionAndAnglesFromTarget:self];

	[snap setColorCodesFromColors:@[
		[_hatsColorWell					LDrawColor],
		[_headsColorWell				LDrawColor],
		[_necksColorWell				LDrawColor],
		[_torsosColorWell				LDrawColor],
		[_rightArmsColorWell			LDrawColor],
		[_rightHandsColorWell			LDrawColor],
		[_rightHandAccessoriesColorWell	LDrawColor],
		[_leftArmsColorWell				LDrawColor],
		[_leftHandsColorWell			LDrawColor],
		[_leftHandAccessoriesColorWell	LDrawColor],
		[_hipsColorWell					LDrawColor],
		[_rightLegsColorWell			LDrawColor],
		[_rightLegAccessoriesColorWell	LDrawColor],
		[_leftLegsColorWell				LDrawColor],
		[_leftLegAccessoriesColorWell	LDrawColor],
	]];
	[snap setPartNamesFromSlotSelections:@[
		[_hatsController					selectedObjects],
		[_headsController					selectedObjects],
		[_necksController					selectedObjects],
		[_torsosController					selectedObjects],
		[_rightArmsController				selectedObjects],
		[_rightHandsController				selectedObjects],
		[_rightHandAccessoriesController	selectedObjects],
		[_leftArmsController				selectedObjects],
		[_leftHandsController				selectedObjects],
		[_leftHandAccessoriesController		selectedObjects],
		[_hipsController					selectedObjects],
		[_rightLegsController				selectedObjects],
		[_rightLegAccessoriesController		selectedObjects],
		[_leftLegsController				selectedObjects],
		[_leftLegAccessoriesController		selectedObjects],
	]];

	[snap writeToUserDefaults:userDefaults];

	//and write it out at last!
	[userDefaults synchronize];
	
}//end saveToPreferences


//========== selectPartWithName:inController: ==================================
//
// Purpose:		Parts are identified in user defaults by their reference name, 
//				such as "3001.dat". This method selects the actual part object 
//				based on the name.
//
//==============================================================================
- (void) selectPartWithName:(NSString *) name
			   inController:(NSArrayController *)controller
{
	NSUInteger index = [LDrawMinifigureSnapshot indexOfPartNamed:name
														 inParts:[controller arrangedObjects]];
	if(index != NSNotFound)
	{
		[controller setSelectionIndex:index];
	}
	
}//end selectPartWithName:inController:


#pragma mark -
#pragma mark DESTRUCTOR
#pragma mark -

//========== dealloc ===========================================================
//
// Purpose:		
//
//==============================================================================
- (void) dealloc
{
    topLevelObjects = nil;
	
}//end dealloc


@end
