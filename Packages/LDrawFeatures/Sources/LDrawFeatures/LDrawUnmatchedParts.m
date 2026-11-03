//==============================================================================
//
//  File:       LDrawUnmatchedParts.m
//  Package:    LDrawFeatures
//
//  Purpose:    The parts that match nothing, for the user to match by hand.
//
//  Created by Sergey Slobodenyuk on 2026-10-28.
//
//==============================================================================

#import <LDrawFeatures/LDrawUnmatchedParts.h>

#import <LDrawCore/LDrawLocalization.h>
#import <LDrawFeatures/LDrawPartUsage.h>
#import <LDrawInventory/LDrawInventoryItem.h>
#import <LDrawInventory/LDrawInventoryPartsFile.h>
#import <LDrawInventory/LDrawPartIdentity.h>
#import <LDrawInventory/LDrawPartLimit.h>
#import <LDrawInventory/LDrawShortcutMap.h>


@interface LDrawUnmatchedPart ()

- (instancetype) initWithPartName:(NSString *)partName
			rebrickablePartNumber:(NSString *)partNumber
							count:(NSUInteger)count;

@end


@implementation LDrawUnmatchedPart

//========== initWithPartName:rebrickablePartNumber:count: =====================
//==============================================================================
- (instancetype) initWithPartName:(NSString *)partName
			rebrickablePartNumber:(NSString *)partNumber
							count:(NSUInteger)count
{
	self = [super init];
	if (self) {
		self->_partName					= [partName copy];
		self->_rebrickablePartNumber	= [partNumber copy];
		self->_count					= count;
	}
	return self;
}


//========== description =======================================================
//==============================================================================
- (NSString *) description
{
	return [NSString stringWithFormat:@"%@ x%lu", self.partName ?: self.rebrickablePartNumber,
			(unsigned long)self.count];
}

@end


@implementation LDrawUnmatchedParts


// MARK: - LISTING -


//---------- partsInUsages:identity:shortcuts: -----------------------[static]--
//------------------------------------------------------------------------------
+ (NSArray<LDrawUnmatchedPart *> *) partsInUsages:(NSArray<LDrawPartUsage *> *)usages
										 identity:(LDrawPartIdentity *)identity
										shortcuts:(LDrawShortcutMap *)shortcuts
{
	NSMutableOrderedSet	*names	= [NSMutableOrderedSet orderedSet];
	NSCountedSet		*placed	= [NSCountedSet set];	// copies the models place, not those of unplaced models

	for (LDrawPartUsage *usage in usages)
	{
		for (LDrawPartUsageCopy *copy in usage.copies)
		{
			NSMutableArray	*unmatched	= [NSMutableArray array];
			NSArray			*pieces		= nil;

			if (copy.isLEGOPart == NO)
				continue;
			if ([identity rebrickablePartNumberForPartName:copy.partName] != nil)
				continue;

			pieces = [shortcuts piecesOfPartNamed:copy.partName];
			if (pieces == nil)
				[unmatched addObject:copy.partName];
			for (LDrawShortcutPiece *piece in pieces)
			{
				if ([identity rebrickablePartNumberForPartName:piece.partName] == nil)
					[unmatched addObject:piece.partName];
			}

			[names addObjectsFromArray:unmatched];
			if (copy.isCounted)
			{
				for (NSString *name in unmatched)
					[placed addObject:name];
			}
		}
	}

	NSMutableArray *parts = [NSMutableArray arrayWithCapacity:[names count]];
	for (NSString *name in names)
	{
		LDrawUnmatchedPart *part = [[LDrawUnmatchedPart alloc] initWithPartName:name
														  rebrickablePartNumber:nil
																		  count:[placed countForObject:name]];
		[parts addObject:part];
	}
	return [self sortedParts:parts];

}//end partsInUsages:identity:shortcuts:


//---------- partsInItems:limit:identity:libraryHasPart: -------------[static]--
//------------------------------------------------------------------------------
+ (NSArray<LDrawUnmatchedPart *> *) partsInItems:(NSArray<LDrawInventoryItem *> *)items
										   limit:(LDrawPartLimit *)limit
										identity:(LDrawPartIdentity *)identity
								  libraryHasPart:(BOOL (^)(NSString *partName))libraryHasPart
{
	NSMutableDictionary<NSString *, NSNumber *>	*counts		= [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, NSNumber *>	*isMatched	= [NSMutableDictionary dictionary];
	NSMutableArray								*parts		= [NSMutableArray array];

	for (LDrawInventoryItem *item in items)
	{
		NSString *number = item.rebrickablePartNumber;

		if (number == nil || (item.ldrawPartName != nil && libraryHasPart(item.ldrawPartName)))
			continue;

		if (isMatched[number] == nil)
		{
			NSString	*pool		= [identity poolKeyForRebrickablePartNumber:number
															matchesMoldVariants:limit.matchesMoldVariants
																matchesAnyPrint:limit.matchesAnyPrint];
			BOOL		 matched	= NO;

			for (NSString *name in [identity partNamesForRebrickablePartNumber:number])
				matched = matched || libraryHasPart(name);
			for (NSString *name in [identity partNamesForRebrickablePartNumber:pool])
				matched = matched || libraryHasPart(name);
			isMatched[number] = @(matched);
		}

		if ([isMatched[number] boolValue] == NO)
			counts[number] = @([counts[number] unsignedIntegerValue] + item.quantity + item.spareQuantity);
	}

	for (NSString *number in counts)
	{
		LDrawUnmatchedPart *part = [[LDrawUnmatchedPart alloc] initWithPartName:nil
														  rebrickablePartNumber:number
																		  count:[counts[number] unsignedIntegerValue]];
		[parts addObject:part];
	}
	return [self sortedParts:parts];

}//end partsInItems:limit:identity:libraryHasPart:


// MARK: - HAND MATCHES -


//---------- overrides:byMatchingPart:toText:libraryHasPart:error: ---[static]--
//------------------------------------------------------------------------------
+ (NSDictionary<NSString *, NSString *> *) overrides:(NSDictionary<NSString *, NSString *> *)overrides
									  byMatchingPart:(LDrawUnmatchedPart *)part
											  toText:(NSString *)text
									  libraryHasPart:(BOOL (^)(NSString *partName))libraryHasPart
											   error:(NSError **)error
{
	NSString *typed	= [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *name	= nil;

	if ([typed length] == 0)
		return overrides ?: @{};

	if (part.partName != nil)
		return [self overrides:overrides byMatchingPartNamed:part.partName toPartNumber:typed];

	name = [LDrawPartIdentity libraryPartName:typed];
	if (libraryHasPart(name) == NO)
	{
		NSString *reason = [LDrawLocalization stringForKey:@"The part library has no part “%@”."];

		if (error != NULL)
			*error = LDrawInventoryMakeError(LDrawInventoryErrorPartNotInLibrary,
											 [NSString stringWithFormat:reason, typed]);
		return nil;
	}
	return [self overrides:overrides byMatchingPartNamed:name toPartNumber:part.rebrickablePartNumber];

}//end overrides:byMatchingPart:toText:libraryHasPart:error:


//---------- overrides:byMatchingPartNamed:toPartNumber: -------------[static]--
//------------------------------------------------------------------------------
+ (NSDictionary<NSString *, NSString *> *) overrides:(NSDictionary<NSString *, NSString *> *)overrides
								 byMatchingPartNamed:(NSString *)partName
										toPartNumber:(NSString *)partNumber
{
	NSMutableDictionary	*matches	= [NSMutableDictionary dictionaryWithDictionary:overrides ?: @{}];
	NSString			*name		= [LDrawPartIdentity normalizedPartName:partName];
	NSString			*number		= [partNumber stringByTrimmingCharactersInSet:
									   [NSCharacterSet whitespaceAndNewlineCharacterSet]];

	if (name == nil)
		return matches;

	if ([number length] > 0)
		matches[name] = number;
	else
		[matches removeObjectForKey:name];
	return matches;

}//end overrides:byMatchingPartNamed:toPartNumber:


// MARK: - UTILITIES -


//---------- sortedParts: --------------------------------------------[static]--
///
/// @abstract	The most first, then by name or number.
///
//------------------------------------------------------------------------------
+ (NSArray<LDrawUnmatchedPart *> *) sortedParts:(NSArray<LDrawUnmatchedPart *> *)parts
{
	return [parts sortedArrayUsingComparator:^NSComparisonResult(LDrawUnmatchedPart *a, LDrawUnmatchedPart *b) {
		if (a.count != b.count)
			return (a.count > b.count) ? NSOrderedAscending : NSOrderedDescending;
		return [a.partName ?: a.rebrickablePartNumber localizedStandardCompare:b.partName ?: b.rebrickablePartNumber];
	}];
}

@end
