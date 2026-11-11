//==============================================================================
//
//  File:       LDrawDirectiveMove.h
//  Package:    LDrawEditing
//
//  Purpose:    A movable directive plus the displacement to move it by.
//
//  Created by Sergey Slobodenyuk on 2026-11-11.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawMovableDirective.h>
#import <LDrawCore/MatrixMath.h>

@class LDrawDirective;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawDirectiveMove
///
/// @abstract   A movable directive plus the displacement to move it by, in the
///             coordinates of its model. The host applies it (undo).
///
//------------------------------------------------------------------------------
@interface LDrawDirectiveMove : NSObject

@property (nonatomic, strong) LDrawDirective<LDrawMovableDirective> *directive;
@property (nonatomic, assign) Vector3 displacement;

- (instancetype)initWithDirective:(LDrawDirective<LDrawMovableDirective> *)directive
					 displacement:(Vector3)displacement;

@end

NS_ASSUME_NONNULL_END
