//==============================================================================
//
//  File:       LDrawCoreRenderer.h
//  Package:    LDrawCore
//
//  Purpose:    Renderer interface seen by model directives. Concrete renderers
//              live in LDrawRenderCore / LDrawRenderMetal / LDrawRenderOpenGL
//              and implement these protocols. The struct/type declarations in
//              this header are intentionally renderer-independent so the same
//              LDrawCore binary can be linked against either GPU renderer.
//
//==============================================================================

#ifndef LDrawCoreRenderer_h
#define LDrawCoreRenderer_h

#import <Foundation/Foundation.h>

////////////////////////////////////////////////////////////////////////////////////////////////////
//
// TEXTURE DEFINITIONS
//
////////////////////////////////////////////////////////////////////////////////////////////////////

// The rendering API defines a public structure for standard LDraw texturing for the purpose of
// drawing.

enum {
	tex_proj_planar = 0
};

enum {					// Culling codes from renderer culling checks.
	cull_skip,			// Don't draw - object is off screen or too-small-to-care.
	cull_box,			// Draw, but consider replacing with a box for speed - the object is rather small.
	cull_draw			// Draw, the object is on screen and big.
};

// LDrawTextureSpec.tex_obj is an opaque, renderer-defined texture handle. On
// Metal-backed builds this stores an id<MTLTexture> bridged as void* (the
// texture object is kept alive by the owning LDrawTexture; the DL never
// outlives the model it caches). On OpenGL-backed builds this stores a GLuint
// widened to uintptr_t and re-narrowed when binding. NULL means untextured.
// Using a plain void* keeps the struct POD so the renderer is free to memcpy /
// memcmp / memset it the way the existing display-list code does.
struct	LDrawTextureSpec {
	int					projection;
	void * _Nullable	tex_obj;
	float				plane_s[4];
	float				plane_t[4];
};

////////////////////////////////////////////////////////////////////////////////////////////////////
//
// META-COLOR BEHAVIOR
//
////////////////////////////////////////////////////////////////////////////////////////////////////

// These "fake" ptrs can be used in place of a float[4] RGBA color for the meta-colors.
#define LDrawRenderCurrentColor    ((float *) 0)
#define LDrawRenderComplementColor ((float *) -1)


////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Opaque Display List Handles
//
////////////////////////////////////////////////////////////////////////////////////////////////////

// The rendering API defines an opaque display list handle that a renderer/collector can return.
// The cleanup function defines a function ptr used to dispose of the display list that a directive
// might be retaining.

typedef void * _Nullable LDrawMeshHandle;							// Opaque handle; NULL if the display list is empty.
typedef void (* _Nullable LDrawMeshCleanup_f)(LDrawMeshHandle who);	// Cleanup function associated with a given DL.

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @protocol   LDrawCollector
///
/// @abstract   Accumulates meshes in a fixed coordinate system. A texture stack
///             can be used to push/pop texture state; if no texture state is
///             pushed, the mesh ends up capable of taking the current texture.
///
//------------------------------------------------------------------------------
@protocol LDrawCollector

// Texture stack - sets up new texturing.  When the stack is totally popped, no texturing is applied.
- (void)pushTexture:(struct LDrawTextureSpec *)tex_spec;
- (void)popTexture;

// Raw drawing APIs to push one quad/tri/line/cond_line.
// Vertices are consecutive float verts, e.g. 12 for quad/cond_line, 9 for tri, 6 for line
// Color can be null to use the current color.  Normal is a float[3] normal ptr.
- (void)drawQuad:(float *) vertices normal:(float *) normal color:(nullable float *)color;
- (void)drawTri:(float *) vertices normal:(float *) normal color:(nullable float *)color;
- (void)drawLine:(float *) vertices normal:(float *) normal color:(nullable float *)color;
- (void)drawConditionalLine:(float *) vertices normal:(float *) normal color:(nullable float *)color;

@end


//------------------------------------------------------------------------------
///
/// @protocol   LDrawCoreRenderer
///
/// @abstract   Visits each directive, which calls the various state routines.
///             Provides stacks for color, transform, wire frame, and texture.
///             Meshes are drawn via begin/end/draw DL, which yields an
///             LDrawCollector that actually receives the mesh.
///
//------------------------------------------------------------------------------
@protocol LDrawCoreRenderer
@required

// Matrix stack.  The new matrix is accumulated onto the existing transform.
- (void)pushMatrix:(float *)matrix;
- (void)popMatrix;

// Returns a cull code indicating whether the AABB from minXYZ to maxXYZ is on screen and big enough
// to be worth drawing.
- (int)checkCull:(float *)minXYZ to:(float *)maxXYZ;

// This draws a plane AABB cube in the current color from minXYZ to maxXYZ.
// It can be used for cheap bounding-box approximations of small bricks.
- (void)drawBoxFrom:(float *)minXyz to:(float *)maxXyz;

// Color stack.  Pushing a color overrides the current color.  If no one ever sets the current color we get
// that generic beige that is the RGBA of color 16.
- (void)pushColor:(nullable float *)color;
- (void)popColor;

// Wire frame count - if a non-zero number of wire frame requests are outstanding, we render in wireframe.
- (void)pushWireFrame;
- (void)popWireFrame;

// Alpha modulation stack.  While factors are outstanding, their product scales the alpha of every
// fragment drawn, including geometry reached by nested directives further down the traversal.  This
// is how a removed MLCAD group draws as a translucent "ghost"; pushing a translucent color instead
// does not work, because the parts inside a submodel push their own opaque colors one level down and
// would override it.
//
// The factor travels to the shader with the draw call rather than being folded into the colors,
// because a mesh can carry colors of its own that the current color never reaches -- printed parts,
// stickers, anything multi-colored in the part file itself.  It is never baked into a display list
// either, because display lists are cached and shared between every reference to the same part.
- (void)pushAlphaModulation:(float)factor;
- (void)popAlphaModulation;

// Texture stack - sets up new texturing.  When the stack is totally popped, no texturing is applied.
- (void)pushTexture:(struct LDrawTextureSpec *)tex_spec;
- (void)popTexture;

// Draw drag handle at a given location (3 floats).  The coordinates are within the current
// transform.  The size is in screen pixels.
- (void)drawDragHandle:(float *)xyz withSize:(float)size;

// Begin/end for a display list.  Multiple display lists can be "open" for recording at one time;
// each one returns its own collector object.  However, only the most recently (innermost)
// display list can be accumulated into at one time.  (This is a bit of a defect of the API that we
// should consider some day fixing.)
- (id<LDrawCollector>)beginDL;
- (void)endDL:(LDrawMeshHandle * _Nonnull)outHandle cleanupFunc:(LDrawMeshCleanup_f * _Nonnull)func;	// *outHandle is NULL if the display list is empty

- (void)drawDL:(LDrawMeshHandle)dl;

@end

NS_ASSUME_NONNULL_END

#endif /* LDrawCoreRenderer_h */
