//==============================================================================
//
//  File:       LPubPliShow.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-09-09.
//
//==============================================================================

#import <LDrawCore/LPubCommand.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LPubPliShow
///
/// @abstract   LPub PLI SHOW command: whether the parts list is displayed.
///
/// @discussion The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubPliShow : LPubCommand

@property (nonatomic, readonly) LPubMetaScope	scope;
@property (nonatomic, readonly) BOOL			isShown;

@end

NS_ASSUME_NONNULL_END
