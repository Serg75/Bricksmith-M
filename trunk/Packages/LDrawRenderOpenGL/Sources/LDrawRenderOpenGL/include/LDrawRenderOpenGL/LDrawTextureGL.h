//==============================================================================
//
//  File:       LDrawTextureGL.h
//  Package:    LDrawRenderOpenGL
//
//  Created by Sergey Slobodenyuk on 2024-05-10.
//
//==============================================================================

#import <Foundation/Foundation.h>
#import <OpenGL/gl.h>

#import <LDrawCore/LDrawTexture.h>

#import <LDrawCore/LDrawContainer.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawTextureGL
///
/// @abstract   OpenGL-backed LDrawTexture; holds the GLuint of the uploaded
///             image.
///
//------------------------------------------------------------------------------
@interface LDrawTextureGL : LDrawTexture
{
	GLuint			textureTag;
}

@end

NS_ASSUME_NONNULL_END
