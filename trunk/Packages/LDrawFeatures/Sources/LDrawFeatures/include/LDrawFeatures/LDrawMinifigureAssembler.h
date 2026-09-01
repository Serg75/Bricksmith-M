//==============================================================================
//
//  File:       LDrawMinifigureAssembler.h
//  Package:    LDrawFeatures
//
//  Purpose:    Positions minifigure catalog parts from an LDrawMinifigureSpec
//              and returns an LDrawMPDModel. Torso arm-socket angle comes from
//              LDrawMLCadIni. Generator preview zoom and autosave names live
//              in the Bricksmith app (LDrawHostChrome).
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawFeatures/LDrawMinifigureSpec.h>

@class LDrawMPDModel;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawMinifigureAssembler
///
/// @abstract   Positions minifigure parts from a spec and returns an MPD model.
///
//------------------------------------------------------------------------------
@interface LDrawMinifigureAssembler : NSObject

/// Mutates spec.part transforms in place and returns a new MPD model that
/// owns those parts. Head and torso are always included (historical).
+ (LDrawMPDModel *)assembleSpec:(LDrawMinifigureSpec *)spec;

@end

NS_ASSUME_NONNULL_END
