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
