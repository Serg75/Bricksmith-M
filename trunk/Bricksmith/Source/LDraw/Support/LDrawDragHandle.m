//==============================================================================
//
// File:		LDrawDragHandle.m
//
// Purpose:		In-scene widget to manipulate a vertex.
//
// Modified:	02/25/2011 Allen Smith. Creation Date.
//
//==============================================================================
#import "LDrawDragHandle.h"

#import OPEN_GL_HEADER
#import OPEN_GL_EXT_HEADER
#import <stdlib.h>

#import "LDrawUtilities.h"

// moved to category
//// Shared tag to draw the standard drag handle sphere
//static GLuint   vaoTag          = 0;
//static GLuint   vboTag          = 0;
//static GLuint   vboVertexCount  = 0;

// moved to header
//static const float HandleDiameter	= 7.0;


@implementation LDrawDragHandle

//========== initWithTag:position: =============================================
//
// Purpose:		Initialize the object with a tag to identify what vertex it is 
//				connected to. 
//
//==============================================================================
- (id) initWithTag:(NSInteger)tagIn
		  position:(Point3)positionIn
{
	self = [super init];
	if(self)
	{
		tag             = tagIn;
		position        = positionIn;
		initialPosition = positionIn;
	}
	
	return self;

}//end initWithTag:position:


#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

//========== initialPosition ===================================================
//
// Purpose:		Returns the coordinate this handle what at when initialized.
//
//==============================================================================
- (Point3) initialPosition
{
	return self->initialPosition;
}


//========== isSelected ========================================================
//
// Purpose:		Drag handles only show up when their associated primitive is 
//				selected, so we always report being selected. This will make us 
//				more transparent to the view selection code. 
//
//==============================================================================
- (BOOL) isSelected
{
	return YES;
}


//========== position ==========================================================
//
// Purpose:		Returns the world-coordinate location of the handle.
//
//==============================================================================
- (Point3) position
{
	return self->position;
}


//========== tag ===============================================================
//
// Purpose:		Returns the identifier for this handle. Used to associate the 
//				handle with a vertex. 
//
//==============================================================================
- (NSInteger) tag
{
	return self->tag;
}


//========== target ============================================================
//
// Purpose:		Returns the object which owns the drag handle.
//
//==============================================================================
- (id) target
{
	return self->target;
}


#pragma mark -

//========== setAction: ========================================================
//
// Purpose:		Sets the method to invoke when the handle is repositioned.
//
//==============================================================================
- (void) setAction:(SEL)actionIn
{
	self->action = actionIn;
}


//========== setPosition:updateTarget: =========================================
//
// Purpose:		Updates the current handle position, and triggers the action if 
//				update flag is YES. 
//
//==============================================================================
- (void) setPosition:(Point3)positionIn
		updateTarget:(BOOL)update
{
	self->position = positionIn;
	
	if(update)
	{
		[self->target performSelector:self->action withObject:self];
	}
}//end setPosition:updateTarget:


//========== setTarget: ========================================================
//
// Purpose:		Sets the object to invoke the action on.
//
//==============================================================================
- (void) setTarget:(id)sender
{
	self->target = sender;
}


#pragma mark -
#pragma mark DRAWING
#pragma mark -


//========== drawSelf: ===========================================================
//
// Purpose:		Draw this directive and its subdirectives by calling APIs on 
//				the passed in renderer, then calling drawSelf on children.
//
// Notes:		Drag handles don't use DLs - they simply push their pos
//				to the renderer immediately.
//
//================================================================================
- (void) drawSelf:(id<LDrawCoreRenderer>)renderer
{
	GLfloat xyz[3] = { position.x, position.y, position.z };	
	[renderer drawDragHandle:xyz withSize:HandleDiameter/2];

}//end drawSelf:



//========== hitTest:transform:viewScale:boundsOnly:creditObject:hits: =======
//
// Purpose:		Tests the directive for an intersection between the pickRay and 
//				spherical drag handle. 
//
//==============================================================================
- (void) hitTest:(Ray3)pickRay
	   transform:(Matrix4)transform
	   viewScale:(float)scaleFactor
	  boundsOnly:(BOOL)boundsOnly
	creditObject:(id)creditObject
			hits:(NSMutableDictionary *)hits
{
	float   handleScale     = 0.0;
	float   drawRadius      = 0.0;
	float   intersectDepth  = 0;
	bool    intersects      = false;
	
	handleScale = 1.0 / scaleFactor;
	drawRadius  = HandleDiameter/2 * handleScale;
	drawRadius  *= 1.5; // allow a little fudge

	
	intersects = V3RayIntersectsSphere(pickRay, self->position, drawRadius, &intersectDepth);

	if(intersects)
	{
		[LDrawUtilities registerHitForObject:self depth:intersectDepth creditObject:creditObject hits:hits];
	}
}//end hitTest:transform:viewScale:boundsOnly:creditObject:hits:


//========== depthTest:inBox:transform:creditObject:bestObject:bestDepth:=======
//
// Purpose:		depthTest finds the closest primitive (in screen space) 
//				overlapping a given point, as well as its device coordinate
//				depth.
//
//==============================================================================
- (void)	depthTest:(Point2) pt 
				inBox:(Box2)bounds 
			transform:(Matrix4)transform 
		 creditObject:(id)creditObject 
		   bestObject:(id *)bestObject 
			bestDepth:(float *)bestDepth
{
	Vector3 v1    = V3MulPointByProjMatrix(self->position, transform);
	if(V2BoxContains(bounds,V2Make(v1.x,v1.y)))
	{
		if(v1.z <= *bestDepth)
		{
			*bestDepth = v1.z;
			*bestObject = creditObject ? creditObject : self;
		}
	}
}//end depthTest:inBox:transform:creditObject:bestObject:bestDepth:


#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== moveBy: ===========================================================
//
// Purpose:		Displace the receiver by the given amounts in each direction. 
//				The amounts in moveVector or relative to the element's current 
//				location.
//
//				Subclasses are required to move by exactly this amount. Any 
//				adjustments they wish to make need to be returned in 
//				-displacementForNudge:.
//
//==============================================================================
- (void) moveBy:(Vector3)moveVector
{
	Point3 newPosition = V3Add(self->position, moveVector);
	
	[self setPosition:newPosition updateTarget:YES];
	
}//end moveBy:


@end
