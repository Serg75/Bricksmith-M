//==============================================================================
//
//  File:       LDrawInspection.m
//  Package:    LDrawEditing
//
//  Purpose:    Inspector and color-panel packing. The host still owns the
//              AppKit inspector and applies undo.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <LDrawEditing/LDrawInspection.h>

#import <LDrawCore/ColorLibrary.h>
#import <LDrawCore/LDrawUtilities.h>
#import <LDrawCore/MatrixMath.h>

#import <math.h>

@implementation LDrawInspection



//---------- inspectorObjectListFromObject: --------------------------[static]--
//
// Purpose:		Convenience method for -inspectObjects.
//
//------------------------------------------------------------------------------
+ (NSArray *)inspectorObjectListFromObject:(id)object
{
	if (object != nil)
		return @[object];
	return @[];
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

@end
