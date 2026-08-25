//==============================================================================
//
//  File:       LDrawRenderOpenGLResources.h
//  Package:    LDrawRenderOpenGL
//
//  Purpose:    Bundle accessor for GLSL shader resources shipped with the
//              LDrawRenderOpenGL Swift Package.
//
//  Info:       Callers should ask this class for the bundle that owns the
//              package's shaders instead of assuming they live in +[NSBundle
//              mainBundle].
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawRenderOpenGLResources
///
/// @abstract   Bundle accessor for GLSL shader resources shipped with the
///             LDrawRenderOpenGL Swift Package.
///
//------------------------------------------------------------------------------
@interface LDrawRenderOpenGLResources : NSObject

+ (NSBundle *)bundle;

@end

NS_ASSUME_NONNULL_END
