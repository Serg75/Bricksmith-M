//==============================================================================
//
//	File:		PartLibraryGPU.m
//
//	Purpose:	This is the centralized repository for obtaining information
//				about the contents of the LDraw folder.
//
//	Info:		This category contains Metal-related code.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import "PartLibrary.h"

#import "LDrawTexture.h"


@interface PartLibrary (Metal)

- (GLuint) textureTagForTexture:(LDrawTexture*)texture;

@end
