//==============================================================================
//
//  File:       LPubPliIgnore.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-09-09.
//
//==============================================================================

#import <LDrawCore/LPubCommand.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @enum       LPubPliIgnoreBranch
///
/// @abstract   Which bracket this is. The two ranges stay apart: a PART END
///             never closes a PLI BEGIN IGN.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LPubPliIgnoreBranch) {
	/// 0 !LPUB PLI BEGIN IGN … 0 !LPUB PLI END
	LPubPliIgnoreBranchPli	= 0,
	/// 0 !LPUB PART BEGIN IGN … 0 !LPUB PART END
	LPubPliIgnoreBranchPart	= 1
};


//------------------------------------------------------------------------------
///
/// @class      LPubPliIgnore
///
/// @abstract   A bracket that keeps a range of parts out of the parts list:
///             0 !LPUB PLI BEGIN IGN … 0 !LPUB PLI END, or
///             0 !LPUB PART BEGIN IGN … 0 !LPUB PART END
///
///             For a step's list, PLI and PART mean the same thing.
///
/// @discussion Every PLI END is parsed here, also one that closes a
///             PLI BEGIN SUB range.
///
///             The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubPliIgnore : LPubCommand

/// YES for `BEGIN IGN`, NO for `END`.
@property (nonatomic, readonly) BOOL beginsRange;

/// PLI or PART.
@property (nonatomic, readonly) LPubPliIgnoreBranch branch;

@end

NS_ASSUME_NONNULL_END
