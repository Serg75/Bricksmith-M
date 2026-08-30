//==============================================================================
//
//  File:       LDrawSplitExpansion.h
//  Package:    LDrawEditing
//
//  Purpose:    One selected part that can be split into its referenced model's
//              bricks.
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawModel;
@class LDrawPart;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawSplitExpansion
///
/// @abstract   One selected part that can be split into its referenced model's
///             bricks.
///
//------------------------------------------------------------------------------
@interface LDrawSplitExpansion : NSObject

@property (nonatomic, strong) LDrawPart *anchor;
@property (nonatomic, strong) LDrawModel *model;
@property (nonatomic, strong) NSArray<LDrawPart *> *expandedParts;

@end

NS_ASSUME_NONNULL_END
