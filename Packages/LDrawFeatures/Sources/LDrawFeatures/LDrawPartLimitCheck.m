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
#import <LDrawInventory/LDrawShortcutMap.h>


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
	NSMutableArray<LDrawPartLimitRow *>						*rowsInOrder;
	NSMutableDictionary<NSString *, LDrawPartLimitRow *>	*rowsByKey;
	NSMutableDictionary<NSString *, NSArray<NSNumber *> *>	*assemblies;		// used count, worst status
	NSMapTable<LDrawPart *, NSNumber *>						*statusByPart;
	NSMapTable<LDrawPart *, NSNumber *>						*colorByPart;		// the color of the worst copy
	NSMapTable<LDrawContainer *, NSArray<NSNumber *> *>		*containerCache;	// problem count, worst status
}


//========== initWithUsage:table: ==============================================
///
/// @abstract	Gives each copy a status in build order, and each part the worst
/// 			status of the copies it stands for. An assembly the limit counts
/// 			by its pieces adds a copy of each piece.
///
//==============================================================================
- (instancetype) initWithUsage:(LDrawPartUsage *)usage table:(LDrawPartLimitTable *)table
{
	self = [super init];
	if (self == nil)
		return nil;

	self->_table			= table;
	self->rowsInOrder		= [NSMutableArray array];
	self->rowsByKey			= [NSMutableDictionary dictionary];
	self->assemblies		= [NSMutableDictionary dictionary];
	self->statusByPart		= [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality
												valueOptions:NSPointerFunctionsStrongMemory];
	self->colorByPart		= [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality
												valueOptions:NSPointerFunctionsStrongMemory];
	self->containerCache	= [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality
												valueOptions:NSPointerFunctionsStrongMemory];

	for (LDrawPartUsageCopy *copy in usage.copies)
	{
		BOOL					 isPart	= (	copy.kind == LDrawPartUsageKindPart
											||	copy.kind == LDrawPartUsageKindSubstitute );
		NSArray					*pieces	= isPart ? [table countedPiecesOfPartNamed:copy.partName] : nil;
		LDrawPartLimitStatus	 worst	= LDrawPartLimitStatusAllowed;

		if (pieces == nil)
		{
			[self addCopyOfPartNamed:copy.partName colorCode:copy.colorCode isPart:isPart from:copy];
			continue;
		}

		for (LDrawShortcutPiece *piece in pieces)
		{
			LDrawColorT color = (piece.colorCode == LDrawCurrentColor) ? copy.colorCode : piece.colorCode;

			worst = MAX(worst, [self addCopyOfPartNamed:piece.partName colorCode:color isPart:YES from:copy]);
		}

		NSString	*key	= [self assemblyKeyForPartNamed:copy.partName colorCode:copy.colorCode];
		NSArray		*known	= self->assemblies[key];
		NSUInteger	 used	= [known[0] unsignedIntegerValue] + (copy.isCounted ? 1 : 0);

		self->assemblies[key] = @[@(used), @(MAX((LDrawPartLimitStatus)[known[1] integerValue], worst))];
	}

	self->_rows = [self->rowsInOrder copy];
	return self;

}//end initWithUsage:table:


//========== addCopyOfPartNamed:colorCode:isPart:from: =========================
///
/// @abstract	Counts one copy of a part in a color, and gives the parts the
/// 			usage copy stands for its status. Returns the status.
///
//==============================================================================
- (LDrawPartLimitStatus) addCopyOfPartNamed:(NSString *)partName
								  colorCode:(LDrawColorT)colorCode
									 isPart:(BOOL)isPart
									   from:(LDrawPartUsageCopy *)copy
{
	LDrawPartLimitTable		*table	= self.table;
	NSString				*key	= [self rowKeyForPartNamed:partName colorCode:colorCode];
	LDrawPartLimitRow		*row	= self->rowsByKey[key];
	LDrawPartLimitStatus	 status	= LDrawPartLimitStatusNoData;

	if (isPart)
		status = [table statusForPartNamed:partName colorCode:colorCode];

	if (row == nil)
	{
		row				= [[LDrawPartLimitRow alloc] init];
		row.partName	= partName;
		row.colorCode	= colorCode;
		row.ownedCount	= (status == LDrawPartLimitStatusNoData)
						  ? NSNotFound
						  : [table ownedCountForPartNamed:partName colorCode:colorCode];
		self->rowsByKey[key] = row;
		[self->rowsInOrder addObject:row];
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

		if (known == nil || status > (LDrawPartLimitStatus)[known integerValue])
		{
			[self->statusByPart setObject:@(status) forKey:part];
			[self->colorByPart setObject:@(copy.colorCode) forKey:part];
		}
	}
	return status;

}//end addCopyOfPartNamed:colorCode:isPart:from:


// MARK: - LOOKUPS -


//========== statusForPart: ====================================================
//==============================================================================
- (LDrawPartLimitStatus) statusForPart:(LDrawPart *)part
{
	return (LDrawPartLimitStatus)[[self->statusByPart objectForKey:part] integerValue];
}


//========== colorCodeForPart: =================================================
//==============================================================================
- (LDrawColorT) colorCodeForPart:(LDrawPart *)part
{
	NSNumber *color = [self->colorByPart objectForKey:part];
	return (color != nil) ? (LDrawColorT)[color intValue] : LDrawColorBogus;
}


//========== usedCountForPartNamed:colorCode: ==================================
//==============================================================================
- (NSUInteger) usedCountForPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode
{
	NSArray *assembly = self->assemblies[[self assemblyKeyForPartNamed:partName colorCode:colorCode]];

	if (assembly != nil)
		return [assembly[0] unsignedIntegerValue];
	return self->rowsByKey[[self rowKeyForPartNamed:partName colorCode:colorCode]].usedCount;
}


//========== statusForPartNamed:colorCode: =====================================
//==============================================================================
- (LDrawPartLimitStatus) statusForPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode
{
	NSArray				*assembly	= self->assemblies[[self assemblyKeyForPartNamed:partName colorCode:colorCode]];
	LDrawPartLimitRow	*row		= self->rowsByKey[[self rowKeyForPartNamed:partName colorCode:colorCode]];

	if (assembly != nil)
		return (LDrawPartLimitStatus)[assembly[1] integerValue];
	if (row != nil)
		return row.status;
	return [self.table statusForPartNamed:partName colorCode:colorCode];
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


//========== assemblyKeyForPartNamed:colorCode: ================================
//==============================================================================
- (NSString *) assemblyKeyForPartNamed:(NSString *)partName colorCode:(LDrawColorT)colorCode
{
	return [NSString stringWithFormat:@"%@\n%d", [partName lowercaseString], (int)colorCode];
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
/// 			not know, which are allowed, and marks each part as checked.
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

			if (part.limitStatus != status || part.isLimitChecked == NO)
			{
				part.limitStatus	= status;
				part.isLimitChecked	= YES;
				[changed addObject:part];
			}
		}
	}
	return changed;

}//end applyReport:toFile:

@end
