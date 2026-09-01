//==============================================================================
//
//  File:       LDrawRenderer.m
//  Package:    LDrawRenderCore
//
//  Purpose:    Viewport camera, events, and drawing coordinator for LDraw models.
//
//              Platform-independent logic shared by the Metal and OpenGL
//              renderer categories. The host view forwards interpreted events;
//              this class cares about their meaning, not modifier keys.
//
//  Info:       This file uses manual reference counting.
//
//  Created by Allen Smith on 4/17/05.
//  Copyright 2005. All rights reserved.
//
//==============================================================================

#import <LDrawRenderCore/LDrawRenderer.h>

#import "LDrawRendererInternal.h"

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawDragHandle.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LDrawUtilities.h>

#define TIME_BOXTEST				0	// output timing data for how long box tests and marquee drags take.

@implementation LDrawRenderer

#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//========== init ==============================================================
//
// Purpose:		Initialize the object.
//
//==============================================================================
- (id)initWithBounds:(CGSize)boundsIn
{
	self = [super init];
	
	//---------- Initialize instance variables ---------------------------------
	
	[self setLDrawColor:[[LDrawColorLibrary sharedColorLibrary] colorForCode:LDrawCurrentColor]];
	
	camera = [[LDrawCamera alloc] init];
	camera.graphicsSurfaceSize = V2MakeSize(boundsIn.width, boundsIn.height);

	isTrackingDrag				= NO;
	selectionMarquee			= ZeroBox2;
	detailMode					= LDrawDetailNormal;
	gridSpacing 				= 20.0;
		
	[self setViewOrientation:LDrawViewOrientation3D];
	
	return self;
	
} // end initWithFrame:


#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

//========== getInverseMatrix ==================================================
//
// Purpose:		Returns the inverse of the current modelview matrix. You can 
//				multiply points by this matrix to convert screen locations (or 
//				vectors) to model points.
//
// Note:		This function filters out the translation which is caused by 
//				"moving" the camera with gluLookAt. That allows us to continue 
//				working with the model as if it's positioned at the origin, 
//				which means that points we generate with this matrix will 
//				correspond to points in the LDraw model itself.
//
//==============================================================================
- (Matrix4)getInverseMatrix
{
	Matrix4	transformation	= Matrix4CreateFromFloats([camera modelView]);
	Matrix4	inversed		= Matrix4Invert(transformation);
	
	return inversed;
	
} // end getInverseMatrix


//========== getMatrix =========================================================
//
// Purpose:		Returns the the current modelview matrix, basically.
//
// Note:		This function filters out the translation which is caused by 
//				"moving" the camera with gluLookAt. That allows us to continue 
//				working with the model as if it's positioned at the origin, 
//				which means that points we generate with this matrix will 
//				correspond to points in the LDraw model itself. 
//
//==============================================================================
- (Matrix4)getMatrix
{
	return Matrix4CreateFromFloats([camera modelView]);
	
} // end getMatrix


//========== isTrackingDrag ====================================================
//
// Purpose:		Returns YES if a mouse-drag is currently in progress.
//
//==============================================================================
- (BOOL)isTrackingDrag
{
	return self->isTrackingDrag;
}


//========== LDrawColor ========================================================
//
// Purpose:		Returns the LDraw color code of the receiver.
//
//==============================================================================
- (LDrawColor *)LDrawColor
{
	return self->color;
	
} // end color


//========== LDrawDirective ====================================================
//
// Purpose:		Returns the file or model being drawn by this view.
//
//==============================================================================
- (LDrawDirective *)LDrawDirective
{
	return self->fileBeingDrawn;
	
} // end LDrawDirective


//========== camera ============================================================
//
// Purpose:		Returns the camera that owns projection, zoom, and scrolling
//				for this renderer.
//
//==============================================================================
- (LDrawCamera *)camera
{
	return camera;
	
} // end camera


//========== projectionMode ====================================================
//
// Purpose:		Returns the current projection mode (perspective or 
//				orthographic) used in the view.
//
//==============================================================================
- (LDrawProjectionMode)projectionMode
{
	return [camera projectionMode];
	
} // end projectionMode


//========== locationMode ====================================================
//
// Purpose:		Returns the current location mode (model or walkthrough).
//
//==============================================================================
- (LDrawLocationMode)locationMode
{
	return [camera locationMode];
	
} // end locationMode


//========== selectionMarquee ==================================================
//==============================================================================
- (Box2)selectionMarquee
{
	return self->selectionMarquee;
}


//========== viewingAngle ======================================================
//
// Purpose:		Returns the modelview rotation, in degrees.
//
// Notes:		These numbers do *not* include the fact that LDraw has an 
//				upside-down coordinate system. So if this method returns 
//				(0,0,0), that means "Front, looking right-side up." 
//				
//==============================================================================
- (Tuple3)viewingAngle
{
	return [camera viewingAngle];

} // end viewingAngle


//========== viewOrientation ===================================================
//
// Purpose:		Returns the current camera orientation for this view.
//
//==============================================================================
- (LDrawViewOrientation)viewOrientation
{
	return self->viewOrientation;
	
} // end viewOrientation


//========== viewport ==========================================================
//
// Purpose:		Returns the viewport. Origin is the lower-left.
//
//==============================================================================
- (Box2)viewport
{
	Box2	viewport = ZeroBox2;
	viewport.size = camera.graphicsSurfaceSize;
	return viewport;
}


//========== zoomPercentage ====================================================
//
// Purpose:		Returns the percentage magnification being applied to the 
//				receiver. (200 means 2x magnification.)  This is the 'nominal'
//				zoom the user sees - it should be used by UI and tool code.
//
//==============================================================================
- (CGFloat)zoomPercentage
{
	return [camera zoomPercentage];
	
} // end zoomPercentage


//========== zoomPercentageForViewport =========================================
//
// Purpose:		Returns the percentage magnification being applied to drawing;
//				this represents the scale from viewport coordinates (which
//				are always window-manager pixels) to document coordinates 
//				(which DO get scaled).
//
//				Use this routine to convert between view and viewport 
//				coordinates.
//
// Notes:		When walk-through is engaged, zoom controls the camera FOV but
//				leaves the document untouched at window size.  So this routine
//				checks the camera mode and just returns 100.0.
//
//==============================================================================
- (CGFloat)zoomPercentageForViewport
{
	if ([self locationMode] == LDrawLocationModeWalkthrough)
		return 100.0;
	return [camera zoomPercentage];
	
} // end zoomPercentageForViewport


#pragma mark -

//========== setAllowsEditing: =================================================
//
// Purpose:		Sets whether the renderer supports part selection and dragging.
//
// Notes:		Querying a delegate isn't sufficient.
//
//==============================================================================
- (void)setAllowsEditing:(BOOL)flag
{
	self->allowsEditing = flag;
}


//========== allowsEditing ====================================================
//
// Purpose:		Returns whether the renderer supports part selection and dragging.
//
//				Querying a delegate isn't sufficient.
//
//==============================================================================
- (BOOL)allowsEditing
{
	return self->allowsEditing;
}


//========== preferredPartTransform ===========================================
//
// Purpose:		Ask the renderer delegate for the transform to apply to newly
//				dropped parts. Returns identity if the delegate does not
//				implement the optional method.
//
//==============================================================================
- (TransformComponents)preferredPartTransform
{
	if ([delegate respondsToSelector:@selector(LDrawRendererPreferredPartTransform:)])
	{
		return [delegate LDrawRendererPreferredPartTransform:self];
	}
	return IdentityComponents;
}


//========== wantsToSelectDirective:byExtendingSelection: =====================
//
// Purpose:		Forward a single-directive selection request to the renderer
//				delegate when it implements the optional method.
//
//==============================================================================
- (void)wantsToSelectDirective:(LDrawDirective *)directive byExtendingSelection:(BOOL)shouldExtend
{
	if ([delegate respondsToSelector:@selector(LDrawRenderer:wantsToSelectDirective:byExtendingSelection:)])
	{
		[delegate LDrawRenderer:self wantsToSelectDirective:directive byExtendingSelection:shouldExtend];
	}
}


//========== wantsToSelectDirectives:selectionMode: ===========================
//
// Purpose:		Forward a multi-directive selection request to the renderer
//				delegate when it implements the optional method.
//
//==============================================================================
- (void)wantsToSelectDirectives:(NSArray *)directives selectionMode:(LDrawSelectionMode)selectionMode
{
	if ([delegate respondsToSelector:@selector(LDrawRenderer:wantsToSelectDirectives:selectionMode:)])
	{
		[delegate LDrawRenderer:self wantsToSelectDirectives:directives selectionMode:selectionMode];
	}
}


//========== willBeginDraggingHandle: =========================================
//
// Purpose:		Tell the renderer delegate a drag-handle drag is starting.
//
//==============================================================================
- (void)willBeginDraggingHandle:(LDrawDragHandle *)handle
{
	if ([delegate respondsToSelector:@selector(LDrawRenderer:willBeginDraggingHandle:)])
	{
		[delegate LDrawRenderer:self willBeginDraggingHandle:handle];
	}
}


//========== dragHandleDidMove: ===============================================
//
// Purpose:		Tell the renderer delegate the drag handle moved.
//
//==============================================================================
- (void)dragHandleDidMove:(LDrawDragHandle *)handle
{
	if ([delegate respondsToSelector:@selector(LDrawRenderer:dragHandleDidMove:)])
	{
		[delegate LDrawRenderer:self dragHandleDidMove:handle];
	}
}


//========== noteNeedsDisplay =================================================
//
// Purpose:		Ask the file being drawn to mark itself dirty so the view
//				redisplays.
//
//==============================================================================
- (void)noteNeedsDisplay
{
	[[self LDrawDirective] noteNeedsDisplay];
}


//========== setDelegate: ======================================================
//
// Purpose:		Sets the object that acts as the delegate for the receiver. 
//
//				This object relies on the the delegate to interface with the 
//				window manager to do things like scrolling. 
//
//==============================================================================
- (void)setDelegate:(id<LDrawRendererDelegate>)object withScroller:(id<LDrawCameraScroller>)newScroller
{
	// weak link.
	self->delegate = object;
	self->scroller = newScroller;
	[self->camera setScroller:newScroller];

} // end setDelegate:


//========== setGridSpacing: ===================================================
//
// Purpose:		Sets the grid amount by which things are dragged.
//
//==============================================================================
- (void)setGridSpacing:(float)newValue
{
	self->gridSpacing = newValue;
}


//========== gridSpacing =======================================================
//
// Purpose:		Returns the grid amount by which things are dragged.
//
//==============================================================================
- (float)gridSpacing
{
	return self->gridSpacing;
}


//========== setLDrawColor: ====================================================
//
// Purpose:		Sets the base color for parts drawn by this view which have no 
//				color themselves.
//
//==============================================================================
- (void)setLDrawColor:(LDrawColor *)newColor
{
	self->color = newColor;
	
	[self->delegate LDrawRendererNeedsRedisplay:self];

} // end setColor


//========== LDrawDirective: ===================================================
//
// Purpose:		Sets the file being drawn in this view.
//
//				We also do other housekeeping here associated with tracking the 
//				model. We also automatically center the model in the view.
//
//==============================================================================
- (void)setLDrawDirective:(LDrawDirective *)newFile
{
	BOOL    virginView  = (self->fileBeingDrawn == nil);
	Box3	bounds		= InvalidBox;
	
	// Update our variable.
	self->fileBeingDrawn = newFile;
	
	if (newFile)
	{
		bounds = [newFile boundingBox3];
		[camera setModelSize:bounds];
	}

	[self->delegate LDrawRendererNeedsRedisplay:self];
	
	if (virginView == YES)
	{
		[self scrollModelPoint:ZeroPoint3 toViewportProportionalPoint:V2Make(0.5,0.5)];
	}

	// Register for important notifications.
	[[NSNotificationCenter defaultCenter] removeObserver:self name:LDrawDirectiveDidChangeNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:LDrawFileActiveModelDidChangeNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:LDrawModelRotationCenterDidChangeNotification object:nil];
	
	if (self->fileBeingDrawn != nil)
	{	
		[[NSNotificationCenter defaultCenter]
				addObserver:self
				   selector:@selector(displayNeedsUpdating:)
					   name:LDrawDirectiveDidChangeNotification
					 object:self->fileBeingDrawn ];
		
		[[NSNotificationCenter defaultCenter]
				addObserver:self
				   selector:@selector(activeModelDidChange:)
					   name:LDrawFileActiveModelDidChangeNotification
					 object:self->fileBeingDrawn ];
		
		[[NSNotificationCenter defaultCenter]
				addObserver:self
				   selector:@selector(rotationCenterChanged:)
					   name:LDrawModelRotationCenterDidChangeNotification
					 object:self->fileBeingDrawn ];
	}
	
	[self updateRotationCenter];
	
} // end setLDrawDirective:


//========== setGraphicsSurfaceSize: ===========================================
///
/// @abstract	Sets the size of the view which will be rendered with the 3D
/// 			engine. This should be in screen coordinates.
///
//==============================================================================
- (void)setGraphicsSurfaceSize:(Size2)size
{
	[camera setGraphicsSurfaceSize:size];
	[self->delegate LDrawRendererNeedsRedisplay:self];
}


//========== setProjectionMode: ================================================
//
// Purpose:		Sets the projection used when drawing the receiver:
//					- orthographic is like a Mercator map; it distorts deeper 
//									objects.
//					- perspective draws deeper objects toward a vanishing point; 
//									this is how humans see the world.
//
//==============================================================================
- (void)setProjectionMode:(LDrawProjectionMode)newProjectionMode
{
	[camera setProjectionMode:newProjectionMode];
	
	[self->delegate LDrawRendererNeedsRedisplay:self];
	
} //end setProjectionMode:


//========== setLocationMode: ================================================
//
// Purpose:		Sets the location mode used when drawing the receiver.
//					- model points the camera at the model center from a distance.
//					- walk-through puts the camera _on_ the model center.
//
//==============================================================================
- (void)setLocationMode:(LDrawLocationMode)newLocationMode
{
	[camera setLocationMode:newLocationMode];
	
	[self->delegate LDrawRendererNeedsRedisplay:self];
	
} //end setLocationMode:


//========== setSelectionMarquee: ==============================================
//
// Purpose:		The box (in view coordinates) in which to draw the selection 
//				marquee. 
//
//==============================================================================
- (void)setSelectionMarquee:(Box2)newBox_view
{
	self->selectionMarquee = newBox_view;
}


//========== setTarget: ========================================================
//
// Purpose:		Sets the object which is the receiver of this view's action 
//				methods. 
//
//==============================================================================
- (void)setTarget:(id)newTarget
{
	self->target = newTarget;
	
} // end setTarget:


//========== setViewingAngle: ==================================================
//
// Purpose:		Sets the modelview rotation, in degrees. The angle is applied in 
//				x-y-z order. 
//
// Notes:		These numbers do *not* include the fact that LDraw has an 
//				upside-down coordinate system. So if this method returns 
//				(0,0,0), that means "Front, looking right-side up." 
//
//==============================================================================
- (void)setViewingAngle:(Tuple3)newAngle
{
	[camera setViewingAngle:newAngle];
	[self->delegate LDrawRendererNeedsRedisplay:self];

} // end setViewingAngle:


//========== setViewOrientation: ===============================================
//
// Purpose:		Changes the camera position from which we view the model. 
//				i.e., LDrawViewOrientationFront means we see the model head-on.
//
//==============================================================================
- (void)setViewOrientation:(LDrawViewOrientation)newOrientation
{
	Tuple3	newAngle	= [LDrawUtilities angleForViewOrientation:newOrientation];

	self->viewOrientation = newOrientation;
		
	// Apply the angle itself.
	[self setViewingAngle:newAngle];
	[self->delegate LDrawRendererNeedsRedisplay:self];
	
} // end setViewOrientation:


//========== setZoomPercentage: ================================================
//
// Purpose:		Enlarges (or reduces) the magnification on this view. The center 
//				point of the original magnification remains the center point of 
//				the new magnification. Does absolutely nothing if this view 
//				isn't contained within a scroll view.
//
// Parameters:	newPercentage: new zoom; pass 100 for 100%, etc. Automatically 
//				constrained to a minimum of 1%. 
//
//==============================================================================
- (void)setZoomPercentage:(CGFloat)newPercentage
{
	[camera setZoomPercentage:newPercentage];
	[delegate LDrawRendererNeedsRedisplay:self];
}


#pragma mark -
#pragma mark DESTRUCTOR
#pragma mark -

//========== dealloc ===========================================================
//
// Purpose:		Remove notification observers.
//
//==============================================================================
- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
} // end dealloc


@end
