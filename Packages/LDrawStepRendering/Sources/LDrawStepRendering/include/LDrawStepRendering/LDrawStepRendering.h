//==============================================================================
//
//  File:       LDrawStepRendering.h
//  Package:    LDrawStepRendering
//
//  Purpose:    Umbrella header. What a host needs to show a step's parts list
//              and callouts over its model, on top of LDrawFeatures: laying
//              the step out against a camera, the pictures of the called-out
//              submodels, and the drawing. A host that also changes callouts
//              adds LDrawStepEditing.
//
//              CoreGraphics and CoreText. No AppKit or UIKit.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import <LDrawStepRendering/LDrawStepCalloutPath.h>
#import <LDrawStepRendering/LDrawStepCalloutPictureStore.h>
#import <LDrawStepRendering/LDrawStepLayoutCache.h>
#import <LDrawStepRendering/LDrawStepOverlayPresenter.h>
#import <LDrawStepRendering/LDrawStepOverlayRenderer.h>
