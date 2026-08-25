//==============================================================================
//
//  File:       LPubRemoveGroup.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2023-02-07.
//
//==============================================================================

#import <LDrawCore/LPubCommand.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LPubRemoveGroup
///
/// @abstract   LPub Remove Group command.
///
//------------------------------------------------------------------------------
@interface LPubRemoveGroup : LPubCommand

/// Command's parameter
@property (nonatomic) NSString *groupName;

@end

NS_ASSUME_NONNULL_END
