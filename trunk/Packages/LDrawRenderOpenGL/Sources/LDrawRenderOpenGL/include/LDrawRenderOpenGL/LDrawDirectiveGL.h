//==============================================================================
//
//  File:       LDrawDirectiveGL.h
//  Package:    LDrawRenderOpenGL
//
//  Purpose:    OpenGL drawing category on LDrawDirective.
//
//  Info:       This category contains OpenGL-related code.
//
//  Created by Sergey Slobodenyuk on 2025-05-17.
//
//==============================================================================

#import <LDrawCore/LDrawDirective.h>


//------------------------------------------------------------------------------
///
/// @class      LDrawDirective
///
/// @abstract   OpenGL drawing category on LDrawDirective.
///
//------------------------------------------------------------------------------
@interface LDrawDirective (OpenGL)

// Overrides the base-class no-op `debugDrawBoundingBox` to draw an
// immediate-mode wire box. The selector is already declared on the base
// class; this category supplies the OpenGL implementation.

@end
