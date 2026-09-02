//==============================================================================
//
//  File:       LDrawRenderMetalResources.h
//  Package:    LDrawRenderMetal
//
//  Purpose:    Bundle accessor for Metal shader resources shipped with the
//              LDrawRenderMetal Swift Package.
//
//  Info:       Callers should ask this class for the bundle that owns
//              `default.metallib` instead of assuming shaders live in
//              +[NSBundle mainBundle]. The implementation prefers the package
//              resource bundle. There is no app-bundle fallback: shaders are
//              no longer copied into the host app bundle.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawRenderMetalResources
///
/// @abstract   Bundle accessor for Metal shader resources shipped with the
///             LDrawRenderMetal Swift Package.
///
//------------------------------------------------------------------------------
@interface LDrawRenderMetalResources : NSObject

/// Return the bundle that owns `default.metallib`.
///
/// Prefers `SWIFTPM_MODULE_BUNDLE` when the package declares resources.
/// Otherwise looks for the nested `LDrawRenderMetal_LDrawRenderMetal.bundle`
/// beside the class bundle.
+ (NSBundle *)bundle;

/// Loads `default.metallib` from the package resource bundle. Returns nil
/// (and asserts in debug) if the library is missing; does not fall back to
/// the app bundle.
+ (nullable id<MTLLibrary>)newDefaultLibraryForDevice:(id<MTLDevice>)device;

@end

NS_ASSUME_NONNULL_END
