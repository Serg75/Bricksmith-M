//==============================================================================
//
//  File:       LDrawViewPolicy.m
//  Package:    LDrawEditing
//
//  Purpose:    Foundation-only zoom and scroll policies for the 3D view.
//
//  Created by Sergey Slobodenyuk on 2026-08-27.
//
//==============================================================================

#import <LDrawEditing/LDrawViewPolicy.h>

@implementation LDrawViewPolicy


//---------- zoomChangeFactorFromScrollDeltaY: -----------------------[static]--
//
// Purpose:		Negative means scroll down/zoom out. 1 = increase 100%;
//				-1 = decrease 100%. Magnification function has asymptotes at
//				y = -1 and y = 1 so that the zoomChange will never be a
//				negative number.
//
//------------------------------------------------------------------------------
+ (float)zoomChangeFactorFromScrollDeltaY:(float)scrollDelta
{
	float magnification = scrollDelta / (fabsf(scrollDelta) + 17.0f);
	return 1.0f + magnification;
}


//---------- scrollDeltaScaleForPreciseScrolling: --------------------[static]--
//
// Purpose:		Non-precise: totally arbitrary ×10. Precise: I find default
//				scrolling intolerably touchy. Apply a completely arbitrary
//				slowing factor of 0.5.
//
//------------------------------------------------------------------------------
+ (float)scrollDeltaScaleForPreciseScrolling:(BOOL)precise
{
	return precise ? 0.5f : 10.0f;
}


//---------- scrollDeltaViewportFromEventDelta:viewFlipped: ----------[static]--
//
// Purpose:		Units are viewport points. But direction is very confusing.
//
//				+x means scroll the image rightward
//				    • expose content to left
//				    • shift origin -x
//
//				+y means scroll the image downward
//				   	• expose content above
//				   	• shift origin -y in flipped coordinate system
//				   	• shift origin +y in non-flipped coordinate system
//
//				For, um, reasons?, the x delta from NSEvent is always backward
//				compared to how we want to move the origin.
//
//------------------------------------------------------------------------------
+ (Vector2)scrollDeltaViewportFromEventDelta:(Vector2)scrollDelta
								 viewFlipped:(BOOL)flipped
{
	Vector2 scrollDelta_viewport = scrollDelta;
	scrollDelta_viewport.x *= -1;
	if (flipped)
		scrollDelta_viewport.y *= -1;
	return scrollDelta_viewport;
}


//---------- autoscrollInset -----------------------------------------[static]--
//
// Purpose:		It's more like 50 in AppKit; we use 20 for the no-autoscroll
//				zone inset.
//
//------------------------------------------------------------------------------
+ (float)autoscrollInset
{
	return 20.0f;
}




//---------- shouldSelectPartsOnMouseDownForDraggingBehavior:… -------[static]--
//
// Purpose:		BeginImmediately always selects. ImmediatelyInOrthoNeverIn-
//				Perspective selects only when orthographic.
//
//------------------------------------------------------------------------------
+ (BOOL)shouldSelectPartsOnMouseDownForDraggingBehavior:(MouseDragBehaviorT)behavior
										 isOrthographic:(BOOL)orthographic
{
	switch (behavior)
	{
		case MouseDraggingBeginImmediately:
			return YES;
		case MouseDraggingImmediatelyInOrthoNeverInPerspective:
			return orthographic;
		case MouseDraggingOff:
		case MouseDraggingBeginAfterDelay:
			return NO;
	}
	return NO;
}


//---------- clickAndHoldDelayInterval -------------------------------[static]--
//
// Purpose:		Delay before click-and-hold becomes drag-and-drop.
//
//------------------------------------------------------------------------------
+ (NSTimeInterval)clickAndHoldDelayInterval
{
	return 0.25;
}


//---------- rotateSelectDragActionForBehavior:… ---------------------[static]--
//
// Purpose:		Rotate-select mouseDragged action from drag prefs and tracking
//				state. The host still calls rotationDragged / marquee /
//				directInteraction.
//
//------------------------------------------------------------------------------
+ (LDrawRotateSelectDragAction)rotateSelectDragActionForBehavior:(MouseDragBehaviorT)behavior
											 canBeginDragAndDrop:(BOOL)canBeginDragAndDrop
											  selectionIsMarquee:(BOOL)selectionIsMarquee
												   isPerspective:(BOOL)isPerspective
{
	switch (behavior)
	{
		case MouseDraggingOff:
			return LDrawRotateSelectDragRotateCamera;

		case MouseDraggingBeginAfterDelay:
			// If the delay has elapsed, begin drag-and-drop. Otherwise, just
			// spin the model.
			return canBeginDragAndDrop
				? LDrawRotateSelectDragDirectInteraction
				: LDrawRotateSelectDragRotateCamera;

		case MouseDraggingBeginImmediately:
			return selectionIsMarquee
				? LDrawRotateSelectDragMarqueeSelection
				: LDrawRotateSelectDragDirectInteraction;

		case MouseDraggingImmediatelyInOrthoNeverInPerspective:
			if (isPerspective)
				return LDrawRotateSelectDragRotateCamera;
			return selectionIsMarquee
				? LDrawRotateSelectDragMarqueeSelection
				: LDrawRotateSelectDragDirectInteraction;
	}
	return LDrawRotateSelectDragRotateCamera;
}



//---------- openingZoomPercentageForMainViewport: -------------------[static]--
//
// Purpose:		Brand-new document viewports: main at 100%, detail at 75%.
//
//------------------------------------------------------------------------------
+ (CGFloat)openingZoomPercentageForMainViewport:(BOOL)isMain
{
	if (isMain)
		return 100;
	return 75;
}


//---------- fittedZoomPercentageAfterFit:previousZoom: --------------[static]--
//
// Purpose:		Back out a wee bit so the user has some room to work with his
//				model. When fit left the zoom unchanged, keep previousZoom.
//
//------------------------------------------------------------------------------
+ (CGFloat)fittedZoomPercentageAfterFit:(CGFloat)fitZoom
						   previousZoom:(CGFloat)previousZoom
{
	if (previousZoom != fitZoom)
		return fitZoom * 0.9;
	return previousZoom;
}


//---------- indexOfLargestViewportAmongAreas: -----------------------[static]--
//
// Purpose:		Find the largest viewport. We'll assume that's the one the user
//				wants to be the main one.
//
//------------------------------------------------------------------------------
+ (NSUInteger)indexOfLargestViewportAmongAreas:(NSArray<NSNumber *> *)areas
{
	NSUInteger	largestIndex	= NSNotFound;
	CGFloat		largestArea		= 0.0;
	NSUInteger	counter			= 0;

	for (counter = 0; counter < [areas count]; counter++)
	{
		CGFloat currentArea = [[areas objectAtIndex:counter] doubleValue];
		if (currentArea > largestArea)
		{
			largestArea  = currentArea;
			largestIndex = counter;
		}
	}

	return largestIndex;
}


//---------- zoomChangeFactorFromMagnification: ----------------------[static]--
//
// Purpose:		User is doing the pinch (zoom) trackpad gesture.
//				1 = increase 100%; −1 = decrease 100%.
//
//------------------------------------------------------------------------------
+ (CGFloat)zoomChangeFactorFromMagnification:(CGFloat)magnification
{
	return 1.0 + magnification;
}


//---------- stepActionForSwipeDeltaX: -------------------------------[static]--
//
// Purpose:		Three-finger swipe (forward and back). On the MacBook Air (1st
//				generation), −1 means forward.
//
//------------------------------------------------------------------------------
+ (LDrawSwipeStepAction)stepActionForSwipeDeltaX:(CGFloat)deltaX
{
	if (deltaX == 0)
		return LDrawSwipeStepNone;
	if (deltaX < 0)
		return LDrawSwipeStepForward;
	return LDrawSwipeStepBack;
}



//---------- projectionModeForViewOrientation: -----------------------[static]--
//
// Purpose:		We treat 3D as a request for perspective, but any straight-on
//				view can logically be expected to be displayed orthographically.
//				WalkThrough is also perspective.
//
//------------------------------------------------------------------------------
+ (ProjectionModeT)projectionModeForViewOrientation:(ViewOrientationT)orientation
{
	if (orientation == ViewOrientation3D || orientation == ViewOrientationWalkThrough)
		return ProjectionModePerspective;
	return ProjectionModeOrthographic;
}


//---------- locationModeForViewOrientation: -------------------------[static]--
//
// Purpose:		WalkThrough uses walkthrough location; other orientations use
//				model.
//
//------------------------------------------------------------------------------
+ (LocationModeT)locationModeForViewOrientation:(ViewOrientationT)orientation
{
	if (orientation == ViewOrientationWalkThrough)
		return LocationModeWalkthrough;
	return LocationModeModel;
}


//---------- viewOrientation:fromHotkeyCharacter: --------------------[static]--
//
// Purpose:		Numpad-style viewing-angle hotkeys.
//
//------------------------------------------------------------------------------
+ (BOOL)viewOrientation:(ViewOrientationT *)outOrientation
	fromHotkeyCharacter:(unichar)character
{
	if (outOrientation == NULL)
		return NO;

	switch (character)
	{
		case '4':
			*outOrientation = ViewOrientationLeft;
			return YES;
		case '6':
			*outOrientation = ViewOrientationRight;
			return YES;
		case '2':
			*outOrientation = ViewOrientationBottom;
			return YES;
		case '8':
			*outOrientation = ViewOrientationTop;
			return YES;
		case '5':
			*outOrientation = ViewOrientationFront;
			return YES;
		case '7':
		case '9':
			*outOrientation = ViewOrientationBack;
			return YES;
		case '0':
			*outOrientation = ViewOrientation3D;
			return YES;
	}
	return NO;
}


//---------- marqueeAutoscrollInterval -------------------------------[static]--
//
// Purpose:		Start a timer to fire…if the user parks the mouse in the auto
//				scroll zone this will continuously scroll. I do _not_ know what
//				the correct scrolling interval should be…auto-scroll seems
//				jerky.
//
//------------------------------------------------------------------------------
+ (NSTimeInterval)marqueeAutoscrollInterval
{
	return 0.2;
}

@end
