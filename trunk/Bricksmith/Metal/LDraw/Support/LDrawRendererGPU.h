//==============================================================================
//
//	LDrawRendererGPU.h
//	Bricksmith
//
//	Purpose:	Draws an LDrawFile with Metal.
//
//	Info:		This category contains Metal-related code.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

@import MetalKit;

#import "LDrawRenderer.h"


@interface LDrawRenderer (Metal) <MTKViewDelegate>

// Initialization
- (void) prepareMetal;

// Drawing
- (void) drawInMTKView:(nonnull MTKView *)view;

// Accessors
- (void) setBackgroundColorRed:(float)red green:(float)green blue:(float)blue;

@end
