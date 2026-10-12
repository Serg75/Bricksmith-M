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

//------------------------------------------------------------------------------
///
/// @class      LDrawRenderer
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

// Pictures
/// Draws the directive once, off screen, into a picture of the given size in pixels.
/// The camera must already be set up for a surface of the same shape. Waits for the GPU.
/// With transparent, the background is clear instead of the background color.
- (nullable CGImageRef) newImageWithPixelSize:(CGSize)pixelSize transparent:(BOOL)transparent CF_RETURNS_RETAINED;

/// A picture of a directive seen straight on with no perspective, on a clear
/// background. `size` is in points and `scale` is pixels per point. The zoom
/// and the center mean what they do for a view. Call it on the main thread.
+ (nullable CGImageRef) newImageOfDirective:(nullable LDrawDirective *)directive
									 center:(Point3)center
							 zoomPercentage:(CGFloat)zoomPercentage
									   size:(CGSize)size
									  scale:(CGFloat)scale CF_RETURNS_RETAINED;

@end

NS_ASSUME_NONNULL_END
