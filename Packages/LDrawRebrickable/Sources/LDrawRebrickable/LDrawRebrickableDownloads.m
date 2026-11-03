//==============================================================================
//
//  File:       LDrawRebrickableDownloads.m
//  Package:    LDrawRebrickable
//
//  Purpose:    Keeps Rebrickable's CSV downloads in a folder, and fetches them
//              again when they change.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawRebrickable/LDrawRebrickableDownloads.h>

#import <LDrawInventory/LDrawInventoryJSON.h>
#import <LDrawRebrickable/LDrawRebrickableCSVReader.h>

static NSString * const BaseURL				= @"https://cdn.rebrickable.com/media/downloads/";
static NSString * const RecordsFileName		= @"downloads.json";
static NSString * const RecordsFilesKey		= @"files";
static NSString * const RecordETagKey		= @"etag";
static NSString * const RecordModifiedKey	= @"lastModified";
static NSString * const RecordCheckedKey	= @"checked";
static NSString * const RecordNewKey		= @"new";
static NSString * const StagingPrefix		= @".incoming-";

static const NSTimeInterval OneDay = 24 * 60 * 60;


//========== ApproximateKilobytes ==============================================
///
/// @abstract	About how big each file is, so progress moves with the bytes and
/// 			not with the file count. The inventory parts are most of it.
///
//==============================================================================
static int64_t ApproximateKilobytes(NSString *name)
{
	NSDictionary<NSString *, NSNumber *> *sizes = @{
		@"inventory_parts"		: @14200,
		@"parts"				: @1060,
		@"sets"					: @520,
		@"minifigs"				: @300,
		@"inventories"			: @270,
		@"part_relationships"	: @200,
		@"inventory_minifigs"	: @100,
		@"inventory_sets"		: @20,
		@"colors"				: @5,
		@"themes"				: @5,
	};
	return [sizes[name] longLongValue] ?: 100;
}


//========== CanceledError =====================================================
//==============================================================================
static NSError *CanceledError(void)
{
	return LDrawRebrickableMakeError(LDrawRebrickableErrorCanceled, nil, nil);
}


@implementation LDrawRebrickableDownloads
{
	NSMutableDictionary<NSString *, NSDictionary *> *records;	// file name → what the server said
}


// MARK: - INITIALIZATION -


//========== initWithFolderURL: ================================================
//==============================================================================
- (instancetype) initWithFolderURL:(NSURL *)folderURL
{
	self = [super init];
	if (self) {
		NSDictionary *file = LDrawJSONReadFile([folderURL URLByAppendingPathComponent:RecordsFileName]);

		self->_folderURL			= [folderURL copy];
		self->_sessionConfiguration	= [NSURLSessionConfiguration defaultSessionConfiguration];
		self->records				= [NSMutableDictionary dictionary];

		NSDictionary *files = LDrawJSONDictionary(file[RecordsFilesKey]);
		for (id name in files)
		{
			if (LDrawJSONString(name) != nil && LDrawJSONDictionary(files[name]) != nil)
				self->records[name] = files[name];
		}
		[self removeStagingFolders];
	}
	return self;

}//end initWithFolderURL:


// MARK: - ACCESSORS -


//---------- catalogFileNames ----------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *) catalogFileNames
{
	return @[@"themes", @"colors", @"parts", @"part_relationships", @"sets", @"minifigs",
			 @"inventories", @"inventory_sets", @"inventory_minifigs", @"inventory_parts"];
}


//========== localURLForFileNamed: =============================================
//==============================================================================
- (NSURL *) localURLForFileNamed:(NSString *)name
{
	return [self.folderURL URLByAppendingPathComponent:[name stringByAppendingString:@".csv.gz"]];
}


//========== hasFilesNamed: ====================================================
//==============================================================================
- (BOOL) hasFilesNamed:(NSArray<NSString *> *)names
{
	for (NSString *name in names)
	{
		if ([[NSFileManager defaultManager] fileExistsAtPath:[[self localURLForFileNamed:name] path]] == NO)
			return NO;
	}
	return YES;
}


//========== hasNewFilesNamed: =================================================
//==============================================================================
- (BOOL) hasNewFilesNamed:(NSArray<NSString *> *)names
{
	@synchronized (self) {
		for (NSString *name in names)
		{
			if (LDrawJSONBool(self->records[name][RecordNewKey], NO))
				return YES;
		}
	}
	return NO;
}


//========== markFilesNamedAsUsed: =============================================
//==============================================================================
- (void) markFilesNamedAsUsed:(NSArray<NSString *> *)names
{
	@synchronized (self) {
		for (NSString *name in names)
		{
			NSMutableDictionary *record = [self->records[name] mutableCopy];

			if (record[RecordNewKey] == nil)
				continue;
			[record removeObjectForKey:RecordNewKey];
			self->records[name] = record;
		}
	}
	[self saveRecords];
}


//========== checkDateForFileNamed: ============================================
//==============================================================================
- (NSDate *) checkDateForFileNamed:(NSString *)name
{
	@synchronized (self) {
		return LDrawJSONDate(self->records[name][RecordCheckedKey]);
	}
}


//========== dataDateForFileNamed: =============================================
///
/// @abstract	The file's Last-Modified date, as the server wrote it.
///
//==============================================================================
- (NSDate *) dataDateForFileNamed:(NSString *)name
{
	NSString		*text		= nil;
	NSDateFormatter	*formatter	= [[NSDateFormatter alloc] init];

	@synchronized (self) {
		text = LDrawJSONString(self->records[name][RecordModifiedKey]);
	}

	formatter.locale		= [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
	formatter.timeZone		= [NSTimeZone timeZoneForSecondsFromGMT:0];
	formatter.dateFormat	= @"EEE, dd MMM yyyy HH:mm:ss zzz";

	return (text != nil) ? [formatter dateFromString:text] : nil;

}//end dataDateForFileNamed:


// MARK: - FETCHING -


//========== updateFilesNamed:force:completionQueue:completion: ================
///
/// @abstract	Fetches the files one after another.
///
/// @discussion	The work runs on the session's queue. A changed file waits in a
/// 			staging folder, and the files replace the old ones together
/// 			once all have come, so a failed update leaves the old ones.
/// 			Records are saved once, at the end, whatever happened.
///
//==============================================================================
- (NSProgress *) updateFilesNamed:(NSArray<NSString *> *)names
							force:(BOOL)force
				  completionQueue:(dispatch_queue_t)completionQueue
					   completion:(void (^)(NSArray<NSString *> *changedNames, NSError *error))completion
{
	NSURLSession				*session		= [NSURLSession sessionWithConfiguration:self.sessionConfiguration];
	NSProgress					*progress		= [NSProgress progressWithTotalUnitCount:0];
	NSMutableDictionary			*staged			= [NSMutableDictionary dictionary];
	NSString					*stagingName	= [StagingPrefix stringByAppendingString:[[NSUUID UUID] UUIDString]];
	NSURL						*staging		= [self.folderURL URLByAppendingPathComponent:stagingName];
	dispatch_queue_t			 queue			= completionQueue ?: dispatch_get_main_queue();
	NSObject					*lock			= [[NSObject alloc] init];
	__block NSURLSessionTask	*current		= nil;
	__weak typeof(self)			 weakSelf		= self;

	// The next step holds itself weakly. A request on its way holds it
	// strongly, so it lives until the last file is done.
	__block __weak void			(^weakFetchNext)(NSUInteger index) = nil;
	void						(^fetchNext)(NSUInteger index) = nil;

	for (NSString *name in names)
		progress.totalUnitCount += ApproximateKilobytes(name);

	progress.cancellationHandler = ^{
		@synchronized (lock) {
			[current cancel];
		}
	};

	void (^finish)(NSError *) = ^(NSError *error) {
		LDrawRebrickableDownloads	*downloads	= weakSelf;
		NSMutableArray				*stored		= [NSMutableArray array];
		NSError						*failure	= error;

		if (failure == nil && downloads == nil)
			failure = CanceledError();
		if (failure == nil)
			failure = [downloads storeStagedFiles:staged stored:stored];
		[downloads saveRecords];
		[[NSFileManager defaultManager] removeItemAtURL:staging error:NULL];
		[session finishTasksAndInvalidate];
		dispatch_async(queue, ^{
			completion(stored, failure);
		});
	};

	weakFetchNext = fetchNext = ^(NSUInteger index) {
		LDrawRebrickableDownloads	*downloads	= weakSelf;
		NSString					*name		= (index < [names count]) ? names[index] : nil;
		int64_t						 weight		= ApproximateKilobytes(name);
		void						(^next)(NSUInteger) = weakFetchNext;

		if (downloads == nil)
		{
			finish(CanceledError());
			return;
		}
		if (name == nil)
		{
			finish(nil);
			return;
		}
		if ([progress isCancelled])
		{
			finish(CanceledError());
			return;
		}
		if (force == NO && [downloads isFreshFileNamed:name])
		{
			progress.completedUnitCount += weight;
			next(index + 1);
			return;
		}

		NSURLRequest				*request	= [downloads requestForFileNamed:name];
		NSURLSessionDownloadTask	*task		= nil;

		task = [session downloadTaskWithRequest:request
							  completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
			LDrawRebrickableDownloads	*strongSelf	= weakSelf;
			NSError						*failure	= nil;

			if (strongSelf == nil)
				failure = CanceledError();
			else
				failure = [strongSelf takeFileNamed:name
											   from:location
										   response:response
											  error:error
										  stagingIn:staging
											 staged:staged];
			if (failure != nil)
			{
				finish(failure);
				return;
			}
			next(index + 1);
		}];

		@synchronized (lock) {
			current = task;
		}
		[progress addChild:task.progress withPendingUnitCount:weight];
		[task resume];
	};

	fetchNext(0);
	return progress;

}//end updateFilesNamed:force:completionQueue:completion:


//========== isFreshFileNamed: =================================================
///
/// @abstract	The file is here and was asked for not long ago.
///
//==============================================================================
- (BOOL) isFreshFileNamed:(NSString *)name
{
	NSDate *checked = [self checkDateForFileNamed:name];

	return	[self hasFilesNamed:@[name]]
		&&	checked != nil
		&&	-[checked timeIntervalSinceNow] < OneDay;
}


//========== requestForFileNamed: ==============================================
///
/// @abstract	A GET that asks for the file only when it changed.
///
//==============================================================================
- (NSURLRequest *) requestForFileNamed:(NSString *)name
{
	NSString			*fileName	= [[self localURLForFileNamed:name] lastPathComponent];
	NSURL				*url		= [[NSURL URLWithString:BaseURL] URLByAppendingPathComponent:fileName];
	NSMutableURLRequest	*request	= [NSMutableURLRequest requestWithURL:url];
	NSDictionary		*record		= nil;

	@synchronized (self) {
		record = self->records[name];
	}

	if ([self hasFilesNamed:@[name]])
	{
		NSString *etag		= LDrawJSONString(record[RecordETagKey]);
		NSString *modified	= LDrawJSONString(record[RecordModifiedKey]);

		if (etag != nil)
			[request setValue:etag forHTTPHeaderField:@"If-None-Match"];
		if (modified != nil)
			[request setValue:modified forHTTPHeaderField:@"If-Modified-Since"];
	}
	return request;

}//end requestForFileNamed:


//========== takeFileNamed:from:response:error:stagingIn:staged: ===============
///
/// @abstract	Moves a changed file into the staging folder, and notes what the
/// 			server said about it. Returns nil for a 200 or a 304, else an
/// 			error.
///
//==============================================================================
- (NSError *) takeFileNamed:(NSString *)name
					   from:(NSURL *)location
				   response:(NSURLResponse *)response
					  error:(NSError *)error
				  stagingIn:(NSURL *)staging
					 staged:(NSMutableDictionary<NSString *, NSDictionary *> *)staged
{
	NSHTTPURLResponse	*http			= (NSHTTPURLResponse *)response;
	NSURL				*destination	= [staging URLByAppendingPathComponent:
										   [[self localURLForFileNamed:name] lastPathComponent]];
	NSFileManager		*fileManager	= [NSFileManager defaultManager];
	NSMutableDictionary	*record			= [NSMutableDictionary dictionary];
	NSError				*moveError		= nil;

	if (error != nil)
	{
		if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled)
			return CanceledError();
		return error;
	}

	if ([http isKindOfClass:[NSHTTPURLResponse class]] == NO || (http.statusCode != 200 && http.statusCode != 304))
	{
		NSString *reason = [NSString stringWithFormat:@"Rebrickable answered %ld for %@.",
							(long)http.statusCode, name];
		return LDrawRebrickableMakeError(LDrawRebrickableErrorBadResponse, reason, nil);
	}

	@synchronized (self) {
		[record addEntriesFromDictionary:self->records[name] ?: @{}];
	}

	record[RecordCheckedKey] = LDrawJSONStringFromDate([NSDate date]);

	if (http.statusCode == 200)
	{
		[fileManager createDirectoryAtURL:staging withIntermediateDirectories:YES attributes:nil error:NULL];
		[fileManager removeItemAtURL:destination error:NULL];
		if ([fileManager moveItemAtURL:location toURL:destination error:&moveError] == NO)
			return moveError;

		record[RecordETagKey]		= [http valueForHTTPHeaderField:@"ETag"];
		record[RecordModifiedKey]	= [http valueForHTTPHeaderField:@"Last-Modified"];
		record[RecordNewKey]		= @YES;
		staged[name] = @{ @"record" : [record copy], @"url" : destination };
		return nil;
	}

	@synchronized (self) {
		self->records[name] = record;
	}
	return nil;

}//end takeFileNamed:from:response:error:stagingIn:staged:


//========== storeStagedFiles:stored: ==========================================
///
/// @abstract	Puts the staged files in place of the old ones, and keeps their
/// 			records. An old file stays until its new one is in place.
///
//==============================================================================
- (NSError *) storeStagedFiles:(NSDictionary<NSString *, NSDictionary *> *)staged
						stored:(NSMutableArray<NSString *> *)stored
{
	NSFileManager *fileManager = [NSFileManager defaultManager];

	for (NSString *name in [[staged allKeys] sortedArrayUsingSelector:@selector(compare:)])
	{
		NSURL	*source			= staged[name][@"url"];
		NSURL	*destination	= [self localURLForFileNamed:name];
		NSError	*error			= nil;
		BOOL	 moved			= NO;

		if ([fileManager fileExistsAtPath:[destination path]])
			moved = [fileManager replaceItemAtURL:destination
									withItemAtURL:source
								   backupItemName:nil
										  options:0
								 resultingItemURL:NULL
											error:&error];
		else
			moved = [fileManager moveItemAtURL:source toURL:destination error:&error];
		if (moved == NO)
			return error;

		@synchronized (self) {
			self->records[name] = staged[name][@"record"];
		}
		[stored addObject:name];
	}
	return nil;

}//end storeStagedFiles:stored:


// MARK: - UTILITIES -


//========== removeStagingFolders ==============================================
///
/// @abstract	Removes the staging folders of runs that did not finish.
///
//==============================================================================
- (void) removeStagingFolders
{
	NSFileManager	*fileManager	= [NSFileManager defaultManager];
	NSArray			*contents		= [fileManager contentsOfDirectoryAtURL:self.folderURL
												 includingPropertiesForKeys:nil
																	options:0
																	  error:NULL];

	for (NSURL *url in contents)
	{
		if ([[url lastPathComponent] hasPrefix:StagingPrefix])
			[fileManager removeItemAtURL:url error:NULL];
	}

}//end removeStagingFolders


//========== saveRecords =======================================================
//==============================================================================
- (void) saveRecords
{
	NSDictionary *file = nil;

	@synchronized (self) {
		file = @{ @"version" : @(LDrawInventoryFileVersion), RecordsFilesKey : [self->records copy] };
	}
	LDrawJSONWriteFile(file, [self.folderURL URLByAppendingPathComponent:RecordsFileName], YES, NULL);
}

@end
