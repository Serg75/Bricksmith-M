//==============================================================================
//
//  File:       LDrawPartLibraryGL.h
//  Package:    LDrawRenderOpenGL
//
//  Purpose:    This is the centralized repository for obtaining information
//              about the contents of the LDraw folder.
//
//  Info:       This category contains OpenGL-related code.
//
//  Created by Sergey Slobodenyuk on 2023-05-31.
//
//==============================================================================

#import <OpenGL/gl.h>
#import <LDrawCore/LDrawPartLibrary.h>

#import <LDrawRenderOpenGL/LDrawTextureGL.h>


//------------------------------------------------------------------------------
///
/// @class      LDrawPartLibraryGL
///
/// @abstract   This is the centralized repository for obtaining information
///             about the contents of the LDraw folder.
///
//------------------------------------------------------------------------------
@interface LDrawPartLibraryGL : LDrawPartLibrary

// Initialization
+ (LDrawPartLibraryGL *)sharedPartLibrary;

- (GLuint)textureTagForTexture:(LDrawTextureGL *)texture;

@end
