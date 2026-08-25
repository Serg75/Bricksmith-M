//==============================================================================
//
//  File:       LDrawPartLibraryGPU.h
//  Package:    LDrawCore
//
//  Purpose:    GPU-agnostic surface the model layer uses to talk to the part
//              library singleton.
//
//  Info:       Replaces the legacy PartLibraryGPU macro from GPU.h. Concrete
//              implementations live in LDrawRenderMetal and LDrawRenderOpenGL;
//              model code calls [PartLibrary sharedPartLibrary] without knowing
//              which subclass was registered at startup.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawPart;
@class LDrawModel;


//------------------------------------------------------------------------------
///
/// @protocol   LDrawPartLibraryGPU
///
/// @abstract   GPU-agnostic surface the model layer uses to talk to the part
///             library singleton.
///
//------------------------------------------------------------------------------
@protocol LDrawPartLibraryGPU <NSObject>

@required
/// Returns a human-readable description of a part by name. Used by tooltips,
/// inspectors, and report generation.
- (NSString *)descriptionForPart:(LDrawPart *)part;
- (NSString *)descriptionForPartName:(NSString *)name;

/// Looks up the cached LDrawModel for the given part reference name.
- (LDrawModel *)modelForName:(NSString *)partName;
- (LDrawModel *)modelForName_threadSafe:(NSString *)partName;

/// Triggers an asynchronous load of the given model into the cache.
- (void)loadModelForName:(NSString *)name inGroup:(dispatch_group_t)parentGroup;
- (void)loadImageForName:(NSString *)imageName inGroup:(dispatch_group_t)parentGroup;

@end
