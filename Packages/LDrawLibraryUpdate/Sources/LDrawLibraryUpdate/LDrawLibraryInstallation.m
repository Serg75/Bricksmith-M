//==============================================================================
//
//  File:       LDrawLibraryInstallation.m
//  Package:    LDrawLibraryUpdate
//
//  Purpose:    One run of an update: downloads, unpacks, then puts the files
//              into the LDraw folder.
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//
//==============================================================================

#import "LDrawLibraryInstallation.h"

#import <LDrawLibraryUpdate/LDrawLibraryRelease.h>

#import <CommonCrypto/CommonDigest.h>
#import <fcntl.h>
#import <sys/file.h>
#import <unistd.h>

#import "LDrawLibraryUpdateErrorInternal.h"
#import "LDrawLibraryZipReader.h"

NSString * const LDrawLibraryModelsFolderName = @"models";

static NSString * const StagingPrefix			= @".bricksmith-update-";
static NSString * const UnpackedFolderName		= @"new";
static NSString * const ReplacedFolderName		= @"old";
static NSString * const ArchiveRootName			= @"ldraw";
static NSString * const UnofficialFolderName	= @"Unofficial";
static NSString * const PartsFolderName			= @"parts";
static NSString * const PartExtension			= @"dat";


//========== CanceledError =====================================================
//==============================================================================
static NSError *CanceledError(void)
{
	return LDrawLibraryUpdateMakeError(LDrawLibraryUpdateErrorCanceled, nil, nil);
}


//========== UnpackUnits =======================================================
///
/// @abstract	How much of the progress unpacking a release takes, next to its
/// 			download, which counts as its bytes.
///
//==============================================================================
static int64_t UnpackUnits(LDrawLibraryRelease *release)
{
	return release.byteCount / 4 + 1;
}


//========== RelativePathOfEntry ===============================================
///
/// @abstract	Where an archive's entry goes inside the LDraw folder, or nil
/// 			for an entry that is not installed: a folder, a file outside
/// 			"ldraw/" or in "Unofficial", and any path with a part that
/// 			starts with a dot. That is a hidden file a Mac added, or "..",
/// 			which could lead out of the folder.
///
//==============================================================================
static NSString *RelativePathOfEntry(NSString *entryPath)
{
	NSString			*path	= [entryPath stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
	NSArray<NSString *>	*parts	= [path componentsSeparatedByString:@"/"];

	if ([parts count] < 2 || [parts[0] caseInsensitiveCompare:ArchiveRootName] != NSOrderedSame)
		return nil;
	if ([parts[1] caseInsensitiveCompare:UnofficialFolderName] == NSOrderedSame)
		return nil;

	for (NSString *part in parts)
	{
		// A folder's own entry ends with an empty part.
		if ([part length] == 0 || [part hasPrefix:@"."])
			return nil;
	}
	return [[parts subarrayWithRange:NSMakeRange(1, [parts count] - 1)] componentsJoinedByString:@"/"];

}//end RelativePathOfEntry


//========== IsInFolder, IsPartPath ============================================
///
/// @abstract	Whether the path is of a file right in the folder, and of a part
/// 			file right in "parts". Parts in its subfolders are not new parts.
///
//==============================================================================
static BOOL IsInFolder(NSString *relativePath, NSString *folderName)
{
	NSArray<NSString *> *parts = [relativePath pathComponents];

	return [parts count] == 2 && [parts[0] caseInsensitiveCompare:folderName] == NSOrderedSame;
}

static BOOL IsPartPath(NSString *relativePath)
{
	return	IsInFolder(relativePath, PartsFolderName)
		&&	[[relativePath pathExtension] caseInsensitiveCompare:PartExtension] == NSOrderedSame;
}


//========== MD5OfFileAtURL ====================================================
///
/// @abstract	The file's MD5 in lowercase hex, or nil when it cannot be read.
/// 			LDraw's list gives no other checksum.
///
//==============================================================================
static NSString *MD5OfFileAtURL(NSURL *fileURL)
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	NSInputStream	*stream		= [NSInputStream inputStreamWithURL:fileURL];
	NSMutableData	*buffer		= [NSMutableData dataWithLength:64 * 1024];
	NSMutableString	*hex		= [NSMutableString string];
	NSInteger		 count		= 0;
	CC_MD5_CTX		 context;
	unsigned char	 digest[CC_MD5_DIGEST_LENGTH];

	CC_MD5_Init(&context);
	[stream open];
	while ((count = [stream read:[buffer mutableBytes] maxLength:[buffer length]]) > 0)
		CC_MD5_Update(&context, [buffer bytes], (CC_LONG)count);
	[stream close];
	CC_MD5_Final(digest, &context);
#pragma clang diagnostic pop

	if (count < 0)
		return nil;

	for (NSUInteger index = 0; index < CC_MD5_DIGEST_LENGTH; index++)
		[hex appendFormat:@"%02x", digest[index]];
	return hex;

}//end MD5OfFileAtURL


@implementation LDrawLibraryInstallation
{
	NSArray<LDrawLibraryRelease *>				*releases;
	NSURL										*folderURL;
	NSURL										*stagingURL;
	NSURL										*unpackedURL;		// in the staging folder, the new files
	NSURL										*replacedURL;		// in the staging folder, the files they replace
	NSURLSession								*session;
	NSURLSessionTask							*currentTask;		// guarded by @synchronized (self)
	int											 folderLock;		// the LDraw folder, open and locked, or -1

	// The unpacked files' paths inside the LDraw folder, keyed by the path in
	// lowercase, so two spellings of a file count once.
	NSMutableDictionary<NSString *, NSString *>	*unpackedPaths;
	NSMutableSet<NSString *>					*madeFolders;		// paths of the folders made while unpacking
}


// MARK: - INITIALIZATION -


//========== initWithReleases:folderURL:configuration: =========================
//==============================================================================
- (instancetype) initWithReleases:(NSArray<LDrawLibraryRelease *> *)someReleases
						folderURL:(NSURL *)aFolderURL
					configuration:(NSURLSessionConfiguration *)configuration
{
	self = [super init];
	if (self) {
		NSString	*stagingName	= [StagingPrefix stringByAppendingString:[[NSUUID UUID] UUIDString]];
		int64_t		 unitCount		= 0;

		for (LDrawLibraryRelease *release in someReleases)
			unitCount += release.byteCount + UnpackUnits(release);

		self->releases		= [someReleases copy];
		self->folderURL		= aFolderURL;
		self->stagingURL	= [aFolderURL URLByAppendingPathComponent:stagingName isDirectory:YES];
		self->unpackedURL	= [self->stagingURL URLByAppendingPathComponent:UnpackedFolderName isDirectory:YES];
		self->replacedURL	= [self->stagingURL URLByAppendingPathComponent:ReplacedFolderName isDirectory:YES];
		self->session		= [NSURLSession sessionWithConfiguration:configuration];
		self->unpackedPaths	= [NSMutableDictionary dictionary];
		self->madeFolders	= [NSMutableSet set];
		self->folderLock	= -1;
		self->_progress		= [NSProgress discreteProgressWithTotalUnitCount:unitCount];

		__weak LDrawLibraryInstallation *weakSelf = self;
		self->_progress.cancellationHandler = ^{
			[weakSelf cancelDownload];
		};
	}
	return self;

}//end initWithReleases:folderURL:configuration:


// MARK: - THE RUN -


//========== install: ==========================================================
//==============================================================================
- (NSArray<NSString *> *) install:(NSError **)error
{
	NSFileManager		*fileManager	= [NSFileManager defaultManager];
	NSArray<NSString *>	*added			= nil;
	NSError				*failure		= nil;

	if ([fileManager isWritableFileAtPath:[self->folderURL path]] == NO)
	{
		NSString *reason = [NSString stringWithFormat:@"The LDraw folder %@ cannot be written.",
							[self->folderURL path]];
		failure = LDrawLibraryUpdateMakeError(LDrawLibraryUpdateErrorNotWritable, reason, self->folderURL);
	}

	if (failure == nil)
		failure = [self lockFolder];

	if (failure == nil)
	{
		// Without the lock another run may be using its staging folder.
		if (self->folderLock >= 0)
			[self removeStagingFolders];
		[fileManager createDirectoryAtURL:self->unpackedURL
			  withIntermediateDirectories:YES
							   attributes:nil
									error:&failure];
	}

	for (LDrawLibraryRelease *release in self->releases)
	{
		NSURL *archiveURL = nil;

		if (failure != nil)
			break;

		archiveURL = [self downloadRelease:release error:&failure];
		if (archiveURL != nil)
		{
			[self unpackArchiveAtURL:archiveURL ofRelease:release error:&failure];
			[fileManager removeItemAtURL:archiveURL error:NULL];
		}
	}

	if (failure == nil && [self.progress isCancelled])
		failure = CanceledError();

	if (failure == nil)
	{
		// From here on the folder changes, so the work runs to its end.
		[self.progress setCancellable:NO];
		added = [self moveUnpackedFiles:&failure];
	}

	[self->session invalidateAndCancel];
	[fileManager removeItemAtURL:self->stagingURL error:NULL];

	// Closing the folder lets go of its lock.
	if (self->folderLock >= 0)
		close(self->folderLock);
	self->folderLock = -1;

	if (failure != nil && error != NULL)
		*error = failure;
	return (failure == nil) ? added : nil;

}//end install:


// MARK: - THE FOLDER -


//========== lockFolder ========================================================
///
/// @abstract	Locks the LDraw folder for this run, or returns an error when
/// 			another run holds it. That run's staging folder is in use, so
/// 			it must not be removed. A folder that cannot be locked is
/// 			updated without the lock.
///
//==============================================================================
- (NSError *) lockFolder
{
	int folder = open([self->folderURL fileSystemRepresentation], O_RDONLY | O_DIRECTORY);

	if (folder < 0)
		return nil;

	if (flock(folder, LOCK_EX | LOCK_NB) != 0)
	{
		BOOL busy = (errno == EWOULDBLOCK);

		close(folder);

		// A volume without locks gets none.
		if (busy == NO)
			return nil;

		return LDrawLibraryUpdateMakeError(LDrawLibraryUpdateErrorBusy,
										   @"Another update of the LDraw folder is under way.",
										   self->folderURL);
	}

	self->folderLock = folder;
	return nil;

}//end lockFolder


//========== removeStagingFolders ==============================================
///
/// @abstract	Removes the staging folders of runs that did not finish.
///
//==============================================================================
- (void) removeStagingFolders
{
	NSFileManager	*fileManager	= [NSFileManager defaultManager];
	NSArray			*contents		= [fileManager contentsOfDirectoryAtURL:self->folderURL
												 includingPropertiesForKeys:nil
																	options:0
																	  error:NULL];

	for (NSURL *url in contents)
	{
		if ([[url lastPathComponent] hasPrefix:StagingPrefix])
			[fileManager removeItemAtURL:url error:NULL];
	}

}//end removeStagingFolders


// MARK: - DOWNLOADING -


//========== cancelDownload ====================================================
//==============================================================================
- (void) cancelDownload
{
	@synchronized (self) {
		[self->currentTask cancel];
	}
}


//========== downloadRelease:error: ============================================
///
/// @abstract	Downloads the release's archive into the staging folder, waits
/// 			for it, and checks it against the list's size and MD5.
///
//==============================================================================
- (NSURL *) downloadRelease:(LDrawLibraryRelease *)release error:(NSError **)error
{
	// The name is our own: the identifier comes from the server.
	NSString					*archiveName	= [[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:@"zip"];
	NSURL						*archiveURL		= [self->stagingURL URLByAppendingPathComponent:archiveName];
	dispatch_semaphore_t		 done			= dispatch_semaphore_create(0);
	NSURLSessionDownloadTask	*task			= nil;
	__block NSError				*failure		= nil;

	task = [self->session downloadTaskWithURL:release.URL
							completionHandler:^(NSURL *location, NSURLResponse *response, NSError *taskError) {
		NSHTTPURLResponse	*http		= (NSHTTPURLResponse *)response;
		NSError				*moveError	= nil;

		if (taskError != nil)
		{
			BOOL canceled = (	[taskError.domain isEqualToString:NSURLErrorDomain]
							 &&	taskError.code == NSURLErrorCancelled );
			failure = canceled ? CanceledError() : taskError;
		}
		else if ([http isKindOfClass:[NSHTTPURLResponse class]] == NO || http.statusCode != 200)
		{
			NSString *reason = [NSString stringWithFormat:@"The LDraw library answered %ld for update %@.",
								(long)http.statusCode, release.identifier];
			failure = LDrawLibraryUpdateMakeError(LDrawLibraryUpdateErrorBadResponse, reason, release.URL);
		}
		else if ([[NSFileManager defaultManager] moveItemAtURL:location toURL:archiveURL error:&moveError] == NO)
		{
			failure = moveError;
		}
		dispatch_semaphore_signal(done);
	}];

	@synchronized (self) {
		self->currentTask = task;
	}
	[self.progress addChild:task.progress withPendingUnitCount:release.byteCount];

	// A cancel that came before the task was set did not reach it.
	if ([self.progress isCancelled])
		[task cancel];
	[task resume];
	dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);

	@synchronized (self) {
		self->currentTask = nil;
	}

	if (failure == nil)
		failure = [self checkArchiveAtURL:archiveURL ofRelease:release];

	if (failure != nil && error != NULL)
		*error = failure;
	return (failure == nil) ? archiveURL : nil;

}//end downloadRelease:error:


//========== checkArchiveAtURL:ofRelease: ======================================
///
/// @abstract	Nil when the file has the size and MD5 the list gives for the
/// 			release, else an error.
///
//==============================================================================
- (NSError *) checkArchiveAtURL:(NSURL *)archiveURL ofRelease:(LDrawLibraryRelease *)release
{
	NSNumber	*size	= nil;
	NSString	*reason	= nil;

	[archiveURL getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];

	if (	[size longLongValue] == release.byteCount
		&&	[MD5OfFileAtURL(archiveURL) isEqualToString:release.md5] )
	{
		return nil;
	}

	reason = [NSString stringWithFormat:@"The download of update %@ is not the file the LDraw library lists.",
			  release.identifier];
	return LDrawLibraryUpdateMakeError(LDrawLibraryUpdateErrorBadDownload, reason, release.URL);

}//end checkArchiveAtURL:ofRelease:


// MARK: - UNPACKING -


//========== unpackArchiveAtURL:ofRelease:error: ===============================
///
/// @abstract	Unpacks the archive's LDraw files into the staging folder. A
/// 			file an earlier release unpacked is replaced.
///
//==============================================================================
- (BOOL) unpackArchiveAtURL:(NSURL *)archiveURL ofRelease:(LDrawLibraryRelease *)release error:(NSError **)error
{
	NSFileManager			*fileManager	= [NSFileManager defaultManager];
	NSError					*failure		= nil;
	LDrawLibraryZipReader	*reader			= [[LDrawLibraryZipReader alloc] initWithFileURL:archiveURL error:&failure];
	NSProgress				*unpacking		= nil;

	unpacking = [NSProgress discreteProgressWithTotalUnitCount:MAX((int64_t)[reader.entries count], 1)];
	[self.progress addChild:unpacking withPendingUnitCount:UnpackUnits(release)];

	for (LDrawLibraryZipEntry *entry in reader.entries)
	{
		if (failure != nil)
			break;

		@autoreleasepool {
			NSString	*relativePath	= RelativePathOfEntry(entry.path);
			NSURL		*fileURL		= nil;
			NSURL		*parentURL		= nil;

			if ([self.progress isCancelled])
				failure = CanceledError();

			if (failure == nil && relativePath != nil)
			{
				fileURL		= [self->unpackedURL URLByAppendingPathComponent:relativePath];
				parentURL	= [fileURL URLByDeletingLastPathComponent];

				if ([self->madeFolders containsObject:[parentURL path]] == NO)
				{
					[fileManager createDirectoryAtURL:parentURL
						  withIntermediateDirectories:YES
										   attributes:nil
												error:&failure];
					[self->madeFolders addObject:[parentURL path]];
				}
				if (failure == nil && [reader writeEntry:entry toURL:fileURL error:&failure])
					self->unpackedPaths[[relativePath lowercaseString]] = relativePath;
			}
			unpacking.completedUnitCount++;
		}
	}

	if (failure != nil && error != NULL)
		*error = failure;
	return (failure == nil);

}//end unpackArchiveAtURL:ofRelease:error:


// MARK: - MOVING -


//========== moveUnpackedFiles: ================================================
///
/// @abstract	Moves the unpacked files into the LDraw folder. A file they
/// 			replace is kept in the staging folder until all are in place,
/// 			and is put back when a move fails. Returns the names of the
/// 			files that are new in "parts".
///
//==============================================================================
- (NSArray<NSString *> *) moveUnpackedFiles:(NSError **)error
{
	NSFileManager					*fileManager	= [NSFileManager defaultManager];
	NSMutableArray<NSString *>		*added			= [NSMutableArray array];
	NSMutableArray<NSURL *>			*newFolders		= [NSMutableArray array];	// outermost first
	NSError							*failure		= nil;

	// Each move is the file, then where its old one is kept.
	NSMutableArray<NSArray<NSURL *> *> *moves = [NSMutableArray array];

	if ([self->unpackedPaths count] == 0)
	{
		failure = LDrawLibraryUpdateMakeError(LDrawLibraryUpdateErrorBadArchive,
											  @"The update holds no LDraw files.",
											  nil);
	}

	for (NSString *path in [self pathsInInstallOrder])
	{
		NSURL	*sourceURL		= [self->unpackedURL URLByAppendingPathComponent:path];
		NSURL	*destinationURL	= [self->folderURL URLByAppendingPathComponent:path];
		NSURL	*backupURL		= [self->replacedURL URLByAppendingPathComponent:path];
		NSURL	*neededFolder	= nil;
		BOOL	 isFolder		= NO;
		BOOL	 exists			= NO;

		if (failure != nil)
			break;

		// The attributes are the link's own, so a broken link counts as there.
		// fileExistsAtPath: follows a link, so one to a folder is a folder.
		[fileManager fileExistsAtPath:[destinationURL path] isDirectory:&isFolder];
		exists = ([fileManager attributesOfItemAtPath:[destinationURL path] error:NULL] != nil);

		// A file never takes a folder's place: that would remove what is in it.
		if (isFolder)
		{
			NSString *reason = [NSString stringWithFormat:@"The update has a file named as the folder %@.",
								[destinationURL path]];
			failure = LDrawLibraryUpdateMakeError(LDrawLibraryUpdateErrorBadArchive, reason, destinationURL);
			break;
		}

		if (exists && [fileManager contentsEqualAtPath:[sourceURL path] andPath:[destinationURL path]])
			continue;

		neededFolder = [(exists ? backupURL : destinationURL) URLByDeletingLastPathComponent];
		if (exists == NO)
			[newFolders addObjectsFromArray:[self missingFoldersUpTo:neededFolder]];
		if ([fileManager createDirectoryAtURL:neededFolder
				  withIntermediateDirectories:YES
								   attributes:nil
										error:&failure] == NO)
		{
			break;
		}

		if (exists && [fileManager moveItemAtURL:destinationURL toURL:backupURL error:&failure] == NO)
			break;

		// Noted before the move, so the undo also clears what a failed move
		// left at the destination.
		[moves addObject:exists ? @[destinationURL, backupURL] : @[destinationURL]];
		if ([fileManager moveItemAtURL:sourceURL toURL:destinationURL error:&failure] == NO)
			break;

		if (exists == NO && IsPartPath(path))
			[added addObject:[[path lastPathComponent] lowercaseString]];
	}

	if (failure != nil)
	{
		[self undoMoves:moves];

		// Only empty folders go, so nothing put in them since is lost.
		for (NSURL *folder in [newFolders reverseObjectEnumerator])
			rmdir([folder fileSystemRepresentation]);

		if (error != NULL)
			*error = failure;
		return nil;
	}
	return [added sortedArrayUsingSelector:@selector(compare:)];

}//end moveUnpackedFiles:


//========== pathsInInstallOrder ===============================================
///
/// @abstract	The unpacked files, with those of "models" last. The release
/// 			notes there say which update the folder holds, so it does not
/// 			claim an update before all of its files are in.
///
//==============================================================================
- (NSArray<NSString *> *) pathsInInstallOrder
{
	return [[self->unpackedPaths allValues] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
		BOOL aIsLast = IsInFolder(a, LDrawLibraryModelsFolderName);
		BOOL bIsLast = IsInFolder(b, LDrawLibraryModelsFolderName);

		if (aIsLast != bIsLast)
			return aIsLast ? NSOrderedDescending : NSOrderedAscending;
		return [a compare:b];
	}];
}


//========== missingFoldersUpTo: ===============================================
///
/// @abstract	The folders inside the LDraw folder, down to the given one,
/// 			that do not exist yet. The outermost comes first.
///
//==============================================================================
- (NSArray<NSURL *> *) missingFoldersUpTo:(NSURL *)folder
{
	NSFileManager			*fileManager	= [NSFileManager defaultManager];
	NSUInteger				 rootLength		= [[self->folderURL path] length];
	NSMutableArray<NSURL *>	*missing		= [NSMutableArray array];
	NSURL					*url			= folder;

	while ([[url path] length] > rootLength && [fileManager fileExistsAtPath:[url path]] == NO)
	{
		[missing insertObject:url atIndex:0];
		url = [url URLByDeletingLastPathComponent];
	}
	return missing;

}//end missingFoldersUpTo:


//========== undoMoves: ========================================================
///
/// @abstract	Takes the moved files out again, last first, and puts the old
/// 			ones back.
///
//==============================================================================
- (void) undoMoves:(NSArray<NSArray<NSURL *> *> *)moves
{
	NSFileManager *fileManager = [NSFileManager defaultManager];

	for (NSArray<NSURL *> *move in [moves reverseObjectEnumerator])
	{
		[fileManager removeItemAtURL:move[0] error:NULL];
		if ([move count] > 1)
			[fileManager moveItemAtURL:move[1] toURL:move[0] error:NULL];
	}
}

@end
