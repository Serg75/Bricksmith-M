//
//  LPubCommand.h
//  Bricksmith
//
//  Created by Sergey Slobodenyuk on 2023-02-08.
//

#import "LDrawMetaCommand.h"

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class		LPubCommand
///
/// @abstract	A generic LPub command.
///
//------------------------------------------------------------------------------
@interface LPubCommand : LDrawMetaCommand

/// Command's substring after !LPUB.
@property (nonatomic, copy) NSString *lPubCommandString;

@end

NS_ASSUME_NONNULL_END
