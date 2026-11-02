//==============================================================================
//
//  File:       LDrawInventoryStore.m
//  Package:    LDrawInventory
//
//  Purpose:    The imported sets, the user's inventories, the catalog and the
//              identity data, kept as JSON files in one folder.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawInventory/LDrawInventoryStore.h>

#import <LDrawInventory/LDrawCombinedInventory.h>
#import <LDrawInventory/LDrawInventoryItem.h>
#import <LDrawInventory/LDrawInventoryPartsFile.h>
#import <LDrawInventory/LDrawPartAvailability.h>
#import <LDrawInventory/LDrawPartIdentity.h>
#import <LDrawInventory/LDrawPartLimit.h>
#import <LDrawInventory/LDrawPartLimitTable.h>
#import <LDrawInventory/LDrawSetInventory.h>

#import <LDrawInventory/LDrawInventoryJSON.h>

NSString * const LDrawInventoryStoreDidChangeNotification = @"LDrawInventoryStoreDidChangeNotification";

static NSString * const InventoriesFileName		= @"inventories.json";
static NSString * const SetsFolderName			= @"sets";
static NSString * const CatalogFileName			= @"catalog.json";
static NSString * const IdentityFileName		= @"identity.json";
static NSString * const OverridesFileName		= @"identity-overrides.json";

static NSString * const VersionKey				= @"version";
static NSString * const InventoriesKey			= @"inventories";
static NSString * const OverridesKey			= @"links";


@implementation LDrawInventoryStore
{
	NSMutableArray<LDrawCombinedInventory *>				*inventories;	// nil until read
	NSMutableDictionary<NSString *, LDrawSetInventory *>	*sets;			// nil until read
	LDrawPartAvailability									*catalog;		// nil until read or when there is none
	BOOL													 catalogWasRead;
	NSDictionary											*identityData;	// nil until read or when there is none
	BOOL													 identityDataWasRead;
	NSDictionary<NSString *, NSString *>					*handMatches;	// nil until read
	NSMutableSet<NSString *>								*lockedFiles;	// unreadable and still in place
	NSUInteger												 batchDepth;	// saves under -performChanges:
	BOOL													 changeIsWaiting;
}


// MARK: - INITIALIZATION -


//========== initWithFolderURL: ================================================
//==============================================================================
- (instancetype) initWithFolderURL:(NSURL *)folderURL
{
	self = [super init];
	if (self) {
		self->_folderURL = [folderURL copy];
	}
	return self;
}


// MARK: - COMBINED INVENTORIES -


//========== combinedInventories ===============================================
///
/// @abstract	Sorted by name, then identifier, so equal names keep an order.
///
//==============================================================================
- (NSArray<LDrawCombinedInventory *> *) combinedInventories
{
	NSSortDescriptor *byName		= [NSSortDescriptor sortDescriptorWithKey:@"name"
																	ascending:YES
																	 selector:@selector(localizedStandardCompare:)];
	NSSortDescriptor *byIdentifier	= [NSSortDescriptor sortDescriptorWithKey:@"identifier" ascending:YES];

	return [[self loadedInventories] sortedArrayUsingDescriptors:@[byName, byIdentifier]];
}


//========== combinedInventoryWithIdentifier: ==================================
//==============================================================================
- (LDrawCombinedInventory *) combinedInventoryWithIdentifier:(NSString *)identifier
{
	NSUInteger index = [self indexOfInventoryWithIdentifier:identifier];
	return (index != NSNotFound) ? [self loadedInventories][index] : nil;
}


//========== saveCombinedInventory:error: ======================================
///
/// @abstract	Adds the inventory, or replaces the one with its identifier.
///
//==============================================================================
- (BOOL) saveCombinedInventory:(LDrawCombinedInventory *)inventory error:(NSError **)error
{
	NSMutableArray	*updated	= [[self loadedInventories] mutableCopy];
	NSUInteger		 index		= [self indexOfInventoryWithIdentifier:inventory.identifier];

	if (index == NSNotFound)
		[updated addObject:inventory];
	else
		[updated replaceObjectAtIndex:index withObject:inventory];

	return [self writeInventories:updated error:error];

}//end saveCombinedInventory:error:


//========== removeCombinedInventoryWithIdentifier:error: ======================
//==============================================================================
- (BOOL) removeCombinedInventoryWithIdentifier:(NSString *)identifier error:(NSError **)error
{
	NSMutableArray	*updated	= [[self loadedInventories] mutableCopy];
	NSUInteger		 index		= [self indexOfInventoryWithIdentifier:identifier];

	if (index == NSNotFound)
		return YES;

	[updated removeObjectAtIndex:index];
	return [self writeInventories:updated error:error];

}//end removeCombinedInventoryWithIdentifier:error:


// MARK: - SETS -


//========== setNumbers ========================================================
//==============================================================================
- (NSArray<NSString *> *) setNumbers
{
	return [[[self loadedSets] allKeys] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}


//========== setInventoryForNumber: ============================================
//==============================================================================
- (LDrawSetInventory *) setInventoryForNumber:(NSString *)setNumber
{
	NSString *number = [LDrawSetInventory normalizedSetNumber:setNumber];
	return (number != nil) ? [self loadedSets][number] : nil;
}


//========== saveSetInventory:error: ===========================================
///
/// @abstract	Adds the set, or replaces the one with its number.
///
//==============================================================================
- (BOOL) saveSetInventory:(LDrawSetInventory *)setInventory error:(NSError **)error
{
	NSURL *url = [self urlForSetNumber:setInventory.setNumber];

	if (LDrawJSONWriteFile([setInventory dictionaryRepresentation], url, YES, error) == NO)
		return NO;

	[self loadedSets][setInventory.setNumber] = setInventory;
	[self postChange];
	return YES;

}//end saveSetInventory:error:


//========== removeSetInventoryForNumber:error: ================================
///
/// @abstract	Removes the set's file. Inventories that name the set keep its
/// 			number and leave it out until it is imported again.
///
//==============================================================================
- (BOOL) removeSetInventoryForNumber:(NSString *)setNumber error:(NSError **)error
{
	NSString	*number	= [LDrawSetInventory normalizedSetNumber:setNumber];
	NSURL		*url	= (number != nil) ? [self urlForSetNumber:number] : nil;

	if (url == nil || [self loadedSets][number] == nil)
		return YES;

	if (	[[NSFileManager defaultManager] removeItemAtURL:url error:error] == NO
		&&	[[NSFileManager defaultManager] fileExistsAtPath:[url path]] )
	{
		return NO;
	}

	[[self loadedSets] removeObjectForKey:number];
	[self postChange];
	return YES;

}//end removeSetInventoryForNumber:error:


// MARK: - WHAT A LIMIT READS -


//========== titleForInventoryIdentifier: ======================================
//==============================================================================
- (NSString *) titleForInventoryIdentifier:(NSString *)identifier
{
	return [self combinedInventoryWithIdentifier:identifier].name ?: [self setInventoryForNumber:identifier].title;
}


//========== itemsForInventoryIdentifier: ======================================
///
/// @abstract	Every item of a combined inventory or a set.
///
//==============================================================================
- (NSArray<LDrawInventoryItem *> *) itemsForInventoryIdentifier:(NSString *)identifier
{
	LDrawCombinedInventory	*inventory	= [self combinedInventoryWithIdentifier:identifier];
	LDrawSetInventory		*set		= nil;
	NSMutableArray			*items		= nil;

	if (inventory == nil)
	{
		set = [self setInventoryForNumber:identifier];
		return set.items;
	}

	items = [NSMutableArray array];
	for (NSString *setNumber in [[inventory.setCounts allKeys] sortedArrayUsingSelector:@selector(compare:)])
	{
		NSUInteger count = [inventory.setCounts[setNumber] unsignedIntegerValue];

		for (LDrawInventoryItem *item in [self setInventoryForNumber:setNumber].items)
			[items addObject:[item itemMultipliedBy:count]];
	}
	[items addObjectsFromArray:inventory.looseItems];

	return items;

}//end itemsForInventoryIdentifier:


//========== resolvedLimit: ====================================================
//==============================================================================
- (LDrawPartLimit *) resolvedLimit:(LDrawPartLimit *)limit
{
	if (	limit.kind == LDrawPartLimitKindInventory
		&&	[self itemsForInventoryIdentifier:limit.inventoryIdentifier] == nil )
	{
		return [limit limitWithKind:LDrawPartLimitKindNone inventoryIdentifier:nil];
	}
	return limit;
}


//========== tableForLimit:identity:year: ======================================
//==============================================================================
- (LDrawPartLimitTable *) tableForLimit:(LDrawPartLimit *)limit
							   identity:(LDrawPartIdentity *)identity
								   year:(NSInteger)currentYear
{
	return [self tableForLimit:limit identity:identity shortcuts:nil year:currentYear];
}


//========== tableForLimit:identity:shortcuts:year: ============================
//==============================================================================
- (LDrawPartLimitTable *) tableForLimit:(LDrawPartLimit *)limit
							   identity:(LDrawPartIdentity *)identity
							  shortcuts:(LDrawShortcutMap *)shortcuts
								   year:(NSInteger)currentYear
{
	LDrawPartLimit			*resolved		= limit;
	LDrawPartAvailability	*availability	= nil;
	NSArray					*items			= nil;

	// The items are read once, and say whether the store has the inventory.
	if (limit.kind == LDrawPartLimitKindAvailableNow)
		availability = [self availability];
	else if (limit.kind == LDrawPartLimitKindInventory)
	{
		items = [self itemsForInventoryIdentifier:limit.inventoryIdentifier];
		if (items == nil)
			resolved = [limit limitWithKind:LDrawPartLimitKindNone inventoryIdentifier:nil];
	}

	return [LDrawPartLimitTable tableForLimit:resolved
								 availability:availability
										items:items
									 identity:identity
									shortcuts:shortcuts
										 year:currentYear];

}//end tableForLimit:identity:shortcuts:year:


// MARK: - CATALOG AND IDENTITY -


//========== availability ======================================================
///
/// @abstract	The catalog, read once. It is large, so it is not read until
/// 			something asks.
///
//==============================================================================
- (LDrawPartAvailability *) availability
{
	if (self->catalogWasRead == NO)
	{
		self->catalog			= [LDrawPartAvailability availabilityWithDictionary:
								   LDrawJSONReadFile([self urlForFile:CatalogFileName])];
		self->catalogWasRead	= YES;
	}
	return self->catalog;
}


//========== hasAvailability ===================================================
//==============================================================================
- (BOOL) hasAvailability
{
	if (self->catalogWasRead)
		return self->catalog != nil;
	return [[NSFileManager defaultManager] fileExistsAtPath:[[self urlForFile:CatalogFileName] path]];
}


//========== saveAvailability:error: ===========================================
//==============================================================================
- (BOOL) saveAvailability:(LDrawPartAvailability *)availability error:(NSError **)error
{
	NSURL *url = [self urlForFile:CatalogFileName];

	if (LDrawJSONWriteFile([availability dictionaryRepresentation], url, NO, error) == NO)
		return NO;

	self->catalog			= availability;
	self->catalogWasRead	= YES;
	[self postChange];
	return YES;

}//end saveAvailability:error:


//========== rebrickableIdentityData ===========================================
//==============================================================================
- (NSDictionary *) rebrickableIdentityData
{
	if (self->identityDataWasRead == NO)
	{
		self->identityData			= LDrawJSONReadFile([self urlForFile:IdentityFileName]);
		self->identityDataWasRead	= YES;
	}
	return self->identityData;
}


//========== saveRebrickableIdentityData:error: ================================
//==============================================================================
- (BOOL) saveRebrickableIdentityData:(NSDictionary *)data error:(NSError **)error
{
	if (LDrawJSONWriteFile(data, [self urlForFile:IdentityFileName], NO, error) == NO)
		return NO;

	self->identityData			= [data copy];
	self->identityDataWasRead	= YES;
	[self postChange];
	return YES;
}


//========== identityOverrides =================================================
//==============================================================================
- (NSDictionary<NSString *, NSString *> *) identityOverrides
{
	NSDictionary		*file		= nil;
	NSDictionary		*links		= nil;
	NSMutableDictionary	*read		= nil;

	if (self->handMatches != nil)
		return self->handMatches;

	file	= [self readUserFile:OverridesFileName];
	links	= LDrawJSONDictionary(file[OverridesKey]);
	read	= [NSMutableDictionary dictionary];
	for (id partName in links)
	{
		if (LDrawJSONString(partName) != nil && LDrawJSONString(links[partName]) != nil)
			read[partName] = links[partName];
	}
	self->handMatches = [read copy];
	return self->handMatches;

}//end identityOverrides


//========== saveIdentityOverrides:error: ======================================
//==============================================================================
- (BOOL) saveIdentityOverrides:(NSDictionary<NSString *, NSString *> *)overrides error:(NSError **)error
{
	NSDictionary *file = @{ VersionKey : @(LDrawInventoryFileVersion), OverridesKey : overrides };

	// Reads the file first, so an unreadable one is moved aside or locked
	// before this save.
	[self identityOverrides];
	if (	[self refusesToWriteFile:OverridesFileName error:error]
		||	LDrawJSONWriteFile(file, [self urlForFile:OverridesFileName], YES, error) == NO )
		return NO;

	self->handMatches = [overrides copy];
	[self postChange];
	return YES;
}


//========== identityWithCatalogRecords: =======================================
//==============================================================================
- (LDrawPartIdentity *) identityWithCatalogRecords:(NSArray<NSDictionary *> *)catalogRecords
{
	return [LDrawPartIdentity identityWithCatalogRecords:catalogRecords
										 rebrickableData:[self rebrickableIdentityData]
											   overrides:[self identityOverrides]];
}


// MARK: - UTILITIES -


//========== loadedInventories =================================================
//==============================================================================
- (NSMutableArray<LDrawCombinedInventory *> *) loadedInventories
{
	if (self->inventories == nil)
	{
		NSDictionary *file = [self readUserFile:InventoriesFileName];

		self->inventories = [NSMutableArray array];
		for (id dictionary in LDrawJSONArray(file[InventoriesKey]))
		{
			LDrawCombinedInventory *inventory = [LDrawCombinedInventory inventoryWithDictionary:dictionary];
			if (inventory != nil)
				[self->inventories addObject:inventory];
		}
	}
	return self->inventories;

}//end loadedInventories


//========== loadedSets ========================================================
///
/// @abstract	Every imported set, read once. Sets are small and few.
///
//==============================================================================
- (NSMutableDictionary<NSString *, LDrawSetInventory *> *) loadedSets
{
	if (self->sets == nil)
	{
		NSURL	*folder	= [self urlForFile:SetsFolderName];
		NSArray	*files	= [[NSFileManager defaultManager] contentsOfDirectoryAtURL:folder
												  includingPropertiesForKeys:nil
																	 options:NSDirectoryEnumerationSkipsHiddenFiles
																	   error:NULL];

		self->sets = [NSMutableDictionary dictionary];
		for (NSURL *file in files)
		{
			if ([[file pathExtension] isEqualToString:@"json"] == NO)
				continue;

			LDrawSetInventory *set = [LDrawSetInventory setInventoryWithDictionary:LDrawJSONReadFile(file)];
			if (set != nil)
				self->sets[set.setNumber] = set;
		}
	}
	return self->sets;

}//end loadedSets


//========== indexOfInventoryWithIdentifier: ===================================
//==============================================================================
- (NSUInteger) indexOfInventoryWithIdentifier:(NSString *)identifier
{
	NSArray<LDrawCombinedInventory *> *loaded = [self loadedInventories];

	for (NSUInteger index = 0; index < [loaded count]; index++)
	{
		if ([loaded[index].identifier isEqualToString:identifier])
			return index;
	}
	return NSNotFound;

}//end indexOfInventoryWithIdentifier:


//========== writeInventories:error: ===========================================
//==============================================================================
- (BOOL) writeInventories:(NSArray<LDrawCombinedInventory *> *)updated error:(NSError **)error
{
	NSDictionary *file = @{
		VersionKey		: @(LDrawInventoryFileVersion),
		InventoriesKey	: [updated valueForKey:@"dictionaryRepresentation"],
	};

	if (	[self refusesToWriteFile:InventoriesFileName error:error]
		||	LDrawJSONWriteFile(file, [self urlForFile:InventoriesFileName], YES, error) == NO )
		return NO;

	self->inventories = [updated mutableCopy];
	[self postChange];
	return YES;

}//end writeInventories:error:


//========== readUserFile: =====================================================
///
/// @abstract	Reads a file that holds the user's own data. A file that is
/// 			there but cannot be read is moved aside, so a save cannot write
/// 			over it.
///
//==============================================================================
- (NSDictionary *) readUserFile:(NSString *)fileName
{
	NSURL			*url	= [self urlForFile:fileName];
	NSDictionary	*file	= LDrawJSONReadFile(url);

	if (file != nil)
		[self->lockedFiles removeObject:fileName];
	else if ([[NSFileManager defaultManager] fileExistsAtPath:[url path]])
		[self moveAsideUnreadableFile:fileName];
	return file;

}//end readUserFile:


//========== moveAsideUnreadableFile: ==========================================
///
/// @abstract	Renames an unreadable file to a free name such as
/// 			"inventories.unreadable.json". When that fails, the file stays
/// 			locked against saves.
///
//==============================================================================
- (void) moveAsideUnreadableFile:(NSString *)fileName
{
	NSFileManager	*fileManager	= [NSFileManager defaultManager];
	NSURL			*url			= [self urlForFile:fileName];
	NSString		*baseName		= [[fileName stringByDeletingPathExtension]
									   stringByAppendingPathExtension:@"unreadable"];
	NSURL			*destination	= nil;

	for (NSUInteger number = 1; number < 1000; number++)
	{
		NSString *name = baseName;

		if (number > 1)
			name = [NSString stringWithFormat:@"%@ %lu", baseName, (unsigned long)number];
		destination = [self urlForFile:[name stringByAppendingPathExtension:@"json"]];
		if ([fileManager fileExistsAtPath:[destination path]] == NO)
			break;
		destination = nil;
	}

	if (destination != nil && [fileManager moveItemAtURL:url toURL:destination error:NULL])
	{
		NSLog(@"Moved the unreadable %@ to %@.", fileName, [destination lastPathComponent]);
		[self->lockedFiles removeObject:fileName];
	}
	else
	{
		NSLog(@"Could not read %@, and it is kept as it is.", fileName);
		if (self->lockedFiles == nil)
			self->lockedFiles = [NSMutableSet set];
		[self->lockedFiles addObject:fileName];
	}

}//end moveAsideUnreadableFile:


//========== refusesToWriteFile:error: =========================================
///
/// @abstract	YES for a file that could not be read or moved aside.
///
//==============================================================================
- (BOOL) refusesToWriteFile:(NSString *)fileName error:(NSError **)error
{
	NSString *reason = nil;

	if ([self->lockedFiles containsObject:fileName] == NO)
		return NO;

	if (error != NULL)
	{
		reason = [NSString stringWithFormat:@"%@ in %@ cannot be read. Fix it or move it away, then try again.",
				  fileName, [self.folderURL path]];
		*error = LDrawInventoryMakeError(LDrawInventoryErrorUnreadableFile, reason);
	}
	return YES;

}//end refusesToWriteFile:error:


//========== urlForFile: =======================================================
//==============================================================================
- (NSURL *) urlForFile:(NSString *)fileName
{
	return [self.folderURL URLByAppendingPathComponent:fileName];
}


//========== urlForSetNumber: ==================================================
///
/// @abstract	A set's file. A slash or colon cannot go in a file name.
///
//==============================================================================
- (NSURL *) urlForSetNumber:(NSString *)setNumber
{
	NSCharacterSet	*unsafe		= [NSCharacterSet characterSetWithCharactersInString:@"/:"];
	NSString		*fileName	= [[[setNumber componentsSeparatedByCharactersInSet:unsafe]
									componentsJoinedByString:@"_"] stringByAppendingPathExtension:@"json"];

	return [[self urlForFile:SetsFolderName] URLByAppendingPathComponent:fileName];
}


//========== postChange ========================================================
//==============================================================================
- (void) postChange
{
	if (self->batchDepth > 0)
	{
		self->changeIsWaiting = YES;
		return;
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:LDrawInventoryStoreDidChangeNotification
														object:self];
}


//========== performChanges: ===================================================
///
/// @abstract	Runs saves that belong together, and posts one change at the
/// 			end, so what follows the store builds once.
///
//==============================================================================
- (void) performChanges:(void (^NS_NOESCAPE)(void))changes
{
	self->batchDepth += 1;
	changes();
	self->batchDepth -= 1;

	if (self->batchDepth == 0 && self->changeIsWaiting)
	{
		self->changeIsWaiting = NO;
		[self postChange];
	}
}

@end
