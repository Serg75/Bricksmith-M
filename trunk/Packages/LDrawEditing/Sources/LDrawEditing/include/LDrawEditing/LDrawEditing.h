//==============================================================================
//
//  File:       LDrawEditing.h
//  Package:    LDrawEditing
//
//  Purpose:    Umbrella header for the LDrawEditing Swift Package.
//
//  Info:       Selection, drag handles, document structure (nesting / delete
//              rules), outline and 3D-view drop, paste placement, MLCAD groups,
//              selection transforms, inspector packing, clipboard packing, search matching,
//              primitive insert placement, 3D-view zoom/scroll policy, and the
//              portable scene controller extracted from LDrawRenderer. No
//              AppKit or UIKit.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawEditing/LDrawClipboard.h>
#import <LDrawEditing/LDrawCompliantNameChange.h>
#import <LDrawEditing/LDrawEditorStrings.h>
#import <LDrawEditing/LDrawInsertion.h>
#import <LDrawEditing/LDrawInspection.h>
#import <LDrawEditing/LDrawMLCadGroup.h>
#import <LDrawEditing/LDrawOriginPartUpdate.h>
#import <LDrawEditing/LDrawOutline.h>
#import <LDrawEditing/LDrawPartTransformUpdate.h>
#import <LDrawEditing/LDrawPaste.h>
#import <LDrawEditing/LDrawRenderer+SceneControllerBridge.h>
#import <LDrawEditing/LDrawSceneController.h>
#import <LDrawEditing/LDrawSearch.h>
#import <LDrawEditing/LDrawSelection.h>
#import <LDrawEditing/LDrawSplitExpansion.h>
#import <LDrawEditing/LDrawStepExportFile.h>
#import <LDrawEditing/LDrawStructure.h>
#import <LDrawEditing/LDrawViewDrop.h>
#import <LDrawEditing/LDrawViewDropMove.h>
#import <LDrawEditing/LDrawViewPolicy.h>
