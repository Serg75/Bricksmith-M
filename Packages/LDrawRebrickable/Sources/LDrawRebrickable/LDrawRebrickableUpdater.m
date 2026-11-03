//==============================================================================
//
//  File:       LDrawRebrickableUpdater.m
//  Package:    LDrawRebrickable
//
//  Purpose:    Keeps a store's Rebrickable data up to date: the downloads, the
//              catalog built from them, and imported sets.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawRebrickable/LDrawRebrickableUpdater.h>

#import <LDrawInventory/LDrawInventoryStore.h>
#import <LDrawInventory/LDrawPartIdentity.h>
#import <LDrawInventory/LDrawSetInventory.h>
#import <LDrawRebrickable/LDrawRebrickableCatalog.h>
#import <LDrawRebrickable/LDrawRebrickableColors.h>
#import <LDrawRebrickable/LDrawRebrickableDownloads.h>
#import <LDrawRebrickable/LDrawRebrickableSetImporter.h>
#import <LDrawRebrickable/LDrawRebrickableSetList.h>


@interface LDrawRebrickableUpdater ()

@property (nonatomic, readwrite) BOOL isUpdating;

@end


@implementation LDrawRebrickableUpdater
{
	LDrawRebrickableSetList	*setList;	// read once; replaced when the catalog is built
	dispatch_queue_t		 workQueue;
}


// MARK: - INITIALIZATION -


//========== initWithDownloads:store: ==========================================
//==============================================================================
- (instancetype) initWithDownloads:(LDrawRebrickableDownloads *)downloads store:(LDrawInventoryStore *)store
{
	self = [super init];
	if (self) {
		self->_downloads	= downloads;
		self->_store		= store;
		self->workQueue		= dispatch_queue_create("LDrawRebrickableUpdater", DISPATCH_QUEUE_SERIAL);
	}
	return self;
}


// MARK: - ACCESSORS -


//========== hasCatalog ========================================================
//==============================================================================
- (BOOL) hasCatalog
{
	return [self.store hasAvailability];
}


//========== lastCheckDate =====================================================
///
/// @abstract	Every update checks the inventory parts file, so its check date
/// 			stands for all the data.
///
//==============================================================================
- (NSDate *) lastCheckDate
{
	return [self hasCatalog] ? [self.downloads checkDateForFileNamed:@"inventory_parts"] : nil;
}


//========== isUpdateDueAfterDays: =============================================
//==============================================================================
- (BOOL) isUpdateDueAfterDays:(NSInteger)days
{
	NSDate *checked = [self lastCheckDate];

	if (days <= 0 || [self hasCatalog] == NO)
		return NO;
	return checked == nil || -[checked timeIntervalSinceNow] > days * 24 * 60 * 60;
}


// MARK: - CATALOG -


//========== updateCatalogForcing:completion: ==================================
///
/// @abstract	Downloads, then builds and saves the catalog when there is
/// 			something new.
///
//==============================================================================
- (NSProgress *) updateCatalogForcing:(BOOL)force completion:(void (^)(BOOL changed, NSError *error))completion
{
	NSArray *names = [LDrawRebrickableDownloads catalogFileNames];

	self.isUpdating = YES;

	return [self.downloads updateFilesNamed:names
									  force:force
							completionQueue:dispatch_get_main_queue()
								 completion:^(NSArray<NSString *> *changedNames, NSError *error) {
		// Files stored by an earlier run whose build failed count as new. A
		// catalog that cannot be read is built again too.
		BOOL needsCatalog = ([self.store availability] == nil || [self.downloads hasNewFilesNamed:names]);

		if (error != nil || needsCatalog == NO || [self.downloads hasFilesNamed:names] == NO)
		{
			self.isUpdating = NO;
			completion(NO, error);
			return;
		}

		dispatch_async(self->workQueue, ^{
			NSError					*buildError	= nil;
			LDrawRebrickableCatalog	*catalog	= [LDrawRebrickableCatalog catalogFromDownloads:self.downloads
																						  error:&buildError];
			dispatch_async(dispatch_get_main_queue(), ^{
				NSError	*saveError	= nil;
				BOOL	 saved		= NO;

				if (catalog != nil)
				{
					self->setList	= catalog.setList;
					saved			= [catalog saveIntoStore:self.store
												  colorLinks:[LDrawRebrickableColors builtInColorLinks]
													   error:&saveError];
				}
				if (saved)
					[self.downloads markFilesNamedAsUsed:names];
				self.isUpdating = NO;
				completion(saved, buildError ?: saveError);
			});
		});
	}];

}//end updateCatalogForcing:completion:


//========== updateIdentityData: ===============================================
///
/// @abstract	Saved data keeps the color links it was built with, so a newer
/// 			shipped table reaches it only through this. Data saved without
/// 			rubber parts gets them here.
///
//==============================================================================
- (BOOL) updateIdentityData:(NSError **)error
{
	NSDictionary	*data	= [self.store rebrickableIdentityData];
	NSDictionary	*links	= [LDrawRebrickableColors builtInColorLinks];
	NSSet			*rubber	= nil;

	if (data == nil)
		return YES;

	if (	[LDrawPartIdentity rubberPartNumbersInRebrickableData:data] == nil
		&&	[self.downloads hasFilesNamed:@[@"parts"]] )
	{
		rubber = [LDrawRebrickableCatalog rubberPartNumbersFromDownloads:self.downloads error:error];
		if (rubber == nil)
			return NO;
	}
	if (rubber == nil && [links isEqualToDictionary:[LDrawPartIdentity colorLinksInRebrickableData:data]])
		return YES;

	data = [LDrawPartIdentity rebrickableDataByUpdating:data
											  partLinks:nil
											 colorLinks:links
											  relations:nil
									   knownPartNumbers:nil
									  rubberPartNumbers:rubber];
	return [self.store saveRebrickableIdentityData:data error:error];

}//end updateIdentityData:


// MARK: - SETS -


//========== loadSetListWithCompletion: ========================================
//==============================================================================
- (void) loadSetListWithCompletion:(void (^)(LDrawRebrickableSetList *setList, NSError *error))completion
{
	if (self->setList != nil)
	{
		completion(self->setList, nil);
		return;
	}

	dispatch_async(self->workQueue, ^{
		NSError					*error	= nil;
		LDrawRebrickableSetList	*list	= [LDrawRebrickableSetList setListFromDownloads:self.downloads error:&error];

		dispatch_async(dispatch_get_main_queue(), ^{
			if (list != nil)
				self->setList = list;
			completion(list, error);
		});
	});

}//end loadSetListWithCompletion:


//========== importSetNumber:completion: =======================================
//==============================================================================
- (void) importSetNumber:(NSString *)setNumber
			  completion:(void (^)(LDrawSetInventory *setInventory, NSError *error))completion
{
	[self loadSetListWithCompletion:^(LDrawRebrickableSetList *list, NSError *listError) {
		if (list == nil)
		{
			completion(nil, listError);
			return;
		}

		dispatch_async(self->workQueue, ^{
			NSError				*error	= nil;
			LDrawSetInventory	*set	= [LDrawRebrickableSetImporter setInventoryForNumber:setNumber
																			   fromDownloads:self.downloads
																					 setList:list
																					   error:&error];
			dispatch_async(dispatch_get_main_queue(), ^{
				NSError *saveError = nil;

				if (set != nil)
					[self.store saveSetInventory:set error:&saveError];
				completion(saveError == nil ? set : nil, error ?: saveError);
			});
		});
	}];

}//end importSetNumber:completion:

@end
