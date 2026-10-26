//==============================================================================
//
//  File:       LDrawPartLimitCheck.m
//  Package:    LDrawFeatures
//
//  Purpose:    Puts what a model uses against what a limit allows.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawFeatures/LDrawPartLimitCheck.h>

#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawFeatures/LDrawPartUsage.h>
#import <LDrawInventory/LDrawPartLimitTable.h>


//========== IsProblem =========================================================
///
/// @abstract	A status worth a mark: anything but allowed or no data.
///
//==============================================================================
static BOOL IsProblem(LDrawPartLimitStatus status)
{
	return status == LDrawPartLimitStatusTooMany
		|| status == LDrawPartLimitStatusNotInColor
		|| status == LDrawPartLimitStatusNotAvailable;
}


@interface LDrawPartLimitRow ()

@property (nonatomic, readwrite, copy) NSString *partName;
@property (nonatomic, readwrite) LDrawColorT colorCode;
@property (nonatomic, readwrite) NSUInteger usedCount;
@property (nonatomic, readwrite) NSUInteger ownedCount;
@property (nonatomic, readwrite) LDrawPartLimitStatus status;

@end


@implementation LDrawPartLimitRow

//========== description =======================================================
//==============================================================================
- (NSString *) description
{
	return [NSString stringWithFormat:@"<%@ %@ color %d: %lu / %ld, status %ld>", [self class], self.partName,
			(int)self.colorCode, (unsigned long)self.usedCount,
			self.ownedCount == NSNotFound ? -1L : (long)self.ownedCount, (long)self.status];
}

@end


@interface LDrawPartLimitReport ()

- (instancetype) initWithUsage:(LDrawPartUsage *)usage table:(LDrawPartLimitTable *)table;

@end


@implementation LDrawPartLimitReport
{
	NSMutableDictionary<NSString *, LDrawPartLimitRow *>	*rowsByKey;
	NSMapTable<LDrawPart *, NSNumber *>						*statusByPart;
	NSMapTable<LDrawContainer *, NSArray<NSNumber *> *>		*containerCache;	// problem count, worst status
}


//========== initWithUsage:table: ==============================================
///
/// @abstract	Gives each copy a status in build order, and each part the worst
/// 			status of the copies it stands for.
///
//==============================================================================
- (instancetype) initWithUsage:(LDrawPartUsage *)usage table:(LDrawPartLimitTable *)table
{
	NSMutableArray<LDrawPartLimitRow *> *rows = [NSMutableArray array];

	self = [super init];
	if (self == nil)
		return nil;

	self->_table			= table;
	self->rowsByKey			= [NSMutableDictionary dictionary];
	self->statusByPart		= [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality
												valueOptions:NSPointerFunctionsStrongMemory];
	self->containerCache	= [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality
												valueOptions:NSPointerFunctionsStrongMemory];

	for (LDrawPartUsageCopy *copy in usage.copies)
	{
		NSString				*key	= [self rowKeyForPartNamed:copy.partName colorCode:copy.colorCode];
		LDrawPartLimitRow		*row	= self->rowsByKey[key];
		LDrawPartLimitStatus	 status	= LDrawPartLimitStatusNoData;

		if (copy.kind == LDrawPartUsageKindPart || copy.kind == LDrawPartUsageKindSubstitute)
			status = [table statusForPartNamed:copy.partName colorCode:copy.colorCode];

		if (row == nil)
		{
			row				= [[LDrawPartLimitRow alloc] init];
			row.partName	= copy.partName;
			row.colorCode	= copy.colorCode;
			row.ownedCount	= (status == LDrawPartLimitStatusNoData)
							  ? NSNotFound
							  : [table ownedCountForPartNamed:copy.partName colorCode:copy.colorCode];
			self->rowsByKey[key] = row;
			[rows addObject:row];
		}

		if (copy.isCounted)
		{
			row.usedCount += 1;

			// The copies past what is owned, in build order.
			if (status == LDrawPartLimitStatusAllowed && row.ownedCount != NSNotFound && row.usedCount > row.ownedCount)
				status = LDrawPartLimitStatusTooMany;
		}

		row.status = MAX(row.status, status);

		for (LDrawPart *part in copy.parts)
		{
			NSNumber *known = [self->statusByPart objectForKey:part];
			[self->statusByPart setObject:@(MAX((LDrawPartLimitStatus)[known integerValue], status)) forKey:part];
		}
	}

	self->_rows = rows;
	return self;

}//end initWithUsage:table:


// MARK: - LOOKUPS -


//========== statusForPart: ====================================================
//==============================================================================
- (LDrawPartLimitStatus) statusForPart:(LDrawPart *)part
{
	return (LDrawPartLimitStatus)[[self->statusByPart objectForKey:part] integerValue];
}


//========== usedCountForPartNamed:colorCode: ==================================
//==============================================================================
- (NSUInteger) usedCountForPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode
{
	return self->rowsByKey[[self rowKeyForPartNamed:partName colorCode:colorCode]].usedCount;
}


//========== partsWithStatus: ==================================================
//==============================================================================
- (NSArray<LDrawPart *> *) partsWithStatus:(LDrawPartLimitStatus)status
{
	NSMutableArray *parts = [NSMutableArray array];

	for (LDrawPart *part in self->statusByPart)
	{
		if ([self statusForPart:part] == status)
			[parts addObject:part];
	}
	return parts;

}//end partsWithStatus:


//========== problemCountInContainer: ==========================================
//==============================================================================
- (NSUInteger) problemCountInContainer:(LDrawContainer *)container
{
	return [[self summaryOfContainer:container][0] unsignedIntegerValue];
}


//========== worstStatusInContainer: ===========================================
//==============================================================================
- (LDrawPartLimitStatus) worstStatusInContainer:(LDrawContainer *)container
{
	return (LDrawPartLimitStatus)[[self summaryOfContainer:container][1] integerValue];
}


// MARK: - UTILITIES -


//========== rowKeyForPartNamed:colorCode: =====================================
///
/// @abstract	The limit's own count key; a copy with no match is kept apart
/// 			by its name and color.
///
//==============================================================================
- (NSString *) rowKeyForPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode
{
	NSString *key = [self.table countKeyForPartNamed:partName colorCode:colorCode];

	return key ?: [NSString stringWithFormat:@"?\n%@\n%d", [partName lowercaseString], (int)colorCode];
}


//========== summaryOfContainer: ===============================================
///
/// @abstract	The problem count and worst status of the parts inside, worked
/// 			out once per container. File Contents asks for each row it
/// 			draws.
///
//==============================================================================
- (NSArray<NSNumber *> *) summaryOfContainer:(LDrawContainer *)container
{
	NSArray<NSNumber *> *summary = [self->containerCache objectForKey:container];

	if (summary == nil)
	{
		NSUInteger				problems	= 0;
		LDrawPartLimitStatus	worst		= LDrawPartLimitStatusAllowed;

		for (id element in [container allEnclosedElements])
		{
			if ([element isKindOfClass:[LDrawPart class]] == NO)
				continue;

			LDrawPartLimitStatus status = [self statusForPart:element];
			if (IsProblem(status))
				problems += 1;
			worst = MAX(worst, status);
		}

		summary = @[@(problems), @(worst)];
		[self->containerCache setObject:summary forKey:container];
	}
	return summary;

}//end summaryOfContainer:

@end


@implementation LDrawPartLimitCheck


//---------- reportForFile:table: ------------------------------------[static]--
//------------------------------------------------------------------------------
+ (LDrawPartLimitReport *) reportForFile:(LDrawFile *)file table:(LDrawPartLimitTable *)table
{
	return [self reportForUsage:[LDrawPartUsage usageOfFile:file] table:table];
}


//---------- reportForUsage:table: -----------------------------------[static]--
//------------------------------------------------------------------------------
+ (LDrawPartLimitReport *) reportForUsage:(LDrawPartUsage *)usage table:(LDrawPartLimitTable *)table
{
	return [[LDrawPartLimitReport alloc] initWithUsage:usage table:table];
}


//---------- applyReport:toFile: -------------------------------------[static]--
///
/// @abstract	Sets every part's status, including the parts the report does
/// 			not know, which are allowed.
///
//------------------------------------------------------------------------------
+ (NSArray<LDrawPart *> *) applyReport:(LDrawPartLimitReport *)report toFile:(LDrawFile *)file
{
	NSMutableArray<LDrawPart *> *changed = [NSMutableArray array];

	for (LDrawContainer *model in [file submodels])
	{
		for (id element in [model allEnclosedElements])
		{
			if ([element isKindOfClass:[LDrawPart class]] == NO)
				continue;

			LDrawPart				*part	= element;
			LDrawPartLimitStatus	 status	= [report statusForPart:part];

			if (part.limitStatus != status)
			{
				part.limitStatus = status;
				[changed addObject:part];
			}
		}
	}
	return changed;

}//end applyReport:toFile:

@end
