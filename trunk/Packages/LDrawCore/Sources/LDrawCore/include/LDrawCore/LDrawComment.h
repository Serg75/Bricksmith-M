//==============================================================================
//
//  File:       LDrawComment.h
//  Package:    LDrawCore
//
//  Purpose:    A comment. It serves only as explanatory text in the model.
//
//  Created by Allen Smith on 3/12/05.
//  Copyright (c) 2005. All rights reserved.
//
//==============================================================================

#import <LDrawCore/LDrawMetaCommand.h>

//------------------------------------------------------------------------------
///
/// @class      LDrawComment
///
/// @abstract   A comment. It serves only as explanatory text in the model.
///
//------------------------------------------------------------------------------
@interface LDrawComment : LDrawMetaCommand

- (NSString *) write;

@end
