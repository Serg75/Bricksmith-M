//==============================================================================
//
//  File:       LPubPliSubstitute.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-09-13.
//
//==============================================================================

#import <LDrawCore/LPubCommand.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LPubPliSubstitute
///
/// @abstract   Lists one part in place of a range of parts:
///             0 !LPUB PLI BEGIN SUB <part> [<color> …] … 0 !LPUB PLI END
///
/// @discussion The closing PLI END is parsed as an LPubPliIgnore.
///
///             LPub3D allows more tokens after the color. They are not
///             read, but they are written back unchanged.
///
///             The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubPliSubstitute : LPubCommand

/// The part listed in the range's place, as written: "2429c01.ldr".
@property (nonatomic, copy, readonly) NSString *partName;

/// The color to list the part in, or LDrawColorBogus when the line gives none.
@property (nonatomic, readonly) NSInteger partColorCode;

/// Whatever followed the color, verbatim.
@property (nonatomic, copy, readonly) NSArray<NSString *> *trailingTokens;

@end

NS_ASSUME_NONNULL_END
