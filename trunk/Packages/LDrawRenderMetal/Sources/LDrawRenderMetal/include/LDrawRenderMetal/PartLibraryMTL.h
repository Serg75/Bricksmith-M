//==============================================================================
//
//  File:       PartLibraryMTL.h
//  Package:    LDrawRenderMetal
//
//  Purpose:    This is the centralized repository for obtaining information
//              about the contents of the LDraw folder.
//
//  Info:       This category contains Metal-related code.
//
//  Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import <LDrawCore/PartLibrary.h>

#import <LDrawRenderMetal/LDrawTextureMTL.h>


//------------------------------------------------------------------------------
///
/// @class      PartLibraryMTL
///
/// @abstract   This is the centralized repository for obtaining information
///             about the contents of the LDraw folder.
///
//------------------------------------------------------------------------------
@interface PartLibraryMTL : PartLibrary

// Initialization
+ (PartLibraryMTL *) sharedPartLibrary;

- (id<MTLTexture>)metalTextureForTexture:(LDrawTextureMTL *)texture;

@end
