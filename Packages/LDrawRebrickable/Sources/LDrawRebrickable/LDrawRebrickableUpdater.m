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
#import <LDrawRebrickable/LDrawRebrickableClient.h>
#import <LDrawRebrickable/LDrawRebrickableColors.h>
#import <LDrawRebrickable/LDrawRebrickableDownloads.h>
#import <LDrawRebrickable/LDrawRebrickableSetImporter.h>
#import <LDrawRebrickable/LDrawRebrickableSetList.h>


@interface LDrawRebrickableUpdater ()

@property (nonatomic, readwrite) BOOL isUpdating;

@end


@implementation LDrawRebrickableUpdater
{
	LDrawRebrickableSetList	*setList;	// read once; built again with the catalog
	dispatch_queue_t		 workQueue;
}


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


//========== hasCatalog ========================================================
//==============================================================================
- (BOOL) hasCatalog
{
	return [self.store hasAvailability];
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
												  colorLinks:[LDrawRebrickableColors colorLinksForFolder:
															  self.downloads.folderURL]
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
/// @abstract	A catalog keeps the color links it was built with, so a newer
/// 			table or fetched links reach it only through this. A catalog
/// 			built before rubber parts were read gets them here.
///
//==============================================================================
- (BOOL) updateIdentityData:(NSError **)error
{
	NSDictionary	*data	= [self.store rebrickableIdentityData];
	NSDictionary	*links	= [LDrawRebrickableColors colorLinksForFolder:self.downloads.folderURL];
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


// MARK: - SETS -


//========== importSetNumber:client:completion: ================================
///
/// @abstract	Imports a set and saves it, with the links an API fetch brings.
///
//==============================================================================
- (void) importSetNumber:(NSString *)setNumber
				  client:(LDrawRebrickableClient *)client
			  completion:(void (^)(LDrawSetInventory *setInventory, NSError *error))completion
{
	if (client != nil)
	{
		client.completionQueue = dispatch_get_main_queue();
		[LDrawRebrickableSetImporter fetchSetInventoryForNumber:setNumber
														 client:client
														setList:self->setList
													 completion:^(LDrawSetInventory *set, NSDictionary *links,
																  NSError *error) {
			__block NSError *saveError = nil;

			if (set != nil)
			{
				[self.store performChanges:^{
					NSDictionary *data = nil;

					if ([links count] > 0)
					{
						data = [LDrawPartIdentity rebrickableDataByUpdating:[self.store rebrickableIdentityData]
																  partLinks:links
																 colorLinks:nil
																  relations:nil
														   knownPartNumbers:nil
														  rubberPartNumbers:nil];
						[self.store saveRebrickableIdentityData:data error:&saveError];
					}
					if (saveError == nil)
						[self.store saveSetInventory:set error:&saveError];
				}];
			}
			completion(saveError == nil ? set : nil, error ?: saveError);
		}];
		return;
	}

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

}//end importSetNumber:client:completion:

@end
