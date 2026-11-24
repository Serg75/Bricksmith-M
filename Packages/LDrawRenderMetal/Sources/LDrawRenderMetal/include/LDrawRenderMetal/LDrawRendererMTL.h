//==============================================================================
//
//  File:       LDrawRendererMTL.h
//  Package:    LDrawRenderMetal
//
//  Purpose:    Draws an LDrawFile with Metal.
//
//  Info:       This category contains Metal-related code.
//
//  Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import <LDrawRenderCore/LDrawRenderer.h>

@import MetalKit;

NS_ASSUME_NONNULL_BEGIN

/// The domain of the errors a renderer makes itself, beside Metal's own.
extern NSErrorDomain const LDrawRendererErrorDomain;

typedef NS_ERROR_ENUM(LDrawRendererErrorDomain, LDrawRendererError) {
	/// A picture could not get the memory for its texture or its pixels.
	LDrawRendererErrorPictureMemory		= 1,
	/// A picture's drawing could not be encoded.
	LDrawRendererErrorPictureNotEncoded	= 2,
	/// The GPU failed without an error from Metal.
	LDrawRendererErrorGPUFailed			= 3,
};

/// How frames drawn in a view blend transparent parts.
typedef NS_ENUM(NSInteger, LDrawTransparencySorting) {
	/// Sorted per pixel in the lists, on a GPU that can keep them.
	LDrawTransparencySortingFull,
	/// The same with fewer layers sorted and the rest averaged. It costs about
	/// half as much and looks the same unless a pixel has many layers.
	LDrawTransparencySortingFast,
	/// One part at a time, which costs least.
	LDrawTransparencySortingOff,
};

//------------------------------------------------------------------------------
///
/// @category   LDrawRenderer (Metal)
///
/// @abstract   Draws an LDrawFile with Metal.
///
//------------------------------------------------------------------------------
@interface LDrawRenderer (Metal) <MTKViewDelegate>

// Initialization
- (void) prepareMetal;

// Drawing
- (void) drawInMTKView:(nonnull MTKView *)view;

// Accessors
- (void) setBackgroundColorRed:(float)red green:(float)green blue:(float)blue;

/// The color of the band around parts with an LDrawPart highlight. Orange
/// until it is set.
- (void) setHighlightColorRed:(float)red green:(float)green blue:(float)blue;

/// Called with how long the GPU took for each frame drawn in a view, on a
/// Metal completion thread. Nil stops it.
- (void) setFrameGPUTimeHandler:(nullable void (^)(CFTimeInterval seconds))handler;

/// How frames drawn in a view blend transparent parts. Full until it is set.
/// Pictures always sort them fully where the GPU can.
- (void) setTransparencySorting:(LDrawTransparencySorting)sorting;

/// Called on the main thread when the GPU fails a frame drawn in a view or an
/// off-screen picture, or a picture cannot be made. `picture` tells which. One
/// handler serves every renderer. Nil stops it.
+ (void) setGPUErrorHandler:(nullable void (^)(NSError *error, BOOL picture))handler;

/// Whether transparent parts are drawn with per-pixel lists on this device.
/// Without them they are blended one at a time.
+ (BOOL) drawsTransparentPartsWithLists;

// Pictures
/// Draws the directive once, off screen, into a picture of the given size in pixels.
/// The camera must already be set up for a surface of the same shape. Waits for the GPU.
/// With transparent, the background is clear instead of the background color.
- (nullable CGImageRef) newImageWithPixelSize:(CGSize)pixelSize transparent:(BOOL)transparent CF_RETURNS_RETAINED;

/// A picture of a directive seen straight on with no perspective, on a clear
/// background. `size` is in points and `scale` is pixels per point. The zoom
/// and the center mean what they do for a view, and `outlineWidth` what it
/// does for a renderer. Call it on the main thread.
+ (nullable CGImageRef) newImageOfDirective:(nullable LDrawDirective *)directive
									 center:(Point3)center
							 zoomPercentage:(CGFloat)zoomPercentage
									   size:(CGSize)size
									  scale:(CGFloat)scale
							   outlineWidth:(CGFloat)outlineWidth CF_RETURNS_RETAINED;

/// The same picture in perspective, as a view draws it: the camera stands back
/// from `cameraBounds` and turns around `rotationCenter`. The middle of the box
/// around where `centeredPoints` (Point3 values) are drawn goes in the middle of
/// the picture, and `center` only says how deep that middle is. NULL for
/// InvalidBox bounds.
+ (nullable CGImageRef) newPerspectiveImageOfDirective:(nullable LDrawDirective *)directive
												center:(Point3)center
										zoomPercentage:(CGFloat)zoomPercentage
												  size:(CGSize)size
												 scale:(CGFloat)scale
										  outlineWidth:(CGFloat)outlineWidth
										  cameraBounds:(Box3)cameraBounds
										rotationCenter:(Point3)rotationCenter
										centeredPoints:(NSData *)centeredPoints CF_RETURNS_RETAINED;

/// Draws a directive once off screen, so the meshes it draws with are built
/// now and views only reuse them. Call it on the main thread.
+ (void) prepareDrawingOfDirective:(LDrawDirective *)directive;

@end

NS_ASSUME_NONNULL_END
