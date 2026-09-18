//==============================================================================
//
//  File:       LPubPageOrientation.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-09-12.
//
//==============================================================================

#import <LDrawCore/LPubCommand.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LPubPageOrientation
///
/// @abstract   LPub PAGE ORIENTATION command: which way up the page is.
///
/// @discussion Read together with PAGE SIZE.
///
///             The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubPageOrientation : LPubCommand

@property (nonatomic, readonly) LPubMetaScope	scope;
@property (nonatomic, readonly) BOOL			isLandscape;

@end

NS_ASSUME_NONNULL_END
