//==============================================================================
//
//  File:       LDrawPartReplacements.m
//  Package:    LDrawFeatures
//
//  Purpose:    The parts that can take the place of a part, and how each
//              would stand against the limit.
//
//  Created by Sergey Slobodenyuk on 2026-11-03.
//
//==============================================================================

#import <LDrawFeatures/LDrawPartReplacements.h>

#import <LDrawCore/LDrawPart.h>
#import <LDrawFeatures/LDrawPartLimitCheck.h>
#import <LDrawFeatures/LDrawPartUsage.h>
#import <LDrawInventory/LDrawPartIdentity.h>
#import <LDrawInventory/LDrawPartLimit.h>
#import <LDrawInventory/LDrawPartLimitTable.h>

/// A plain part can have hundreds of prints; the rest are left out.
static const NSUInteger MaximumPrintCount = 10;


//========== StatusRank ========================================================
///
/// @abstract	Allowed first, then each problem from the least to the worst.
/// 			No data comes last, since nothing is known.
///
//==============================================================================
static NSInteger StatusRank(LDrawPartLimitStatus status)
{
	return (status == LDrawPartLimitStatusNoData) ? LDrawPartLimitStatusNotAvailable + 1 : status;
}


@interface LDrawPartReplacement ()

- (instancetype) initWithPartName:(NSString *)partName
							 kind:(LDrawPartReplacementKind)kind
						colorCode:(LDrawColorT)colorCode
						setsColor:(BOOL)setsColor
						   status:(LDrawPartLimitStatus)status
					   ownedCount:(NSUInteger)ownedCount
						usedCount:(NSUInteger)usedCount;

@end


@implementation LDrawPartReplacement

//========== initWithPartName:kind:colorCode:... ===============================
//==============================================================================
- (instancetype) initWithPartName:(NSString *)partName
							 kind:(LDrawPartReplacementKind)kind
						colorCode:(LDrawColorT)colorCode
						setsColor:(BOOL)setsColor
						   status:(LDrawPartLimitStatus)status
					   ownedCount:(NSUInteger)ownedCount
						usedCount:(NSUInteger)usedCount
{
	self = [super init];
	if (self) {
		self->_partName		= [partName copy];
		self->_kind			= kind;
		self->_colorCode	= colorCode;
		self->_setsColor	= setsColor;
		self->_status		= status;
		self->_ownedCount	= ownedCount;
		self->_usedCount	= usedCount;
	}
	return self;
}


//========== description =======================================================
//==============================================================================
- (NSString *) description
{
	return [NSString stringWithFormat:@"%@%@/%d", self.setsColor ? @"" : @"~", self.partName, self.colorCode];
}

@end


@implementation LDrawPartReplacements
{
	LDrawPartLimitReport	*report;
	LDrawPartLimitTable		*table;			// nil when no limit restricts
	LDrawPartIdentity		*identity;
	BOOL					(^libraryHasPart)(NSString *partName);

	NSString				*partName;		// of the parts replaced
	LDrawColorT				 colorCode;		// they are checked in, or LDrawColorBogus
	BOOL					 canSetColor;
	NSUInteger				 copies;		// the parts stand for
	NSMutableSet			*offered;		// normalized names, the parts' own first
}


// MARK: - LISTING -


//---------- replacementsForParts:... --------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSArray<LDrawPartReplacement *> *) replacementsForParts:(NSArray<LDrawPart *> *)parts
													report:(LDrawPartLimitReport *)report
													 usage:(LDrawPartUsage *)usage
												  identity:(LDrawPartIdentity *)identity
											libraryHasPart:(BOOL (^)(NSString *partName))libraryHasPart
{
	NSString				*name			= [[parts firstObject] displayName];
	NSString				*number			= nil;
	LDrawPartReplacements	*search			= nil;
	NSMutableArray			*replacements	= [NSMutableArray array];
	BOOL					 sharesColor	= YES;

	for (LDrawPart *part in parts)
	{
		if (	[[LDrawPartIdentity normalizedPartName:[part displayName]]
				 isEqualToString:[LDrawPartIdentity normalizedPartName:name]] == NO )
			return @[];
	}
	number = (name != nil) ? [identity rebrickablePartNumberForPartName:name] : nil;
	if (number == nil)
		return @[];

	search = [[LDrawPartReplacements alloc] init];
	search->report			= report;
	search->table			= (report.table.limit.isRestricting && report.table.hasData) ? report.table : nil;
	search->identity		= identity;
	search->libraryHasPart	= libraryHasPart;
	search->partName		= name;
	search->copies			= [self copiesOfParts:parts usage:usage sharesColor:&sharesColor];
	search->offered			= [NSMutableSet setWithObject:[LDrawPartIdentity normalizedPartName:name]];
	search->colorCode		= [self colorCodeOfParts:parts report:report canSetColor:&search->canSetColor];

	// Copies built in different colors are checked like parts that differ in color.
	if (sharesColor == NO)
	{
		search->colorCode	= LDrawColorBogus;
		search->canSetColor	= NO;
	}

	for (LDrawPartReplacementKind kind = LDrawPartReplacementKindMold; kind <= LDrawPartReplacementKindPrint; kind++)
	{
		NSMutableArray *ofKind = [NSMutableArray array];

		for (NSString *candidate in [search partNamesOfKind:kind forPartNumber:number])
			[ofKind addObjectsFromArray:[search replacementsByPartNamed:candidate kind:kind]];

		[ofKind sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(LDrawPartReplacement *first,
																				 LDrawPartReplacement *second)
		{
			return [@(StatusRank(first.status)) compare:@(StatusRank(second.status))];
		}];
		[replacements addObjectsFromArray:ofKind];
	}
	return replacements;

}//end replacementsForParts:...


//========== partNamesOfKind:forPartNumber: ====================================
///
/// @abstract	The LDraw parts related to the Rebrickable part in this way,
/// 			each offered once, and only when the library has it.
///
//==============================================================================
- (NSArray<NSString *> *) partNamesOfKind:(LDrawPartReplacementKind)kind forPartNumber:(NSString *)number
{
	NSArray			*numbers	= @[];
	NSString		*plain		= nil;
	NSMutableArray	*names		= [NSMutableArray array];

	switch (kind)
	{
		case LDrawPartReplacementKindMold:
			numbers = [self->identity moldVariantsOfRebrickablePartNumber:number];
			break;
		case LDrawPartReplacementKindPlain:
			plain	= [self->identity plainPartNumberOfRebrickablePartNumber:number];
			numbers	= (plain != nil) ? @[plain] : @[];
			break;
		case LDrawPartReplacementKindPrint:
			numbers = (self->table != nil) ? [self->identity printPartNumbersOfRebrickablePartNumber:number] : @[];
			break;
	}

	for (NSString *related in numbers)
	{
		NSString *name	= nil;
		NSString *key	= nil;

		if (kind == LDrawPartReplacementKindPrint && [names count] == MaximumPrintCount)
			break;

		name	= [self libraryPartNameForPartNumber:related];
		key		= (name != nil) ? [LDrawPartIdentity normalizedPartName:name] : nil;
		if (name == nil || [self->offered containsObject:key])
			continue;
		if (kind == LDrawPartReplacementKindPrint && [self->table allowsPartNamed:name] == NO)
			continue;

		[self->offered addObject:key];
		[names addObject:name];
	}
	return names;

}//end partNamesOfKind:forPartNumber:


//========== libraryPartNameForPartNumber: =====================================
///
/// @abstract	The first LDraw part linked to the Rebrickable part that the
/// 			library has, or nil.
///
//==============================================================================
- (NSString *) libraryPartNameForPartNumber:(NSString *)number
{
	for (NSString *name in [self->identity partNamesForRebrickablePartNumber:number])
	{
		if (self->libraryHasPart(name))
			return name;
	}
	return nil;

}//end libraryPartNameForPartNumber:


//========== replacementsByPartNamed:kind: =====================================
///
/// @abstract	The part in the parts' color, and when it is not made in that
/// 			color, in each color the limit has it in.
///
//==============================================================================
- (NSArray<LDrawPartReplacement *> *) replacementsByPartNamed:(NSString *)name kind:(LDrawPartReplacementKind)kind
{
	NSMutableArray			*found		= [NSMutableArray array];
	LDrawPartLimitStatus	 status		= LDrawPartLimitStatusAllowed;
	BOOL					 keepsColor	= YES;

	if (self->table != nil && self->colorCode == LDrawColorBogus)
	{
		status = [self->table allowsPartNamed:name] ? LDrawPartLimitStatusAllowed : LDrawPartLimitStatusNotAvailable;
	}
	else if (self->table != nil)
	{
		// A color the part is not made in is not offered when the limit does more than warn.
		status		= [self->table statusForPartNamed:name colorCode:self->colorCode];
		keepsColor	= [self->table allowsPickingColorCode:self->colorCode forPartNamed:name];
	}

	if (keepsColor)
	{
		[found addObject:[self replacementByPartNamed:name
												 kind:kind
											colorCode:self->colorCode
											setsColor:NO
											   status:status]];
	}

	if (status == LDrawPartLimitStatusNotInColor && self->canSetColor)
	{
		for (NSNumber *code in [self->table colorCodesForPartNamed:name])
		{
			LDrawColorT color = (LDrawColorT)[code intValue];

			[found addObject:[self replacementByPartNamed:name
													 kind:kind
												colorCode:color
												setsColor:YES
												   status:[self->table statusForPartNamed:name colorCode:color]]];
		}
	}
	return found;

}//end replacementsByPartNamed:kind:


//========== replacementByPartNamed:kind:colorCode:setsColor:status: ===========
///
/// @abstract	Counts what the model would use once the parts are replaced.
///
//==============================================================================
- (LDrawPartReplacement *) replacementByPartNamed:(NSString *)name
											 kind:(LDrawPartReplacementKind)kind
										colorCode:(LDrawColorT)color
										setsColor:(BOOL)setsColor
										   status:(LDrawPartLimitStatus)status
{
	NSUInteger	 owned	= NSNotFound;
	NSUInteger	 used	= NSNotFound;
	NSString	*key	= nil;
	NSString	*own	= nil;

	if (self->table != nil && color != LDrawColorBogus)
		owned = [self->table ownedCountForPartNamed:name colorCode:color];

	if (owned != NSNotFound && status == LDrawPartLimitStatusAllowed)
	{
		key		= [self->table countKeyForPartNamed:name colorCode:color];
		own		= [self->table countKeyForPartNamed:self->partName colorCode:self->colorCode];
		used	= [self->report usedCountForPartNamed:name colorCode:color];

		// Copies counted with the parts already are not counted again.
		if (key == nil || [key isEqualToString:own] == NO)
			used += self->copies;
		if (used > owned)
			status = LDrawPartLimitStatusTooMany;
	}

	return [[LDrawPartReplacement alloc] initWithPartName:name
													 kind:kind
												colorCode:color
												setsColor:setsColor
												   status:status
											   ownedCount:owned
												usedCount:used];

}//end replacementByPartNamed:kind:colorCode:setsColor:status:


// MARK: - UTILITIES -


//---------- colorCodeOfParts:report:canSetColor: --------------------[static]--
///
/// @abstract	The color the parts were checked in, or LDrawColorBogus when
/// 			they differ. A color can be set only on parts that share one of
/// 			their own, other than color 16.
///
//------------------------------------------------------------------------------
+ (LDrawColorT) colorCodeOfParts:(NSArray<LDrawPart *> *)parts
						  report:(LDrawPartLimitReport *)report
					 canSetColor:(BOOL *)canSetColor
{
	LDrawColorT	first	= [[[parts firstObject] LDrawColor] colorCode];
	LDrawColorT	checked	= LDrawColorBogus;
	BOOL		canSet	= (first != LDrawCurrentColor);

	for (LDrawPart *part in parts)
	{
		LDrawColorT own		= [[part LDrawColor] colorCode];
		LDrawColorT code	= (report != nil) ? [report colorCodeForPart:part] : LDrawColorBogus;

		if (code == LDrawColorBogus)
			code = own;
		if (part == [parts firstObject])
			checked = code;
		else if (code != checked)
			checked = LDrawColorBogus;
		if (own != first)
			canSet = NO;
	}

	*canSetColor = canSet && checked != LDrawColorBogus;
	return checked;

}//end colorCodeOfParts:report:canSetColor:


//---------- copiesOfParts:usage:sharesColor: ------------------------[static]--
///
/// @abstract	How many counted copies the parts stand for. A part inside a
/// 			submodel placed twice is two. The copies may not share a color
/// 			when a part in color 16 sits in a submodel placed in two colors.
///
//------------------------------------------------------------------------------
+ (NSUInteger) copiesOfParts:(NSArray<LDrawPart *> *)parts
					   usage:(LDrawPartUsage *)usage
				 sharesColor:(BOOL *)sharesColor
{
	NSHashTable	*wanted	= [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
	NSUInteger	 count	= 0;
	BOOL		 found	= NO;
	LDrawColorT	 color	= LDrawColorBogus;

	*sharesColor = YES;
	if (usage == nil)
		return [parts count];

	for (LDrawPart *part in parts)
		[wanted addObject:part];

	// A part inside a SUB range stands for nothing; the substitute counts.
	for (LDrawPartUsageCopy *copy in usage.copies)
	{
		if (	(copy.kind != LDrawPartUsageKindPart && copy.kind != LDrawPartUsageKindMissing)
			||	[wanted containsObject:[copy.parts firstObject]] == NO )
			continue;

		if (found && copy.colorCode != color)
			*sharesColor = NO;
		found	= YES;
		color	= copy.colorCode;
		if (copy.isCounted)
			count++;
	}
	return count;

}//end copiesOfParts:usage:sharesColor:

@end
