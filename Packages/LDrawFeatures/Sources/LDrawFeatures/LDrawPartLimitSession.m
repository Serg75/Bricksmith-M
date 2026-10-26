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

@property (nonatomic, readwrite) LDrawPartLimit *effectiveLimit;
@property (nonatomic, readwrite) LDrawPartLimitTable *table;
@property (nonatomic, readwrite) LDrawPartIdentity *identity;

@end


@implementation LDrawPartLimitSession
{
	NSArray<NSDictionary *>								*catalogRecords;
	NSMutableDictionary<NSString *, LDrawPartLimitTable *>	*inventoryTables;	// by identifier
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

		[self rebuild];

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


//========== tableForInventoryIdentifier: ======================================
//==============================================================================
- (LDrawPartLimitTable *) tableForInventoryIdentifier:(NSString *)identifier
{
	LDrawPartLimitTable	*table		= self->inventoryTables[identifier];
	LDrawPartLimit		*limit		= nil;

	if (table != nil)
		return table;

	limit = [self.store resolvedLimit:[self.limit limitWithKind:LDrawPartLimitKindInventory
											inventoryIdentifier:identifier]];
	if (limit.kind != LDrawPartLimitKindInventory)
		return nil;

	table = [self.store tableForLimit:limit identity:self.identity year:self.currentYear];
	if (self->inventoryTables == nil)
		self->inventoryTables = [NSMutableDictionary dictionary];
	self->inventoryTables[identifier] = table;

	return table;

}//end tableForInventoryIdentifier:


//========== setCatalogRecords: ================================================
//==============================================================================
- (void) setCatalogRecords:(NSArray<NSDictionary *> *)records
{
	self->catalogRecords = [records copy];
	[self reload];
}


// MARK: - BUILDING -


//========== reload ============================================================
//==============================================================================
- (void) reload
{
	[self rebuild];
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


//========== rebuild ===========================================================
//==============================================================================
- (void) rebuild
{
	self.identity = [self.store identityWithCatalogRecords:self->catalogRecords];
	[self rebuildTable];
}


//========== rebuildTable ======================================================
//==============================================================================
- (void) rebuildTable
{
	self->inventoryTables = nil;
	self.effectiveLimit	= [self.store resolvedLimit:self.limit];
	self.table			= [self.store tableForLimit:self.effectiveLimit
										   identity:self.identity
											   year:self.currentYear];
}


//========== postChange ========================================================
//==============================================================================
- (void) postChange
{
	[[NSNotificationCenter defaultCenter] postNotificationName:LDrawPartLimitDidChangeNotification object:self];
}

@end
