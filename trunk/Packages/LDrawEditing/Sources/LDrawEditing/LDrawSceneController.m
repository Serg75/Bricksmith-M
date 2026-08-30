//==============================================================================
//
//  File:       LDrawSceneController.m
//  Package:    LDrawEditing
//
//  Purpose:    Portable editor scene controller: selection, marquee, and
//              drag-handle interaction. Camera tools stay on LDrawRenderer.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <LDrawEditing/LDrawSceneController.h>

#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawDragHandle.h>
#import <LDrawCore/LDrawDrawableElement.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/MacLDraw.h>
#import <LDrawCore/MatrixMath.h>
#import <LDrawRenderCore/LDrawCamera.h>

#define HANDLE_SIZE 3

@interface LDrawSceneController ()
@property (nonatomic, assign, readwrite) Box2                  selectionMarquee;
@property (nonatomic, assign, readwrite) BOOL                  isTrackingDrag;
@property (nonatomic, assign, readwrite) BOOL                  didPartSelection;
@property (nonatomic, strong, nullable)  LDrawDragHandle      *activeDragHandle;
@property (nonatomic, assign)            BOOL                  isStartingDrag;
@property (nonatomic, assign)            Vector3               draggingOffset;
@property (nonatomic, assign)            Point3                initialDragLocation;

- (BOOL)updateDirectives:(NSArray *)directives
		withDragPosition:(Point2)point_view
	 depthReferencePoint:(Point3)modelReferencePoint
		   constrainAxis:(BOOL)constrainAxis;
@end


@implementation LDrawSceneController

//========== initWithRendererBridge: ==========================================
//
// Purpose:		Create a scene controller that talks to the renderer through
//				the given bridge. Camera tools stay on LDrawRenderer.
//
//==============================================================================
- (instancetype)initWithRendererBridge:(id<LDrawSceneControllerRendererBridge>)bridge
{
	self = [super init];
	if (self)
	{
		_rendererBridge   = bridge;
		_selectionMarquee = ZeroBox2;
		_draggingOffset   = ZeroPoint3;
		_initialDragLocation = ZeroPoint3;
	}
	return self;
}


#pragma mark -
#pragma mark Selection
#pragma mark -

//========== setSelectionMarquee: =============================================
//
// Purpose:		The box (in view coordinates) in which to draw the selection
//				marquee.
//
//				Also copies the box onto the renderer so the overlay can draw.
//
//==============================================================================
- (void)setSelectionMarquee:(Box2)box
{
	_selectionMarquee = box;
	[self.rendererBridge setSelectionMarquee:box];
}


#pragma mark -
#pragma mark Mouse Events
#pragma mark -

//========== mouseMovedToPoint: ===============================================
//
// Purpose:		Mouse is hovering in the view. Forward the point so the host
//				can show model coordinates under the cursor.
//
//==============================================================================
- (void)mouseMovedToPoint:(Point2)point_view
{
	[self.rendererBridge publishMouseOverPoint:point_view];
}


//========== mouseDownAtPoint: ================================================
//
// Purpose:		Signals that a mouse-down has been received; clear various state
//				flags in preparation for selection or dragging.
//
//				The host view is responsible for correct interpretation of the
//				event and routing it to the appropriate methods here. Camera
//				tools stay on LDrawRenderer.
//
//==============================================================================
- (void)mouseDownAtPoint:(Point2)point_view
{
	_isTrackingDrag   = NO;
	_didPartSelection = NO;
	(void)point_view;
}


//========== mouseDraggedToPoint: =============================================
//
// Purpose:		Signals that a mouse-drag has been received; set tracking flags
//				used to distinguish a click from a drag on mouse-up.
//
//				The host view is responsible for correct interpretation of the
//				event and routing it here.
//
//==============================================================================
- (void)mouseDraggedToPoint:(Point2)point_view
{
	_isStartingDrag = (_isTrackingDrag == NO);
	_isTrackingDrag = YES;
	(void)point_view;
}


//========== mouseUpAtPoint: ==================================================
//
// Purpose:		Signals that a mouse-up has been received; clear tracking and
//				drag-handle state in preparation for selection or dragging.
//
//				The marquee is left in place. -[LDrawRenderer mouseUp] inspects
//				its size to decide whether to redisplay, then zeros it.
//
//==============================================================================
- (void)mouseUpAtPoint:(Point2)point_view
{
	// Leave the marquee in place. -[LDrawRenderer mouseUp] inspects its size
	// to decide whether to redisplay, then zeros it. Clearing here (which also
	// syncs through the bridge) made that check always fail, so the overlay
	// could stick until an unrelated redraw.
	_isTrackingDrag   = NO;
	_activeDragHandle = nil;
	(void)point_view;
}


//========== mouseSelectionClickAtPoint:selectionMode: ========================
//
// Purpose:		Attempt to select the part under the click, or start a zero-size
//				marquee if nothing was hit.
//
//				Hit-tests drag handles first, then the model. The nearest
//				directive is offered to the host via the renderer bridge.
//
// Returns:		YES if a directive was hit, NO otherwise.
//
//==============================================================================
- (BOOL)mouseSelectionClickAtPoint:(Point2)point_view selectionMode:(SelectionModeT)selectionMode
{
	id<LDrawSceneControllerRendererBridge> bridge = self.rendererBridge;
	LDrawDirective *clickedDirective = nil;

	[self setSelectionMarquee:V2MakeBox(point_view.x, point_view.y, 0, 0)];

	if (	[bridge LDrawDirective] != nil
	   &&	[bridge allowsEditing] == YES)
	{
		Point2	point_viewport	= [bridge convertPointToViewport:point_view];
		Point2	bl				= V2Make(point_viewport.x - HANDLE_SIZE, point_viewport.y - HANDLE_SIZE);
		Point2	tr				= V2Make(point_viewport.x + HANDLE_SIZE, point_viewport.y + HANDLE_SIZE);
		float	depth			= 1.0;

		Box2	viewport		= [bridge viewport];
		Point2	point_clip		= V2Make( (point_viewport.x - viewport.origin.x) * 2.0 / V2BoxWidth(viewport)  - 1.0,
									     (point_viewport.y - viewport.origin.y) * 2.0 / V2BoxHeight(viewport) - 1.0 );

		float x1 = (MIN(bl.x,tr.x) - viewport.origin.x) * 2.0 / V2BoxWidth (viewport) - 1.0;
		float x2 = (MAX(bl.x,tr.x) - viewport.origin.x) * 2.0 / V2BoxWidth (viewport) - 1.0;
		float y1 = (MIN(bl.y,tr.y) - viewport.origin.x) * 2.0 / V2BoxHeight(viewport) - 1.0;
		float y2 = (MAX(bl.y,tr.y) - viewport.origin.y) * 2.0 / V2BoxHeight(viewport) - 1.0;

		Box2 test_box = V2MakeBoxFromPoints( V2Make(x1, y1), V2Make(x2, y2) );

		LDrawCamera *cam = [bridge camera];
		Matrix4 mvp = Matrix4Multiply(
							Matrix4CreateFromGLMatrix4([cam getModelView]),
							Matrix4CreateFromGLMatrix4([cam getProjection]));

		id bestObject = nil;
		[[bridge LDrawDirective] depthTest:point_clip inBox:test_box transform:mvp creditObject:nil bestObject:&bestObject bestDepth:&depth];
		clickedDirective = bestObject;

		if ([clickedDirective isKindOfClass:[LDrawDragHandle class]])
		{
			_activeDragHandle = (LDrawDragHandle *)clickedDirective;
		}
		else
		{
			_activeDragHandle = nil;

			BOOL extendSelection = selectionMode == SelectionExtend || selectionMode == SelectionIntersection;
			BOOL has_sel_directive = clickedDirective != nil && [clickedDirective isSelected];
			BOOL has_any_directive = clickedDirective != nil;

			switch (selectionMode)
			{
				case SelectionReplace:
					if (!has_sel_directive)
						[bridge wantsToSelectDirective:clickedDirective byExtendingSelection:extendSelection];
					break;

				case SelectionExtend:
					if (has_any_directive)
						[bridge wantsToSelectDirective:clickedDirective byExtendingSelection:extendSelection];
					break;

				case SelectionIntersection:
					if (!has_sel_directive)
						[bridge wantsToSelectDirective:clickedDirective byExtendingSelection:extendSelection];
					break;

				case SelectionSubtract:
					if (has_any_directive && !has_sel_directive)
						[bridge wantsToSelectDirective:clickedDirective byExtendingSelection:extendSelection];
					break;
			}
		}
	}

	_didPartSelection = YES;
	return (clickedDirective == nil) ? NO : YES;
}


//========== mouseSelectionDragToPoint:selectionMode: =========================
//
// Purpose:		Update the selection marquee to the dragged point and select
//				every directive under the rectangle.
//
//				The host maps modifier keys to selectionMode (replace, extend,
//				subtract, intersection).
//
//==============================================================================
- (void)mouseSelectionDragToPoint:(Point2)point_view selectionMode:(SelectionModeT)selectionMode
{
	id<LDrawSceneControllerRendererBridge> bridge = self.rendererBridge;

	[self setSelectionMarquee:V2MakeBoxFromPoints(self.selectionMarquee.origin, point_view)];

	if (	[bridge LDrawDirective] != nil
	   &&	[bridge allowsEditing] == YES)
	{
		NSArray *fineDrawParts = [bridge getDirectivesUnderRect:self.selectionMarquee
												amongDirectives:@[[bridge LDrawDirective]]
													   fastDraw:NO];
		[bridge wantsToSelectDirectives:fineDrawParts selectionMode:selectionMode];
	}

	_didPartSelection = YES;
}


//========== dragHandleDraggedToPoint:constrainDragAxis: ======================
//
// Purpose:		Move the active drag handle (and its vertex) with the mouse.
//
//				If constrainDragAxis is YES, motion is isolated to the greatest
//				component so the handle tracks one world axis.
//
//==============================================================================
- (void)dragHandleDraggedToPoint:(Point2)point_view constrainDragAxis:(BOOL)constrainDragAxis
{
	id<LDrawSceneControllerRendererBridge> bridge = self.rendererBridge;
	if (self.activeDragHandle == nil)
	{
		return;
	}

	Point3 modelReferencePoint = [self.activeDragHandle position];
	[bridge publishMouseOverPoint:point_view];

	if (self.isStartingDrag)
	{
		[bridge willBeginDraggingHandle:self.activeDragHandle];
	}

	BOOL moved = [self updateDirectives:@[self.activeDragHandle]
					   withDragPosition:point_view
					depthReferencePoint:modelReferencePoint
						  constrainAxis:constrainDragAxis];

	if (moved)
	{
		[bridge noteNeedsDisplay];
		[bridge dragHandleDidMove:self.activeDragHandle];
	}
}


#pragma mark -
#pragma mark Drag and Drop
#pragma mark -

//========== setDraggingOffset: ===============================================
//
// Purpose:		Record the offset from the first dragged part to the click, so
//				re-entering the originating view does not snap part 0 under the
//				mouse.
//
//==============================================================================
- (void)setDraggingOffset:(Vector3)offset
{
	_draggingOffset = offset;
}


//========== draggingEnteredAtPoint: ==========================================
//
// Purpose:		Place dragged parts in the model at the given view point.
//
//				If setTransform is YES, each part receives the host's preferred
//				transform (identity when the renderer has no delegate). Locally
//				originated drags are a move; others are a copy.
//
//==============================================================================
- (void)draggingEnteredAtPoint:(Point2)point_view
					directives:(NSArray *)directives
				  setTransform:(BOOL)setTransform
			 originatedLocally:(BOOL)originatedLocally
{
	id<LDrawSceneControllerRendererBridge> bridge = self.rendererBridge;
	LDrawDrawableElement *firstDirective = [directives objectAtIndex:0];
	Point3 modelReferencePoint = [firstDirective position];

	if (setTransform == YES)
	{
		LDrawPart *newPart = [directives objectAtIndex:0];
		[newPart setTransformComponents:[bridge preferredPartTransform]];
	}

	if (originatedLocally == YES)
	{
		modelReferencePoint = V3Add(modelReferencePoint, self.draggingOffset);
	}
	else
	{
		[self setDraggingOffset:ZeroPoint3];
	}

	self.initialDragLocation = modelReferencePoint;

	[self updateDirectives:directives
		  withDragPosition:point_view
	   depthReferencePoint:modelReferencePoint
			 constrainAxis:NO];

	id file = [bridge LDrawDirective];
	if ([file respondsToSelector:@selector(setDraggingDirectives:)])
	{
		[file setDraggingDirectives:directives];
		[bridge noteNeedsDisplay];
	}
}


//========== updateDragWithPosition:constrainAxis: ============================
//
// Purpose:		Move currently-dragged parts as the mouse moves.
//
//				Displacement is snapped to the current grid. Axis constraint
//				isolates the greatest component of the cumulative move.
//
//==============================================================================
- (void)updateDragWithPosition:(Point2)point_view constrainAxis:(BOOL)constrainAxis
{
	id<LDrawSceneControllerRendererBridge> bridge = self.rendererBridge;
	id file = [bridge LDrawDirective];

	[bridge publishMouseOverPoint:point_view];

	if ([file respondsToSelector:@selector(draggingDirectives)])
	{
		NSArray *directives = [file draggingDirectives];
		LDrawDrawableElement *firstDirective = [directives objectAtIndex:0];
		Point3 modelReferencePoint = V3Add([firstDirective position], self.draggingOffset);

		BOOL moved = [self updateDirectives:directives
						   withDragPosition:point_view
						depthReferencePoint:modelReferencePoint
							  constrainAxis:constrainAxis];
		if (moved)
		{
			[bridge noteNeedsDisplay];
		}
	}
}


//========== endDragging ======================================================
//
// Purpose:		Clear draggingDirectives on the file being drawn and ask the
//				renderer to redisplay.
//
//==============================================================================
- (void)endDragging
{
	id file = [self.rendererBridge LDrawDirective];
	if ([file respondsToSelector:@selector(setDraggingDirectives:)])
	{
		[file setDraggingDirectives:nil];
		[self.rendererBridge noteNeedsDisplay];
	}
}


//========== updateDirectives:withDragPosition:depthReferencePoint:constrainAxis: =
//
// Purpose:		Apply a grid-snapped displacement to directives based on the
//				new view point relative to the depth reference.
//
//				Returns YES if anything actually moved.
//
//==============================================================================
- (BOOL)updateDirectives:(NSArray *)directives
		withDragPosition:(Point2)point_view
	 depthReferencePoint:(Point3)modelReferencePoint
		   constrainAxis:(BOOL)constrainAxis
{
	id<LDrawSceneControllerRendererBridge> bridge = self.rendererBridge;
	LDrawDrawableElement *firstDirective = [directives objectAtIndex:0];
	Point3 oldPosition = modelReferencePoint;
	Point3 modelPoint = [bridge modelPointForPoint:point_view depthReferencePoint:modelReferencePoint];
	Vector3 displacement = V3Sub(modelPoint, oldPosition);
	Vector3 cumulativeDisplacement = V3Sub(modelPoint, self.initialDragLocation);

	if (constrainAxis == YES)
	{
		cumulativeDisplacement = V3IsolateGreatestComponent(cumulativeDisplacement);
		Point3 constrainedPosition = V3Add(self.initialDragLocation, cumulativeDisplacement);
		displacement = V3Sub(constrainedPosition, oldPosition);
	}

	displacement = [firstDirective position:displacement snappedToGrid:[bridge gridSpacing]];

	if (V3EqualPoints(displacement, ZeroPoint3) == NO)
	{
		for (id directive in directives)
		{
			[directive moveBy:displacement];
		}
		return YES;
	}
	return NO;
}

@end
