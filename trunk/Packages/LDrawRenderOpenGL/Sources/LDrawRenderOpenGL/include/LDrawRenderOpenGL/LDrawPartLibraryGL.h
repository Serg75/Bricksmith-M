//==============================================================================
//
//  File:       LDrawPartLibraryGL.h
//  Package:    LDrawRenderOpenGL
//
//  Purpose:    This is the centralized repository for obtaining information
//              about the contents of the LDraw folder.
//
//  Info:       OpenGL-backed subclass of LDrawPartLibrary.
//
//  Created by Sergey Slobodenyuk on 2023-05-31.
//
//==============================================================================

#import <OpenGL/gl.h>
#import <LDrawCore/LDrawPartLibrary.h>

#import <LDrawRenderOpenGL/LDrawTextureGL.h>

NS_ASSUME_NONNULL_BEGIN

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

NS_ASSUME_NONNULL_END
