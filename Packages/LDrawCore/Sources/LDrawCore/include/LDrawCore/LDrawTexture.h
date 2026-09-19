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
#import <LDrawCore/LDrawCoreRenderer.h>

NS_ASSUME_NONNULL_BEGIN

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
- (nullable NSString *)glossmapName;
- (NSString *)imageDisplayName;
- (NSString *)imageReferenceName;

- (void)setGlossmapName:(nullable NSString *)newName;
- (void)setImageDisplayName:(NSString *)newName;
- (void)setImageDisplayName:(NSString *)newName parse:(BOOL)shouldParse inGroup:(nullable dispatch_group_t)parentGroup;

// Utilities
+ (BOOL)lineIsTextureBeginning:(NSString*)line;
+ (BOOL)lineIsTextureFallback:(NSString*)line;
+ (BOOL)lineIsTextureTerminator:(NSString*)line;
- (BOOL)parsePlanarTextureFromLine:(NSString *)line parentGroup:(nullable dispatch_group_t)parentGroup;

// Builds the projection the renderer needs to stamp this texture onto the
// enclosed geometry. The renderer subclasses differ only in the kind of
// texture handle they hold, so they pass it in as the opaque `tex_obj` value.
- (struct LDrawTextureSpec)textureSpecWithHandle:(void * _Nullable)textureHandle;

@end

NS_ASSUME_NONNULL_END
