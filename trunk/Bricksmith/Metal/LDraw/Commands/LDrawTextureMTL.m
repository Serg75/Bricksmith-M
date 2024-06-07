//
//  LDrawTextureMTL.m
//  Bricksmith-Metal
//
//  Created by Sergey Slobodenyuk on 2024-05-11.
//

#import "LDrawTextureMTL.h"

#import "PartLibraryMTL.h"


@implementation LDrawTextureMTL

//========== drawSelf: ===========================================================
//
// Purpose:		Draw this directive and its subdirectives by calling APIs on
//				the passed in renderer, then calling drawSelf on children.
//
// Notes:		The texture is a container, so it passes drawSelf to give child
//				parts time to draw.  It first pushes its own texture state onto
//				the stack.  This means that an untextured part inside a texture
//				will pick up the projected texture, which is what the LDraw spec
//				calls for.
//
//================================================================================
- (void) drawSelf:(id<LDrawCoreRenderer>)renderer
{
	NSArray 		*commands			= [self subdirectives];
	LDrawDirective	*currentDirective	= nil;

	Vector3 		normal				= ZeroPoint3;
	float			length				= 0;

	if(self->metalTexture == nil)
		self->metalTexture = [[PartLibraryMTL sharedPartLibrary] metalTextureForTexture:self];

	struct LDrawTextureSpec spec;

	normal = V3Sub(self->planePoint2, self->planePoint1);
	length = V3Length(normal);//128./80;//
	normal = V3Normalize(normal);

	spec.plane_s[0] = normal.x / length;
	spec.plane_s[1] = normal.y / length;
	spec.plane_s[2] = normal.z / length;
	spec.plane_s[3] = V3DistanceFromPointToPlane(ZeroPoint3, normal, self->planePoint1) / length;

	normal = V3Sub(self->planePoint3, self->planePoint1);
	length = V3Length(normal);//128./80;//
	normal = V3Normalize(normal);

	spec.plane_t[0] = normal.x / length;
	spec.plane_t[1] = normal.y / length;
	spec.plane_t[2] = normal.z / length;
	spec.plane_t[3] = V3DistanceFromPointToPlane(ZeroPoint3, normal, self->planePoint1) / length;

	spec.projection = tex_proj_planar;
	spec.tex_obj = self->metalTexture;

	[renderer pushTexture:&spec];
	for(currentDirective in commands)
	{
		[currentDirective drawSelf:renderer];
	}
	[renderer popTexture];
	
}//end drawSelf:


//========== collectSelf: ========================================================
//
// Purpose:		Collect self is called on each directive by its parents to
//				accumulate _mesh_ data into a display list for later drawing.
//				The collector protocol passed in is some object capable of
//				remembering the collectable data.
//
// Notes:		LDrawTexture is a collection of sub-directives that all receive
//				projective texturing.  So we first push our texture state to the
//				collector and then recurse.
//
//================================================================================
- (void) collectSelf:(id<LDrawCollector>)renderer
{
	NSArray 		*commands			= [self subdirectives];
	LDrawDirective	*currentDirective	= nil;

	Vector3 		normal				= ZeroPoint3;
	float			length				= 0;

	if(self->metalTexture == nil)
		self->metalTexture = [[PartLibraryMTL sharedPartLibrary] metalTextureForTexture:self];

	struct LDrawTextureSpec spec;

	normal = V3Sub(self->planePoint2, self->planePoint1);
	length = V3Length(normal);//128./80;//
	normal = V3Normalize(normal);

	spec.plane_s[0] = normal.x / length;
	spec.plane_s[1] = normal.y / length;
	spec.plane_s[2] = normal.z / length;
	spec.plane_s[3] = V3DistanceFromPointToPlane(ZeroPoint3, normal, self->planePoint1) / length;

	normal = V3Sub(self->planePoint3, self->planePoint1);
	length = V3Length(normal);//128./80;//
	normal = V3Normalize(normal);

	spec.plane_t[0] = normal.x / length;
	spec.plane_t[1] = normal.y / length;
	spec.plane_t[2] = normal.z / length;
	spec.plane_t[3] = V3DistanceFromPointToPlane(ZeroPoint3, normal, self->planePoint1) / length;

	spec.projection = tex_proj_planar;
	spec.tex_obj = self->metalTexture;

	[renderer pushTexture:&spec];
	for(currentDirective in commands)
	{
		[currentDirective collectSelf:renderer];
	}
	[renderer popTexture];
	[self revalCache:DisplayList];

}//end collectSelf:


@end
