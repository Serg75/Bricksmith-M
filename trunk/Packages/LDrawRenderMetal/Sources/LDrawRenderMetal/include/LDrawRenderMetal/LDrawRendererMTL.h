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

@end
