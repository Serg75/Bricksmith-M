//==============================================================================
//
// File:		LDrawDrawableElement.m
//
// Purpose:		Abstract superclass for all LDraw elements that can actually be 
//				drawn (polygons and parts). The class wraps common functionality 
//				such as color and mouse-selection.
//
//  Created by Allen Smith on 4/20/05.
//  Copyright (c) 2005. All rights reserved.
//==============================================================================
#import "LDrawDrawableElement.h"

#import "ColorLibrary.h"
#import "LDrawColor.h"
#import "LDrawContainer.h"
#import "LDrawUtilities.h"


@implementation LDrawDrawableElement

#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -


//========== init ==============================================================
//
// Purpose:		Create a fresh object. This is the default initializer.
//
//==============================================================================
- (id) init
{
	self = [super init];
	
	self->hidden = NO;
	
	return self;
	
}//end init


//========== initWithCoder: ====================================================
//
// Purpose:		Reads a representation of this object from the given coder,
//				which is assumed to always be a keyed decoder. This allows us to 
//				read and write LDraw objects as NSData.
//
//==============================================================================
- (id) initWithCoder:(NSCoder *)decoder
{
	self = [super initWithCoder:decoder];
	
	[self setLDrawColor:[decoder	decodeObjectForKey:@"color"]];
	[self setHidden:[decoder		decodeBoolForKey:@"hidden"]];
	
	// If the part's color comes from the library, use the library version 
	// instead of the dearchived one. 
	//
	// Note: This won't help us for file-local colors. They are messy. We don't 
	//		 know what model we belong to until after the part's step has been 
	//		 fully unpacked and added to the model. Only then can we finally 
	//		 retrieve the model's local color library. Currently we have no 
	//		 hooks for that operation; we need a -directiveDidMoveToModel: call 
	//		 and distribute it to all children. 
	ColorLibrary    *colorLibrary   = [ColorLibrary sharedColorLibrary];
	LDrawColor      *libraryColor   = [colorLibrary colorForCode:[self->color colorCode]];
	if(libraryColor)
	{
		[self setLDrawColor:libraryColor];
	}
	
	return self;
	
}//end initWithCoder:


//========== encodeWithCoder: ==================================================
//
// Purpose:		Writes a representation of this object to the given coder,
//				which is assumed to always be a keyed decoder. This allows us to 
//				read and write LDraw objects as NSData.
//
//==============================================================================
- (void) encodeWithCoder:(NSCoder *)encoder
{
	[super encodeWithCoder:encoder];
	
	[encoder encodeObject:self->color	forKey:@"color"];
	[encoder encodeBool:hidden			forKey:@"hidden"];
	
}//end encodeWithCoder:



//========== copyWithZone: =====================================================
//
// Purpose:		Returns a duplicate of this file.
//
//==============================================================================
- (id) copyWithZone:(NSZone *)zone
{
	LDrawDrawableElement *copied = (LDrawDrawableElement *)[super copyWithZone:zone];
	
	// Colors are references, so they don't get copied
	[copied setLDrawColor:[self LDrawColor]];
	
	return copied;
	
}//end copyWithZone:


#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

//========== boundingBox3 ======================================================
//
// Purpose:		Returns the minimum and maximum points of the box which 
//				perfectly contains this object.
//
//==============================================================================
- (Box3) boundingBox3
{
	Box3 bounds = InvalidBox;
	
	//You shouldn't be here. Look in a subclass.
	
	return bounds;
	
}//end boundingBox3


//========== projectedBoundingBoxWithModelView:projection:view: ================
//
// Purpose:		Returns the 2D projection (you should ignore the z) of the 
//				object's bounds. 
//
//==============================================================================
- (Box3) projectedBoundingBoxWithModelView:(Matrix4)modelView
								projection:(Matrix4)projection
									  view:(Box2)viewport;
{
	Box3    bounds          = [self boundingBox3];
	Point3  windowPoint     = ZeroPoint3;
	Box3    projectedBounds = InvalidBox;
	
	if(V3EqualBoxes(bounds, InvalidBox) == NO)
	{		
		// front lower left
		windowPoint     = V3Project(bounds.min,
									modelView, projection, viewport);
		projectedBounds = V3UnionBoxAndPoint(projectedBounds, windowPoint);
		
		// front lower right
		windowPoint     = V3Project(V3Make(bounds.max.x, bounds.min.y, bounds.min.z),
									modelView, projection, viewport);
		projectedBounds = V3UnionBoxAndPoint(projectedBounds, windowPoint);
		
		// front upper right
		windowPoint     = V3Project(V3Make(bounds.max.x, bounds.max.y, bounds.min.z),
									modelView, projection, viewport);
		projectedBounds = V3UnionBoxAndPoint(projectedBounds, windowPoint);
		
		// front upper left
		windowPoint     = V3Project(V3Make(bounds.min.x, bounds.max.y, bounds.min.z),
									modelView, projection, viewport);
		projectedBounds = V3UnionBoxAndPoint(projectedBounds, windowPoint);
		
		// back lower left
		windowPoint     = V3Project(V3Make(bounds.min.x, bounds.min.y, bounds.max.z),
									modelView, projection, viewport);
		projectedBounds = V3UnionBoxAndPoint(projectedBounds, windowPoint);
		
		// back lower right
		windowPoint     = V3Project(V3Make(bounds.max.x, bounds.min.y, bounds.max.z),
									modelView, projection, viewport);
		projectedBounds = V3UnionBoxAndPoint(projectedBounds, windowPoint);
		
		// back upper right
		windowPoint     = V3Project(V3Make(bounds.max.x, bounds.max.y, bounds.max.z),
									modelView, projection, viewport);
		projectedBounds = V3UnionBoxAndPoint(projectedBounds, windowPoint);
		
		// back upper left
		windowPoint     = V3Project(V3Make(bounds.min.x, bounds.max.y, bounds.max.z),
									modelView, projection, viewport);
		projectedBounds = V3UnionBoxAndPoint(projectedBounds, windowPoint);
	}
	
	return projectedBounds;
	
}//end projectedBoundingBoxWithModelView:projection:view:


//========== isHidden ==========================================================
//
// Purpose:		Returns whether this element will be drawn or not.
//
//==============================================================================
- (BOOL) isHidden
{
	return self->hidden;
	
}//end isHidden


//========== LDrawColor ========================================================
//
// Purpose:		Returns the LDraw color code of the receiver.
//
//==============================================================================
-(LDrawColor *) LDrawColor
{
	return color;
	
}//end LDrawColor


//========== position ==========================================================
//
// Purpose:		Returns some position for the element. This is used by 
//				drag-and-drop. This is not necessarily human-usable information.
//
//==============================================================================
- (Point3) position
{
	return ZeroPoint3;
	
}//end position


#pragma mark -

//========== setHidden: ========================================================
//
// Purpose:		Sets whether this part will be drawn, or whether it will be 
//				skipped during drawing. This setting only affects drawing; 
//				hidden parts will always be written out. Also, note that 
//				hiddenness is a temporary state; it is not saved and restored.
//
//==============================================================================
- (void) setHidden:(BOOL) flag
{
	if(self->hidden != flag)
	{
		self->hidden = flag;
		[self invalCache:(CacheFlagBounds|DisplayList)];
	}
	
}//end setHidden:


//========== setLDrawColor: ====================================================
//
// Purpose:		Sets the color of this element.
//
//==============================================================================
- (void) setLDrawColor:(LDrawColor *)newColor
{
	self->color = newColor;
	[self invalCache:(DisplayList)];	// Needed to force anyone who is cached to recompute the new DL with possibly baked color!	
	
}//end setLDrawColor:


#pragma mark -
#pragma mark MOVEMENT
#pragma mark -

//========== displacementForNudge: =============================================
//
// Purpose:		Returns the amount by which the element wants to move, given a 
//				"nudge" in the specified direction. A "nudge" is generated by 
//				pressing the arrow keys. If they feel it appropriate, subclasses 
//				are perfectly welcome to scale this value. (LDrawParts do this.)
//
//==============================================================================
- (Vector3) displacementForNudge:(Vector3)nudgeVector
{
	//possibly refined by subclasses.
	return nudgeVector;
	
}//end displacementForNudge:


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
	//implemented by subclasses.
	
}//end moveBy:


//========== position:snappedToGrid: ===========================================
//
// Purpose:		Orients position at discrete points separated by the given grid 
//				spacing. 
//
// Notes:		This method may be overridden by subclasses to provide more 
//				intelligent grid alignment. 
//
//				This method is provided mainly as a service to drag-and-drop. 
//				In the case of LDrawParts, you should generally avoid this 
//				method in favor of 
//				-[LDrawPart components:snappedToGrid:minimumAngle:].
//
//==============================================================================
- (Point3) position:(Point3)position
	  snappedToGrid:(float)gridSpacing
{
	position.x = roundf(position.x/gridSpacing) * gridSpacing;
	position.y = roundf(position.y/gridSpacing) * gridSpacing;
	position.z = roundf(position.z/gridSpacing) * gridSpacing;
	
	return position;
	
}//end position:snappedToGrid:


#pragma mark -
#pragma mark UTILITIES
#pragma mark -

//==== flattenIntoLines:conditionalLines:triangles:quadrilaterals:other:... ====
//
// Purpose:		Appends the directive into the appropriate container. 
//
// Notes:		This is used to flatten a complicated hiearchy of primitives and 
//				part references to files containing yet more primitives into a 
//				single flat list, which may be drawn to produce a shape visually 
//				identical to the original structure. The flattened structure, 
//				however, has the advantage that it is much faster to traverse 
//				during drawing. 
//
//				This is the core of -[LDrawModel optimizeStructure].
//
//==============================================================================
- (void) flattenIntoLines:(NSMutableArray *)lines
		 conditionalLines:(NSMutableArray *)conditionalLines
				triangles:(NSMutableArray *)triangles
		   quadrilaterals:(NSMutableArray *)quadrilaterals
					other:(NSMutableArray *)everythingElse
			 currentColor:(LDrawColor *)parentColor
		 currentTransform:(Matrix4)transform
		  normalTransform:(Matrix3)normalTransform
				recursive:(BOOL)recursive
{
	// Resolve the correct color and set it. Our subclasses will be responsible 
	// for then adding themselves to the correct list. 

	// Figure out the actual color of the directive.
	
	if([self->color colorCode] == LDrawCurrentColor)
	{
		if([parentColor colorCode] == LDrawCurrentColor)
		{
			// just add
		}
		else
		{
			// set directiveCopy to parent color
			[self setLDrawColor:parentColor];
		}
	}
	else if([self->color colorCode] == LDrawEdgeColor)
	{
		if([parentColor colorCode] == LDrawCurrentColor)
		{
			// just add
		}
		else
		{
			// set directiveCopy to compliment color
			LDrawColor  *complimentColor        = [parentColor complimentColor];
			
			[self setLDrawColor:complimentColor];
			
			// then add.
		}
	}
	else
	{
		// This directive is already explicitly colored. Just add.
	}
	
}//end flattenIntoLines:conditionalLines:triangles:quadrilaterals:other:...


@end
