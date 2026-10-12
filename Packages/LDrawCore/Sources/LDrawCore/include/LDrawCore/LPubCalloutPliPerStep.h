//==============================================================================
//
//  File:       LPubCalloutPliPerStep.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubCommand.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LPubCalloutPliPerStep
///
/// @abstract   Where the parts of a called-out submodel are listed:
///             0 !LPUB CALLOUT PLI PER_STEP [GLOBAL|LOCAL] (TRUE|FALSE)
///
/// @discussion TRUE, which is LPub3D's default, gives each step in the
///             callout's box a parts list of its own. FALSE lists all of them
///             in the parts list of the step that holds the callout.
///
///             The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubCalloutPliPerStep : LPubCommand

@property (nonatomic, readonly) LPubMetaScope	scope;

/// YES when each step in the box lists its own parts.
@property (nonatomic, readonly) BOOL			isPerStep;

@end

NS_ASSUME_NONNULL_END
