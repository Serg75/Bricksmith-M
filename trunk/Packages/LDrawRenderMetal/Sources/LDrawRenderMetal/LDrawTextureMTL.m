//==============================================================================
//
//  File:       LDrawTextureMTL.m
//  Package:    LDrawRenderMetal
//
//  Created by Sergey Slobodenyuk on 2024-05-11.
//
//==============================================================================

#import <LDrawRenderMetal/LDrawTextureMTL.h>

#import <LDrawRenderMetal/PartLibraryMTL.h>


@implementation LDrawTextureMTL

//---------- load ----------------------------------------------------[static]--
//
// Purpose:		Registers this renderer-specific subclass as the LDrawTexture
//				class used by the model parser. Replaces the legacy
//				`LDrawTextureGPU` macro indirection.
//
//------------------------------------------------------------------------------
+ (void)load
{
	[LDrawTexture registerTextureClass:[LDrawTextureMTL class]];
} // end load


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
- (void)drawSelf:(id<LDrawCoreRenderer>)renderer
{
	NSArray 		*commands			= [self subdirectives];
	LDrawDirective	*currentDirective	= nil;

	if (self->metalTexture == nil)
		self->metalTexture = [[PartLibraryMTL sharedPartLibrary] metalTextureForTexture:self];

	struct LDrawTextureSpec spec = [self textureSpecWithHandle:(__bridge void *)self->metalTexture];

	[renderer pushTexture:&spec];
	for (currentDirective in commands)
	{
		[currentDirective drawSelf:renderer];
	}
	[renderer popTexture];
	
} // end drawSelf:


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
- (void)collectSelf:(id<LDrawCollector>)renderer
{
	NSArray 		*commands			= [self subdirectives];
	LDrawDirective	*currentDirective	= nil;

	if (self->metalTexture == nil)
		self->metalTexture = [[PartLibraryMTL sharedPartLibrary] metalTextureForTexture:self];

	struct LDrawTextureSpec spec = [self textureSpecWithHandle:(__bridge void *)self->metalTexture];

	[renderer pushTexture:&spec];
	for (currentDirective in commands)
	{
		[currentDirective collectSelf:renderer];
	}
	[renderer popTexture];
	[self revalCache:DisplayList];

} // end collectSelf:


@end
