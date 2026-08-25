//==============================================================================
//
//  File:       PartLibraryGL.h
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
#import <LDrawCore/PartLibrary.h>

#import <LDrawRenderOpenGL/LDrawTextureGL.h>


//------------------------------------------------------------------------------
///
/// @class      PartLibraryGL
///
/// @abstract   This is the centralized repository for obtaining information
///             about the contents of the LDraw folder.
///
//------------------------------------------------------------------------------
@interface PartLibraryGL : PartLibrary

// Initialization
+ (PartLibraryGL *)sharedPartLibrary;

- (GLuint)textureTagForTexture:(LDrawTextureGL *)texture;

@end
