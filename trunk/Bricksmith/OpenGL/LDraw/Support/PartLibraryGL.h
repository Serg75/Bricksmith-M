//==============================================================================
//
//	File:		PartLibraryGL.m
//
//	Purpose:	This is the centralized repository for obtaining information
//				about the contents of the LDraw folder.
//
//	Info:		This category contains OpenGL-related code.
//
//	Created by Sergey Slobodenyuk on 2023-05-31.
//
//==============================================================================

#import "PartLibrary.h"

#import "GPU.h"
#import LDrawTextureGPU_h


@interface PartLibraryGL : PartLibrary

// Initialization
+ (PartLibraryGL *) sharedPartLibrary;

- (GLuint) textureTagForTexture:(LDrawTextureGPU*)texture;

@end
