//==============================================================================
//
//  File:       LPubAssemShowStepNumber.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubCommand.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LPubAssemShowStepNumber
///
/// @abstract   Whether LPub3D prints step numbers:
///             0 !LPUB ASSEM SHOW_STEP_NUMBER [GLOBAL|LOCAL] (TRUE|FALSE)
///
/// @discussion TRUE is LPub3D's default. FALSE hides the numbers of the steps
///             in a callout's box too.
///
///             The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubAssemShowStepNumber : LPubCommand

@property (nonatomic, readonly) LPubMetaScope	scope;

/// YES when step numbers are printed.
@property (nonatomic, readonly) BOOL			isShown;

@end

NS_ASSUME_NONNULL_END
