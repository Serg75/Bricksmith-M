//==============================================================================
//
//	File:		PartLibraryMTL.h
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

#import "GPU.h"
#import LDrawTextureGPU_h


@interface PartLibraryMTL : PartLibrary

// Initialization
+ (PartLibraryMTL *) sharedPartLibrary;

- (id<MTLTexture>)metalTextureForTexture:(LDrawTextureGPU*)texture;

@end
