//==============================================================================
//
//  File:       LDrawInspection.h
//  Package:    LDrawEditing
//
//  Purpose:    Foundation-only packing for the inspector and color panel.
//              The host still loads NIBs and applies undo.
//
//  Info:       Empty/multiple/single selection, part and step inspector
//              fields, rotation shortcut tags, last-object color, and
//              inspector error keys.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/MatrixMath.h>

@class LDrawColor;

NS_ASSUME_NONNULL_BEGIN

/// Inspector takes an array so it can show a multiple-selection message.
/// Pass a single element to inspect anything.
typedef NS_ENUM(NSInteger, LDrawInspectorSelectionKind) {
	LDrawInspectorSelectionEmpty    = 0,
	LDrawInspectorSelectionMultiple = 1,
	LDrawInspectorSelectionSingle   = 2
};

/// Inspector rotation popup tags (absolute = 0, relative = 1).
typedef NS_ENUM(NSInteger, LDrawPartInspectorRotationT) {
	LDrawPartInspectorRotationAbsolute = 0,
	LDrawPartInspectorRotationRelative = 1
};

/// Step-inspector shortcut tags. Custom is −1 for both popups; relative
/// shortcuts are 0–3; absolute head-on views match LDrawViewOrientation.
typedef NS_ENUM(NSInteger, LDrawStepInspectorRotationShortcutT) {
	LDrawStepInspectorRotationShortcutCustom              = -1,
	LDrawStepInspectorRotationShortcutUpsideDown          = 0,
	LDrawStepInspectorRotationShortcutClockwise90         = 1,
	LDrawStepInspectorRotationShortcutCounterClockwise90  = 2,
	LDrawStepInspectorRotationShortcutBackside            = 3
};

typedef struct {
	BOOL relativePopupEnabled;
	BOOL absolutePopupEnabled;
	BOOL angleFieldsEnabled;
	BOOL viewAngleButtonVisible;
} LDrawStepInspectorConstraints;


//------------------------------------------------------------------------------
///
/// @class      LDrawInspection
///
/// @abstract   Inspector and color-panel packing. The host still owns the
///             AppKit inspector and applies undo.
///
//------------------------------------------------------------------------------
@interface LDrawInspection : NSObject

/// Convenience for inspectObject:. Nil becomes an empty list; otherwise a
/// one-element array. The host still calls inspectObjects:.
+ (NSArray *)inspectorObjectListFromObject:(nullable id)object;

/// Nil or empty → Empty; more than one → Multiple; otherwise Single.
+ (LDrawInspectorSelectionKind)inspectorSelectionKindForObjects:(nullable NSArray *)objects;

/// First object when the selection is Single; otherwise nil.
+ (nullable id)singleInspectableObjectInSelection:(nullable NSArray *)objects;

/// Color of the last selected object when it is colorable; otherwise the
/// fallback. If two or more directives have different colors, the last
/// object’s color is displayed. The host still sets the panel.
+ (nullable LDrawColor *)colorOfLastObjectInSelection:(nullable NSArray *)selection
										fallingBackTo:(nullable LDrawColor *)currentColor;

/// Scale is entered as a percentage. Rotation is kept from oldComponents
/// (the Apply button owns rotation). Shear x/y/z → shear_XY/XZ/YZ.
+ (TransformComponents)inspectorComponentsFromPosition:(Point3)position
										scalingPercent:(Vector3)scaling
												 shear:(Tuple3)shear
										 oldComponents:(TransformComponents)oldComponents;

+ (void)inspectorFieldsFromComponents:(TransformComponents)components
							 position:(Point3 * _Nullable)outPosition
					   scalingPercent:(Vector3 * _Nullable)outScaling
								shear:(Tuple3 * _Nullable)outShear;

+ (BOOL)inspectorScalingPercent:(Vector3)formContents
		  differsFromComponents:(TransformComponents)components;

+ (BOOL)inspectorShear:(Tuple3)formContents
 differsFromComponents:(TransformComponents)components;

/// Relative rotation shows zeros; absolute shows degrees of the part’s
/// rotation. The host still writes the fields.
+ (Tuple3)partInspectorRotationDegreesForComponents:(TransformComponents)components
									   rotationType:(LDrawPartInspectorRotationT)rotationType;

+ (TransformComponents)componentsByApplyingAbsoluteRotationDegrees:(Tuple3)rotationDegrees
													  toComponents:(TransformComponents)components;

/// See if we recognize the angles as something we provide a shortcut for.
/// If currentTag is already Custom, it is left alone. The host still selects
/// the popup item.
+ (NSInteger)relativeRotationShortcutTagForAngle:(Tuple3)angle currentTag:(NSInteger)currentTag;
+ (NSInteger)absoluteRotationShortcutTagForAngle:(Tuple3)angle currentTag:(NSInteger)currentTag;

/// Sets the xyz values of the angle field according to the pop-up.
/// Absolute Custom uses customAbsoluteAngle (the current viewing angle).
+ (Tuple3)stepInspectorAngleForRotationType:(LDrawStepRotationT)rotationType
								shortcutTag:(NSInteger)shortcutTag
						customAbsoluteAngle:(Tuple3)customAbsoluteAngle;

/// Enables what should be enabled. Relative/Absolute popups follow the
/// rotation type; Custom unlocks the angle fields; Absolute Custom also
/// shows the “use current angle” button.
+ (LDrawStepInspectorConstraints)stepInspectorConstraintsForRotationType:(LDrawStepRotationT)rotationType
													 relativeShortcutTag:(NSInteger)relativeTag
													 absoluteShortcutTag:(NSInteger)absoluteTag;

/// I seem to be beset by −0. I don't want to display −0!
+ (Tuple3)displayViewingAngleFromAngle:(Tuple3)angle;

/// AppKit inspector class name for this directive. Nil when the object has no
/// inspector (for example LDrawColor). Empty string for unmapped directives.
+ (nullable NSString *)inspectorClassNameForObject:(id)object;

/// YES when edited coordinates differ from the object’s stored value.
+ (BOOL)inspectorPoint:(Point3)edited differsFromPoint:(Point3)original;

/// EmptySelection / MultipleSelection, or nil for Single. The host still localizes.
+ (nullable NSString *)inspectorErrorKeyForSelectionKind:(LDrawInspectorSelectionKind)kind;

/// NoInspector — object has no known inspector. The host still localizes.
+ (NSString *)inspectorErrorKeyWhenNoInspector;

@end

NS_ASSUME_NONNULL_END
