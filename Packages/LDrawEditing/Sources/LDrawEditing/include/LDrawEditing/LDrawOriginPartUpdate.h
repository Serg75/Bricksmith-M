//==============================================================================
//
//  File:       LDrawOriginPartUpdate.h
//  Package:    LDrawEditing
//
//  Purpose:    One part whose origin-change matrix is ready to apply.
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>

@class LDrawPart;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawOriginPartUpdate
///
/// @abstract   One part whose origin-change matrix is ready to apply.
///             previousComponents is the pre-change transform for undo.
///
//------------------------------------------------------------------------------
@interface LDrawOriginPartUpdate : NSObject

@property (nonatomic, strong) LDrawPart *part;
@property (nonatomic, assign) Matrix4 matrix;
@property (nonatomic, assign) TransformComponents previousComponents;

@end

NS_ASSUME_NONNULL_END
