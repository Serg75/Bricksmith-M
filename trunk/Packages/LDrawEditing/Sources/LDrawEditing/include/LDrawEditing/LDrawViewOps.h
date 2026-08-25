//==============================================================================
//
//  File:       LDrawViewOps.h
//  Package:    LDrawEditing
//
//  Purpose:    Foundation-only zoom, scroll, and mouse-drag policies for the 3D
//              view. The host still reads NSEvent and drives the renderer.
//
//  Created by Sergey Slobodenyuk on 2026-08-27.
//
//==============================================================================

#import <Foundation/Foundation.h>
#import <LDrawCore/LDrawUtilities.h>
#import <LDrawCore/MacLDraw.h>
#import <LDrawCore/MatrixMath.h>
#import <LDrawRenderCore/LDrawCamera.h>

NS_ASSUME_NONNULL_BEGIN

/// What RotateSelectTool does during mouseDragged for the current drag prefs.
typedef NS_ENUM(NSInteger, LDrawRotateSelectDragAction) {
	LDrawRotateSelectDragRotateCamera       = 0,
	LDrawRotateSelectDragDirectInteraction  = 1,
	LDrawRotateSelectDragMarqueeSelection   = 2
};

/// Three-finger swipe → step navigation. Vertical (deltaX == 0) is ignored.
typedef NS_ENUM(NSInteger, LDrawSwipeStepAction) {
	LDrawSwipeStepNone    = 0,
	LDrawSwipeStepForward = 1,
	LDrawSwipeStepBack    = 2
};


//------------------------------------------------------------------------------
///
/// @class      LDrawViewOps
///
/// @abstract   Foundation-only zoom, scroll, and mouse-drag policies for the 3D
///             view. The host still reads NSEvent and drives the renderer.
///
//------------------------------------------------------------------------------
@interface LDrawViewOps : NSObject

/// Magnification asymptote: delta / (|delta| + 17). Zoom change is 1 + that.
/// Preserves the Purpose comment from LDrawView scrollWheel:.
+ (float)zoomChangeFactorFromScrollDeltaY:(float)scrollDelta;

/// Non-precise trackpad/mouse: ×10. Precise: ×0.5 (slowing factor).
+ (float)scrollDeltaScaleForPreciseScrolling:(BOOL)precise;

/// Flip X always; flip Y when the view is flipped. Units are viewport points.
+ (Vector2)scrollDeltaViewportFromEventDelta:(Vector2)scrollDelta
								 viewFlipped:(BOOL)flipped;

/// Inset used for the no-autoscroll zone (more like 50 in AppKit).
+ (float)autoscrollInset;

/// BeginImmediately, or ImmediatelyInOrtho when orthographic → select now.
+ (BOOL)shouldSelectPartsOnMouseDownForDraggingBehavior:(MouseDragBehaviorT)behavior
										 isOrthographic:(BOOL)orthographic;

/// Delay before click-and-hold becomes drag-and-drop (0.25 s).
+ (NSTimeInterval)clickAndHoldDelayInterval;

/// Rotate-select mouseDragged action from drag prefs and tracking state.
+ (LDrawRotateSelectDragAction)rotateSelectDragActionForBehavior:(MouseDragBehaviorT)behavior
											 canBeginDragAndDrop:(BOOL)canBeginDragAndDrop
											  selectionIsMarquee:(BOOL)selectionIsMarquee
												   isPerspective:(BOOL)isPerspective;

/// Brand-new document viewports: main at 100%, detail at 75%.
+ (CGFloat)openingZoomPercentageForMainViewport:(BOOL)isMain;

/// After zoomToFit, back out 10% when fit changed the zoom so the model isn’t
/// edge-flush. Returns previousZoom when fit left the zoom unchanged.
+ (CGFloat)fittedZoomPercentageAfterFit:(CGFloat)fitZoom
						   previousZoom:(CGFloat)previousZoom;

/// Index of the largest area (width×height). NSNotFound if areas is empty.
+ (NSUInteger)indexOfLargestViewportAmongAreas:(NSArray<NSNumber *> *)areas;

/// Trackpad pinch: 1 + magnification (1 = increase 100%; −1 = decrease 100%).
+ (CGFloat)zoomChangeFactorFromMagnification:(CGFloat)magnification;

+ (LDrawSwipeStepAction)stepActionForSwipeDeltaX:(CGFloat)deltaX;


/// We treat 3D / WalkThrough as perspective; straight-on views are orthographic.
+ (ProjectionModeT)projectionModeForViewOrientation:(ViewOrientationT)orientation;

/// WalkThrough → walkthrough location; otherwise model.
+ (LocationModeT)locationModeForViewOrientation:(ViewOrientationT)orientation;

/// Numpad-style viewing-angle hotkeys: 4/6/2/8/5/7|9/0.
+ (BOOL)viewOrientation:(ViewOrientationT *)outOrientation
	fromHotkeyCharacter:(unichar)character;

/// Marquee parked in the autoscroll zone: repeating timer interval.
+ (NSTimeInterval)marqueeAutoscrollInterval;

@end

NS_ASSUME_NONNULL_END
