//==============================================================================
//
//  File:       LDrawTextureMTL.h
//  Package:    LDrawRenderMetal
//
//  Created by Sergey Slobodenyuk on 2024-05-11.
//
//==============================================================================

#import <Metal/Metal.h>

#import <LDrawCore/LDrawTexture.h>

//------------------------------------------------------------------------------
///
/// @class      LDrawTextureMTL
///
/// @abstract   Metal-backed LDrawTexture; holds the MTLTexture of the uploaded
///             image.
///
//------------------------------------------------------------------------------
@interface LDrawTextureMTL : LDrawTexture
{
	__strong id<MTLTexture> metalTexture;
}

@end
