//==============================================================================
//
//  File:       LDrawSelection+Rotation.m
//  Package:    LDrawEditing
//
//  Purpose:    Rotation helpers for LDrawSelection.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import <LDrawEditing/LDrawSelection.h>

#import <LDrawCore/LDrawDrawableElement.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawUtilities.h>
#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/MatrixMath.h>

@implementation LDrawSelection (Rotation)

//========== rotateSelectionAround:extraFine:aroundOrigin: =====================
//
// Purpose:		Rotates all selected parts in a clockwise direction around the 
//				specified axis. The rotationAxis should be either 
//				+/- i, +/- j or +/- k.
//
//				If extraFine is YES, the rotation angle is reduced in 5 times.
//
//				If aroundOrigin is YES, the rotation center is the origin of
//				the model, otherwise - the center of the selected directives.
//
//				This method is used by the rotate toolbar methods. It chooses
//				the actual number of degrees based on the current grid mode.
//
//==============================================================================
+ (Tuple3)rotationForAxis:(Vector3)axis degrees:(float)degrees
{
	axis = V3Normalize(axis);

	Tuple3 rotation = {0};
	rotation.x = axis.x * degrees;
	rotation.y = axis.y * degrees;
	rotation.z = axis.z * degrees;
	return rotation;
}


//---------- partRelativeRotation:forPart: --------------------------[static]--
//
// Purpose:		Convert a world-axis rotation into the equivalent rotation in
//				the part's local axes.
//
//				To make the rotation be part-relative we change TO the part
//				(inverse of part is world->part), apply the rotation, then
//				change back (part matrix is part->world).
//
//------------------------------------------------------------------------------
+ (Tuple3)partRelativeRotation:(Tuple3)rotation forPart:(LDrawPart *)part
{
	// To make the rotation be "part relative" we basically change TO the
	// part (inverse of part is world->part), apply the rotation, then change
	// back (part matrix is part->world).
	TransformComponents rotateComponents = IdentityComponents;
	rotateComponents.rotate.x = radians(rotation.x);
	rotateComponents.rotate.y = radians(rotation.y);
	rotateComponents.rotate.z = radians(rotation.z);
	Matrix4 addedRotation = Matrix4CreateTransformation(&rotateComponents);

	Matrix4 orig = [part transformationMatrix];
	orig.element[3][0] = 0.0;
	orig.element[3][1] = 0.0;
	orig.element[3][2] = 0.0;

	Matrix4 origInv = Matrix4Invert(orig);

	// World -> part, apply rotation, part -> world.
	addedRotation = Matrix4Multiply(Matrix4Multiply(origInv, addedRotation), orig);

	if (Matrix4DecomposeTransformation(addedRotation, &rotateComponents))
	{
		rotation.x = degrees(rotateComponents.rotate.x);
		rotation.y = degrees(rotateComponents.rotate.y);
		rotation.z = degrees(rotateComponents.rotate.z);
	}
	return rotation;
}


//---------- partRelativeRotation:forSelection:partRelative: --------[static]--
//
// Purpose:		When partRelative is YES and the selection is a single part,
//				convert the world-axis rotation into that part's local axes.
//				Otherwise return rotation unchanged.
//
//------------------------------------------------------------------------------
+ (Tuple3)partRelativeRotation:(Tuple3)rotation
				  forSelection:(NSArray *)selection
				  partRelative:(BOOL)partRelative
{
	if (partRelative == NO || [selection count] != 1) return rotation;

	id obj = [selection objectAtIndex:0];
	if ([obj isKindOfClass:[LDrawPart class]] == NO) return rotation;

	return [self partRelativeRotation:rotation forPart:(LDrawPart *)obj];
}


//---------- rotationModeForSelectionCount:aroundOrigin: ------------[static]--
//
// Purpose:		Choose rotate-around-selection-center, part-positions, or a
//				fixed point based on how many parts are selected and whether
//				the user asked to rotate around the origin.
//
//------------------------------------------------------------------------------
+ (LDrawRotationMode)rotationModeForSelectionCount:(NSUInteger)count aroundOrigin:(BOOL)aroundOrigin
{
	if (aroundOrigin)
	{
		return LDrawRotateAroundFixedPoint;
	}
	if (count == 1)
	{
		// Just one part selected; rotate around that part's origin. That is
		// presumably what the part's author intended to be the rotation point.
		return LDrawRotateAroundPartPositions;
	}
	// More than one part selected. We now must make a "best guess" about 
	// what to rotate around. So we will go with the center of the bounding 
	// box of the selection.
	return LDrawRotateAroundSelectionCenter;
}

//========== rotateSelection:mode:fixedCenter: =================================
//
// Purpose:		Rotates the selected parts according to the specified mode.
//
// Parameters:	rotation	= degrees x,y,z to rotate
//				mode		= how to derive the rotation centerpoint
//				fixedCenter	= explicit centerpoint, or NULL if mode not equal to 
//							  LDrawRotateAroundFixedPoint
//
//==============================================================================
+ (Point3)rotationCenterForDirectives:(NSArray *)directives
								 mode:(LDrawRotationMode)mode
						  fixedCenter:(const Point3 * _Nullable)fixedCenter
{
	Point3 rotationCenter = {0};

	if (mode == LDrawRotateAroundSelectionCenter)
	{
		Box3 selectionBounds = [LDrawUtilities boundingBox3ForDirectives:directives];
		rotationCenter = V3Midpoint(selectionBounds.min, selectionBounds.max);
	}
	else if (mode == LDrawRotateAroundFixedPoint && fixedCenter != NULL)
	{
		rotationCenter = *fixedCenter;
	}
	return rotationCenter;
}


//---------- rotationCenterFromFirstDrawable: -----------------------[static]--
//
// Purpose:		Return the position of the first drawable, used as a fallback
//				rotation center.
//
//------------------------------------------------------------------------------
+ (Point3)rotationCenterFromFirstDrawable:(NSArray *)drawables
{
	if ([drawables count] == 0) return ZeroPoint3;
	return [(LDrawDrawableElement *)[drawables objectAtIndex:0] position];
}

//---------- quickRotationAxis:forMenuTag: ---------------------------[static]--
//
// Purpose:		One of the quick rotation shortcuts was clicked. Build a
//				rotation in the requested direction (deduced from the sender's
//				tag).
//
//------------------------------------------------------------------------------
+ (BOOL)quickRotationAxis:(Vector3 *)outAxis forMenuTag:(NSInteger)tag
{
	Vector3 axis = ZeroPoint3;

	switch (tag)
	{
		case rotatePositiveXTag:
			axis = V3Make( 1,  0,  0);
			break;
		case rotateNegativeXTag:
			axis = V3Make(-1,  0,  0);
			break;
		case rotatePositiveYTag:
			axis = V3Make( 0,  1,  0);
			break;
		case rotateNegativeYTag:
			axis = V3Make( 0, -1,  0);
			break;
		case rotatePositiveZTag:
			axis = V3Make( 0,  0,  1);
			break;
		case rotateNegativeZTag:
			axis = V3Make( 0,  0, -1);
			break;
		default:
			return NO;
	}
	*outAxis = axis;
	return YES;
}


//---------- quickRotationMenuTagForAxis:positive: -------------------[static]--
//
// Purpose:		Button that rotates around an axis. Tags match the Edit menu
//				quick-rotate items.
//
//------------------------------------------------------------------------------
+ (NSInteger)quickRotationMenuTagForAxis:(LDrawQuickRotationAxis)axis
								positive:(BOOL)positive
{
	switch (axis)
	{
		case LDrawQuickRotationAxisX:
			return positive ? rotatePositiveXTag : rotateNegativeXTag;
		case LDrawQuickRotationAxisY:
			return positive ? rotatePositiveYTag : rotateNegativeYTag;
		case LDrawQuickRotationAxisZ:
			return positive ? rotatePositiveZTag : rotateNegativeZTag;
	}
	return rotatePositiveXTag;
}


//---------- quickRotationAxis:positive:forToolbarIdentifier: --------[static]--
//
// Purpose:		Button that rotates around an axis. Rotation identifiers match
//				both localized string key and image name.
//
//------------------------------------------------------------------------------
+ (BOOL)quickRotationAxis:(LDrawQuickRotationAxis *)outAxis
				 positive:(BOOL *)outPositive
	 forToolbarIdentifier:(NSString *)identifier
{
	if ([identifier isEqualToString:@"Rotate+X"])
	{
		*outAxis     = LDrawQuickRotationAxisX;
		*outPositive = YES;
		return YES;
	}
	if ([identifier isEqualToString:@"Rotate-X"])
	{
		*outAxis     = LDrawQuickRotationAxisX;
		*outPositive = NO;
		return YES;
	}
	if ([identifier isEqualToString:@"Rotate+Y"])
	{
		*outAxis     = LDrawQuickRotationAxisY;
		*outPositive = YES;
		return YES;
	}
	if ([identifier isEqualToString:@"Rotate-Y"])
	{
		*outAxis     = LDrawQuickRotationAxisY;
		*outPositive = NO;
		return YES;
	}
	if ([identifier isEqualToString:@"Rotate+Z"])
	{
		*outAxis     = LDrawQuickRotationAxisZ;
		*outPositive = YES;
		return YES;
	}
	if ([identifier isEqualToString:@"Rotate-Z"])
	{
		*outAxis     = LDrawQuickRotationAxisZ;
		*outPositive = NO;
		return YES;
	}
	return NO;
}


@end
