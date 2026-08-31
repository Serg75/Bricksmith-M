//==============================================================================
//
//  File:       LDrawSelection+Nudge.m
//  Package:    LDrawEditing
//
//  Purpose:    Keyboard and toolbar nudge helpers for LDrawSelection.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import "LDrawSelectionInternal.h"

#import <LDrawEditing/LDrawSelection.h>

#import <LDrawCore/LDrawLSynth.h>
#import <LDrawCore/LDrawMovableDirective.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/MatrixMath.h>

@implementation LDrawSelection (Nudge)

//========== nudgeVectorForMatrix: =============================================
//
// Purpose:		Returns the direction of a keyboard part nudge. The target of 
//				our nudgeAction queries this method to find how to nudge the 
//				selection. 
//
// Notes:		the nudge is aligned to the axes of the partMatrix passed in.
//				This lets us nudge in part space; the client can pass the
//				identity matrix to disable this.
//
//==============================================================================
+ (Vector3)nudgeVector:(Vector3)screenNudge
			partMatrix:(Matrix4)partMatrix
		  cameraMatrix:(Matrix4)cameraMatrix
		  orthographic:(BOOL)orthographic
		  useTurntable:(BOOL)useTurntable
{
	// These 3 axes are the directions the _user_ thinks are right, down, and away, in model coordinates.
	// Note that this assumes that the rotation elements of the camera matrix have no skew or scaling,
	// so we can use the transpose as an inverse.
	Vector3 xUser = V3Make(cameraMatrix.element[0][0], cameraMatrix.element[1][0], cameraMatrix.element[2][0]);
	Vector3 yUser = V3Make(cameraMatrix.element[0][1], cameraMatrix.element[1][1], cameraMatrix.element[2][1]);
	Vector3 zUser = V3Make(cameraMatrix.element[0][2], cameraMatrix.element[1][2], cameraMatrix.element[2][2]);

	// If we are in a non-orthographic turn-table view, assume that the user's idea of up is up in model
	// coordinates, no matter how silly the alignment is.  In turn-table view, the user really knows where
	// the model's "up" is and expects to go that way.
	if (!orthographic && useTurntable)
	{
		// But use the original screen space Y to know if we are "upside down" and reverse THAT.  Otherwise
		// editing the undersides of plates is insane.
		if (yUser.y < 0.0)
			yUser = V3Make(0, -1, 0);
		else
			yUser = V3Make(0, 1, 0);
	}

	// Get the axis basis vectors of the model - this is the direction we will nudge, e.g. an "x part"
	// nudge moves the part to its own right.
	Vector3 xPart = V3Make(partMatrix.element[0][0],partMatrix.element[0][1],partMatrix.element[0][2]);
	Vector3 yPart = V3Make(partMatrix.element[1][0],partMatrix.element[1][1],partMatrix.element[1][2]);
	Vector3 zPart = V3Make(partMatrix.element[2][0],partMatrix.element[2][1],partMatrix.element[2][2]);

	// Now, take lots o dot products to find the correlation between the user and model axes.
	float xUp = V3Dot(yUser,xPart);
	float yUp = V3Dot(yUser,yPart);
	float zUp = V3Dot(yUser,zPart);

	float xRight = V3Dot(xUser,xPart);
	float yRight = V3Dot(xUser,yPart);
	float zRight = V3Dot(xUser,zPart);

	float xBack = V3Dot(zUser,xPart);
	float yBack = V3Dot(zUser,yPart);
	float zBack = V3Dot(zUser,zPart);

	// We're going to compare them and link the strongest axes together, saving the dot product that we got.
	Vector3	xNudge = ZeroPoint3, yNudge = ZeroPoint3, zNudge = ZeroPoint3;
	float xDot = 0.0f, yDot = 0.0f, zDot = 0.0f;

	// Settle Y first, then X.  Since Y is hacked to not be in screen space for some views, there is
	// a risk that model Y and screen Z are closely correlated.  Find the "up" vector, then take the
	// right-most of remaining as X.
	if (fabsf(xUp) > fabsf(yUp) && fabsf(xUp) > fabsf(zUp))
	{
		// CASE 1: model "X" axis is up.
		yNudge = xPart;
		yDot = xUp;

		// Figure out which is more "to the right" - Y or Z
		if (fabsf(yRight) > fabsf(zRight))
		{
			// Y axis is to the right.
			xNudge = yPart;
			xDot = yRight;
			// Z is forward
			zNudge = zPart;
			zDot = zBack;
		}
		else
		{
			// Z axis is to the right.
			xNudge = zPart;
			xDot = zRight;
			// Y is forward
			zNudge = yPart;
			zDot = yBack;
		}

	}
	else if (fabsf(yUp) > fabsf(zUp))
	{
		// CASE 2: model "Y" axis is up.
		yNudge = yPart;
		yDot = yUp;

		if (fabsf(xRight) > fabsf(zRight))
		{
			// X axis is right
			xNudge = xPart;
			xDot = xRight;
			// Z is forward
			zNudge = zPart;
			zDot = zBack;
		}
		else
		{
			// Z axis is right
			xNudge = zPart;
			xDot = zRight;
			// X is forward
			zNudge = xPart;
			zDot = xBack;
		}
	}
	else
	{
		// CASE 3: model "Z" axis is up.
		yNudge = zPart;
		yDot = zUp;
		float yRightZ = V3Dot(xUser,yPart);
		if (fabsf(xRight) > fabsf(yRightZ))
		{
			// X is right
			xNudge = xPart;
			xDot = xRight;
			// Y is forward
			zNudge = yPart;
			zDot = yBack;
		}
		else
		{
			// Y is right
			xNudge = yPart;
			xDot = yRightZ;
			// X is forward
			zNudge = xPart;
			zDot = xBack;
		}
	}

	// If any correlation was highly negative, the axis goes the wrong way.
	// Flip the nudge sign.

	if (xDot < 0.0f)
		xNudge = V3Negate(xNudge);
	if (yDot < 0.0f)
		yNudge = V3Negate(yNudge);
	if (zDot < 0.0f)
		zNudge = V3Negate(zNudge);

	// Now apply the nudge - basically .x of the nudge vector from the
	// key stroke applies xNudge, etc.
	return V3Make(
				screenNudge.x * xNudge.x +
				screenNudge.y * yNudge.x +
				screenNudge.z * zNudge.x,

				screenNudge.x * xNudge.y +
				screenNudge.y * yNudge.y +
				screenNudge.z * zNudge.y,

				screenNudge.x * xNudge.z +
				screenNudge.y * yNudge.z +
				screenNudge.z * zNudge.z);
}

//========== nudgeKeyDown: =====================================================
//
// Purpose:		We have received a keypress intended to move bricks. We need to
//				figure out which direction to move them with respect to how the
//				model is currently oriented.
//
//==============================================================================
+ (BOOL)screenNudge:(Vector3 *)outNudge
		   forArrow:(LDrawArrowNudge)arrow
		  modifiers:(NSUInteger)modifiers
{
	if (outNudge == NULL || arrow == LDrawArrowNudgeNone)
	{
		return NO;
	}

	Vector3 xNudge = V3Make(1.0, 0.0, 0.0);
	Vector3 yNudge = V3Make(0.0, 1.0, 0.0);
	Vector3 zNudge = V3Make(0.0, 0.0, 1.0);
	Vector3 actualNudge = ZeroPoint3;

	// By holding down the option key, we transcend the two-plane
	// limitation presented by the arrow keys. Option-presses mean
	// movement along the z-axis. Note that move "in" to the screen (up
	// arrow, left arrow?) is a movement along the screen's negative
	// z-axis.
	BOOL isZMovement = (modifiers & kLDrawModifierOption) != 0;

	// now we must select which axis we actually are nudging on.
	switch (arrow)
	{
		case LDrawArrowNudgeUp:
			// into the screen (-z)
			actualNudge = isZMovement ? V3Negate(zNudge) : yNudge;
			break;
		case LDrawArrowNudgeDown:
			actualNudge = isZMovement ? zNudge : V3Negate(yNudge);
			break;
		case LDrawArrowNudgeLeft:
			// Option-left maps onto +Z (historical: the opposite sign made
			// default 3D perspective view go the wrong way).
			actualNudge = isZMovement ? zNudge : V3Negate(xNudge);
			break;
		case LDrawArrowNudgeRight:
			actualNudge = isZMovement ? V3Negate(zNudge) : xNudge;
			break;
		case LDrawArrowNudgeNone:
			return NO;
	}

	if ((modifiers & kLDrawModifierShift) != 0)
	{
		actualNudge = V3Scale(actualNudge, 10.0);
	}
	else if ((modifiers & kLDrawModifierCommand) != 0)
	{
		actualNudge = V3Scale(actualNudge, 0.04);
	}

	*outNudge = actualNudge;
	return YES;
}

//---------- nudgeOrientationMatrixForSelection: --------------------[static]--
//
// Purpose:		Build the orientation matrix used to interpret arrow-key nudges
//				for the selection (from the first movable directive).
//
//------------------------------------------------------------------------------
+ (Matrix4)nudgeOrientationMatrixForSelection:(NSArray *)selection
								 partRelative:(BOOL)partRelative
{
	Matrix4 xform = IdentityMatrix4;
	if (partRelative == NO || [selection count] == 0)
	{
		return xform;
	}

	id first = [selection objectAtIndex:0];
	if ([first isKindOfClass:[LDrawPart class]])
	{
		xform = [(LDrawPart *)first transformationMatrix];
		xform.element[3][0] = 0.0f;
		xform.element[3][1] = 0.0f;
		xform.element[3][2] = 0.0f;
	}
	else if ([first isKindOfClass:[LDrawLSynth class]])
	{
		xform = [(LDrawLSynth *)first transformationMatrix];
		xform.element[3][0] = 0.0f;
		xform.element[3][1] = 0.0f;
		xform.element[3][2] = 0.0f;
	}
	return xform;
}

//========== nudgeSelectionBy: =================================================
//
// Purpose:		Nudges all selected (and nudgeable) directives in the direction 
//				indicated by nudgeVector, which should be normalized. The exact 
//				amount nudged is dependent on the directives themselves, but we 
//				give them our best estimate based on the grid granularity.
//
//==============================================================================
+ (BOOL)worldNudge:(Vector3 *)outNudge
   fromScreenNudge:(Vector3)screenNudge
	   gridSpacing:(float)gridSpacing
		 selection:(NSArray *)selection
{
	if (outNudge == NULL)
	{
		return NO;
	}

	// We do not normalize the nudge vector - nudge might be set to a multiple of the grid on purpose.

	id firstNudgable = nil;
	// find the first selected item that can actually be moved.
	for (id currentObject in selection)
	{
		if ([currentObject conformsToProtocol:@protocol(LDrawMovableDirective)])
		{
			firstNudgable = currentObject;
			break;
		}
	}
	if (firstNudgable == nil)
	{
		return NO;
	}

	// We do not normalize the nudge vector — it may already be a grid multiple.
	Vector3 scaled = screenNudge;
	scaled.x *= gridSpacing;
	scaled.y *= gridSpacing;
	scaled.z *= gridSpacing;

	// Brick studs vs plates use different vertical/horizontal scales; the first
	// movable decides the absolute step, then the whole selection uses that.
	*outNudge = [(id<LDrawMovableDirective>)firstNudgable displacementForNudge:scaled];
	return YES;
}

//---------- nudgeUnitVectorForAxis:sign: ----------------------------[static]--
//
// Purpose:		The toolbar button indicating movement along the axis has been
//				clicked. The direction to move can be determined by the tag of
//				the button clicked: -1 for negative movement; +1 for positive
//				movement.
//
//------------------------------------------------------------------------------
+ (Vector3)nudgeUnitVectorForAxis:(LDrawNudgeAxis)axis sign:(NSInteger)sign
{
	Vector3 nudgeVector = V3Make(0, 0, 0);

	switch (axis)
	{
		case LDrawNudgeAxisX:
			nudgeVector = V3Make(1, 0, 0);
			nudgeVector.x *= sign;
			break;
		case LDrawNudgeAxisY:
			nudgeVector = V3Make(0, 1, 0);
			nudgeVector.y *= sign;
			break;
		case LDrawNudgeAxisZ:
			nudgeVector = V3Make(0, 0, 1);
			nudgeVector.z *= sign;
			break;
	}

	return nudgeVector;
}


@end
