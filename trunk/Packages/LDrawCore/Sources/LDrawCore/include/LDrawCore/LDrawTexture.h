//==============================================================================
//
//  File:       LDrawTexture.h
//  Package:    LDrawCore
//
//  Purpose:    Support for projecting images onto LDraw geometry.
//
//  Modified:   04/10/2012 Allen Smith. Creation Date.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawContainer.h>

//------------------------------------------------------------------------------
///
/// @class      LDrawTexture
///
/// @abstract   Support for projecting images onto LDraw geometry.
///
//------------------------------------------------------------------------------
@interface LDrawTexture : LDrawContainer
{
	NSArray 		*fallback;
	NSString		*imageDisplayName;
	NSString		*imageReferenceName;
	NSString		*glossmapName;

	Point3			planePoint1;
	Point3			planePoint2;
	Point3			planePoint3;

	NSArray			*dragHandles;
	Box3			cachedBounds;		// cached bounds of the enclosed directives
}

// Concrete subclass registry. Renderer packages (LDrawRenderMetal,
// LDrawRenderOpenGL) call +registerTextureClass: at +load time with their
// LDrawTexture subclass; model code uses +textureClass to instantiate the
// correct kind without knowing which renderer is active. Replaces the legacy
// `LDrawTextureGPU` macro from Source/Other/GPU.h.
+ (Class)textureClass;
+ (void)registerTextureClass:(Class)cls;

// Accessors
- (NSString *)glossmapName;
- (NSString *)imageDisplayName;
- (NSString *)imageReferenceName;

- (void)setGlossmapName:(NSString *)newName;
- (void)setImageDisplayName:(NSString *)newName;
- (void)setImageDisplayName:(NSString *)newName parse:(BOOL)shouldParse inGroup:(dispatch_group_t)parentGroup;

// Utilities
+ (BOOL)lineIsTextureBeginning:(NSString*)line;
+ (BOOL)lineIsTextureFallback:(NSString*)line;
+ (BOOL)lineIsTextureTerminator:(NSString*)line;
- (BOOL)parsePlanarTextureFromLine:(NSString *)line parentGroup:(dispatch_group_t)parentGroup;

@end
