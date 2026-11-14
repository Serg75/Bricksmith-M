//==============================================================================
//
//  File:       LDrawLibraryUpdater.m
//  Package:    LDrawLibraryUpdate
//
//  Purpose:    Brings an LDraw folder up to date with the releases of LDraw's
//              part library.
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//
//==============================================================================

#import <LDrawLibraryUpdate/LDrawLibraryUpdater.h>

#import <LDrawLibraryUpdate/LDrawLibraryRelease.h>

#import "LDrawLibraryInstallation.h"
#import "LDrawLibraryUpdateErrorInternal.h"

static NSString * const ReleaseListAddress		= @"https://library.ldraw.org/ptreleases/tab";
static const NSTimeInterval ListTimeout			= 30;

// Release notes are named "Note", the update's two-digit year and number, then
// "CA.txt".
static NSString * const NotesPrefix				= @"note";
static NSString * const NotesSuffix				= @"ca.txt";
static const NSUInteger NotesNameLength			= 14;
static const NSInteger  FirstLDrawYear			= 97;


//========== ReleaseOfNotesNamed ===============================================
///
/// @abstract	The update whose release notes have the name, such as "2026-10"
/// 			for "Note2610CA.txt", or nil for another file.
///
//==============================================================================
static NSString *ReleaseOfNotesNamed(NSString *name)
{
	NSString		*lowercase	= [name lowercaseString];
	NSCharacterSet	*notDigits	= [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
	NSString		*digits		= nil;
	NSInteger		 year		= 0;
	NSInteger		 number		= 0;

	if (	[lowercase length] != NotesNameLength
		||	[lowercase hasPrefix:NotesPrefix] == NO
		||	[lowercase hasSuffix:NotesSuffix] == NO )
	{
		return nil;
	}

	digits = [lowercase substringWithRange:NSMakeRange([NotesPrefix length], 4)];
	if ([digits rangeOfCharacterFromSet:notDigits].location != NSNotFound)
		return nil;

	year	= [[digits substringToIndex:2] integerValue];
	number	= [[digits substringFromIndex:2] integerValue];
	if (number == 0)
		return nil;

	// LDraw's first updates are from 1997.
	year += (year >= FirstLDrawYear) ? 1900 : 2000;
	return [NSString stringWithFormat:@"%04ld-%02ld", (long)year, (long)number];

}//end ReleaseOfNotesNamed


@implementation LDrawLibraryUpdater


// MARK: - INITIALIZATION -


//========== initWithFolderURL: ================================================
//==============================================================================
- (instancetype) initWithFolderURL:(NSURL *)folderURL
{
	self = [super init];
	if (self) {
		self->_folderURL			= [folderURL copy];
		self->_sessionConfiguration	= [NSURLSessionConfiguration defaultSessionConfiguration];
	}
	return self;

}//end initWithFolderURL:


// MARK: - THE FOLDER -


//---------- installedReleaseInFolderURL: ----------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *) installedReleaseInFolderURL:(NSURL *)folderURL
{
	NSFileManager	*fileManager	= [NSFileManager defaultManager];
	NSString		*folderPath		= [folderURL path];
	NSString		*newest			= nil;

	for (NSString *folderName in [fileManager contentsOfDirectoryAtPath:folderPath error:NULL])
	{
		NSString *modelsPath = [folderPath stringByAppendingPathComponent:folderName];

		if ([folderName caseInsensitiveCompare:LDrawLibraryModelsFolderName] != NSOrderedSame)
			continue;

		for (NSString *name in [fileManager contentsOfDirectoryAtPath:modelsPath error:NULL])
		{
			NSString *release = ReleaseOfNotesNamed(name);

			if (release != nil && (newest == nil || [release compare:newest] == NSOrderedDescending))
				newest = release;
		}
	}
	return newest;

}//end installedReleaseInFolderURL:


// MARK: - THE SERVER -


//========== fetchReleaseListWithCompletionQueue:completion: ===================
//==============================================================================
- (void) fetchReleaseListWithCompletionQueue:(dispatch_queue_t)completionQueue
								  completion:(void (^)(LDrawLibraryReleaseList *list, NSError *error))completion
{
	NSURLSession		*session	= [NSURLSession sessionWithConfiguration:self.sessionConfiguration];
	NSURL				*listURL	= [NSURL URLWithString:ReleaseListAddress];
	dispatch_queue_t	 queue		= completionQueue ?: dispatch_get_main_queue();
	NSURLRequest		*request	= [NSURLRequest requestWithURL:listURL
													   cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
												   timeoutInterval:ListTimeout];
	NSURLSessionTask	*task		= nil;

	task = [session dataTaskWithRequest:request
					  completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		NSHTTPURLResponse		*http		= (NSHTTPURLResponse *)response;
		LDrawLibraryReleaseList	*list		= nil;
		NSError					*failure	= error;

		if (failure == nil && ([http isKindOfClass:[NSHTTPURLResponse class]] == NO || http.statusCode != 200))
		{
			NSString *reason = [NSString stringWithFormat:@"The LDraw library answered %ld for its list of releases.",
								(long)http.statusCode];
			failure = LDrawLibraryUpdateMakeError(LDrawLibraryUpdateErrorBadResponse, reason, listURL);
		}

		if (failure == nil)
		{
			NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

			list = (text != nil) ? [[LDrawLibraryReleaseList alloc] initWithText:text] : nil;
			if (list == nil)
			{
				failure = LDrawLibraryUpdateMakeError(LDrawLibraryUpdateErrorBadResponse,
													  @"The LDraw library's list of releases could not be read.",
													  listURL);
			}
		}

		dispatch_async(queue, ^{
			completion(list, failure);
		});
	}];

	[task resume];
	[session finishTasksAndInvalidate];

}//end fetchReleaseListWithCompletionQueue:completion:


// MARK: - INSTALLING -


//========== installReleases:completionQueue:completion: =======================
///
/// @abstract	Runs the update on a background queue.
///
//==============================================================================
- (NSProgress *) installReleases:(NSArray<LDrawLibraryRelease *> *)releases
				 completionQueue:(dispatch_queue_t)completionQueue
					  completion:(void (^)(NSArray<NSString *> *addedPartNames, NSError *error))completion
{
	dispatch_queue_t			 queue			= completionQueue ?: dispatch_get_main_queue();
	LDrawLibraryInstallation	*installation	= [[LDrawLibraryInstallation alloc]
												   initWithReleases:releases
														  folderURL:self.folderURL
													  configuration:self.sessionConfiguration];

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		NSError				*error	= nil;
		NSArray<NSString *>	*added	= [installation install:&error];

		dispatch_async(queue, ^{
			completion(added ?: @[], error);
		});
	});

	return installation.progress;

}//end installReleases:completionQueue:completion:

@end
