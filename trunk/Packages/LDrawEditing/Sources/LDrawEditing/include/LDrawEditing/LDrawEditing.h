//==============================================================================
//
//  File:       LDrawEditing.h
//  Package:    LDrawEditing
//
//  Purpose:    Host-facing umbrella for the LDrawEditing Swift Package.
//
//  Info:       Selection, document structure, outline and 3D-viewport drop, paste
//              placement, MLCAD groups, inspector packing, clipboard packing,
//              search matching, primitive insert placement, 3D-viewport zoom/scroll
//              policy, and the portable scene controller. Result DTOs are
//              pulled in by the types that return them, not re-exported here.
//              Pasteboard type names are in LDrawPasteboard.h. No AppKit or UIKit.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawEditing/LDrawPasteboard.h>
#import <LDrawEditing/LDrawClipboard.h>
#import <LDrawEditing/LDrawEditorStrings.h>
#import <LDrawEditing/LDrawInsertion.h>
#import <LDrawEditing/LDrawInspection.h>
#import <LDrawEditing/LDrawMLCadGroup.h>
#import <LDrawEditing/LDrawOutline.h>
#import <LDrawEditing/LDrawPaste.h>
#import <LDrawEditing/LDrawRenderer+SceneControllerBridge.h>
#import <LDrawEditing/LDrawSceneController.h>
#import <LDrawEditing/LDrawSearch.h>
#import <LDrawEditing/LDrawSelection.h>
#import <LDrawEditing/LDrawStructure.h>
#import <LDrawEditing/LDrawViewportDrop.h>
#import <LDrawEditing/LDrawViewportPolicy.h>
