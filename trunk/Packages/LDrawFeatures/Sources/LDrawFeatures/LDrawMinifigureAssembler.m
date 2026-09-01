//==============================================================================
//
//  File:       LDrawMinifigureAssembler.m
//  Package:    LDrawFeatures
//
//  Purpose:    Positions minifigure parts the same way the AppKit generator
//              dialog did, using MLCad.ini torso arm angles. Generator preview
//              zoom and autosave names live in Bricksmith LDrawHostChrome.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <LDrawFeatures/LDrawMinifigureAssembler.h>

#include <stdarg.h>

#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/MatrixMath.h>
#import <LDrawFeatures/LDrawMinifigureSpec.h>
#import <LDrawFeatures/LDrawMLCadIni.h>

//========== moveBy:parts: =====================================================
//
// Purpose:		Moves the given nil-terminated list of parts.
//
//==============================================================================
static void MoveParts(Vector3 moveVector, LDrawPart *firstPart, ...)
{
	LDrawPart	*currentObject	= nil;
	va_list		 parts;

	va_start(parts, firstPart);

	currentObject = firstPart;
	while (currentObject != nil)
	{
		[currentObject moveBy:moveVector];
		currentObject = va_arg(parts, LDrawPart *);
	}

	va_end(parts);
}


//========== rotateParts:byDegrees: ============================================
//
// Purpose:		Rotates the given nil-terminated list of parts around the point 
//				(0,0,0).
//
// Notes:		This is the first variadic function I ever wrote.
//
//==============================================================================
static void RotateParts(Tuple3 degrees, LDrawPart *firstPart, ...)
{
	Point3		 theOrigin		= V3Make(0,0,0);
	LDrawPart	*currentObject	= nil;
	va_list		 parts;

	va_start(parts, firstPart);

	currentObject = firstPart;
	while (currentObject != nil)
	{
		[currentObject rotateByDegrees:degrees centerPoint:theOrigin];
		currentObject = va_arg(parts, LDrawPart *);
	}

	va_end(parts);
}



@implementation LDrawMinifigureAssembler

//========== generateMinifigure ================================================
//
// Purpose:		This is it! It's time to manufacture the minifigure!
//
//==============================================================================
+ (LDrawMPDModel *)assembleSpec:(LDrawMinifigureSpec *)spec
						iniFile:(LDrawMLCadIni *)iniFile
{
	LDrawMPDModel	*newMinifigure	= [LDrawMPDModel model];
	LDrawStep		*firstStep		= [[newMinifigure steps] objectAtIndex:0];

	[newMinifigure setModelDisplayName:spec.modelName];

	// create the parts based on the current selections
	LDrawPart	*hat				= spec.hat;
	LDrawPart	*head				= spec.head;
	LDrawPart	*neck				= spec.neck;
	LDrawPart	*torso				= spec.torso;
	LDrawPart	*leftArm			= spec.leftArm;
	LDrawPart	*leftHand			= spec.leftHand;
	LDrawPart	*leftHandAccessory	= spec.leftHandAccessory;
	LDrawPart	*rightArm			= spec.rightArm;
	LDrawPart	*rightHand			= spec.rightHand;
	LDrawPart	*rightHandAccessory	= spec.rightHandAccessory;
	LDrawPart	*hips				= spec.hips;
	LDrawPart	*leftLeg			= spec.leftLeg;
	LDrawPart	*leftLegAccessory	= spec.leftLegAccessory;
	LDrawPart	*rightLeg			= spec.rightLeg;
	LDrawPart	*rightLegAccessory	= spec.rightLegAccessory;

	// Assign the colors
	// (host applies colors onto the spec parts before assemble)
	// other values
	float		armAngle			= 0.0f;
	if (torso != nil)
	{
		armAngle = [iniFile armAngleForTorsoName:[torso referenceName]];
	}

	///////////////////////////////////////
	//
	//	Do Positioning
	//
	///////////////////////////////////////

	//---------- head pieces ---------------------------------------------------

	// * hat
	RotateParts(V3Make(0, spec.angleOfHat, 0),	hat, nil);

	// * head
	RotateParts(V3Make(0, spec.angleOfHead, 0),	hat, head, nil);
	MoveParts(V3Make(  0, -24,   0),				hat, head, nil);

	// * neck accessory
	RotateParts(V3Make(0, spec.angleOfNeck, 0),	neck, nil);

	// move up for neck accessory
	if (spec.hasNeckAccessory == YES)
	{
		MoveParts(V3Make(  0, -spec.headElevation, 0),	hat, head, nil);
	}

	//---------- right arm pieces ----------------------------------------------

	// * position the right accessory in the hand

	RotateParts(V3Make(0, spec.angleOfRightHandAccessory, 0),
				rightHandAccessory, nil);
	if (spec.hasRightHand == YES)
	{
		// 15 degrees to fit the hand at 0 degrees
		RotateParts(V3Make(15, 0, 0),
					rightHandAccessory, nil);
		MoveParts(V3Make(  0,   0, -10), rightHandAccessory, nil);
	}
	else
	{
		// fit skeleton arm
		MoveParts(V3Make( -6,   0, -29.5), rightHandAccessory, nil);
	}


	// * position the right hand in the right arm
	if (spec.hasRightHand == YES)	//don't do this if using the skeleton arm.
	{
		//		- apply hand rotation
		RotateParts(V3Make(0, 0, spec.angleOfRightHand),
					rightHand, rightHandAccessory, nil);

		//		-- rotate hand to match arm socket
		RotateParts(V3Make(45, 0, 0),
					rightHand, rightHandAccessory, nil);

		//		-- move hand into arm
		MoveParts(V3Make( -5,  19, -10), rightHand, rightHandAccessory, nil);
	}


	// * position the right arm in the torso

	//		-- apply arm rotation
	//			negative so it matches how the circular slider looks.
	RotateParts(V3Make(-spec.angleOfRightArm, 0, 0),
				rightArm, rightHand, rightHandAccessory, nil);

	//		-- rotate arm to match torso
	//			this value is derived from a little trig on the torso surface.
	RotateParts(V3Make(0, 0, armAngle),
				rightArm, rightHand, rightHandAccessory, nil);

	//		-- move arm into torso
	MoveParts(V3Make(-15.4,  8, 0), rightArm, rightHand, rightHandAccessory, nil);


	//---------- left arm pieces -----------------------------------------------

	// * position the left accessory in the hand

	RotateParts(V3Make(0, spec.angleOfLeftHandAccessory, 0),
				leftHandAccessory, nil);
	if (spec.hasLeftHand == YES)
	{
		// 15 degrees to fit the hand at 0 degrees
		RotateParts(V3Make(15, 0, 0),
					leftHandAccessory, nil);
		MoveParts(V3Make(  0,   0, -10), leftHandAccessory, nil);
	}
	else
	{
		// fit skeleton arm
		MoveParts(V3Make(  6,   0, -29.5), leftHandAccessory, nil);
	}


	// * position the left hand in the left arm
	if (spec.hasLeftHand == YES)	//don't do this if using the skeleton arm.
	{
		//		- apply hand rotation
		RotateParts(V3Make(0, 0, spec.angleOfLeftHand),
					leftHand, leftHandAccessory, nil);

		//		-- rotate hand to match arm socket
		RotateParts(V3Make(45, 0, 0),
					leftHand, leftHandAccessory, nil);

		//		-- move hand into arm
		MoveParts(V3Make(  5,  19, -10), leftHand, leftHandAccessory, nil);
	}


	// * position the left arm in the torso

	//		-- apply arm rotation
	//			negative so it matches how the circular slider looks.
	RotateParts(V3Make(-spec.angleOfLeftArm, 0, 0),
				leftArm, leftHand, leftHandAccessory, nil);

	//		-- rotate arm to match torso
	//			this value is derived from a little trig on the torso surface.
	RotateParts(V3Make(0, 0, -armAngle),
				leftArm, leftHand, leftHandAccessory, nil);

	//		-- move arm into torso
	MoveParts(V3Make(15.4,  8, 0), leftArm, leftHand, leftHandAccessory, nil);


	//---------- Legs ----------------------------------------------------------

	[hips				moveBy:V3Make(  0,  32,   0)];

	//---------- right leg pieces ----------------------------------------------

	// * position the right accessory on the foot

	// leg accessories' origins take them to their inserted position, which is
	// counter to the behavior of the rest of MLCad.ini, where the parts' origins
	// are the rotation centerpoint of the part.
	[rightLegAccessory rotateByDegrees:V3Make(0, spec.angleOfRightLegAccessory, 0)
						   centerPoint:V3Make(-10, 28, -1) ]; //center of the foot.;

	// * position the right leg on the hips
	RotateParts(V3Make(-spec.angleOfRightLeg, 0, 0),	rightLegAccessory, rightLeg, nil);
	MoveParts(V3Make(  0,  44,   0),					rightLegAccessory, rightLeg, nil);

	//---------- left leg pieces ----------------------------------------------

	// * position the left accessory on the foot

	// leg accessories' origins take them to their inserted position, which is
	// counter to the behavior of the rest of MLCad.ini, where the parts' origins
	// are the rotation centerpoint of the part.
	[leftLegAccessory rotateByDegrees:V3Make(0, spec.angleOfLeftLegAccessory, 0)
						  centerPoint:V3Make(10, 28, -1) ]; //center of the foot.;

	// * position the left leg on the hips
	RotateParts(V3Make(-spec.angleOfLeftLeg, 0, 0),	leftLegAccessory, leftLeg, nil);
	MoveParts(V3Make(  0,  44,   0),					leftLegAccessory, leftLeg, nil);




	///////////////////////////////////////
	//
	//	Create the Model
	//
	///////////////////////////////////////


	if (spec.hasHat == YES)
		[firstStep addDirective:hat];

//	if (hasYES == YES)
		[firstStep addDirective:head];

	if (spec.hasNeckAccessory == YES)
		[firstStep addDirective:neck];

//	if (hasTorso == YES)
		[firstStep addDirective:torso];

	if (spec.hasLeftArm == YES)
		[firstStep addDirective:leftArm];

	if (spec.hasLeftHand == YES)
		[firstStep addDirective:leftHand];

	if (spec.hasLeftHandAccessory == YES)
		[firstStep addDirective:leftHandAccessory];
	if (spec.hasRightArm == YES)
		[firstStep addDirective:rightArm];

	if (spec.hasRightHand == YES)
		[firstStep addDirective:rightHand];

	if (spec.hasRightHandAccessory == YES)
		[firstStep addDirective:rightHandAccessory];

	if (spec.hasHips == YES)
		[firstStep addDirective:hips];

	if (spec.hasLeftLeg == YES)
		[firstStep addDirective:leftLeg];

	if (spec.hasLeftLegAccessory == YES)
		[firstStep addDirective:leftLegAccessory];

	if (spec.hasRightLeg == YES)
		[firstStep addDirective:rightLeg];

	if (spec.hasRightLegAccessory == YES)
		[firstStep addDirective:rightLegAccessory];

	// this is it! We've got a minifigure!
	return newMinifigure;
}

@end
