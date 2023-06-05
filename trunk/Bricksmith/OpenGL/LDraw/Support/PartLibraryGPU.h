//==============================================================================
//
//	File:		PartLibraryGPU.m
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

#import "LDrawTexture.h"

@interface PartLibrary (OpenGL)

- (GLuint) textureTagForTexture:(LDrawTexture*)texture;

@end
