//==============================================================================
//
//  File:       LDrawLPubRangeTracker.m
//  Package:    LDrawFeatures
//
//  Purpose:    Follows LPub3D's IGN and SUB ranges while a step's directives
//              are walked.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import "LDrawLPubRangeTracker.h"

#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LPubPliIgnore.h>
#import <LDrawCore/LPubPliSubstitute.h>


@implementation LDrawLPubRange

//========== init ==============================================================
//==============================================================================
- (instancetype) init
{
	self = [super init];
	if (self) {
		self->_enclosedParts = [NSMutableArray array];
	}
	return self;
}


//========== listedPartName ====================================================
//==============================================================================
- (NSString *) listedPartName
{
	NSCharacterSet	*quotes	= [NSCharacterSet characterSetWithCharactersInString:@"\""];
	NSString		*name	= [[self.substitute.partName lowercaseString] stringByTrimmingCharactersInSet:quotes];

	if (self.substitute == nil || self.suppressed || [name length] == 0)
		return nil;
	return name;
}

@end


@implementation LDrawLPubRangeTracker
{
	NSMutableArray<LDrawLPubRange *>	*pliRanges;
	NSInteger							 partIgnoreDepth;
}


//========== init ==============================================================
//==============================================================================
- (instancetype) init
{
	self = [super init];
	if (self) {
		self->pliRanges = [NSMutableArray array];
	}
	return self;
}


//========== readBracket:closedRange: ==========================================
///
/// @abstract	Opens or closes a range for an IGN or SUB line.
///
//==============================================================================
- (BOOL) readBracket:(LDrawDirective *)directive closedRange:(LDrawLPubRange **)closedRange
{
	*closedRange = nil;

	if ([directive isKindOfClass:[LPubPliSubstitute class]]) {
		LDrawLPubRange *range = [[LDrawLPubRange alloc] init];

		range.substitute	= (LPubPliSubstitute *)directive;
		range.suppressed	= self.isInsideRange;
		[self->pliRanges addObject:range];
		return YES;
	}

	if ([directive isKindOfClass:[LPubPliIgnore class]] == NO) {
		return NO;
	}

	LPubPliIgnore *bracket = (LPubPliIgnore *)directive;

	if (bracket.branch == LPubPliIgnoreBranchPart) {
		if (bracket.beginsRange) {
			self->partIgnoreDepth += 1;
		}
		else if (self->partIgnoreDepth > 0) {
			self->partIgnoreDepth -= 1;
		}
	}
	else if (bracket.beginsRange) {
		[self->pliRanges addObject:[[LDrawLPubRange alloc] init]];
	}
	else if (self->pliRanges.count > 0) {
		*closedRange = self->pliRanges.lastObject;
		[self->pliRanges removeLastObject];
	}
	return YES;

}//end readBracket:closedRange:


//========== notePart:color: ===================================================
///
/// @abstract	Every open range keeps the part, and the first part's color for
/// 			a substitute that names none.
///
//==============================================================================
- (void) notePart:(LDrawPart *)part color:(LDrawColor *)color
{
	for (LDrawLPubRange *range in self->pliRanges) {
		if (range.firstColor == nil) {
			range.firstColor = color;
		}
		[range.enclosedParts addObject:part];
	}
}


//========== isInsideRange =====================================================
//==============================================================================
- (BOOL) isInsideRange
{
	return self->pliRanges.count > 0 || self->partIgnoreDepth > 0;
}


//========== openRanges ========================================================
//==============================================================================
- (NSArray<LDrawLPubRange *> *) openRanges
{
	return [self->pliRanges copy];
}

@end
