//==============================================================================
//
//  File:       LDrawViewDropMove.h
//  Package:    LDrawEditing
//
//  Purpose:    Drawable original plus the displacement to apply after a
//              same-document 3D-view drop.
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>

@class LDrawDrawableElement;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawViewDropMove
///
/// @abstract   Drawable original plus the displacement to apply after a
///             same-document 3D-view drop.
///
//------------------------------------------------------------------------------
@interface LDrawViewDropMove : NSObject

@property (nonatomic, strong) LDrawDrawableElement *directive;
@property (nonatomic, assign) Vector3 displacement;

- (instancetype)initWithDirective:(LDrawDrawableElement *)directive
					 displacement:(Vector3)displacement;

@end

NS_ASSUME_NONNULL_END
