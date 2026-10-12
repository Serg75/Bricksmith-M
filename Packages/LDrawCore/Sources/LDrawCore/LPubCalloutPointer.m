//==============================================================================
//
//  File:       LPubCalloutPointer.m
//  Package:    LDrawCore
//
//  Purpose:    One arrow from a callout's box to the place its submodel goes.
//
//              Line format, for a corner:
//              0 !LPUB CALLOUT POINTER (TOP_LEFT|TOP_RIGHT|BOTTOM_LEFT|
//                  BOTTOM_RIGHT) <x> <y> [<base>]
//              and for a side:
//              0 !LPUB CALLOUT POINTER (TOP|BOTTOM|LEFT|RIGHT|CENTER)
//                  <location> <x> <y> [<base>]
//
//              An arrow with a bend in it has three more points and a segment
//              count: <x> <y> <x2> <y2> <x3> <y3> <x4> <y4> [<base>] <segments>
//
//              A line in any other form stays a plain LPubCommand. A parsed
//              line is written back as it was read.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubCalloutPointer.h>

#import <LDrawCore/LDrawKeywords.h>


/// The base LPub3D gives an arrow whose line has none, in inches.
static const double DEFAULT_BASE_WIDTH_INCHES = 1.0 / 8.0;

/// How many numbers follow the tip in the long form, before the base.
static const NSUInteger EXTRA_POINT_NUMBERS = 6;


//========== IsCorner() ========================================================
///
/// @abstract	Whether a position is one of the four corners.
///
//==============================================================================
static BOOL IsCorner(LPubPlacementPosition position)
{
	return position == LPubPlacementPositionTopLeft
		|| position == LPubPlacementPositionTopRight
		|| position == LPubPlacementPositionBottomLeft
		|| position == LPubPlacementPositionBottomRight;

}//end IsCorner


@implementation LPubCalloutPointer


// MARK: - INITIALIZATION -


//========== init ==============================================================
///
/// @abstract	An arrow with no line behind it is a straight one of the default
///				width.
///
//==============================================================================
- (id) init
{
	self = [super init];
	if (self) {
		self->_baseWidth	= DEFAULT_BASE_WIDTH_INCHES;
		self->_segmentCount	= 1;
	}
	return self;

}//end init


//---------- lpubCommandInstance: ------------------------------------[static]--
///
/// @abstract	Builds the command from the line's words, or nil if the
/// 			line is not this command.
///
/// @discussion	The numbers after the position are: a location for a side, the
/// 			tip, then either nothing, a base, or the long form's six
/// 			numbers, optional base and segment count.
///
//------------------------------------------------------------------------------
+ (LPubCommand *) lpubCommandInstance:(NSArray<NSString *> *)parameters
{
	if (parameters.count < 5
		|| [parameters[0] isEqualToString:LPUB_CALLOUT] == NO
		|| [parameters[1] isEqualToString:LPUB_CALLOUT_POINTER] == NO) {
		return nil;
	}

	LPubPlacementPosition position = LPubPlacementPositionCenter;

	if ([LPubPlacement getPosition:&position fromToken:parameters[2]] == NO) {
		return nil;
	}

	// Every word after the position is a number.
	NSUInteger	numberCount	= parameters.count - 3;
	double		numbers[12]	= { 0.0 };

	if (numberCount > 12) {
		return nil;
	}

	for (NSUInteger counter = 0; counter < numberCount; counter++) {
		if ([LPubCommand getNumber:&numbers[counter] fromToken:parameters[counter + 3]] == NO) {
			return nil;
		}
	}

	// A side starts with its location. What is left is the same for both.
	NSUInteger	index		= 0;
	double		location	= 0.0;

	if (IsCorner(position) == NO) {
		location = numbers[index];
		index += 1;
	}

	NSUInteger	remaining		= numberCount - index;
	Point2		tip				= V2Make(numbers[index], numbers[index + 1]);
	double		base			= 0.0;
	NSInteger	segmentCount	= 1;
	BOOL		isLongForm		= NO;

	if (remaining == 2) {
		// The tip alone.
	}
	else if (remaining == 3) {
		base = numbers[index + 2];
	}
	else if (remaining == 2 + EXTRA_POINT_NUMBERS + 1) {
		isLongForm = YES;
	}
	else if (remaining == 2 + EXTRA_POINT_NUMBERS + 2) {
		isLongForm	= YES;
		base		= numbers[numberCount - 2];
	}
	else {
		return nil;
	}

	// The long form ends with its segment count, a whole number.
	if (isLongForm
		&& [LPubCommand getInteger:&segmentCount fromToken:parameters.lastObject atLeast:1] == NO) {
		return nil;
	}

	LPubCalloutPointer *command = [LPubCalloutPointer new];

	command->_position		= position;
	command->_location		= location;
	command->_tip			= tip;
	command->_baseWidth		= (base > 0.0) ? base : DEFAULT_BASE_WIDTH_INCHES;
	command->_segmentCount	= segmentCount;
	[command adoptCommandString:[parameters componentsJoinedByString:@" "]];

	return command;

}//end lpubCommandInstance:


//---------- commandStringWithPosition:location:tip: -----------------[static]--
///
/// @abstract	The text of a straight arrow, with three decimals as LPub3D
/// 			writes them. A base of 0 is LPub3D's own width.
///
//------------------------------------------------------------------------------
+ (NSString *) commandStringWithPosition:(LPubPlacementPosition)position
								location:(double)location
									 tip:(Point2)tip
{
	NSMutableArray<NSString *> *words = [NSMutableArray array];

	[words addObject:LPUB_CALLOUT];
	[words addObject:LPUB_CALLOUT_POINTER];
	[words addObject:[LPubPlacement nameForPosition:position]];

	if (IsCorner(position) == NO) {
		[words addObject:[NSString stringWithFormat:@"%.3f", location]];
	}

	[words addObject:[NSString stringWithFormat:@"%.3f", tip.x]];
	[words addObject:[NSString stringWithFormat:@"%.3f", tip.y]];
	[words addObject:@"0"];

	return [words componentsJoinedByString:@" "];

}//end commandStringWithPosition:location:tip:


// MARK: - DISPLAY -


//========== browsingDescription ===============================================
///
/// @abstract	A short description of the line, shown to the user.
///
//==============================================================================
- (NSString *) browsingDescription
{
	return [NSString stringWithFormat:@"%@ %@ [%g %g]", LPUB_CALLOUT, LPUB_CALLOUT_POINTER,
			self.tip.x, self.tip.y];

}//end browsingDescription


// MARK: - ACCESSORS -


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubCalloutPointer *other = (LPubCalloutPointer *)command;

	self->_position		= other->_position;
	self->_location		= other->_location;
	self->_tip			= other->_tip;
	self->_baseWidth	= other->_baseWidth;
	self->_segmentCount	= other->_segmentCount;

}//end adoptPropertiesFromCommand:


@end
