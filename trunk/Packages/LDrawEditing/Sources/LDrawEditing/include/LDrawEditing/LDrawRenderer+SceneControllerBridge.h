//==============================================================================
//
//  File:       LDrawRenderer+SceneControllerBridge.h
//  Package:    LDrawEditing
//
//  Purpose:    Declares LDrawRenderer (LDrawRenderCore) as the renderer bridge
//              for LDrawSceneController.
//
//  Info:       The bridge methods already live on LDrawRenderer; this category
//              only publishes protocol conformance without creating a package
//              dependency cycle.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <LDrawRenderCore/LDrawRenderer.h>
#import <LDrawEditing/LDrawSceneController.h>

//------------------------------------------------------------------------------
///
/// @class      LDrawRenderer
///
/// @abstract   Declares LDrawRenderer (LDrawRenderCore) as the renderer bridge
///             for LDrawSceneController.
///
//------------------------------------------------------------------------------
@interface LDrawRenderer (SceneControllerBridge) <LDrawSceneControllerRendererBridge>
@end
