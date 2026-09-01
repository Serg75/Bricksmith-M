//==============================================================================
//
//  File:       LDrawCore.h
//  Package:    LDrawCore
//
//  Purpose:    Host-facing umbrella for the LDrawCore Swift Package.
//
//  Info:       LDrawCore is the Foundation-only LDraw model layer: parser,
//              file/model/step containers, primitives, color library, math, and
//              the part library. It has no AppKit, UIKit, or GPU renderer
//              dependencies and is shared by Bricksmith and other host apps.
//              Implementation helpers (LDrawFastSet, LDrawClassInspector,
//              PartCatalogBuilder, ComputationalGeometry, MatrixMathEx.c) are
//              private next to their .m/.c files, not under include/. Host
//              chrome keys live in LDrawFeatures; pasteboard type names live in
//              LDrawEditing. Column-major 4x4 helpers that used to live in
//              MatrixMathEx.h are declared on MatrixMath.h.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

// Math, keys, and string helpers
#import <LDrawCore/LDrawKeys.h>
#import <LDrawCore/MatrixMath.h>
#import <LDrawCore/LDrawKeywords.h>
#import <LDrawCore/LDrawLocalization.h>
#import <LDrawCore/LDrawPathNames.h>
#import <LDrawCore/LDrawPaths.h>
#import <LDrawCore/LDrawRegex.h>
#import <LDrawCore/NSScanner+LDraw.h>
#import <LDrawCore/NSString+LDraw.h>

// Protocol surface consumed by renderer / feature packages
#import <LDrawCore/LDrawCoreRenderer.h>
#import <LDrawCore/LDrawLSynthConfigSource.h>
#import <LDrawCore/LDrawLSynthRuntimeSource.h>
#import <LDrawCore/LDrawMovableDirective.h>
#import <LDrawCore/LDrawGroupedObject.h>

// Color
#import <LDrawCore/LDrawColorLibrary.h>
#import <LDrawCore/LDrawColor.h>

// Directive base class + drag handle widget
#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawDragHandle.h>
#import <LDrawCore/LDrawDrawableElement.h>

// Container / file / model / step hierarchy
#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawStep.h>

// Primitives & directives
#import <LDrawCore/LDrawComment.h>
#import <LDrawCore/LDrawConditionalLine.h>
#import <LDrawCore/LDrawLine.h>
#import <LDrawCore/LDrawMetaCommand.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawQuadrilateral.h>
#import <LDrawCore/LDrawTexture.h>
#import <LDrawCore/LDrawTriangle.h>
#import <LDrawCore/LDrawHighResPrimitives.h>

// LSynth
#import <LDrawCore/LDrawLSynth.h>
#import <LDrawCore/LDrawLSynthDirective.h>

// LPub
#import <LDrawCore/LPubCommand.h>
#import <LDrawCore/LPubRemoveGroup.h>

// Support utilities
#import <LDrawCore/LDrawUtilities.h>
#import <LDrawCore/LDrawModelManager.h>
#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawCore/LDrawPartReport.h>
#import <LDrawCore/LDrawPartSpecific.h>
