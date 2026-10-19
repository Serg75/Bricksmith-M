//==============================================================================
//
//  File:       LPubPlacement.m
//  Package:    LDrawCore
//
//  Purpose:    Where a callout's box, a step's assembly, its parts list or
//              the page's number sits.
//
//              Line format, after 0 !LPUB (CALLOUT | ASSEM | PLI | PAGE NUMBER)
//              PLACEMENT [GLOBAL|LOCAL]:
//              (TOP|BOTTOM) [LEFT|CENTER|RIGHT] <relative to>
//                  (INSIDE|OUTSIDE) [[OFFSET] <x> <y>]
//              (LEFT|RIGHT) [TOP|CENTER|BOTTOM] <relative to>
//                  (INSIDE|OUTSIDE) [[OFFSET] <x> <y>]
//              (TOP_LEFT|TOP_RIGHT|BOTTOM_LEFT|BOTTOM_RIGHT|CENTER)
//                  <relative to> (INSIDE|OUTSIDE) [[OFFSET] <x> <y>]
//
//              A line in any other form stays a plain LPubCommand. A parsed
//              line is written back as it was read.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawCore/LPubPlacement.h>

#import <LDrawCore/LDrawKeywords.h>


static NSString * const LPUB_PLACEMENT_INSIDE	= @"INSIDE";
static NSString * const LPUB_PLACEMENT_OUTSIDE	= @"OUTSIDE";
static NSString * const LPUB_PLACEMENT_OFFSET	= @"OFFSET";


//========== PositionNames() ===================================================
///
/// @abstract	The keyword of each position, in the order of the enum.
///
//==============================================================================
static NSArray<NSString *> *PositionNames(void)
{
	static NSArray<NSString *> *names = nil;
	static dispatch_once_t		onceToken;

	dispatch_once(&onceToken, ^{
		names = @[@"TOP_LEFT", @"TOP", @"TOP_RIGHT", @"RIGHT", @"BOTTOM_RIGHT",
				  @"BOTTOM", @"BOTTOM_LEFT", @"LEFT", @"CENTER"];
	});

	return names;

}//end PositionNames


//========== RelativeToNames() =================================================
///
/// @abstract	Every keyword LPub3D takes for what a box is placed against.
///
//==============================================================================
static NSSet<NSString *> *RelativeToNames(void)
{
	static NSSet<NSString *>	*names = nil;
	static dispatch_once_t		 onceToken;

	dispatch_once(&onceToken, ^{
		names = [NSSet setWithObjects:
				 @"PAGE", @"ASSEM", @"MULTI_STEP", @"STEP_NUMBER", @"PLI", @"CALLOUT", @"PAGE_NUMBER",
				 @"DOCUMENT_TITLE", @"MODEL_ID", @"DOCUMENT_AUTHOR", @"PUBLISH_URL", @"MODEL_DESCRIPTION",
				 @"PUBLISH_DESCRIPTION", @"PUBLISH_COPYRIGHT", @"PUBLISH_EMAIL", @"LEGO_DISCLAIMER",
				 @"MODEL_PARTS", @"APP_PLUG", @"MODEL_CATEGORY", @"DOCUMENT_LOGO", @"DOCUMENT_COVER_IMAGE",
				 @"APP_PLUG_IMAGE", @"PAGE_HEADER", @"PAGE_FOOTER", @"SUBMODEL_DISPLAY", @"ROTATE_ICON",
				 @"ASSEM_PART", @"STEP", @"RANGE", @"TEXT", @"BOM", @"PAGE_POINTER", @"SINGLE_STEP",
				 @"RESERVE", @"COVER_PAGE", @"ANNOTATION", @"DIVIDER_POINTER", nil];
	});

	return names;

}//end RelativeToNames


//========== IsSide() ==========================================================
///
/// @abstract	Whether a position is one of the four sides.
///
//==============================================================================
static BOOL IsSide(LPubPlacementPosition position)
{
	return position == LPubPlacementPositionTop
		|| position == LPubPlacementPositionBottom
		|| position == LPubPlacementPositionLeft
		|| position == LPubPlacementPositionRight;

}//end IsSide


//========== IsJustificationForSide() ==========================================
///
/// @abstract	Whether a word can say where along a side a box sits. Top and
/// 			bottom take LEFT, CENTER or RIGHT. Left and right take TOP,
/// 			CENTER or BOTTOM.
///
//==============================================================================
static BOOL IsJustificationForSide(LPubPlacementPosition justification, LPubPlacementPosition side)
{
	if (justification == LPubPlacementPositionCenter) {
		return YES;
	}

	if (side == LPubPlacementPositionTop || side == LPubPlacementPositionBottom) {
		return justification == LPubPlacementPositionLeft || justification == LPubPlacementPositionRight;
	}

	return justification == LPubPlacementPositionTop || justification == LPubPlacementPositionBottom;

}//end IsJustificationForSide


//========== OffsetText() ======================================================
///
/// @abstract	An offset as LPub3D writes one: four decimals.
///
//==============================================================================
static NSString *OffsetText(double offset)
{
	return [NSString stringWithFormat:@"%.4f", offset];

}//end OffsetText


@implementation LPubPlacement


// MARK: - INITIALIZATION -


//========== init ==============================================================
///
/// @abstract	A command with no line behind it is placed against nothing.
///
//==============================================================================
- (id) init
{
	self = [super init];
	if (self) {
		self->_relativeTo		= @"";
		self->_justification	= LPubPlacementPositionCenter;
	}
	return self;

}//end init


//---------- lpubCommandInstance: ------------------------------------[static]--
///
/// @abstract	Builds the command from the line's words, or nil if the
/// 			line is not this command.
///
/// @discussion	LPub3D takes only the combinations it has a place for. Outside,
/// 			a side needs a justification and the middle is not allowed.
/// 			Inside, the only justification allowed is CENTER, which means
/// 			nothing there.
///
//------------------------------------------------------------------------------
+ (LPubCommand *) lpubCommandInstance:(NSArray<NSString *> *)parameters
{
	LPubPlacementBranch	branch	= LPubPlacementBranchCallout;
	NSUInteger			index	= 1;

	if (parameters.count < 2) {
		return nil;
	}

	if ([parameters[0] isEqualToString:LPUB_ASSEM]) {
		branch = LPubPlacementBranchAssembly;
	}
	else if ([parameters[0] isEqualToString:LPUB_PLI]) {
		branch = LPubPlacementBranchPartsList;
	}
	else if ([parameters[0] isEqualToString:LPUB_PAGE] && [parameters[1] isEqualToString:LPUB_PAGE_NUMBER]) {
		branch	= LPubPlacementBranchPageNumber;
		index	= 2;
	}
	else if ([parameters[0] isEqualToString:LPUB_CALLOUT] == NO) {
		return nil;
	}

	if (parameters.count < index + 4 || [parameters[index] isEqualToString:LPUB_PLACEMENT] == NO) {
		return nil;
	}
	index += 1;

	LPubMetaScope			scope			= [LPubCommand scopeInParameters:parameters index:&index];
	LPubPlacementPosition	position		= LPubPlacementPositionCenter;
	LPubPlacementPosition	justification	= LPubPlacementPositionCenter;
	BOOL					hasJustification = NO;

	if (index >= parameters.count || [self getPosition:&position fromToken:parameters[index]] == NO) {
		return nil;
	}
	index += 1;

	// A side may be followed by where along it the box sits.
	if (index < parameters.count && IsSide(position)
		&& [self getPosition:&justification fromToken:parameters[index]]) {

		if (IsJustificationForSide(justification, position) == NO) {
			return nil;
		}
		hasJustification = YES;
		index += 1;
	}

	// Then what it is placed against, and on which side of its edge.
	if (index + 1 >= parameters.count || [RelativeToNames() containsObject:parameters[index]] == NO) {
		return nil;
	}

	NSString	*relativeTo		= parameters[index];
	NSString	*preposition	= parameters[index + 1];
	BOOL		 isInside		= [preposition isEqualToString:LPUB_PLACEMENT_INSIDE];

	if (isInside == NO && [preposition isEqualToString:LPUB_PLACEMENT_OUTSIDE] == NO) {
		return nil;
	}
	index += 2;

	if (isInside) {
		if (hasJustification && justification != LPubPlacementPositionCenter) {
			return nil;
		}
		justification = LPubPlacementPositionCenter;
	}
	else if (position == LPubPlacementPositionCenter || (IsSide(position) && hasJustification == NO)) {
		return nil;
	}

	// The offset is two numbers, with or without the word before them.
	double x = 0.0, y = 0.0;

	if (index < parameters.count && [parameters[index] isEqualToString:LPUB_PLACEMENT_OFFSET]) {
		index += 1;

		if (index == parameters.count) {
			return nil;
		}
	}

	if (index < parameters.count) {
		if (parameters.count - index != 2
			|| [LPubCommand getNumber:&x fromToken:parameters[index]] == NO
			|| [LPubCommand getNumber:&y fromToken:parameters[index + 1]] == NO) {
			return nil;
		}
	}

	LPubPlacement *command = [LPubPlacement new];

	command->_branch		= branch;
	command->_scope			= scope;
	command->_position		= position;
	command->_justification	= justification;
	command->_relativeTo	= [relativeTo copy];
	command->_isInside		= isInside;
	command->_offset		= V2Make(x, y);
	[command adoptCommandString:[parameters componentsJoinedByString:@" "]];

	return command;

}//end lpubCommandInstance:


//---------- getPosition:fromToken: ----------------------------------[static]--
+ (BOOL) getPosition:(LPubPlacementPosition *)outPosition fromToken:(NSString *)token
{
	NSUInteger found = [PositionNames() indexOfObject:token];

	if (found == NSNotFound) {
		return NO;
	}

	*outPosition = (LPubPlacementPosition)found;
	return YES;

}//end getPosition:fromToken:


//---------- nameForPosition: ----------------------------------------[static]--
+ (NSString *) nameForPosition:(LPubPlacementPosition)position
{
	return PositionNames()[position];

}//end nameForPosition:


// MARK: - DISPLAY -


//========== browsingDescription ===============================================
///
/// @abstract	A short description of the line, shown to the user.
///
//==============================================================================
- (NSString *) browsingDescription
{
	NSString *subject = LPUB_CALLOUT;

	if (self.branch == LPubPlacementBranchAssembly) {
		subject = LPUB_ASSEM;
	}
	else if (self.branch == LPubPlacementBranchPartsList) {
		subject = LPUB_PLI;
	}
	else if (self.branch == LPubPlacementBranchPageNumber) {
		subject = [NSString stringWithFormat:@"%@ %@", LPUB_PAGE, LPUB_PAGE_NUMBER];
	}

	return [NSString stringWithFormat:@"%@ %@ [%@ %@ %@]", subject, LPUB_PLACEMENT,
			PositionNames()[self.position], self.relativeTo,
			self.isInside ? LPUB_PLACEMENT_INSIDE : LPUB_PLACEMENT_OUTSIDE];

}//end browsingDescription


// MARK: - EDITING -


//========== commandStringWithOffset: ==========================================
///
/// @abstract	This line's text with another offset.
///
/// @discussion	The words up to INSIDE or OUTSIDE are kept as typed, and so is
///				the OFFSET word when the line has one. LPub3D reads the two
///				numbers with or without it.
///
//==============================================================================
- (NSString *) commandStringWithOffset:(Point2)offset
{
	NSMutableArray<NSString *> *words = [self.lPubCommandWords mutableCopy];

	NSUInteger sideIndex = [words indexOfObject:self.isInside ? LPUB_PLACEMENT_INSIDE : LPUB_PLACEMENT_OUTSIDE];

	if (sideIndex == NSNotFound) {
		return self.lPubCommandString;
	}

	BOOL hasOffsetWord = (sideIndex + 1 < words.count && [words[sideIndex + 1] isEqualToString:LPUB_PLACEMENT_OFFSET]);

	[words removeObjectsInRange:NSMakeRange(sideIndex + 1, words.count - sideIndex - 1)];

	if (hasOffsetWord) {
		[words addObject:LPUB_PLACEMENT_OFFSET];
	}
	[words addObject:OffsetText(offset.x)];
	[words addObject:OffsetText(offset.y)];

	return [words componentsJoinedByString:@" "];

}//end commandStringWithOffset:


//---------- defaultCalloutCommandStringWithOffset: ------------------[static]--
+ (NSString *) defaultCalloutCommandStringWithOffset:(Point2)offset
{
	return [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@ %@ %@", LPUB_CALLOUT, LPUB_PLACEMENT,
			PositionNames()[LPubPlacementPositionRight], PositionNames()[LPubPlacementPositionCenter],
			LPUB_ASSEM, LPUB_PLACEMENT_OUTSIDE, OffsetText(offset.x), OffsetText(offset.y)];

}//end defaultCalloutCommandStringWithOffset:


// MARK: - ACCESSORS -


//========== adoptPropertiesFromCommand: =======================================
///
/// @abstract	Takes the properties the parser derived from new text.
///
//==============================================================================
- (void) adoptPropertiesFromCommand:(LPubCommand *)command
{
	LPubPlacement *other = (LPubPlacement *)command;

	self->_branch			= other->_branch;
	self->_scope			= other->_scope;
	self->_position			= other->_position;
	self->_justification	= other->_justification;
	self->_relativeTo		= [other->_relativeTo copy];
	self->_isInside			= other->_isInside;
	self->_offset			= other->_offset;

}//end adoptPropertiesFromCommand:


@end
