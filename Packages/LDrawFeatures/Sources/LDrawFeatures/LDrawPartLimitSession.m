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

#import <LDrawInventory/LDrawInventoryStore.h>
#import <LDrawInventory/LDrawPartIdentity.h>
#import <LDrawInventory/LDrawPartLimit.h>
#import <LDrawInventory/LDrawPartLimitTable.h>

NSString * const LDrawPartLimitDidChangeNotification = @"LDrawPartLimitDidChangeNotification";


@interface LDrawPartLimitSession ()

@property (nonatomic, readwrite) LDrawPartLimitTable *table;

@end


@implementation LDrawPartLimitSession
{
	NSArray<NSDictionary *>								*catalogRecords;
	NSSet<NSNumber *>									*rubberColorCodes;
	NSMutableDictionary<NSString *, LDrawPartLimitTable *>	*inventoryTables;	// by identifier

	// The identity map, and the store's data it was built from.
	LDrawPartIdentity									*builtIdentity;
	NSDictionary										*identityData;
	NSDictionary										*identityOverrides;
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


//========== setLimit: =========================================================
//==============================================================================
- (void) setLimit:(LDrawPartLimit *)limit
{
	if ([limit isEqual:self->_limit])
		return;

	self->_limit = [limit copy];
	[self rebuildTable];
	[self postChange];
}


//========== setCurrentYear: ===================================================
//==============================================================================
- (void) setCurrentYear:(NSInteger)currentYear
{
	if (currentYear == self->_currentYear)
		return;

	self->_currentYear = currentYear;
	[self rebuildTable];
	[self postChange];
}


//========== setShortcuts: =====================================================
//==============================================================================
- (void) setShortcuts:(LDrawShortcutMap *)shortcuts
{
	if (shortcuts == self->_shortcuts)
		return;

	self->_shortcuts = shortcuts;
	[self rebuildTable];
	[self postChange];
}


//========== tableForInventoryIdentifier: ======================================
//==============================================================================
- (LDrawPartLimitTable *) tableForInventoryIdentifier:(NSString *)identifier
{
	LDrawPartLimitTable	*table		= self->inventoryTables[identifier];
	LDrawPartLimit		*limit		= [self.limit limitWithKind:LDrawPartLimitKindInventory
											inventoryIdentifier:identifier];

	if (table != nil)
		return table;

	table = [self.store tableForLimit:limit identity:self.identity shortcuts:self.shortcuts year:self.currentYear];
	if (table.limit.kind != LDrawPartLimitKindInventory)
		return nil;

	if (self->inventoryTables == nil)
		self->inventoryTables = [NSMutableDictionary dictionary];
	self->inventoryTables[identifier] = table;

	return table;

}//end tableForInventoryIdentifier:


//========== setCatalogRecords:rubberColorCodes: ===============================
//==============================================================================
- (void) setCatalogRecords:(NSArray<NSDictionary *> *)records rubberColorCodes:(NSSet<NSNumber *> *)codes
{
	self->catalogRecords	= [records copy];
	self->rubberColorCodes	= [codes copy];
	self->builtIdentity		= nil;
	[self reload];
}


//========== effectiveLimit ====================================================
//==============================================================================
- (LDrawPartLimit *) effectiveLimit
{
	return self.table.limit;
}


//========== restrictingTable ==================================================
//==============================================================================
- (LDrawPartLimitTable *) restrictingTable
{
	LDrawPartLimitTable *table = self.table;

	return (table.limit.isRestricting && table.hasData) ? table : nil;
}


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


// MARK: - BUILDING -


//========== reload ============================================================
///
/// @abstract	Builds the identity map and the table again, and posts the
/// 			notification.
///
//==============================================================================
- (void) reload
{
	[self rebuildTable];
	[self postChange];
}


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

	self->inventoryTables	= nil;
	self.table				= [self.store tableForLimit:self.limit
											   identity:identity
											  shortcuts:self.shortcuts
												   year:self.currentYear];
}


//========== postChange ========================================================
//==============================================================================
- (void) postChange
{
	[[NSNotificationCenter defaultCenter] postNotificationName:LDrawPartLimitDidChangeNotification object:self];
}

@end
