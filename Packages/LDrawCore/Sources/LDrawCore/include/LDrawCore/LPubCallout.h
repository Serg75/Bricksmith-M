//==============================================================================
//
//  File:       LPubCallout.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubCommand.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @enum       LPubCalloutLine
///
/// @abstract   Which line of a callout this is.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LPubCalloutLine) {
	/// 0 !LPUB CALLOUT BEGIN [ASSEMBLED|ROTATED]
	LPubCalloutLineBegin	= 0,
	/// 0 !LPUB CALLOUT DIVIDER
	LPubCalloutLineDivider	= 1,
	/// 0 !LPUB CALLOUT END
	LPubCalloutLineEnd		= 2
};


//------------------------------------------------------------------------------
///
/// @enum       LPubCalloutMode
///
/// @abstract   What a callout shows of the submodels placed inside it.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LPubCalloutMode) {
	/// The submodel's own steps. A BEGIN with no keyword.
	LPubCalloutModeUnassembled	= 0,
	/// One picture of the finished submodel.
	LPubCalloutModeAssembled	= 1,
	/// One picture of the finished submodel, turned as it sits in its parent.
	LPubCalloutModeRotated		= 2
};


//------------------------------------------------------------------------------
///
/// @class      LPubCallout
///
/// @abstract   The lines that mark out a callout:
///             0 !LPUB CALLOUT BEGIN [ASSEMBLED|ROTATED] … 0 !LPUB CALLOUT END,
///             and 0 !LPUB CALLOUT DIVIDER
///
/// @discussion BEGIN and END stand in the parent's step, around the parts that
///             place the called-out submodels. DIVIDER stands between the
///             steps of a called-out submodel, and starts a new row or column
///             of the box.
///
///             The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubCallout : LPubCommand

@property (nonatomic, readonly) LPubCalloutLine line;

/// Meaningful for BEGIN only. Unassembled for the other lines.
@property (nonatomic, readonly) LPubCalloutMode mode;

@end

NS_ASSUME_NONNULL_END
