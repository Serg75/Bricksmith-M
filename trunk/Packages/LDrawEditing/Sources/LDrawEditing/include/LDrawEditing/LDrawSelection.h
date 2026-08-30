//==============================================================================
//
//  File:       LDrawSelection.h
//  Package:    LDrawEditing
//
//  Purpose:    Foundation-only helpers for rotating, nudging, hiding, and
//              coloring a part selection, and for mapping modifier keys to
//              selection modes.
//
//  Info:       Computes rotation tuples, part-relative axes, rotation-center
//              mode, camera-aligned nudge, world nudge from the first movable,
//              Shift/Option selection modes, hide/color filters, visible
//              enclosed elements, marquee merge, randomized palette assignment,
//              snap/mirror, and toolbar quick-rotate / nudge mapping. The host
//              still applies undoable transforms. Modifier bits match
//              NSEventModifierFlags so an AppKit host can pass
//              event.modifierFlags through unchanged.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/MacLDraw.h>
#import <LDrawCore/MatrixMath.h>

#import <LDrawEditing/LDrawPartTransformUpdate.h>

@class LDrawPart;

NS_ASSUME_NONNULL_BEGIN

typedef enum {
	RotateAroundSelectionCenter = 0,
	RotateAroundPartPositions   = 1,
	RotateAroundFixedPoint      = 2
} RotationModeT;

typedef NS_ENUM(NSInteger, LDrawArrowNudge) {
	LDrawArrowNudgeNone  = 0,
	LDrawArrowNudgeUp    = 1,
	LDrawArrowNudgeDown  = 2,
	LDrawArrowNudgeLeft  = 3,
	LDrawArrowNudgeRight = 4
};

/// Document-toolbar axis for a unit nudge (± tag).
typedef NS_ENUM(NSInteger, LDrawNudgeAxis) {
	LDrawNudgeAxisX = 0,
	LDrawNudgeAxisY = 1,
	LDrawNudgeAxisZ = 2
};

/// Toolbar quick-rotate buttons map to menu tags on X/Y/Z.
typedef NS_ENUM(NSInteger, LDrawQuickRotationAxis) {
	LDrawQuickRotationAxisX = 0,
	LDrawQuickRotationAxisY = 1,
	LDrawQuickRotationAxisZ = 2
};


//------------------------------------------------------------------------------
///
/// @class      LDrawSelection
///
/// @abstract   Foundation-only helpers for rotating, nudging, hiding, and
///             coloring a part selection, and for mapping modifier keys to
///             selection modes.
///
//------------------------------------------------------------------------------
@interface LDrawSelection : NSObject

+ (Tuple3)rotationForAxis:(Vector3)axis degrees:(float)degrees;
+ (Tuple3)partRelativeRotation:(Tuple3)rotation forPart:(LDrawPart *)part;

/// Part-oriented grid: only when a single LDrawPart is selected.
+ (Tuple3)partRelativeRotation:(Tuple3)rotation
				  forSelection:(NSArray *)selection
				  partRelative:(BOOL)partRelative;
+ (RotationModeT)rotationModeForSelectionCount:(NSUInteger)count aroundOrigin:(BOOL)aroundOrigin;

/// Screen-space nudge mapped onto the part's axes using the camera basis.
/// Pass identity for partMatrix to nudge in model space. useTurntable should
/// be YES when the host's rotate mode is turntable and the view is perspective.
+ (Vector3)nudgeVector:(Vector3)screenNudge
			partMatrix:(Matrix4)partMatrix
		  cameraMatrix:(Matrix4)cameraMatrix
		  orthographic:(BOOL)orthographic
		  useTurntable:(BOOL)useTurntable;

/// Shift = 1<<17, Option = 1<<19 (NSEventModifierFlagShift / Option).
+ (SelectionModeT)selectionModeFromModifiers:(NSUInteger)modifiers;

/// Maps an arrow + modifier mask into a screen-space unit nudge.
/// Option moves on Z; Shift ×10; Command ×0.04. Returns NO if arrow is None.
+ (BOOL)screenNudge:(Vector3 *)outNudge
		   forArrow:(LDrawArrowNudge)arrow
		  modifiers:(NSUInteger)modifiers;

+ (NSArray *)movableDirectivesInSelection:(NSArray *)selection;
+ (NSArray *)partsInSelection:(NSArray *)selection;

/// First LDrawPart in the selection, or nil if none.
+ (nullable LDrawPart *)firstPartInSelection:(NSArray *)selection;

/// Shared LDrawPart referenceName among selected parts, or nil if none or mixed.
+ (nullable NSString *)sharedReferenceNameInSelection:(NSArray *)selection;

/// Shared class of every selected object, or Nil if empty or mixed.

/// Identity, or the first selected object's rotation with translation zeroed
/// when partRelative is YES (part-oriented grid).
+ (Matrix4)nudgeOrientationMatrixForSelection:(NSArray *)selection
								 partRelative:(BOOL)partRelative;

/// Scales the screen nudge by gridSpacing, then asks the first movable for
/// displacementForNudge so the whole selection moves the same amount.
+ (BOOL)worldNudge:(Vector3 *)outNudge
   fromScreenNudge:(Vector3)screenNudge
	   gridSpacing:(float)gridSpacing
		 selection:(NSArray *)selection;

/// Shared center for RotateAroundSelectionCenter / FixedPoint.
/// RotateAroundPartPositions still uses each part's origin in the host loop.
+ (Point3)rotationCenterForDirectives:(NSArray *)directives
								 mode:(RotationModeT)mode
						  fixedCenter:(const Point3 * _Nullable)fixedCenter;

/// Origin when the list is empty; otherwise the first drawable’s position.
/// The host still sets the model’s rotation center.
+ (Point3)rotationCenterFromFirstDrawable:(NSArray *)drawables;

/// Marquee merge: replace = new, extend = old|new, subtract = old−new,
/// intersection = old&new. Empty result means the host should deselect.
+ (NSArray *)mergedSelectionWithMarked:(NSArray *)marked
						 newDirectives:(NSArray *)directives
								  mode:(SelectionModeT)mode;

+ (NSArray *)hideableDirectivesInSelection:(NSArray *)selection;
+ (NSArray *)hiddenHideableDirectivesIn:(NSArray *)directives;
+ (NSArray *)colorableDirectivesInSelection:(NSArray *)selection;

/// Hide originals during a move drag so the dragging copy is the only
/// visual manifestation. Unhide before an undoable delete when the drag
/// left the document.
+ (void)setHidden:(BOOL)hidden forDirectives:(NSArray *)directives;

/// While a part is dragged, it is drawn selected.
+ (void)setSelected:(BOOL)selected forDirectives:(NSArray *)directives;

/// Visible enclosed elements of a model. Does not include the steps or model
/// themselves. Hidden elements are ignored. The host still selects in bulk
/// (selectDirective 4000 times is too slow).
+ (NSArray *)visibleDirectivesIn:(NSArray *)directives;

/// YES if any hideable selected element is visible (visibleFlag YES) or hidden
/// (visibleFlag NO). Used to enable Hide Parts / Show Parts.
+ (BOOL)selection:(NSArray *)selection containsVisibility:(BOOL)visibleFlag;

/// One color per colorable directive, drawn from the unique colors already in
/// the set. Consecutive repeats are avoided when the palette has more than one
/// color. The host still applies the colors (undo).
+ (NSArray *)randomizedColorsForDirectives:(NSArray *)colorable;

/// Aligns selected parts to the grid. Kind of a weird legacy API. The host
/// still applies the components (undo).
+ (NSArray<LDrawPartTransformUpdate *> *)snappedTransformUpdatesForSelection:(NSArray *)selection
																 gridSpacing:(float)gridSpacing
																minimumAngle:(float)degrees;

/// Aligns selected parts along one axis of the grid. The host still applies
/// the components (undo).
+ (NSArray<LDrawPartTransformUpdate *> *)snappedTransformUpdatesForSelection:(NSArray *)selection
																 gridSpacing:(float)gridSpacing
																		axis:(Vector3)axis;

/// Move selected parts symmetrically by axis. Pass −1 on components to mirror
/// and 1 on the others. The host still applies the components (undo).
+ (NSArray<LDrawPartTransformUpdate *> *)mirroredTransformUpdatesForSelection:(NSArray *)selection
																		 axis:(Vector3)axis;

/// One of the quick rotation shortcuts was clicked. Build a rotation in the
/// requested direction (deduced from the sender's tag). Returns NO for
/// unrecognized tags; outAxis is unchanged in that case.
+ (BOOL)quickRotationAxis:(Vector3 *)outAxis forMenuTag:(NSInteger)tag;

/// Menu tag for toolbar quick-rotate buttons (rotatePositiveXTag, etc.).
+ (NSInteger)quickRotationMenuTagForAxis:(LDrawQuickRotationAxis)axis
								positive:(BOOL)positive;

/// Toolbar rotation identifiers match both localized string key and image
/// name (Rotate+X, Rotate-X, …). Returns NO when unrecognized.
+ (BOOL)quickRotationAxis:(LDrawQuickRotationAxis *)outAxis
				 positive:(BOOL *)outPositive
	 forToolbarIdentifier:(NSString *)identifier;

/// During a copy drag the outline selection is cleared; use the saved
/// selection when resolving the enclosing container.
+ (nullable id)outlineItemForCopyDragContainerLookupWithCurrentItem:(nullable id)currentItem
											 selectedBeforeCopyDrag:(nullable NSArray *)beforeCopy;

/// Move drags hide the originals; copy drags leave them visible for deselect.
+ (void)prepareViewDragOriginals:(NSArray *)drawables asCopy:(BOOL)copyFlag;

/// Hide → @"UndoHidePart"; show → @"UndoShowPart". The host still localizes.
+ (NSString *)hideShowUndoActionKeyForHidden:(BOOL)hideFlag;

/// Common selection-edit undo localization keys. The host still localizes.
+ (NSString *)moveUndoActionKey;
+ (NSString *)rotateUndoActionKey;
+ (NSString *)colorUndoActionKey;
+ (NSString *)snapToGridUndoActionKey;
+ (NSString *)setGroupUndoActionKey;

/// Toolbar nudge: unit vector on axis × sign (−1 or +1 from the button tag).
+ (Vector3)nudgeUnitVectorForAxis:(LDrawNudgeAxis)axis sign:(NSInteger)sign;

@end

NS_ASSUME_NONNULL_END
