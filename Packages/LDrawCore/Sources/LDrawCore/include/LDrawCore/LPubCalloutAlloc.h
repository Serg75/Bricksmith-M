//==============================================================================
//
//  File:       LPubCalloutAlloc.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubCommand.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LPubCalloutAlloc
///
/// @abstract   Which way the steps in a callout's box run:
///             0 !LPUB CALLOUT ALLOC [GLOBAL|LOCAL] (HORIZONTAL|VERTICAL)
///
/// @discussion LPub3D stacks the steps downward when a file says nothing.
///
///             The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubCalloutAlloc : LPubCommand

@property (nonatomic, readonly) LPubMetaScope	scope;

/// YES when the steps run downward, NO when they run to the right.
@property (nonatomic, readonly) BOOL			isVertical;

@end

NS_ASSUME_NONNULL_END
