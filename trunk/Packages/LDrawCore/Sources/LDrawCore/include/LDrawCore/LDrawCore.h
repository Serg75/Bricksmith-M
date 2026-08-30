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
//              Implementation helpers (FastSet, PartCatalogBuilder,
//              ComputationalGeometry) are private headers next to their .m
//              files, not under include/. Host chrome keys live in
//              LDrawFeatures; pasteboard type names live in LDrawEditing.
//
//  Created by Sergey Slobodenyuk on 2026-05-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

// Math, keys, and string helpers
#import <LDrawCore/MacLDraw.h>
#import <LDrawCore/MatrixMath.h>
#import <LDrawCore/MatrixMathEx.h>
#import <LDrawCore/LDrawKeywords.h>
#import <LDrawCore/LDrawPathNames.h>
#import <LDrawCore/LDrawPaths.h>
#import <LDrawCore/LDrawRegex.h>
#import <LDrawCore/ScannerCategory.h>
#import <LDrawCore/StringCategory.h>
#import <LDrawCore/ClassInspector.h>

// Protocol surface consumed by renderer / feature packages
#import <LDrawCore/LDrawCoreRenderer.h>
#import <LDrawCore/LDrawLSynthConfigSource.h>
#import <LDrawCore/LDrawPartLibraryGPU.h>
#import <LDrawCore/LDrawMovableDirective.h>
#import <LDrawCore/LDrawObjectWithValue.h>

// Color
#import <LDrawCore/ColorLibrary.h>
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
#import <LDrawCore/ModelManager.h>
#import <LDrawCore/PartLibrary.h>
#import <LDrawCore/PartReport.h>
#import <LDrawCore/PartSpecific.h>
