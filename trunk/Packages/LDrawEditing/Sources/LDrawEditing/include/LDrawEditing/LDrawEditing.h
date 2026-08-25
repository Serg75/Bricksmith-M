//==============================================================================
//
//  File:       LDrawEditing.h
//  Package:    LDrawEditing
//
//  Purpose:    Umbrella header for the LDrawEditing Swift Package.
//
//  Info:       Selection, drag handles, document tree (nesting / delete rules),
//              selection transforms, clipboard packing, search matching,
//              primitive insert placement, 3D-view zoom/scroll policy, and the
//              portable scene controller extracted from LDrawRenderer. No
//              AppKit or UIKit.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawEditing/LDrawDocumentTree.h>
#import <LDrawEditing/LDrawSceneController.h>
#import <LDrawEditing/LDrawRenderer+SceneControllerBridge.h>
#import <LDrawEditing/LDrawSelectionOps.h>
#import <LDrawEditing/LDrawClipboard.h>
#import <LDrawEditing/LDrawSearchOps.h>
#import <LDrawEditing/LDrawInsertOps.h>
#import <LDrawEditing/LDrawViewOps.h>
