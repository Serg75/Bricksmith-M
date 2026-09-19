//==============================================================================
//
//  File:       LDrawSceneEditing.h
//  Package:    LDrawEditing
//
//  Purpose:    Adapter from LDrawRenderer to LDrawSceneControllerRendererBridge.
//
//  Info:       RenderCore cannot conform to the scene-controller protocol
//              without depending on Editing. Host views construct the
//              controller with -initWithRenderer:, which wraps the renderer
//              here. Tests and fakes can still pass a custom bridge.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawEditing/LDrawSceneController.h>

@class LDrawRenderer;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawSceneEditing
///
/// @abstract   Forwards scene-controller renderer queries onto LDrawRenderer.
///             Does not category-extend the renderer.
///
//------------------------------------------------------------------------------
@interface LDrawSceneEditing : NSObject <LDrawSceneControllerRendererBridge>

@property (nonatomic, weak, readonly, nullable) LDrawRenderer *renderer;

- (instancetype)initWithRenderer:(LDrawRenderer *)renderer NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
