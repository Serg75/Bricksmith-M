//==============================================================================
//
//  File:       LDrawPartLimitStatus.h
//  Package:    LDrawCore
//
//  Purpose:    How a part stands against the parts limit the editor has on.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

/// How a part stands against the parts limit. A later value is worse, so the
/// worst of several is the largest.
typedef NS_ENUM(NSInteger, LDrawPartLimitStatus)
{
	/// The limit allows the part in its color, or no limit is on.
	LDrawPartLimitStatusAllowed			= 0,

	/// Nothing is known about the part or its color, so it cannot be checked.
	LDrawPartLimitStatusNoData			= 1,

	/// The part and color are allowed, but the model uses more than the
	/// inventory holds.
	LDrawPartLimitStatusTooMany			= 2,

	/// The part is allowed, but not in this color.
	LDrawPartLimitStatusNotInColor		= 3,

	/// The part is not allowed in any color.
	LDrawPartLimitStatusNotAvailable	= 4
};
