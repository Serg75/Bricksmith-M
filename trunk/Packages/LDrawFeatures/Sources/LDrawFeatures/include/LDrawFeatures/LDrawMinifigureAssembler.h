//==============================================================================
//
//  File:       LDrawMinifigureAssembler.h
//  Package:    LDrawFeatures
//
//  Purpose:    Positions minifigure catalog parts from an LDrawMinifigureSpec
//              and returns an LDrawMPDModel. Torso arm-socket angle comes from
//              a host-provided LDrawMLCadIni. Generator preview zoom and autosave names live
//              in the host app (LDrawHostChrome).
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawFeatures/LDrawMinifigureSpec.h>

@class LDrawMPDModel;
@class LDrawMLCadIni;

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
/// iniFile supplies torso arm-socket angles; nil means 0°.
+ (LDrawMPDModel *)assembleSpec:(LDrawMinifigureSpec *)spec
						iniFile:(nullable LDrawMLCadIni *)iniFile;

@end

NS_ASSUME_NONNULL_END
