//==============================================================================
//
//  File:       LDrawLibraryRelease.m
//  Package:    LDrawLibraryUpdate
//
//  Purpose:    LDraw's releases, as its server lists them.
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//
//==============================================================================

#import <LDrawLibraryUpdate/LDrawLibraryRelease.h>

// The columns of a row.
enum
{
	ColumnKind			= 0,
	ColumnIdentifier	= 1,
	ColumnFormat		= 3,
	ColumnURL			= 4,
	ColumnByteCount		= 5,
	ColumnMD5			= 6,
	ColumnCount			= 7
};


//========== IsReleaseIdentifier ===============================================
///
/// @abstract	Whether the text is an update's year and number, such as
/// 			"2026-10". Identifiers are compared as text, so one of another
/// 			shape could sort after every real update.
///
//==============================================================================
static BOOL IsReleaseIdentifier(NSString *text)
{
	NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];

	if ([text length] != 7 || [text characterAtIndex:4] != '-')
		return NO;

	for (NSUInteger index = 0; index < 7; index++)
	{
		unichar character = [text characterAtIndex:index];

		// Only ASCII digits: decimalDigitCharacterSet also has other scripts'.
		if (index != 4 && (character > 127 || [digits characterIsMember:character] == NO))
			return NO;
	}
	return YES;
}


@implementation LDrawLibraryRelease

//========== initWithColumns:complete: =========================================
///
/// @abstract	A release from a row of the list, or nil when the row is not a
/// 			zip archive at an https address, or its update is not a year
/// 			and number.
///
//==============================================================================
- (instancetype) initWithColumns:(NSArray<NSString *> *)columns complete:(BOOL)complete
{
	NSURL *url = [NSURL URLWithString:columns[ColumnURL]];

	if (	[columns[ColumnFormat] isEqualToString:@"ZIP"] == NO
		||	[[url scheme] isEqualToString:@"https"] == NO
		||	IsReleaseIdentifier(columns[ColumnIdentifier]) == NO )
	{
		return nil;
	}

	self = [super init];
	if (self) {
		self->_identifier	= [columns[ColumnIdentifier] copy];
		self->_URL			= url;
		self->_byteCount	= [columns[ColumnByteCount] longLongValue];
		self->_md5			= [[columns[ColumnMD5] lowercaseString] copy];
		self->_complete		= complete;
	}
	return self;

}//end initWithColumns:complete:


//---------- byteCountOfReleases: ------------------------------------[static]--
//------------------------------------------------------------------------------
+ (int64_t) byteCountOfReleases:(NSArray<LDrawLibraryRelease *> *)releases
{
	int64_t byteCount = 0;

	for (LDrawLibraryRelease *release in releases)
		byteCount += release.byteCount;
	return byteCount;

}//end byteCountOfReleases:


//---------- identifierReachedByReleases: ----------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *) identifierReachedByReleases:(NSArray<LDrawLibraryRelease *> *)releases
{
	return [[releases lastObject] identifier];
}

@end


@implementation LDrawLibraryReleaseList
{
	NSSet<NSString *> *updateIdentifiers;	// of every update, with a zip archive or not
}


// MARK: - INITIALIZATION -


//========== initWithText: =====================================================
///
/// @abstract	Reads the rows: kind, update, date, format, address, size and
/// 			MD5, with tabs between.
///
//==============================================================================
- (instancetype) initWithText:(NSString *)text
{
	NSMutableDictionary<NSString *, LDrawLibraryRelease *>	*zips			= [NSMutableDictionary dictionary];
	NSMutableSet<NSString *>								*identifiers	= [NSMutableSet set];
	LDrawLibraryRelease										*complete		= nil;
	NSMutableArray<LDrawLibraryRelease *>					*updates		= [NSMutableArray array];
	NSString												*latest			= nil;

	for (NSString *line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]])
	{
		NSArray<NSString *>	*columns	= [line componentsSeparatedByString:@"\t"];
		LDrawLibraryRelease	*release	= nil;

		if ([columns count] < ColumnCount || IsReleaseIdentifier(columns[ColumnIdentifier]) == NO)
			continue;

		if ([columns[ColumnKind] isEqualToString:@"UPDATE"])
		{
			release = [[LDrawLibraryRelease alloc] initWithColumns:columns complete:NO];
			[identifiers addObject:columns[ColumnIdentifier]];
			if (release != nil)
				zips[release.identifier] = release;
		}
		else if ([columns[ColumnKind] isEqualToString:@"COMPLETE"])
		{
			complete = [[LDrawLibraryRelease alloc] initWithColumns:columns complete:YES] ?: complete;
		}
	}

	if (complete == nil)
		return nil;

	for (NSString *identifier in [[zips allKeys] sortedArrayUsingSelector:@selector(compare:)])
		[updates addObject:zips[identifier]];

	// The complete library can be older than the newest update, or newer.
	latest = complete.identifier;
	for (NSString *identifier in identifiers)
	{
		if ([identifier compare:latest] == NSOrderedDescending)
			latest = identifier;
	}

	self = [super init];
	if (self) {
		self->_updates				= [updates copy];
		self->_complete				= complete;
		self->_latestIdentifier		= [latest copy];
		self->updateIdentifiers		= [identifiers copy];
	}
	return self;

}//end initWithText:


// MARK: - WHAT TO INSTALL -


//========== releasesToInstallAfter: ===========================================
//==============================================================================
- (NSArray<LDrawLibraryRelease *> *) releasesToInstallAfter:(NSString *)installed
{
	NSArray<LDrawLibraryRelease *>	*viaUpdates		= nil;
	NSArray<LDrawLibraryRelease *>	*viaComplete	= nil;
	NSArray<LDrawLibraryRelease *>	*afterComplete	= [self updatesAfter:self.complete.identifier];

	// Identifiers are a year and a two-digit number, so they sort as text.
	if (installed != nil && [installed compare:self.latestIdentifier] != NSOrderedAscending)
		return @[];

	if (installed != nil)
		viaUpdates = [self updatesAfter:installed];
	if (afterComplete != nil)
		viaComplete = [@[self.complete] arrayByAddingObjectsFromArray:afterComplete];

	// The smaller download wins, and the complete library a tie.
	if (viaUpdates != nil && viaComplete != nil)
	{
		int64_t updatesSize		= [LDrawLibraryRelease byteCountOfReleases:viaUpdates];
		int64_t completeSize	= [LDrawLibraryRelease byteCountOfReleases:viaComplete];

		return (updatesSize < completeSize) ? viaUpdates : viaComplete;
	}
	if (viaUpdates != nil || viaComplete != nil)
		return viaUpdates ?: viaComplete;

	// Nothing reaches the newest update. The complete library comes closest.
	if (installed == nil || [self.complete.identifier compare:installed] == NSOrderedDescending)
		return @[self.complete];
	return @[];

}//end releasesToInstallAfter:


//========== updatesAfter: =====================================================
///
/// @abstract	The zip updates after the given one, oldest first. Nil when
/// 			they do not reach the newest update, because an update in
/// 			between has no zip archive.
///
//==============================================================================
- (NSArray<LDrawLibraryRelease *> *) updatesAfter:(NSString *)identifier
{
	NSMutableArray<LDrawLibraryRelease *>	*updates	= [NSMutableArray array];
	NSUInteger								 newerCount	= 0;

	for (NSString *other in self->updateIdentifiers)
	{
		if ([other compare:identifier] == NSOrderedDescending)
			newerCount++;
	}

	for (LDrawLibraryRelease *release in self.updates)
	{
		if ([release.identifier compare:identifier] == NSOrderedDescending)
			[updates addObject:release];
	}

	if ([updates count] != newerCount)
		return nil;

	// The complete library can be the only release of the newest update.
	if (	[identifier compare:self.latestIdentifier] == NSOrderedAscending
		&&	[[[updates lastObject] identifier] isEqualToString:self.latestIdentifier] == NO )
	{
		return nil;
	}
	return updates;

}//end updatesAfter:

@end
