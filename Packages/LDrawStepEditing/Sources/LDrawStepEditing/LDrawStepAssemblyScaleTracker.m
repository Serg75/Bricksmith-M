//==============================================================================
//
//  File:       LDrawStepAssemblyScaleTracker.m
//  Package:    LDrawStepEditing
//
//  Purpose:    Follows a drag of a handle on the frame around a step being
//              arranged.
//
//  Created by Sergey Slobodenyuk on 2026-10-21.
//
//==============================================================================

#import <LDrawStepEditing/LDrawStepAssemblyScaleTracker.h>


/// The smallest scale a drag asks for, so the step never shrinks to nothing.
static const double MINIMUM_SCALE = 0.05;

/// How far the handle must be from the point the step grows from, in points.
/// Nearer, a small move would change the scale by too much.
static const double MINIMUM_REACH = 4.0;


@implementation LDrawStepAssemblyScaleTracker
{
	/// The point the step grows from, in the view.
	Point2		anchor;

	/// From there to the handle's corner when the drag started.
	Vector2		reach;

	/// Where the pointer took the handle, from its corner.
	Vector2		grab;
}


//========== beginAtPoint:presentation:scale: ==================================
- (BOOL) beginAtPoint:(Point2)point
		 presentation:(nullable LDrawStepPartListPresentation *)presentation
				scale:(double)scale
{
	LDrawStepArrangeHandle handle = [presentation arrangeHandleAtPoint:point];

	self->_handle = LDrawStepArrangeHandleNone;

	if (handle == LDrawStepArrangeHandleNone || scale <= 0.0) {
		return NO;
	}

	Point2 corner = V2BoxMid([presentation rectOfArrangeHandle:handle]);

	self->anchor	= presentation.stepAnchorInView;
	self->reach		= V2Make(corner.x - self->anchor.x, corner.y - self->anchor.y);
	self->grab		= V2Make(point.x - corner.x, point.y - corner.y);

	if (hypot(self->reach.x, self->reach.y) < MINIMUM_REACH) {
		return NO;
	}

	self->_startScale	= scale;
	self->_handle		= handle;

	return YES;

}//end beginAtPoint:presentation:scale:


//========== isScaling =========================================================
- (BOOL) isScaling
{
	return self.handle != LDrawStepArrangeHandleNone;

}//end isScaling


//========== scaleForDragToPoint: ==============================================
///
/// @abstract	The start scale, times how far the handle would be from the
/// 			point the step grows from, along its first line from there.
///
//==============================================================================
- (double) scaleForDragToPoint:(Point2)point
{
	if (self.isScaling == NO) {
		return self.startScale;
	}

	Vector2	moved	= V2Make(point.x - self->grab.x - self->anchor.x, point.y - self->grab.y - self->anchor.y);
	double	along	= moved.x * self->reach.x + moved.y * self->reach.y;
	double	length	= self->reach.x * self->reach.x + self->reach.y * self->reach.y;

	return MAX(self.startScale * along / length, MINIMUM_SCALE);

}//end scaleForDragToPoint:


//========== end ===============================================================
- (void) end
{
	self->_handle = LDrawStepArrangeHandleNone;

}//end end


@end
