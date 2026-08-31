//==============================================================================
//
//  File:       LDrawPartLibraryMTL.h
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

#import <LDrawCore/LDrawPartLibrary.h>

#import <LDrawRenderMetal/LDrawTextureMTL.h>


//------------------------------------------------------------------------------
///
/// @class      LDrawPartLibraryMTL
///
/// @abstract   This is the centralized repository for obtaining information
///             about the contents of the LDraw folder.
///
//------------------------------------------------------------------------------
@interface LDrawPartLibraryMTL : LDrawPartLibrary

// Initialization
+ (LDrawPartLibraryMTL *) sharedPartLibrary;

- (id<MTLTexture>)metalTextureForTexture:(LDrawTextureMTL *)texture;

@end
