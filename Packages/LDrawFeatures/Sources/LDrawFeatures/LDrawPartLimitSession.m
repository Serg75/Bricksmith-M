//==============================================================================
//
//  File:       LDrawPartLimitSession.m
//  Package:    LDrawFeatures
//
//  Purpose:    The editor's one parts limit, and the table built for it.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawFeatures/LDrawPartLimitSession.h>

#import <LDrawCore/LDrawPartLibrary.h>
#import <LDrawInventory/LDrawInventoryStore.h>
#import <LDrawInventory/LDrawPartIdentity.h>
#import <LDrawInventory/LDrawPartLimit.h>
#import <LDrawInventory/LDrawPartLimitTable.h>
#import <LDrawInventory/LDrawShortcutMap.h>

NSString * const LDrawPartLimitDidChangeNotification = @"LDrawPartLimitDidChangeNotification";


@interface LDrawPartLimitSession ()

@property (nonatomic, readwrite) LDrawPartLimitTable *table;
@property (nonatomic, readwrite, nullable) LDrawShortcutMap *shortcuts;

@end


@implementation LDrawPartLimitSession
{
	NSArray<NSDictionary *>									*catalogRecords;
	NSSet<NSNumber *>										*rubberColorCodes;
	NSMutableDictionary										*limitTables;			// other limits', until data changes
	BOOL													 hasRestrictingLimits;	// a model's limit restricts

	// The identity map, and the store's data it was built from.
	LDrawPartIdentity										*builtIdentity;
	NSDictionary											*identityData;
	NSDictionary											*identityOverrides;

	NSUInteger												 shortcutsGeneration;	// the newest read of shortcuts
	BOOL													 shortcutsAreCurrent;	// a read of the records was started
}


// MARK: - INITIALIZATION -


//========== initWithStore: ====================================================
///
/// @abstract	No limit until the host sets one. Follows the store's changes.
///
//==============================================================================
- (instancetype) initWithStore:(LDrawInventoryStore *)store
{
	self = [super init];
	if (self) {
		self->_store		= store;
		self->_limit		= [LDrawPartLimit noLimit];
		self->_currentYear	= [[NSCalendar currentCalendar] component:NSCalendarUnitYear fromDate:[NSDate date]];

		[self rebuildTable];

		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(storeDidChange:)
													 name:LDrawInventoryStoreDidChangeNotification
												   object:store];
	}
	return self;

}//end initWithStore:


//========== dealloc ===========================================================
//==============================================================================
- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}


// MARK: - ACCESSORS -


//========== identity ==========================================================
///
/// @abstract	Built when first asked, and again when the records or the
/// 			store's data change. The store keeps what it read, so the same
/// 			objects mean the same data.
///
//==============================================================================
- (LDrawPartIdentity *) identity
{
	NSDictionary *data		= [self.store rebrickableIdentityData];
	NSDictionary *overrides	= [self.store identityOverrides];

	if (self->builtIdentity == nil || data != self->identityData || overrides != self->identityOverrides)
	{
		self->identityData		= data;
		self->identityOverrides	= overrides;
		self->builtIdentity		= [LDrawPartIdentity identityWithCatalogRecords:self->catalogRecords
																rebrickableData:data
																	  overrides:overrides
															   rubberColorCodes:self->rubberColorCodes];
	}
	return self->builtIdentity;

}//end identity


//========== needsPartsData ====================================================
//==============================================================================
- (BOOL) needsPartsData
{
	return		self.limit.kind != LDrawPartLimitKindNone
			||	self->hasRestrictingLimits
			||	[[self.store setNumbers] count] > 0
			||	[[self.store combinedInventories] count] > 0;
}


//========== setLimit: =========================================================
//==============================================================================
- (void) setLimit:(LDrawPartLimit *)limit
{
	if ([limit isEqual:self->_limit])
		return;

	self->_limit = [limit copy];
	[self reload];
}


//========== setCurrentYear: ===================================================
//==============================================================================
- (void) setCurrentYear:(NSInteger)currentYear
{
	if (currentYear == self->_currentYear)
		return;

	self->_currentYear = currentYear;
	[self reload];
}


//========== setShortcuts: =====================================================
//==============================================================================
- (void) setShortcuts:(LDrawShortcutMap *)shortcuts
{
	if (shortcuts == self->_shortcuts)
		return;

	self->_shortcuts = shortcuts;
	[self reload];
}


//========== setCatalogRecords:rubberColorCodes: ===============================
//==============================================================================
- (void) setCatalogRecords:(NSArray<NSDictionary *> *)records rubberColorCodes:(NSSet<NSNumber *> *)codes
{
	BOOL sameRecords	= (records == self->catalogRecords || [records isEqualToArray:self->catalogRecords]);
	BOOL sameCodes		= (codes == self->rubberColorCodes || [codes isEqualToSet:self->rubberColorCodes]);

	if (sameRecords && sameCodes)
		return;

	self->catalogRecords		= [records copy];
	self->rubberColorCodes		= [codes copy];
	self->builtIdentity			= nil;
	self->shortcutsAreCurrent	= (sameRecords && self->shortcutsAreCurrent);
	[self reload];
}


// MARK: - INVENTORIES -


//========== choosableLimitsWithOptionsOf: =====================================
//==============================================================================
- (NSArray<LDrawPartLimit *> *) choosableLimitsWithOptionsOf:(LDrawPartLimit *)current
{
	NSMutableArray *limits = [NSMutableArray array];

	[limits addObject:[current limitWithKind:LDrawPartLimitKindNone inventoryIdentifier:nil]];
	[limits addObject:[current limitWithKind:LDrawPartLimitKindAvailableNow inventoryIdentifier:nil]];
	for (NSString *identifier in [self.store inventoryIdentifiers])
		[limits addObject:[current limitWithKind:LDrawPartLimitKindInventory inventoryIdentifier:identifier]];
	return limits;

}//end choosableLimitsWithOptionsOf:


//========== tableForInventoryIdentifier:withOptionsOf: ========================
//==============================================================================
- (LDrawPartLimitTable *) tableForInventoryIdentifier:(NSString *)identifier withOptionsOf:(LDrawPartLimit *)limit
{
	LDrawPartLimit		*inventory	= [limit limitWithKind:LDrawPartLimitKindInventory inventoryIdentifier:identifier];
	LDrawPartLimitTable	*table		= [self tableForLimit:inventory];

	return (table.limit.kind == LDrawPartLimitKindInventory) ? table : nil;

}//end tableForInventoryIdentifier:withOptionsOf:


//========== tableForLimit: ====================================================
///
/// @abstract	The default limit's table is always built; others when first
/// 			asked for. No limit needs no identity map, so a user who never
/// 			limits parts never builds one.
///
//==============================================================================
- (LDrawPartLimitTable *) tableForLimit:(LDrawPartLimit *)limit
{
	LDrawPartLimitTable	*table		= nil;
	LDrawPartIdentity	*identity	= nil;

	if ([limit isEqual:self.limit])
		return self.table;

	table = self->limitTables[limit];
	if (table != nil)
		return table;

	if (limit.isRestricting && self->hasRestrictingLimits == NO)
	{
		// A model's limit needs the parts data even when the default does not.
		self->hasRestrictingLimits = YES;
		[self readShortcutsIfNeeded];
	}

	identity	= limit.isRestricting ? self.identity : [LDrawPartIdentity emptyIdentity];
	table		= [self.store tableForLimit:limit identity:identity shortcuts:self.shortcuts year:self.currentYear];
	if (self->limitTables == nil)
		self->limitTables = [NSMutableDictionary dictionary];
	self->limitTables[limit] = table;
	return table;

}//end tableForLimit:


//========== restrictingTableForLimit: =========================================
//==============================================================================
- (LDrawPartLimitTable *) restrictingTableForLimit:(LDrawPartLimit *)limit
{
	LDrawPartLimitTable *table = [self tableForLimit:limit];

	return (table.limit.isRestricting && table.hasData) ? table : nil;
}


// MARK: - BUILDING -


//========== storeDidChange: ===================================================
///
/// @abstract	A set, an inventory, the catalog or the identity data was
/// 			saved, any of which can change what the limit allows.
///
//==============================================================================
- (void) storeDidChange:(NSNotification *)notification
{
	[self reload];
}


//========== reload ============================================================
///
/// @abstract	Builds the table again and posts the notification.
///
//==============================================================================
- (void) reload
{
	[self rebuildTable];
	[[NSNotificationCenter defaultCenter] postNotificationName:LDrawPartLimitDidChangeNotification object:self];
	[self readShortcutsIfNeeded];
}


//========== rebuildTable ======================================================
///
/// @abstract	The table for the limit. No limit needs no identity map, so a
/// 			user who never limits parts never builds one.
///
//==============================================================================
- (void) rebuildTable
{
	BOOL				 limits		= (self.limit.kind != LDrawPartLimitKindNone);
	LDrawPartIdentity	*identity	= limits ? self.identity : [LDrawPartIdentity emptyIdentity];

	self->limitTables		= nil;
	self.table				= [self.store tableForLimit:self.limit
											   identity:identity
											  shortcuts:self.shortcuts
												   year:self.currentYear];
}


//========== readShortcutsIfNeeded =============================================
///
/// @abstract	Reads the records' shortcuts once the parts data is needed. A
/// 			read of older records is dropped when it ends.
///
//==============================================================================
- (void) readShortcutsIfNeeded
{
	NSArray		*records	= self->catalogRecords;
	NSUInteger	 generation	= 0;

	if (self->shortcutsAreCurrent || [records count] == 0 || [self needsPartsData] == NO)
		return;

	self->shortcutsAreCurrent	= YES;
	generation					= ++self->shortcutsGeneration;

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		NSSet				*partNames	= [NSSet setWithArray:[records valueForKey:PART_NUMBER_KEY]];
		LDrawShortcutMap	*map		= [LDrawShortcutMap libraryMapWithPartNames:partNames];

		[map readPartsNamed:partNames];
		dispatch_async(dispatch_get_main_queue(), ^{
			if (generation == self->shortcutsGeneration)
				[self setShortcuts:map];
		});
	});
}

@end
