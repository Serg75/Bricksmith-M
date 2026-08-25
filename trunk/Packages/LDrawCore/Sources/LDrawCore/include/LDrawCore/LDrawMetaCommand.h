//==============================================================================
//
//  File:       LDrawMetaCommand.h
//  Package:    LDrawCore
//
//  Purpose:    Basic holder for a meta-command.
//
//  Created by Allen Smith on 2/19/05.
//  Copyright (c) 2005. All rights reserved.
//
//==============================================================================

#import <LDrawCore/LDrawDirective.h>


//------------------------------------------------------------------------------
///
/// @class      LDrawMetaCommand
///
/// @abstract   Basic holder for a meta-command.
///
//------------------------------------------------------------------------------
@interface LDrawMetaCommand : LDrawDirective

// Initialization
- (BOOL) finishParsing:(NSScanner *)scanner;

// Directives
- (NSString *) write;

// Accessors
@property (nonatomic) NSString *commandString;

@end
