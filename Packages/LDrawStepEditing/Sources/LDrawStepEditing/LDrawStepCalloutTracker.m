//==============================================================================
//
//  File:       LDrawStepCalloutTracker.m
//  Package:    LDrawStepEditing
//
//  Purpose:    Follows one press on a callout's box or on the button that
//              leads back.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import <LDrawStepEditing/LDrawStepCalloutTracker.h>

#import <LDrawCore/LPubCallout.h>
#import <LDrawFeatures/LDrawStepCallout.h>
#import <LDrawFeatures/LDrawStepCalloutBox.h>
#import <LDrawStepEditing/LDrawStepCalloutEdit.h>


/// How far the pointer must move with the button down before a press on a
/// callout counts as a drag and not a click.
static const double DRAG_SLOP = 3.0;


@interface LDrawStepCalloutTracker ()

@property (nonatomic) BOOL										isDragging;
@property (nonatomic) NSUInteger								draggedBoxIndex;
@property (nonatomic) Point2									dragOrigin;
@property (nonatomic, strong, nullable) LDrawStepCalloutEdit	*edit;
@property (nonatomic, strong, nullable) LDrawStepCallout		*chosenCallout;
@property (nonatomic, strong, nullable) LDrawModel				*chosenSubmodel;

@end


@implementation LDrawStepCalloutTracker
{
	NSArray<LDrawStepCalloutBox *>	*boxes;
	BOOL							 isOnPage;
	Size2							 viewSize;
	Box2							 returnButtonRect;

	/// What the press was on: a callout's BEGIN line, or the tracker itself
	/// for the button. The callouts are collected again on every layout, and
	/// their BEGIN lines stay the same, so a press and its release can be
	/// compared.
	id								 pressedLink;

	/// The press was on a box that can be dragged: where the press was, and
	/// how far from there the box's corner is.
	BOOL							 hasGrab;
	Point2							 grabPoint;
	Point2							 grabOffset;

	/// The drag was abandoned, so the rest of the gesture moves nothing.
	BOOL							 hasAbandonedDrag;
}


//========== showBoxes:onPage:viewSize:returnButtonRect: =======================
- (void) showBoxes:(NSArray<LDrawStepCalloutBox *> *)newBoxes
			onPage:(BOOL)newIsOnPage
		  viewSize:(Size2)newViewSize
  returnButtonRect:(Box2)newReturnButtonRect
{
	self->boxes				= [newBoxes copy];
	self->isOnPage			= newIsOnPage;
	self->viewSize			= newViewSize;
	self->returnButtonRect	= newReturnButtonRect;

}//end showBoxes:onPage:viewSize:returnButtonRect:


//========== reset =============================================================
- (void) reset
{
	self->pressedLink		= nil;
	self->hasGrab			= NO;
	self->hasAbandonedDrag	= NO;
	self.isDragging			= NO;

}//end reset


// MARK: - EVENTS -


//========== isLinkAtPoint: ====================================================
- (BOOL) isLinkAtPoint:(Point2)point
{
	return [self linkAtPoint:point] != nil;

}//end isLinkAtPoint:


//========== beginAtPoint: =====================================================
- (BOOL) beginAtPoint:(Point2)point
{
	[self reset];

	self->pressedLink = [self linkAtPoint:point];

	if (self->pressedLink == nil) {
		return NO;
	}

	// A press on the button is on no box.
	LDrawStepCalloutBox *box = nil;

	if (self->pressedLink != self) {
		box = [LDrawStepCalloutBox boxAtPoint:point amongBoxes:self->boxes];
	}

	// Off the page the boxes are stacked, so there is nothing to move.
	if (self->isOnPage && box.isPlacedByFile) {
		self->hasGrab			= YES;
		self->grabPoint			= point;
		self->grabOffset		= V2Sub(box.frameRect.origin, point);
		self.draggedBoxIndex	= [self->boxes indexOfObjectIdenticalTo:box];
	}

	return YES;

}//end beginAtPoint:


//========== dragToPoint: ======================================================
- (LDrawStepCalloutTrackerResult) dragToPoint:(Point2)point
{
	if (self->hasGrab == NO) {
		return (self->pressedLink != nil) ? LDrawStepCalloutTrackerResultUsed : LDrawStepCalloutTrackerResultNone;
	}

	if (self->hasAbandonedDrag) {
		return LDrawStepCalloutTrackerResultUsed;
	}

	if (self.isDragging == NO) {
		if (hypot(point.x - self->grabPoint.x, point.y - self->grabPoint.y) < DRAG_SLOP) {
			return LDrawStepCalloutTrackerResultUsed;
		}

		// It is a drag now, so letting go follows no link.
		self.isDragging		= YES;
		self->pressedLink	= nil;
	}

	self.dragOrigin = V2Add(point, self->grabOffset);

	return LDrawStepCalloutTrackerResultMoved;

}//end dragToPoint:


//========== endAtPoint:inStep: ================================================
- (LDrawStepCalloutTrackerResult) endAtPoint:(Point2)point inStep:(nullable LDrawStep *)step
{
	id		pressed		= self->pressedLink;
	BOOL	wasDragged	= self.isDragging || self->hasAbandonedDrag;

	self->pressedLink	= nil;
	self->hasGrab		= NO;

	if (wasDragged) {
		self.edit				= self.isDragging ? [self dragEditInStep:step] : nil;
		self.isDragging			= NO;
		self->hasAbandonedDrag	= NO;

		return LDrawStepCalloutTrackerResultDropped;
	}

	if (pressed == nil) {
		return LDrawStepCalloutTrackerResultNone;
	}

	if ([self linkAtPoint:point] != pressed) {
		return LDrawStepCalloutTrackerResultUsed;
	}

	if (pressed == self) {
		return LDrawStepCalloutTrackerResultChoseReturn;
	}

	for (LDrawStepCalloutBox *box in self->boxes) {
		if (box.callout.beginDirective == pressed) {
			self.chosenCallout	= box.callout;
			self.chosenSubmodel	= [box submodelAtPoint:point];
			return LDrawStepCalloutTrackerResultChoseCallout;
		}
	}

	return LDrawStepCalloutTrackerResultUsed;

}//end endAtPoint:inStep:


//========== abandonDrag =======================================================
- (BOOL) abandonDrag
{
	if (self.isDragging == NO) {
		return NO;
	}

	self.isDragging			= NO;
	self->hasAbandonedDrag	= YES;

	return YES;

}//end abandonDrag


// MARK: - PRIVATE -


//========== linkAtPoint: ======================================================
///
/// @abstract	What a point of the view is over: the BEGIN line of a callout,
///				the tracker itself for the button that leads back, or nil.
///
//==============================================================================
- (nullable id) linkAtPoint:(Point2)point
{
	if (V2BoxContains(V2MakeBox(0.0, 0.0, self->viewSize.width, self->viewSize.height), point) == NO) {
		return nil;
	}

	if (V2BoxWidth(self->returnButtonRect) > 0.0 && V2BoxContains(self->returnButtonRect, point)) {
		return self;
	}

	return [LDrawStepCalloutBox boxAtPoint:point amongBoxes:self->boxes].callout.beginDirective;

}//end linkAtPoint:


//========== dragEditInStep: ===================================================
///
/// @abstract	The edit that letting go of the drag makes.
///
/// @discussion	Read from the layout the drag is shown in, so what is written
///				is what is on screen.
///
//==============================================================================
- (nullable LDrawStepCalloutEdit *) dragEditInStep:(nullable LDrawStep *)step
{
	if (self.draggedBoxIndex >= self->boxes.count) {
		return nil;
	}

	LDrawStepCalloutBox *box = self->boxes[self.draggedBoxIndex];

	return [LDrawStepCalloutEdit editMovingBox:box toOrigin:box.frameRect.origin inStep:step];

}//end dragEditInStep:

@end
