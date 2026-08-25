//==============================================================================
//
//  File:       LDrawSelectionOps.m
//  Package:    LDrawEditing
//
//  Purpose:    Rotation, nudge, and selection-mode helpers so any host can
//              compute the same axis / part-relative / center-mode result.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <LDrawEditing/LDrawSelectionOps.h>

#import <stdlib.h>

#import <LDrawCore/ColorLibrary.h>
#import <LDrawCore/LDrawDrawableElement.h>
#import <LDrawCore/LDrawLSynth.h>
#import <LDrawCore/LDrawMovableDirective.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LDrawUtilities.h>
#import <LDrawCore/MatrixMath.h>

#import <math.h>

// Match NSEventModifierFlags so AppKit hosts pass event.modifierFlags through.
static const NSUInteger kLDrawModifierShift   = 1UL << 17;
static const NSUInteger kLDrawModifierOption  = 1UL << 19;
static const NSUInteger kLDrawModifierCommand = 1UL << 20;

@implementation LDrawSelectionOps

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
+ (RotationModeT)rotationModeForSelectionCount:(NSUInteger)count aroundOrigin:(BOOL)aroundOrigin
{
	if (aroundOrigin)
	{
		return RotateAroundFixedPoint;
	}
	if (count == 1)
	{
		// Just one part selected; rotate around that part's origin. That is
		// presumably what the part's author intended to be the rotation point.
		return RotateAroundPartPositions;
	}
	// More than one part selected. We now must make a "best guess" about 
	// what to rotate around. So we will go with the center of the bounding 
	// box of the selection.
	return RotateAroundSelectionCenter;
}


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


//---------- selectionModeFromModifiers: ----------------------------[static]--
//
// Purpose:		Map Shift / Option bits to replace, extend, subtract, or
//				intersection. Modifier bits match NSEventModifierFlags so an
//				AppKit host can pass event.modifierFlags through unchanged.
//
//------------------------------------------------------------------------------
+ (SelectionModeT)selectionModeFromModifiers:(NSUInteger)modifiers
{
	BOOL shift  = (modifiers & kLDrawModifierShift)  != 0;
	BOOL option = (modifiers & kLDrawModifierOption) != 0;

	if (shift)
	{
		return option ? SelectionIntersection : SelectionExtend;
	}
	return option ? SelectionSubtract : SelectionReplace;
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


//========== moveSelectionBy: ==================================================
//
// Purpose:		Moves all selected (and moveable) directives in the direction 
//				indicated by movementVector.
//
//==============================================================================
+ (NSArray *)movableDirectivesInSelection:(NSArray *)selection
{
	NSMutableArray *movable = [NSMutableArray array];
	for (id currentObject in selection)
	{
		if ([currentObject conformsToProtocol:@protocol(LDrawMovableDirective)])
		{
			[movable addObject:currentObject];
		}
	}
	return movable;
}


//---------- partsInSelection: --------------------------------------[static]--
//
// Purpose:		Return the LDrawPart objects in selection, ignoring other
//				directive types.
//
//------------------------------------------------------------------------------
+ (NSArray *)partsInSelection:(NSArray *)selection
{
	NSMutableArray *parts = [NSMutableArray array];
	for (id currentObject in selection)
	{
		if ([currentObject isKindOfClass:[LDrawPart class]])
		{
			[parts addObject:currentObject];
		}
	}
	return parts;
}


//---------- firstPartInSelection: ----------------------------------[static]--
//
// Purpose:		Return the first LDrawPart in selection, or nil.
//
//------------------------------------------------------------------------------
+ (LDrawPart *)firstPartInSelection:(NSArray *)selection
{
	return [[self partsInSelection:selection] firstObject];
}


//---------- sharedReferenceNameInSelection: ------------------------[static]--
//
// Purpose:		Return the part name when every selected part is the same
//				reference; otherwise nil.
//
//------------------------------------------------------------------------------
+ (NSString *)sharedReferenceNameInSelection:(NSArray *)selection
{
	NSString *parentName = nil;
	for (id object in selection)
	{
		if ([object isKindOfClass:[LDrawPart class]] == NO)
		{
			continue;
		}

		NSString *thisName = [(LDrawPart *)object referenceName];
		if (parentName == nil || [thisName compare:parentName] == NSOrderedSame)
		{
			parentName = thisName;
		}
		else
		{
			return nil;
		}
	}
	return parentName;
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
+ (Point3)rotationCenterForDirectives:(NSArray *)directives
								 mode:(RotationModeT)mode
						  fixedCenter:(const Point3 * _Nullable)fixedCenter
{
	Point3 rotationCenter = {0};

	if (mode == RotateAroundSelectionCenter)
	{
		Box3 selectionBounds = [LDrawUtilities boundingBox3ForDirectives:directives];
		rotationCenter = V3Midpoint(selectionBounds.min, selectionBounds.max);
	}
	else if (mode == RotateAroundFixedPoint && fixedCenter != NULL)
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


//---------- mergedSelectionWithMarked:newDirectives:mode: -----------[static]--
//
// Purpose:		Bulk-select after a marquee. Calculate the union of the past
//				selection and this one if we are extending. Otherwise we only
//				want the new selection. Subtract removes the marquee from the
//				old set; intersection keeps the overlap.
//
//				If the array is empty, the host should deselect. The old
//				selection is still preserved when extension is used and the
//				marquee is empty (extend of nothing is the old set).
//
//------------------------------------------------------------------------------
+ (NSArray *)mergedSelectionWithMarked:(NSArray *)marked
						 newDirectives:(NSArray *)directives
								  mode:(SelectionModeT)mode
{
	if (mode == SelectionIntersection)
	{
		NSMutableSet *orig = [NSMutableSet setWithArray:marked];
		[orig intersectSet:[NSSet setWithArray:directives]];
		return [orig allObjects];
	}

	// Replace takes the new set; every other mode starts from the marked set.
	NSMutableArray *all = (mode != SelectionReplace)
		? [NSMutableArray arrayWithArray:marked]
		: [NSMutableArray arrayWithArray:directives];

	if (mode == SelectionExtend)
	{
		[all addObjectsFromArray:directives];
	}
	else if (mode == SelectionSubtract)
	{
		[all removeObjectsInArray:directives];
	}

	return all;
}


//========== setSelectionToHidden: =============================================
//
// Purpose:		Hides or shows all the hideable selected elements.
//
//==============================================================================
+ (NSArray *)hideableDirectivesInSelection:(NSArray *)selection
{
	NSMutableArray *hideable = [NSMutableArray array];
	for (id currentObject in selection)
	{
		if ([currentObject respondsToSelector:@selector(setHidden:)])
		{
			[hideable addObject:currentObject];
		}
	}
	return hideable;
}


//---------- setHidden:forDirectives: -------------------------------[static]--
//
// Purpose:		Show or hide every hideable directive in the list.
//
//------------------------------------------------------------------------------
+ (void)setHidden:(BOOL)hidden forDirectives:(NSArray *)directives
{
	for (id currentDirective in directives)
	{
		[currentDirective setHidden:hidden];
	}
}


//---------- setSelected:forDirectives: -----------------------------[static]--
//
// Purpose:		Set the selected flag on every directive in the list.
//
//------------------------------------------------------------------------------
+ (void)setSelected:(BOOL)selected forDirectives:(NSArray *)directives
{
	// while a part is dragged, it is drawn selected
	for (id currentObject in directives)
	{
		[currentObject setSelected:selected];
	}
}


//---------- hiddenHideableDirectivesIn: ----------------------------[static]--
//
// Purpose:		Return hideable directives that are currently hidden, for Show.
//
//------------------------------------------------------------------------------
+ (NSArray *)hiddenHideableDirectivesIn:(NSArray *)directives
{
	NSMutableArray *hidden = [NSMutableArray array];
	for (id currentObject in directives)
	{
		if (	[currentObject respondsToSelector:@selector(setHidden:)]
		   &&	[currentObject respondsToSelector:@selector(isHidden)]
		   &&	[currentObject isHidden] == YES)
		{
			[hidden addObject:currentObject];
		}
	}
	return hidden;
}


//---------- visibleDirectivesIn: ------------------------------------[static]--
//
// Purpose:		Selects all the visible LDraw elements in the active model. This
//				does not select the steps or model--only the contained elements
//				themselves. Hidden elements are also ignored.
//
//------------------------------------------------------------------------------
+ (NSArray *)visibleDirectivesIn:(NSArray *)directives
{
	NSMutableArray *visibleElements = [NSMutableArray arrayWithCapacity:[directives count]];

	for (id currentElement in directives)
	{
		if ([currentElement respondsToSelector:@selector(isHidden)] == NO
		   || [currentElement isHidden] == NO)
		{
			[visibleElements addObject:currentElement];
		}
	}
	return visibleElements;
}


//---------- colorableDirectivesInSelection: ------------------------[static]--
//
// Purpose:		Return the subset of selection that accepts an LDraw color
//				change.
//
//------------------------------------------------------------------------------
+ (NSArray *)colorableDirectivesInSelection:(NSArray *)selection
{
	NSMutableArray *colorable = [NSMutableArray array];
	for (id currentObject in selection)
	{
		if ([currentObject conformsToProtocol:@protocol(LDrawColorable)])
		{
			[colorable addObject:currentObject];
		}
	}
	return colorable;
}


//========== elementsAreSelectedOfVisibility: ==================================
//
// Purpose:		Returns YES if there are elements selected which have the 
//				requested visibility.
//
//==============================================================================
+ (BOOL)selection:(NSArray *)selection containsVisibility:(BOOL)visibleFlag
{
	BOOL invisibleSelected = NO;
	BOOL visibleSelected   = NO;

	for (id currentObject in selection)
	{
		if ([currentObject respondsToSelector:@selector(isHidden)])
		{
			invisibleSelected = invisibleSelected || [currentObject isHidden];
			visibleSelected   = visibleSelected   || ([currentObject isHidden] == NO);
		}
	}

	return visibleFlag ? visibleSelected : invisibleSelected;
}


//========== randomizeLDrawColors: =============================================
//
// Purpose:		Randomizes every part in the selection to be one of the parts
//				found in the selection.
//
//				This is meant for a power tool, e.g. if you want to turn a big
//				pile of 1x1 plates into "gravel", you can color the entire set
//				gray and then change a few to the other colors (maybe black,
//				brown, etc.).  randomizeLDrawColors will randomize the entire
//				set.
//
// Notes:		We try to avoid consecutive colors - if the underlying bricks
//				were built "in order", this gives an author a way to avoid
//				aesthetically ugly blocks of repeating colors that are present
//				in true random distributions.
//
//				This routine depends on LDrawColors hashing into sets with
//				deduplication.  This _does_ work for colors that come from
//				the palette, but I have not tested it with models that use
//				custom colors in an LDraw directive in their MPD file.
//
//==============================================================================
+ (NSArray *)randomizedColorsForDirectives:(NSArray *)colorable
{
	NSUInteger count = [colorable count];
	if (count == 0)
	{
		return [NSArray array];
	}

	NSMutableSet *allColors = [NSMutableSet setWithCapacity:count];
	// Build a hash set of all colors
	for (id currentObject in colorable)
	{
		[allColors addObject:[currentObject LDrawColor]];
	}

	NSUInteger colorCount = [allColors count];
	if (colorCount == 0)
	{
		return [NSArray array];
	}

	NSArray        *palette = [allColors allObjects];
	NSMutableArray *result  = [NSMutableArray arrayWithCapacity:count];
	int             last    = -1;

	for (NSUInteger counter = 0; counter < count; ++counter)
	{
		int r = rand() % (int)colorCount;
		// Try to avoid consecutives if we have enough palette --
		// this technically makes the distribution not random, but
		// it probably looks better unless the parts are just super
		// tiny.
		while (colorCount > 1 && r == last)
		{
			r = rand() % (int)colorCount;
		}
		last = r;
		[result addObject:[palette objectAtIndex:(NSUInteger)r]];
	}
	return result;
}


//---------- snappedTransformUpdatesForSelection:gridSpacing:minimumAngle:
//
// Purpose:		Aligns all selected parts to the current grid setting. Kind of a
//				weird legacy API. The host still applies the components (undo).
//
//------------------------------------------------------------------------------
+ (NSArray<LDrawPartTransformUpdate *> *)snappedTransformUpdatesForSelection:(NSArray *)selection
																 gridSpacing:(float)gridSpacing
																minimumAngle:(float)degrees
{
	NSMutableArray *updates = [NSMutableArray array];
	for (LDrawPart *part in [self partsInSelection:selection])
	{
		LDrawPartTransformUpdate *update = [LDrawPartTransformUpdate new];
		update.part = part;
		update.components = [part componentsSnappedToGrid:gridSpacing minimumAngle:degrees];
		[updates addObject:update];
	}
	return updates;
}


//---------- snappedTransformUpdatesForSelection:gridSpacing:axis: ---[static]--
//
// Purpose:		Aligns by axis all selected parts to the current grid setting.
//
//------------------------------------------------------------------------------
+ (NSArray<LDrawPartTransformUpdate *> *)snappedTransformUpdatesForSelection:(NSArray *)selection
																 gridSpacing:(float)gridSpacing
																		axis:(Vector3)axis
{
	NSMutableArray *updates = [NSMutableArray array];
	for (LDrawPart *part in [self partsInSelection:selection])
	{
		LDrawPartTransformUpdate *update = [LDrawPartTransformUpdate new];
		update.part = part;
		update.components = [part componentsSnappedToGrid:gridSpacing byAxis:axis];
		[updates addObject:update];
	}
	return updates;
}


//---------- mirroredTransformUpdatesForSelection:axis: --------------[static]--
//
// Purpose:		Move all selected parts symmetrically by axis. Pass −1 to
//				component(s) which should be mirrored, and 1 to others.
//
//------------------------------------------------------------------------------
+ (NSArray<LDrawPartTransformUpdate *> *)mirroredTransformUpdatesForSelection:(NSArray *)selection
																		 axis:(Vector3)axis
{
	NSMutableArray *updates = [NSMutableArray array];
	for (LDrawPart *part in [self partsInSelection:selection])
	{
		LDrawPartTransformUpdate *update = [LDrawPartTransformUpdate new];
		update.part = part;
		update.components = [part componentsMirroredByAxis:axis];
		[updates addObject:update];
	}
	return updates;
}


//---------- inspectorObjectListFromObject: --------------------------[static]--
//
// Purpose:		Convenience method for -inspectObjects.
//
//------------------------------------------------------------------------------
+ (NSArray *)inspectorObjectListFromObject:(id)object
{
	if (object != nil)
		return [NSArray arrayWithObject:object];
	return [NSArray array];
}


//---------- inspectorSelectionKindForObjects: -----------------------[static]--
//
// Purpose:		Displays an object with its own special inspection panel.
//
//				This method takes an array in order to easily accommodate a
//				"multiple selection" error message. If you actually want
//				anything inspected, you should pass an array with a single
//				element.
//
//------------------------------------------------------------------------------
+ (LDrawInspectorSelectionKind)inspectorSelectionKindForObjects:(NSArray *)objects
{
	if (objects == nil || [objects count] == 0)
		return LDrawInspectorSelectionEmpty;
	if ([objects count] > 1)
		return LDrawInspectorSelectionMultiple;
	return LDrawInspectorSelectionSingle;
}


//---------- singleInspectableObjectInSelection: ---------------------[static]--
//
// Purpose:		First object when the selection is a single item.
//
//------------------------------------------------------------------------------
+ (id)singleInspectableObjectInSelection:(NSArray *)objects
{
	if ([self inspectorSelectionKindForObjects:objects] != LDrawInspectorSelectionSingle)
		return nil;
	return [objects objectAtIndex:0];
}


//---------- colorOfLastObjectInSelection:fallingBackTo: -------------[static]--
//
// Purpose:		Updates the selected color based on the colors in
//				selectedObjects. If two or more directives have different
//				colors, then the color of the last object selected is displayed.
//				If there are no colorable directives, the color selection
//				remains unchanged.
//
//------------------------------------------------------------------------------
+ (LDrawColor *)colorOfLastObjectInSelection:(NSArray *)selection
							   fallingBackTo:(LDrawColor *)currentColor
{
	id currentObject = [selection lastObject];
	if (currentObject != nil)
	{
		if ([currentObject conformsToProtocol:@protocol(LDrawColorable)])
			return [currentObject LDrawColor];
	}
	return currentColor;
}


//---------- inspectorComponentsFromPosition:scalingPercent:shear: ---[static]--
//
// Purpose:		Fill the components structure. Scale is converted from
//				percentage. Rotation is handled by the Apply button.
//
//------------------------------------------------------------------------------
+ (TransformComponents)inspectorComponentsFromPosition:(Point3)position
										scalingPercent:(Vector3)scaling
												 shear:(Tuple3)shear
										 oldComponents:(TransformComponents)oldComponents
{
	TransformComponents components = IdentityComponents;
	components.scale     = V3MulScalar(scaling, 0.01); //convert from percentage
	components.shear_XY  = shear.x;
	components.shear_XZ  = shear.y;
	components.shear_YZ  = shear.z;
	components.rotate    = oldComponents.rotate; //rotation is handled by the Apply button.
	components.translate = position;
	return components;
}


//---------- inspectorFieldsFromComponents:position:scalingPercent:shear:
//
// Purpose:		Restores the palette to reflect the state of the object. Scale
//				is converted to percentage. Shear is stuffed into x/y/z despite
//				the bad name mismatches.
//
//------------------------------------------------------------------------------
+ (void)inspectorFieldsFromComponents:(TransformComponents)components
							 position:(Point3 *)outPosition
					   scalingPercent:(Vector3 *)outScaling
								shear:(Tuple3 *)outShear
{
	if (outPosition != NULL)
		*outPosition = components.translate;
	if (outScaling != NULL)
		*outScaling = V3MulScalar(components.scale, 100.0); //convert to percentage.
	if (outShear != NULL)
	{
		Tuple3 shear = ZeroPoint3;
		shear.x = components.shear_XY;
		shear.y = components.shear_XZ;
		shear.z = components.shear_YZ;
		*outShear = shear;
	}
}


//---------- inspectorScalingPercent:differsFromComponents: ----------[static]--
//
// Purpose:		The user had been editing the scaling percentages; now he has
//				stopped. We need to find out if he actually changed something.
//
//------------------------------------------------------------------------------
+ (BOOL)inspectorScalingPercent:(Vector3)formContents
		  differsFromComponents:(TransformComponents)components
{
	return formContents.x != components.scale.x * 100.0
		|| formContents.y != components.scale.y * 100.0
		|| formContents.z != components.scale.z * 100.0;
}


//---------- inspectorShear:differsFromComponents: -------------------[static]--
//
// Purpose:		The user had been editing the shear; now he has stopped.
//				(Please disregard the meaningless x, y, and z tags in the
//				formContents.)
//
//------------------------------------------------------------------------------
+ (BOOL)inspectorShear:(Tuple3)formContents
 differsFromComponents:(TransformComponents)components
{
	return formContents.x != components.shear_XY
		|| formContents.y != components.shear_XZ
		|| formContents.z != components.shear_YZ;
}


//---------- partInspectorRotationDegreesForComponents:rotationType: -[static]--
//
// Purpose:		Fills in the rotation angles based on the data-entry mode:
//				absolute or relative.
//
//				An absolute rotation means that the actual rotation angles for
//				the part are displayed and edited. A relative rotation means
//				that whatever we enter in is *added to* the current angles.
//
//------------------------------------------------------------------------------
+ (Tuple3)partInspectorRotationDegreesForComponents:(TransformComponents)components
									   rotationType:(LDrawPartInspectorRotationT)rotationType
{
	if (rotationType == LDrawPartInspectorRotationRelative)
		return ZeroPoint3;
	Tuple3 rotation = ZeroPoint3;
	rotation.x = degrees(components.rotate.x);
	rotation.y = degrees(components.rotate.y);
	rotation.z = degrees(components.rotate.z);
	return rotation;
}


//---------- componentsByApplyingAbsoluteRotationDegrees:toComponents:
//
// Purpose:		An absolute rotation. Convert from degrees.
//
//------------------------------------------------------------------------------
+ (TransformComponents)componentsByApplyingAbsoluteRotationDegrees:(Tuple3)rotationDegrees
													  toComponents:(TransformComponents)components
{
	components.rotate.x = radians(rotationDegrees.x);
	components.rotate.y = radians(rotationDegrees.y);
	components.rotate.z = radians(rotationDegrees.z);
	return components;
}


//---------- relativeRotationShortcutTagForAngle:currentTag: ---------[static]--
//
// Purpose:		See if we recognize the angles as something we provide a
//				shortcut for. If currentTag is already Custom, it is left
//				alone.
//
//------------------------------------------------------------------------------
+ (NSInteger)relativeRotationShortcutTagForAngle:(Tuple3)angle currentTag:(NSInteger)currentTag
{
	if (currentTag == LDrawStepInspectorRotationShortcutCustom)
		return currentTag;
	if (V3PointsWithinTolerance(angle, V3Make(0, 0, 180)) == YES)
		return LDrawStepInspectorRotationShortcutUpsideDown;
	if (V3PointsWithinTolerance(angle, V3Make(0, 90, 0)) == YES)
		return LDrawStepInspectorRotationShortcutClockwise90;
	if (V3PointsWithinTolerance(angle, V3Make(0, -90, 0)) == YES)
		return LDrawStepInspectorRotationShortcutCounterClockwise90;
	if (		V3PointsWithinTolerance(angle, V3Make(0, 180, 0)) == YES
		||	V3PointsWithinTolerance(angle, V3Make(180, 0, 180)) == YES ) // an alternate decomposition that comes out of Bricksmith's math
		return LDrawStepInspectorRotationShortcutBackside;
	return LDrawStepInspectorRotationShortcutCustom;
}


//---------- absoluteRotationShortcutTagForAngle:currentTag: ---------[static]--
//
// Purpose:		If the angle is a known head-on view, select that, otherwise,
//				call it "custom." If currentTag is already Custom, it is left
//				alone.
//
//------------------------------------------------------------------------------
+ (NSInteger)absoluteRotationShortcutTagForAngle:(Tuple3)angle currentTag:(NSInteger)currentTag
{
	if (currentTag == LDrawStepInspectorRotationShortcutCustom)
		return currentTag;
	ViewOrientationT viewOrientation = [LDrawUtilities viewOrientationForAngle:angle];
	if (viewOrientation != ViewOrientation3D)
		return viewOrientation;
	return LDrawStepInspectorRotationShortcutCustom;
}


//---------- stepInspectorAngleForRotationType:shortcutTag: ----------[static]--
//
// Purpose:		Sets the xyz values of the angle field according to the
//				selection in the pop-up menu.
//
//------------------------------------------------------------------------------
+ (Tuple3)stepInspectorAngleForRotationType:(LDrawStepRotationT)rotationType
								shortcutTag:(NSInteger)shortcutTag
						customAbsoluteAngle:(Tuple3)customAbsoluteAngle
{
	if (rotationType == LDrawStepRotationRelative)
	{
		switch (shortcutTag)
		{
			case LDrawStepInspectorRotationShortcutUpsideDown:
				return V3Make(0, 0, 180);
			case LDrawStepInspectorRotationShortcutClockwise90:
				return V3Make(0, 90, 0);
			case LDrawStepInspectorRotationShortcutCounterClockwise90:
				return V3Make(0, -90, 0);
			case LDrawStepInspectorRotationShortcutBackside:
				return V3Make(0, 180, 0);
			case LDrawStepInspectorRotationShortcutCustom:
				return V3Make(0, 0, 0);
			default:
				return ZeroPoint3;
		}
	}
	if (rotationType == LDrawStepRotationAbsolute)
	{
		if (shortcutTag == LDrawStepInspectorRotationShortcutCustom)
			return customAbsoluteAngle;
		return [LDrawUtilities angleForViewOrientation:(ViewOrientationT)shortcutTag];
	}
	return ZeroPoint3;
}


//---------- stepInspectorConstraintsForRotationType: ----------------[static]--
//
// Purpose:		Enables what should be enabled, and disables what should not be
//				enabled.
//
//------------------------------------------------------------------------------
+ (LDrawStepInspectorConstraints)stepInspectorConstraintsForRotationType:(LDrawStepRotationT)rotationType
													 relativeShortcutTag:(NSInteger)relativeTag
													 absoluteShortcutTag:(NSInteger)absoluteTag
{
	LDrawStepInspectorConstraints constraints = { NO, NO, NO, NO };
	constraints.relativePopupEnabled = (rotationType == LDrawStepRotationRelative);
	constraints.absolutePopupEnabled = (rotationType == LDrawStepRotationAbsolute);

	if (	rotationType == LDrawStepRotationRelative
	   &&	relativeTag == LDrawStepInspectorRotationShortcutCustom)
	{
		constraints.angleFieldsEnabled = YES;
	}
	else if (	rotationType == LDrawStepRotationAbsolute
			&&	absoluteTag == LDrawStepInspectorRotationShortcutCustom)
	{
		constraints.angleFieldsEnabled     = YES;
		constraints.viewAngleButtonVisible = YES;
	}
	else if (rotationType == LDrawStepRotationAdditive)
	{
		constraints.angleFieldsEnabled = YES;
	}
	return constraints;
}


//---------- displayViewingAngleFromAngle: ---------------------------[static]--
//
// Purpose:		I seem to be beset by −0. I don't want to display −0!
//
//------------------------------------------------------------------------------
+ (Tuple3)displayViewingAngleFromAngle:(Tuple3)angle
{
	angle.x = round(angle.x);
	angle.y = round(angle.y);
	angle.z = round(angle.z);
	return angle;
}


//---------- inspectorClassNameForObject: ----------------------------[static]--
//
// Purpose:		Inspectable objects will tell us what class to use to inspect
//				with. The host still instantiates the AppKit inspector.
//
//------------------------------------------------------------------------------
+ (NSString *)inspectorClassNameForObject:(id)object
{
	if ([object respondsToSelector:@selector(inspectorClassName)])
		return [object inspectorClassName];
	return nil;
}


//---------- inspectorPoint:differsFromPoint: ----------------------[static]--
//
// Purpose:		The user had been editing the coordinate; now he has stopped.
//				We need to find out if he actually changed something. If so,
//				update the object.
//
//------------------------------------------------------------------------------
+ (BOOL)inspectorPoint:(Point3)edited differsFromPoint:(Point3)original
{
	return V3EqualPoints(edited, original) == NO;
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


//---------- outlineItemForCopyDragContainerLookupWithCurrentItem:... [static]--
//
// Purpose:		If we are doing a copy-drag operation, remember the original
//				selection and use it. (We can't use the current selection during
//				copy drag because we clear it when the drag begins.)
//
//------------------------------------------------------------------------------
+ (id)outlineItemForCopyDragContainerLookupWithCurrentItem:(id)currentItem
									selectedBeforeCopyDrag:(NSArray *)beforeCopy
{
	if ([beforeCopy count] > 0)
		return [beforeCopy objectAtIndex:0];
	return currentItem;
}


//---------- prepareViewDragOriginals:asCopy: ------------------------[static]--
//
// Purpose:		The parts you see being dragged around are always copies of the
//				originals. When we aren't actually doing a copy drag, we just
//				hide the originals.
//
//------------------------------------------------------------------------------
+ (void)prepareViewDragOriginals:(NSArray *)drawables asCopy:(BOOL)copyFlag
{
	if (copyFlag == NO)
		[self setHidden:YES forDirectives:drawables];
}


//---------- hideShowUndoActionKeyForHidden: -------------------------[static]--
//
// Purpose:		Undo-aware call to change the visibility attribute of an
//				element. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)hideShowUndoActionKeyForHidden:(BOOL)hideFlag
{
	if (hideFlag == YES)
		return @"UndoHidePart";
	return @"UndoShowPart";
}


//---------- moveUndoActionKey ---------------------------------------[static]--
+ (NSString *)moveUndoActionKey
{
	return @"UndoMove";
}


//---------- rotateUndoActionKey ------------------------------------[static]--
//
// Purpose:		Undo action name key for rotating the selection. The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)rotateUndoActionKey
{
	return @"UndoRotate";
}


//---------- colorUndoActionKey -------------------------------------[static]--
//
// Purpose:		Undo action name key for coloring the selection. The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)colorUndoActionKey
{
	return @"UndoColor";
}


//---------- snapToGridUndoActionKey --------------------------------[static]--
//
// Purpose:		Undo action name key for snapping the selection to the grid.
//				The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)snapToGridUndoActionKey
{
	return @"UndoSnapToGrid";
}


//---------- setGroupUndoActionKey ----------------------------------[static]--
//
// Purpose:		Undo action name key for assigning an MLCAD group. The host
//				still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)setGroupUndoActionKey
{
	return @"UndoSetGroup";
}


//---------- inspectorErrorKeyForSelectionKind: ----------------------[static]--
//
// Purpose:		EmptySelection / MultipleSelection, or nil for Single. The host
//				still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)inspectorErrorKeyForSelectionKind:(LDrawInspectorSelectionKind)kind
{
	switch (kind)
	{
		case LDrawInspectorSelectionEmpty:    return @"EmptySelection";
		case LDrawInspectorSelectionMultiple: return @"MultipleSelection";
		case LDrawInspectorSelectionSingle:   return nil;
	}
	return nil;
}


//---------- inspectorErrorKeyWhenNoInspector ------------------------[static]--
//
// Purpose:		Object has no known inspector. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)inspectorErrorKeyWhenNoInspector
{
	return @"NoInspector";
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


@implementation LDrawPartTransformUpdate
@end
