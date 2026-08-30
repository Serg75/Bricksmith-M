//==============================================================================
//
//  File:       LDrawPartTransformUpdate.h
//  Package:    LDrawEditing
//
//  Purpose:    One part whose snapped or mirrored transform is ready to apply.
//
//  Created by Sergey Slobodenyuk on 2026-08-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>

@class LDrawPart;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawPartTransformUpdate
///
/// @abstract   One part whose snapped or mirrored transform is ready to apply.
///
//------------------------------------------------------------------------------
@interface LDrawPartTransformUpdate : NSObject

@property (nonatomic, strong) LDrawPart *part;
@property (nonatomic, assign) TransformComponents components;

@end

NS_ASSUME_NONNULL_END
