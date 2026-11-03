//==============================================================================
//
//  File:       LDrawPartLimitChecker.m
//  Package:    LDrawFeatures
//
//  Purpose:    One file's check against the parts limit, and what a host shows
//              for it.
//
//  Created by Sergey Slobodenyuk on 2026-11-03.
//
//==============================================================================

#import <LDrawFeatures/LDrawPartLimitChecker.h>

#import <LDrawCore/LDrawColorLibrary.h>
#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawLocalization.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawFeatures/LDrawPartLimitCheck.h>
#import <LDrawFeatures/LDrawPartUsage.h>
#import <LDrawInventory/LDrawPartLimit.h>
#import <LDrawInventory/LDrawPartLimitTable.h>

static NSString * const ProblemSymbolName	= @"exclamationmark.triangle.fill";
static NSString * const NotedSymbolName		= @"questionmark.circle";
static NSString * const MissingSymbolName	= @"questionmark.square.dashed";

// The statuses the summary lists, worst first.
static const LDrawPartLimitStatus SummaryStatuses[] = {
	LDrawPartLimitStatusNotAvailable,
	LDrawPartLimitStatusNotInColor,
	LDrawPartLimitStatusTooMany,
	LDrawPartLimitStatusNoData,
};


@interface LDrawPartLimitBadge ()

- (instancetype)initWithSymbolName:(nullable NSString *)symbolName
							  tint:(LDrawPartLimitBadgeTint)tint
							 count:(NSUInteger)count;

@end


@implementation LDrawPartLimitBadge

//========== initWithSymbolName:tint:count: ====================================
//==============================================================================
- (instancetype)initWithSymbolName:(NSString *)symbolName tint:(LDrawPartLimitBadgeTint)tint count:(NSUInteger)count
{
	self = [super init];
	if (self)
	{
		self->_symbolName	= [symbolName copy];
		self->_tint			= tint;
		self->_count		= count;
	}
	return self;
}

@end


@implementation LDrawPartLimitChecker
{
	LDrawPartUsage		*usage;			// nil after an edit until asked for
	NSMapTable			*missingCounts;	// parts not in the library, by container, until the next edit
	BOOL				 hasMarks;		// some part may hold a status from an earlier limit
}


//========== initWithFile: =====================================================
//==============================================================================
- (instancetype)initWithFile:(LDrawFile *)aFile
{
	self = [super init];
	if (self)
	{
		self->_file			= aFile;
		self->missingCounts	= [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
															   | NSPointerFunctionsObjectPointerPersonality
													valueOptions:NSPointerFunctionsStrongMemory];
	}
	return self;
}


// MARK: - CHECKING -


//========== modelDidChange ====================================================
//==============================================================================
- (void)modelDidChange
{
	self->usage = nil;
	[self->missingCounts removeAllObjects];
}


//========== usage =============================================================
//==============================================================================
- (LDrawPartUsage *)usage
{
	LDrawFile *checked = self.file;

	if (self->usage == nil && checked != nil)
		self->usage = [LDrawPartUsage usageOfFile:checked];
	return self->usage;
}


//========== checkAgainstTable: ================================================
//==============================================================================
- (BOOL)checkAgainstTable:(LDrawPartLimitTable *)table
{
	LDrawFile	*checked	= self.file;
	BOOL		 restricts	= table.limit.isRestricting;
	NSArray		*changed	= nil;

	if (checked == nil)
		return NO;

	if (restricts == NO && self->hasMarks == NO)
	{
		self->_report = nil;
		return NO;
	}

	self->_report	= [LDrawPartLimitCheck reportForUsage:[self usage] table:table];
	changed			= [LDrawPartLimitCheck applyReport:self->_report toFile:checked];
	self->hasMarks	= restricts;

	return [changed count] > 0;
}


//========== showsMarks ========================================================
//==============================================================================
- (BOOL)showsMarks
{
	return		self.report != nil
			&&	self.report.table.limit.isRestricting
			&&	[LDrawPart limitMarkStyle] != LDrawRenderMarkNone;
}


// MARK: - A LIST OF THE MODEL -


//========== badgeForItem: =====================================================
//==============================================================================
- (LDrawPartLimitBadge *)badgeForItem:(id)item
{
	LDrawPartLimitStatus	 status		= LDrawPartLimitStatusAllowed;
	NSUInteger				 count		= 0;
	NSUInteger				 missing	= 0;
	BOOL					 isPart		= [item isKindOfClass:[LDrawPart class]];

	if ([self showsMarks])
	{
		if (isPart)
			status = [(LDrawPart *)item limitStatus];
		else if ([item isKindOfClass:[LDrawContainer class]])
		{
			count	= [self.report problemCountInContainer:item];
			status	= (count > 0) ? [self.report worstStatusInContainer:item] : LDrawPartLimitStatusAllowed;
		}
	}

	if (LDrawPartLimitStatusIsProblem(status) == NO)
		missing = [self missingPartCountInItem:item];
	if (missing > 0)
		return [[LDrawPartLimitBadge alloc] initWithSymbolName:MissingSymbolName
														  tint:LDrawPartLimitBadgeTintGray
														 count:isPart ? 0 : missing];

	return [[LDrawPartLimitBadge alloc] initWithSymbolName:[LDrawPartLimitPresentation badgeSymbolNameForStatus:status]
													  tint:[LDrawPartLimitPresentation badgeTintForStatus:status]
													 count:count];
}


//========== missingPartCountInItem: ===========================================
///
/// @abstract	How many parts the part library lacks: 1 or 0 for a part, and
/// 			the parts inside a step or model.
///
/// @discussion	A container's count is kept until the next edit, since a list
/// 			asks for every row each time it draws.
///
//==============================================================================
- (NSUInteger)missingPartCountInItem:(id)item
{
	__block NSUInteger	 count	= 0;
	NSNumber			*known	= nil;

	if ([item isKindOfClass:[LDrawPart class]])
		return [(LDrawPart *)item partIsMissing] ? 1 : 0;
	if ([item isKindOfClass:[LDrawContainer class]] == NO)
		return 0;

	known = [self->missingCounts objectForKey:item];
	if (known != nil)
		return [known unsignedIntegerValue];

	[(LDrawContainer *)item applyToAllParts:^(LDrawPart *part) {
		if ([part partIsMissing])
			count += 1;
	}];
	[self->missingCounts setObject:@(count) forKey:item];
	return count;
}


//========== toolTipForItem:store: =============================================
//==============================================================================
- (NSString *)toolTipForItem:(id)item store:(LDrawInventoryStore *)store
{
	NSUInteger	 count		= 0;
	NSUInteger	 missing	= 0;
	NSString	*line		= nil;

	if ([item isKindOfClass:[LDrawPart class]])
	{
		NSString *note = [LDrawLocalization stringForKey:@"The part library does not have this part."];

		if ([self showsMarks])
			line = [LDrawPartLimitPresentation lineForPart:item report:self.report store:store fully:YES];
		if ([(LDrawPart *)item partIsMissing] == NO)
			return line;
		return (line != nil) ? [NSString stringWithFormat:@"%@ %@", note, line] : note;
	}

	if ([self showsMarks] && [item isKindOfClass:[LDrawContainer class]])
		count = [self.report problemCountInContainer:item];
	if (count > 0)
		return [self textForCount:count
							  one:@"1 part breaks the parts limit."
							 many:@"%lu parts break the parts limit."];

	missing = [self missingPartCountInItem:item];
	if (missing > 0)
		return [self textForCount:missing
							  one:@"1 part is not in the part library."
							 many:@"%lu parts are not in the part library."];
	return nil;
}


//========== lineForPart:store: ================================================
//==============================================================================
- (NSString *)lineForPart:(LDrawPart *)part store:(LDrawInventoryStore *)store
{
	if ([self showsMarks] == NO)
		return nil;
	return [LDrawPartLimitPresentation lineForPart:part report:self.report store:store fully:NO];
}


//========== textForCount:one:many: ============================================
///
/// @abstract	The text for one part, or the text for many with the count in it.
///
//==============================================================================
- (NSString *)textForCount:(NSUInteger)count one:(NSString *)oneKey many:(NSString *)manyKey
{
	if (count == 1)
		return [LDrawLocalization stringForKey:oneKey];
	return [NSString localizedStringWithFormat:[LDrawLocalization stringForKey:manyKey], (unsigned long)count];
}


// MARK: - THE SUMMARY -


//========== problemCount ======================================================
///
/// @abstract	The file's problems, or 0 when no limit restricts.
///
//==============================================================================
- (NSUInteger)problemCount
{
	LDrawPartLimitReport *report = self.report;

	if (report == nil || report.table.limit.isRestricting == NO)
		return 0;
	return [report problemCountInContainer:self.file];
}


//========== notedPartCount ====================================================
///
/// @abstract	How many parts have no data or are not in the part library. A
/// 			part counts once.
///
//==============================================================================
- (NSUInteger)notedPartCount
{
	NSHashTable *parts = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];

	for (LDrawPart *part in [self.report partsWithStatus:LDrawPartLimitStatusNoData])
		[parts addObject:part];
	for (LDrawPart *part in [self.report missingParts])
		[parts addObject:part];
	return [parts count];
}


//========== summaryBadge ======================================================
//==============================================================================
- (LDrawPartLimitBadge *)summaryBadge
{
	LDrawPartLimitReport	*report		= self.report;
	NSUInteger				 problems	= [self problemCount];
	NSUInteger				 noted		= 0;

	if (problems > 0)
	{
		LDrawPartLimitStatus worst = [report worstStatusInContainer:self.file];

		return [[LDrawPartLimitBadge alloc] initWithSymbolName:ProblemSymbolName
														  tint:[LDrawPartLimitPresentation badgeTintForStatus:worst]
														 count:problems];
	}

	if (report.table.limit.isRestricting && [report.table hasData])
		noted = [self notedPartCount];
	return [[LDrawPartLimitBadge alloc] initWithSymbolName:NotedSymbolName
													  tint:LDrawPartLimitBadgeTintGray
													 count:noted];
}


//========== summaryToolTip ====================================================
//==============================================================================
- (NSString *)summaryToolTip
{
	if ([self problemCount] > 0)
		return [LDrawLocalization stringForKey:@"Parts that break the parts limit"];
	return [LDrawLocalization stringForKey:@"Parts with no data, or not in the part library"];
}


//========== summaryStatuses ===================================================
//==============================================================================
- (NSArray<NSNumber *> *)summaryStatuses
{
	NSMutableArray *statuses = [NSMutableArray array];

	for (size_t index = 0; index < sizeof(SummaryStatuses) / sizeof(SummaryStatuses[0]); index++)
	{
		if ([[self.report partsWithStatus:SummaryStatuses[index]] count] > 0)
			[statuses addObject:@(SummaryStatuses[index])];
	}
	return statuses;
}


//========== nearestAllowedColors ==============================================
//==============================================================================
- (NSMapTable<LDrawPart *, LDrawColor *> *)nearestAllowedColors
{
	LDrawPartLimitTable	*table		= self.report.table;
	LDrawColorLibrary	*library	= [LDrawColorLibrary sharedColorLibrary];
	NSMapTable			*colors		= [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality
															valueOptions:NSPointerFunctionsStrongMemory];

	for (LDrawPart *part in [self.report partsWithStatus:LDrawPartLimitStatusNotInColor])
	{
		LDrawColor		*color		= [part LDrawColor];
		NSMutableArray	*choices	= [NSMutableArray array];
		LDrawColor		*nearest	= nil;

		if ([color colorCode] == LDrawCurrentColor)
			continue;

		for (NSNumber *code in [table colorCodesForPartNamed:[part displayName]])
		{
			LDrawColor *choice = [library colorForCode:(LDrawColorT)[code intValue]];
			if (choice != nil)
				[choices addObject:choice];
		}

		// A part inside a SUB range takes the substitute's status, and may
		// already be in its nearest color.
		nearest = [LDrawPartLimitPresentation nearestColorTo:color amongColors:choices];
		if (nearest != nil && [nearest colorCode] != [color colorCode])
			[colors setObject:nearest forKey:part];
	}
	return colors;
}

@end
