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

static NSString * const DefaultBaseURL		= @"https://cdn.rebrickable.com/media/downloads/";
static NSString * const RecordsFileName		= @"downloads.json";
static NSString * const RecordsFilesKey		= @"files";
static NSString * const RecordETagKey		= @"etag";
static NSString * const RecordModifiedKey	= @"lastModified";
static NSString * const RecordCheckedKey	= @"checked";

static const NSTimeInterval OneDay = 24 * 60 * 60;


//========== CancelledError ====================================================
//==============================================================================
static NSError *CancelledError(void)
{
	return [NSError errorWithDomain:LDrawRebrickableErrorDomain code:LDrawRebrickableErrorCancelled userInfo:nil];
}


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
		self->_baseURL				= [NSURL URLWithString:DefaultBaseURL];
		self->_sessionConfiguration	= [NSURLSessionConfiguration defaultSessionConfiguration];
		self->_minimumCheckInterval	= OneDay;
		self->records				= [NSMutableDictionary dictionary];

		NSDictionary *files = LDrawJSONDictionary(file[RecordsFilesKey]);
		for (id name in files)
		{
			if (LDrawJSONString(name) != nil && LDrawJSONDictionary(files[name]) != nil)
				self->records[name] = files[name];
		}
	}
	return self;

}//end initWithFolderURL:


//---------- catalogFileNames ----------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *) catalogFileNames
{
	return @[@"themes", @"colors", @"parts", @"part_relationships", @"sets", @"minifigs",
			 @"inventories", @"inventory_sets", @"inventory_minifigs", @"inventory_parts"];
}


// MARK: - ACCESSORS -


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
/// @discussion	The work runs on the session's queue. Records are saved once,
/// 			at the end, whatever happened.
///
//==============================================================================
- (NSProgress *) updateFilesNamed:(NSArray<NSString *> *)names
							force:(BOOL)force
				  completionQueue:(dispatch_queue_t)completionQueue
					   completion:(void (^)(NSArray<NSString *> *changedNames, NSError *error))completion
{
	NSURLSession				*session	= [NSURLSession sessionWithConfiguration:self.sessionConfiguration];
	NSProgress					*progress	= [NSProgress progressWithTotalUnitCount:0];
	NSMutableArray				*changed	= [NSMutableArray array];
	dispatch_queue_t			 queue		= completionQueue ?: dispatch_get_main_queue();
	NSObject					*lock		= [[NSObject alloc] init];
	__block NSURLSessionTask	*current	= nil;
	__weak typeof(self)			 weakSelf	= self;

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
		[weakSelf saveRecords];
		[session finishTasksAndInvalidate];
		dispatch_async(queue, ^{
			completion(changed, error);
		});
	};

	weakFetchNext = fetchNext = ^(NSUInteger index) {
		LDrawRebrickableDownloads	*downloads	= weakSelf;
		NSString					*name		= (index < [names count]) ? names[index] : nil;
		int64_t						 weight		= ApproximateKilobytes(name);
		void						(^next)(NSUInteger) = weakFetchNext;

		if (downloads == nil || name == nil)
		{
			finish(nil);
			return;
		}
		if ([progress isCancelled])
		{
			finish(CancelledError());
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
			NSError *failure = [weakSelf takeFileNamed:name from:location response:response error:error];

			if (failure != nil)
			{
				finish(failure);
				return;
			}
			if ([(NSHTTPURLResponse *)response statusCode] == 200)
				[changed addObject:name];
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
		&&	-[checked timeIntervalSinceNow] < self.minimumCheckInterval;
}


//========== requestForFileNamed: ==============================================
///
/// @abstract	A GET that asks for the file only when it changed.
///
//==============================================================================
- (NSURLRequest *) requestForFileNamed:(NSString *)name
{
	NSString			*fileName	= [name stringByAppendingString:@".csv.gz"];
	NSURL				*url		= [self.baseURL URLByAppendingPathComponent:fileName];
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


//========== takeFileNamed:from:response:error: ================================
///
/// @abstract	Keeps a fetched file and what the server said about it. Returns
/// 			an error when there is nothing to keep.
///
//==============================================================================
- (NSError *) takeFileNamed:(NSString *)name
					   from:(NSURL *)location
				   response:(NSURLResponse *)response
					  error:(NSError *)error
{
	NSHTTPURLResponse	*http			= (NSHTTPURLResponse *)response;
	NSURL				*destination	= [self localURLForFileNamed:name];
	NSFileManager		*fileManager	= [NSFileManager defaultManager];
	NSMutableDictionary	*record			= [NSMutableDictionary dictionary];
	NSError				*moveError		= nil;

	if (error != nil)
	{
		if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled)
			return CancelledError();
		return error;
	}

	if ([http isKindOfClass:[NSHTTPURLResponse class]] == NO || (http.statusCode != 200 && http.statusCode != 304))
	{
		NSString *reason = [NSString stringWithFormat:@"Rebrickable answered %ld for %@.",
							(long)http.statusCode, name];
		return [NSError errorWithDomain:LDrawRebrickableErrorDomain
								   code:LDrawRebrickableErrorBadResponse
							   userInfo:@{ NSLocalizedDescriptionKey : reason }];
	}

	@synchronized (self) {
		[record addEntriesFromDictionary:self->records[name] ?: @{}];
	}

	if (http.statusCode == 200)
	{
		[fileManager createDirectoryAtURL:self.folderURL withIntermediateDirectories:YES attributes:nil error:NULL];
		[fileManager removeItemAtURL:destination error:NULL];
		if ([fileManager moveItemAtURL:location toURL:destination error:&moveError] == NO)
			return moveError;

		record[RecordETagKey]		= [http valueForHTTPHeaderField:@"ETag"];
		record[RecordModifiedKey]	= [http valueForHTTPHeaderField:@"Last-Modified"];
	}
	record[RecordCheckedKey] = LDrawJSONStringFromDate([NSDate date]);

	@synchronized (self) {
		self->records[name] = record;
	}
	return nil;

}//end takeFileNamed:from:response:error:


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
