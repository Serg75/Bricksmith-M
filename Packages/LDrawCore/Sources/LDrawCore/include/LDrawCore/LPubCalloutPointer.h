//==============================================================================
//
//  File:       LPubCalloutPointer.h
//  Package:    LDrawCore
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubPlacement.h>
#import <LDrawCore/LPubCommand.h>
#import <LDrawCore/MatrixMath.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LPubCalloutPointer
///
/// @abstract   One arrow from a callout's box to the place its submodel goes:
///             0 !LPUB CALLOUT POINTER <position> [<location>] <x> <y> [<base>]
///
/// @discussion A side takes a location, a corner does not. LPub3D also writes
///             a longer form for an arrow with a bend in it, which carries
///             three more points and a segment count.
///
///             The properties are read from the line. Set lPubCommandString
///             to change them.
///
//------------------------------------------------------------------------------
@interface LPubCalloutPointer : LPubCommand

/// The side or corner of the box the arrow leaves from.
@property (nonatomic, readonly) LPubPlacementPosition	position;

/// Where along that side the arrow leaves, from 0 to 1. Zero for a corner.
@property (nonatomic, readonly) double					location;

/// The tip. For a straight arrow, fractions of the parent step's assembly
/// picture, from its top left. For a bent one, LPub3D's own page units.
@property (nonatomic, readonly) Point2					tip;

/// The width of the arrow where it leaves the box, in inches. LPub3D's 1/8
/// when the line gives none, or zero.
@property (nonatomic, readonly) double					baseWidth;

/// How many straight pieces the arrow has: 1 for the short form.
@property (nonatomic, readonly) NSInteger				segmentCount;

/// The text of a straight arrow that leaves a side or a corner of the box and
/// points at `tip`, with LPub3D's own base width. `location` is not written
/// for a corner.
+ (NSString *) commandStringWithPosition:(LPubPlacementPosition)position
								location:(double)location
									 tip:(Point2)tip
	NS_SWIFT_NAME(commandString(position:location:tip:));

@end

NS_ASSUME_NONNULL_END
