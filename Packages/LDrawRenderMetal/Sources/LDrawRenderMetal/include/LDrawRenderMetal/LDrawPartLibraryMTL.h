//==============================================================================
//
//  File:       LDrawPartLibraryMTL.h
//  Package:    LDrawRenderMetal
//
//  Purpose:    This is the centralized repository for obtaining information
//              about the contents of the LDraw folder.
//
//  Info:       Metal-backed subclass of LDrawPartLibrary.
//
//  Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import <LDrawCore/LDrawPartLibrary.h>

#import <LDrawRenderMetal/LDrawTextureMTL.h>

NS_ASSUME_NONNULL_BEGIN

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

- (nullable id<MTLTexture>)metalTextureForTexture:(LDrawTextureMTL *)texture;

@end

NS_ASSUME_NONNULL_END
