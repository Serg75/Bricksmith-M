//==============================================================================
//
//  File:       LPubPlacement.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubCommand.h>
#import <LDrawCore/MatrixMath.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @enum       LPubPlacementPosition
///
/// @abstract   A side, a corner or the middle of a box, in LPub3D's order.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LPubPlacementPosition) {
	LPubPlacementPositionTopLeft		= 0,
	LPubPlacementPositionTop			= 1,
	LPubPlacementPositionTopRight		= 2,
	LPubPlacementPositionRight			= 3,
	LPubPlacementPositionBottomRight	= 4,
	LPubPlacementPositionBottom			= 5,
	LPubPlacementPositionBottomLeft		= 6,
	LPubPlacementPositionLeft			= 7,
	LPubPlacementPositionCenter			= 8
};


//------------------------------------------------------------------------------
///
/// @enum       LPubPlacementBranch
///
/// @abstract   What a PLACEMENT line places.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LPubPlacementBranch) {
	/// A callout's box.
	LPubPlacementBranchCallout		= 0,
	/// The step's assembly picture.
	LPubPlacementBranchAssembly		= 1,
	/// The step's parts list.
	LPubPlacementBranchPartsList	= 2
};


//------------------------------------------------------------------------------
///
/// @class      LPubPlacement
///
/// @abstract   Where a callout's box, a step's assembly or its parts list sits:
///             0 !LPUB (CALLOUT | ASSEM | PLI) PLACEMENT [GLOBAL|LOCAL]
///                 <position> [<justification>] <relative to> (INSIDE|OUTSIDE)
///                 [[OFFSET] <x> <y>]
///
/// @discussion Outside, a box on a side also says where along that side it
///             sits, such as TOP LEFT or RIGHT CENTER. A corner, and any
///             position inside, takes no such word.
///
///             The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubPlacement : LPubCommand

@property (nonatomic, readonly) LPubPlacementBranch		branch;
@property (nonatomic, readonly) LPubMetaScope			scope;

/// The side or corner of the other thing that the box is put at.
@property (nonatomic, readonly) LPubPlacementPosition	position;

/// Where along that side the box sits. Center when the line has no such word.
@property (nonatomic, readonly) LPubPlacementPosition	justification;

/// The keyword for what the box is placed against, such as ASSEM or PAGE.
@property (nonatomic, readonly, copy) NSString			*relativeTo;

/// YES for INSIDE, NO for OUTSIDE.
@property (nonatomic, readonly) BOOL					isInside;

/// How far the box is moved from that place, as fractions of the size of what
/// it is placed against. Zero when the line has none.
@property (nonatomic, readonly) Point2					offset;

/// Reads a token as a position. NO for any other word.
+ (BOOL) getPosition:(LPubPlacementPosition *)outPosition fromToken:(NSString *)token;

/// The keyword of a position, such as TOP_LEFT.
+ (NSString *) nameForPosition:(LPubPlacementPosition)position;

/// This line's text with another offset. Everything before the offset stays
/// as typed.
- (NSString *) commandStringWithOffset:(Point2)offset;

/// The text of a line that puts a callout's box where LPub3D puts one with no
/// line, to the right of the assembly in the middle, moved by `offset`.
+ (NSString *) defaultCalloutCommandStringWithOffset:(Point2)offset;

@end

NS_ASSUME_NONNULL_END
