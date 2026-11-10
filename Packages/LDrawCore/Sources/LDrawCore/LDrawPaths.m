//==============================================================================
//
//  File:       LDrawPaths.m
//  Package:    LDrawCore
//
//  Purpose:    Looks up LDraw-related file locations.
//
//  Modified:   05/03/2011 Allen Smith. Creation Date.
//
//==============================================================================

#import <LDrawCore/LDrawPaths.h>

#import <os/lock.h>

#import <LDrawCore/LDrawPathNames.h>

// What a part's name starts with to name its high or low version.
static NSString * const HighPrefix	= PRIMITIVES_48_DIRECTORY_NAME @"\\";
static NSString * const LowPrefix	= PRIMITIVES_8_DIRECTORY_NAME @"\\";

@interface LDrawPaths ()
{
	// Guards the three host-supplied paths. The host can reassign the preferred
	// folder from Preferences on the main thread while a background catalog scan
	// or part load is reading it, and these are strong ivars under ARC, so an
	// unsynchronized read racing a write risks an over-release, not merely a
	// stale value.
	//
	// os_unfair_lock is not recursive, so it is only ever held across a bare
	// pointer read or write -- never across a file-system call, and never while
	// calling another method on self. Every reader below goes through these
	// accessors rather than touching the ivars directly.
	os_unfair_lock	pathsLock;

	NSString		*preferredLDrawPath;
	NSString		*internalLDrawPath;
	NSString		*overridesPath;
	NSString		*bundledLdconfigPath;

	// The folders a part is looked up in: the library's, and the overrides
	// folder's. Built from the paths above, and cleared by any change.
	NSArray			*librarySearchPaths;
	NSArray			*overridesSearchPaths;

	// The names under each "48" or "8" folder, by folder, so a part's version
	// is only looked for where it exists. Cleared by any change, so turning the
	// overrides off and on finds a file added meanwhile.
	NSMutableDictionary<NSString *, NSSet<NSString *> *>	*versionNames;

	// Counts changes, so a list built from old settings is not stored.
	NSUInteger		pathGeneration;

	// Whether pathForPartName: uses the overrides folder. It keeps its path
	// while turned off.
	BOOL			overridesEnabled;

	// Which version of a part pathForPartName: looks for first.
	LDrawResolution	resolution;
}

/// Host-provided fallback LDConfig.ldr. Thread-safe.
- (NSString *)bundledLdconfigPath;

/// Clears the folder and name lists. Call it with pathsLock held.
- (void)clearListsLocked;

@end


@implementation LDrawPaths

//---------- sharedPaths ---------------------------------------------[static]--
//
// Purpose:		Returns the global object.
//
//------------------------------------------------------------------------------
+ (LDrawPaths *)sharedPaths
{
	static LDrawPaths *sharedObject = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedObject = [[LDrawPaths alloc] init];
	});
	return sharedObject;
}


//---------- internalLDrawPathInBundle: ------------------------------[static]--
//
// Purpose:		Bundled unofficial LDraw tree used for host-distributed
//				parts. The host still calls setInternalLDrawPath:.
//
//------------------------------------------------------------------------------
+ (NSString *)internalLDrawPathInBundle:(NSBundle *)bundle
{
	return [[bundle resourcePath] stringByAppendingPathComponent:LDRAW_DIRECTORY_NAME];
}


//---------- bundledLdconfigPathInBundle: ----------------------------[static]--
//
// Purpose:		Bundled LDConfig.ldr. The host still prefers LDraw/LDConfig.ldr
//				when that file exists.
//
//------------------------------------------------------------------------------
+ (NSString *)bundledLdconfigPathInBundle:(NSBundle *)bundle
{
	return [bundle pathForResource:LDCONFIG ofType:LDCONFIG_EXTENSION];
}


//========== init ==============================================================
//
// Purpose:		Initialize the object. The host still sets the preferred LDraw
//				folder, bundled unofficial tree, and bundled ldconfig path.
//
//==============================================================================
- (id)init
{
	self = [super init];
	if (self != nil)
	{
		pathsLock			= OS_UNFAIR_LOCK_INIT;
		overridesEnabled	= YES;
	}
	return self;
}


//========== copyWithZone: =====================================================
//
// Purpose:		A copy with the same paths and settings, for work that must not
//				see a change made meanwhile.
//
//==============================================================================
- (id)copyWithZone:(NSZone *)zone
{
	LDrawPaths *copy = [[[self class] allocWithZone:zone] init];

	[copy setPreferredLDrawPath:[self preferredLDrawPath]];
	[copy setInternalLDrawPath:[self internalLDrawPath]];
	[copy setOverridesPath:[self overridesPath]];
	[copy setBundledLdconfigPath:[self bundledLdconfigPath]];
	[copy setOverridesEnabled:[self overridesEnabled]];
	[copy setResolution:[self resolution]];

	return copy;
}


#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

//========== internalLDrawPath =================================================
//
// Purpose:		References an LDraw folder baked into the host app to distribute 
//				some unofficial parts. 
//
//==============================================================================
- (NSString *)internalLDrawPath
{
	os_unfair_lock_lock(&pathsLock);
	NSString *path = internalLDrawPath;	// retained by ARC while locked
	os_unfair_lock_unlock(&pathsLock);

	return path;
}


//========== setInternalLDrawPath: =============================================
//
// Purpose:		Bundled unofficial LDraw tree (host Resources/LDraw).
//
//==============================================================================
- (void)setInternalLDrawPath:(NSString *)pathIn
{
	// Copy outside the lock: a mutable string retained by reference would let
	// the caller change the path out from under a reader the lock can't help.
	NSString *newPath = [pathIn copy];

	os_unfair_lock_lock(&pathsLock);
	internalLDrawPath = newPath;
	[self clearListsLocked];
	os_unfair_lock_unlock(&pathsLock);
}


//========== preferredLDrawPath ================================================
//==============================================================================
- (NSString *)preferredLDrawPath
{
	os_unfair_lock_lock(&pathsLock);
	NSString *path = preferredLDrawPath;	// retained by ARC while locked
	os_unfair_lock_unlock(&pathsLock);

	return path;
}


//========== setPreferredLDrawPath: ============================================
//
// Purpose:		Sets the user's preferred location for the LDraw directory.
//
//==============================================================================
- (void)setPreferredLDrawPath:(NSString *)pathIn
{
	NSString *newPath = [pathIn copy];

	os_unfair_lock_lock(&pathsLock);
	preferredLDrawPath = newPath;
	[self clearListsLocked];
	os_unfair_lock_unlock(&pathsLock);
}


//========== overridesPath =====================================================
//==============================================================================
- (NSString *)overridesPath
{
	os_unfair_lock_lock(&pathsLock);
	NSString *path = overridesPath;	// retained by ARC while locked
	os_unfair_lock_unlock(&pathsLock);

	return path;
}


//========== setOverridesPath: =================================================
//
// Purpose:		Sets the folder whose parts replace library parts of the same
//				name. An empty path means none.
//
//==============================================================================
- (void)setOverridesPath:(NSString *)pathIn
{
	NSString *newPath = ([pathIn length] > 0) ? [pathIn copy] : nil;

	os_unfair_lock_lock(&pathsLock);
	overridesPath = newPath;
	[self clearListsLocked];
	os_unfair_lock_unlock(&pathsLock);
}


//========== overridesEnabled ==================================================
//
// Purpose:		Whether pathForPartName: looks in the overrides folder. YES
//				unless it was turned off.
//
//==============================================================================
- (BOOL)overridesEnabled
{
	os_unfair_lock_lock(&pathsLock);
	BOOL enabled = overridesEnabled;
	os_unfair_lock_unlock(&pathsLock);

	return enabled;
}


//========== setOverridesEnabled: ==============================================
//==============================================================================
- (void)setOverridesEnabled:(BOOL)flag
{
	os_unfair_lock_lock(&pathsLock);
	overridesEnabled = flag;
	[self clearListsLocked];
	os_unfair_lock_unlock(&pathsLock);
}


//========== resolution ========================================================
//==============================================================================
- (LDrawResolution)resolution
{
	os_unfair_lock_lock(&pathsLock);
	LDrawResolution current = resolution;
	os_unfair_lock_unlock(&pathsLock);

	return current;
}


//========== setResolution: ====================================================
//
// Purpose:		High looks for "48\" and Low for "8\" in front of a part's name
//				first, and falls back to the part itself. An unknown value, such
//				as one saved by a later version, means Normal.
//
//==============================================================================
- (void)setResolution:(LDrawResolution)newResolution
{
	if (newResolution != LDrawResolutionLow && newResolution != LDrawResolutionHigh)
		newResolution = LDrawResolutionNormal;

	os_unfair_lock_lock(&pathsLock);
	resolution = newResolution;
	[self clearListsLocked];
	os_unfair_lock_unlock(&pathsLock);
}


//========== clearListsLocked ==================================================
//
// Purpose:		Clears the folder and name lists, so they are built again from
//				the new settings.
//
//==============================================================================
- (void)clearListsLocked
{
	librarySearchPaths		= nil;
	overridesSearchPaths	= nil;
	versionNames			= nil;
	pathGeneration++;
}


//========== setBundledLdconfigPath: ===========================================
//
// Purpose:		Fallback LDConfig.ldr when LDraw/LDConfig.ldr is missing.
//
//==============================================================================
- (void)setBundledLdconfigPath:(NSString *)pathIn
{
	NSString *newPath = [pathIn copy];

	os_unfair_lock_lock(&pathsLock);
	bundledLdconfigPath = newPath;
	os_unfair_lock_unlock(&pathsLock);
}


//========== bundledLdconfigPath ===============================================
//
// Purpose:		Fallback LDConfig.ldr supplied by the host.
//
//==============================================================================
- (NSString *)bundledLdconfigPath
{
	os_unfair_lock_lock(&pathsLock);
	NSString *path = bundledLdconfigPath;	// retained by ARC while locked
	os_unfair_lock_unlock(&pathsLock);

	return path;
}


#pragma mark -
#pragma mark STANDARD PATHS
#pragma mark -

//========== partsPathForDomain: ===============================================
//==============================================================================
- (NSString *)partsPathForDomain:(LDrawDomain)domain
{
	NSString	*baseLDrawPath	= nil;
	NSString	*path			= nil;
	
	if (domain == LDrawUserOverrides)
	{
		return [[self overridesPath] stringByAppendingPathComponent:PARTS_DIRECTORY_NAME];
	}
	else if (domain == LDrawUserOfficial || domain == LDrawUserUnofficial)
	{
		baseLDrawPath = [self preferredLDrawPath];
	}
	else
	{
		baseLDrawPath = [self internalLDrawPath];
	}

	if (domain == LDrawUserOfficial || domain == LDrawInternalOfficial)
	{
		path = [baseLDrawPath stringByAppendingPathComponent:PARTS_DIRECTORY_NAME];
	}
	else
	{
		path = [baseLDrawPath stringByAppendingPathComponent:UNOFFICIAL_DIRECTORY_NAME];
		path = [path          stringByAppendingPathComponent:PARTS_DIRECTORY_NAME];
	}
	
	return path;
}


//========== primitivesPathForDomain: ==========================================
//==============================================================================
- (NSString *)primitivesPathForDomain:(LDrawDomain)domain
{
	NSString	*baseLDrawPath	= nil;
	NSString	*path			= nil;
	
	if (domain == LDrawUserOverrides)
	{
		return [[self overridesPath] stringByAppendingPathComponent:PRIMITIVES_DIRECTORY_NAME];
	}
	else if (domain == LDrawUserOfficial || domain == LDrawUserUnofficial)
	{
		baseLDrawPath = [self preferredLDrawPath];
	}
	else
	{
		baseLDrawPath = [self internalLDrawPath];
	}

	if (domain == LDrawUserOfficial || domain == LDrawInternalOfficial)
	{
		path = [baseLDrawPath stringByAppendingPathComponent:PRIMITIVES_DIRECTORY_NAME];
	}
	else
	{
		path = [baseLDrawPath stringByAppendingPathComponent:UNOFFICIAL_DIRECTORY_NAME];
		path = [path          stringByAppendingPathComponent:PRIMITIVES_DIRECTORY_NAME];
	}
	
	return path;
}


//========== primitives48PathForDomain: ========================================
//==============================================================================
- (NSString *)primitives48PathForDomain:(LDrawDomain)domain
{
	NSString *path = [self primitivesPathForDomain:domain];
	
	path = [path stringByAppendingPathComponent:PRIMITIVES_48_DIRECTORY_NAME];
	
	return path;
}


//========== ldconfigPath ======================================================
//
// Purpose:		Returns the path to LDraw/ldconfig.ldr, or maybe our fallback 
//				internal file. If this method returns a path that doesn't 
//				actually exist, it means somebody was messing with the 
//				application bundle. 
//
//==============================================================================
- (NSString *)ldconfigPath
{
	NSFileManager	*fileManager	= [[NSFileManager alloc] init];
	NSString		*installedPath	= nil;
	NSString		*ldconfigPath	= nil;
	
	// Try in the LDraw folder first
	installedPath	= [[self preferredLDrawPath] stringByAppendingPathComponent:LDCONFIG_FILE_NAME];
	
	if (installedPath != nil) // could be nil if no LDraw folder is set in prefs
	{
		if ([fileManager fileExistsAtPath:installedPath] == YES)
		{
			ldconfigPath = installedPath;
		}
	}
	
	// Try the host-provided bundled copy
	if (ldconfigPath == nil)
		ldconfigPath = [self bundledLdconfigPath];

	return ldconfigPath;
	
} // end ldconfigPath


//========== MLCadIniPathWithBundledPath: ======================================
//
// Purpose:		Returns the path to a valid MLCad.ini file. By default, this is
//				LDraw/MLCad.ini.
//
//				Because MLCad.ini is a third-party add-on not distributed with
//				LDraw, the host typically bundles its own copy and passes that
//				path as bundledPath. Prefer the copy in LDraw/ when it exists.
//
//==============================================================================
- (NSString *)MLCadIniPathWithBundledPath:(NSString *)bundledPath
{
	NSFileManager	*fileManager		= [[NSFileManager alloc] init];
	NSString		*preferredPath		= [[self preferredLDrawPath] stringByAppendingPathComponent:MLCAD_INI_FILE_NAME];

	// we want MLCad.ini to be in the LDraw folder.
	if ([fileManager isReadableFileAtPath:preferredPath] == YES)
		return preferredPath;

	return bundledPath;

} // end MLCadIniPathWithBundledPath:


//========== partCatalogPath ===================================================
//
// Purpose:		Returns the path at which the part catalog should exist. (It may 
//				not actually exist there; this method doesn't check.) 
//
//==============================================================================
- (NSString *)partCatalogPath
{
	NSString        *pathToPartList = nil;
	NSString        *ldrawPath      = [self preferredLDrawPath];	// read once

	// Do we have an LDraw folder?
	if (ldrawPath != nil)
	{
		pathToPartList = [ldrawPath stringByAppendingPathComponent:PART_CATALOG_NAME];
	}
	
	return pathToPartList;
}


//========== subpartsPathForDomain: ============================================
//==============================================================================
- (NSString *)subpartsPathForDomain:(LDrawDomain)domain
{
	NSString *path = [self partsPathForDomain:domain];
	
	path = [path stringByAppendingPathComponent:SUBPARTS_DIRECTORY_NAME];
	
	return path;
}


#pragma mark -
#pragma mark UTILITIES
#pragma mark -

//========== findLDrawPathRelativeToApplicationPath: ===========================
//
// Purpose:		Attempts to search out an LDraw path on the system.
//				applicationPath is the host app bundle path; nil skips the
//				two candidates next to the application.
//
//==============================================================================
- (NSString *)findLDrawPathRelativeToApplicationPath:(NSString *)applicationPath
{
	NSInteger   counter                 = 0;
	BOOL        foundAPath              = NO;

	NSString    *applicationFolder      = [applicationPath stringByDeletingLastPathComponent];
	NSString    *siblingFolder          = [applicationFolder stringByDeletingLastPathComponent];
	NSString    *library                = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSLocalDomainMask, YES) objectAtIndex:0];
	NSString    *userLibrary            = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask,  YES) objectAtIndex:0];
	NSString    *applicationSupport     = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSLocalDomainMask,  YES) objectAtIndex:0];
	NSString    *userApplicationSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask,  YES) objectAtIndex:0];

	// Try User Defaults first; maybe we've already saved one.
	NSString    *preferencePath         = [self preferredLDrawPath];
	NSString    *ldrawPath              = preferencePath;

	if (preferencePath == nil)
		preferencePath = @""; //we're going to add this to an array. Can't have a nil object.

	applicationFolder       = [applicationFolder		stringByAppendingPathComponent:LDRAW_DIRECTORY_NAME];
	siblingFolder           = [siblingFolder			stringByAppendingPathComponent:LDRAW_DIRECTORY_NAME];
	library                 = [library					stringByAppendingPathComponent:LDRAW_DIRECTORY_NAME];
	userLibrary             = [userLibrary				stringByAppendingPathComponent:LDRAW_DIRECTORY_NAME];
	applicationSupport      = [applicationSupport		stringByAppendingPathComponent:LDRAW_DIRECTORY_NAME];
	userApplicationSupport  = [userApplicationSupport	stringByAppendingPathComponent:LDRAW_DIRECTORY_NAME];

	NSMutableArray *potentialPaths = [NSMutableArray arrayWithObject:preferencePath];
	if (applicationPath != nil)
	{
		[potentialPaths addObject:applicationFolder];
		[potentialPaths addObject:siblingFolder];
	}
	[potentialPaths addObjectsFromArray:@[
		applicationSupport,
		userApplicationSupport,
		library,
		userLibrary,
	]];
	for (counter = 0; counter < [potentialPaths count] && foundAPath == NO; counter++)
	{
		ldrawPath   = [potentialPaths objectAtIndex:counter];
		foundAPath  = [self validateLDrawFolder:ldrawPath];
	}

	// Not there.
	if (foundAPath == NO)
	{
		ldrawPath = nil;
	}

	return ldrawPath;

} // end findLDrawPathRelativeToApplicationPath:


//========== pathForPartName: ==================================================
//
// Purpose:		Ferret out where this part is defined in the LDraw folder.
//				Parts can be defined in any of the following folders:
//				LDraw/p				(primitives)
//				LDraw/parts			(parts)
//				LDraw/parts/s		(subparts)
//				LDraw/unofficial	(unofficial parts root -- Allen's addition)
//				Overrides/p and Overrides/parts, which win over all of these.
//
//				For regular parts and primitives, the partName is simply the 
//				filename as found in LDraw/parts or LDraw/p. But for subparts, 
//				partName is "s\partname.dat".
//
//				This method automatically converts any occurance of the DOS 
//				path-separator ('\') found in partName to the UNIX path separator 
//				('/'), then searches LDraw/parts/partName and LDraw/p/partName 
//				for the file. Thus, any subfolder can be specified this way, if 
//				the overlords of LDraw should choose to inflict another naming 
//				nightmare like this one.
//
// Returns:		The path of the part if it is found in one of the  folders, or 
//				nil if the part is not defined in the LDraw folder.
//
//==============================================================================
- (NSString *)pathForPartName:(NSString *)partName
{
	return [self pathForPartName:partName usingOverrides:[self overridesEnabled]];

} // end pathForPartName:


//========== pathForPartName:usingOverrides: ===================================
//
// Purpose:		Finds the part with or without the overrides folder, whether
//				or not it is turned off.
//
//==============================================================================
- (NSString *)pathForPartName:(NSString *)partName usingOverrides:(BOOL)useOverrides
{
	return [self pathForPartName:partName usingOverrides:useOverrides listings:nil];

} // end pathForPartName:usingOverrides:


//========== pathsForPartNames: ================================================
//
// Purpose:		The file of each part, found as pathForPartName: finds it. Each
//				folder is listed once, in place of a check per part and folder.
//
//==============================================================================
- (NSDictionary<NSString *, NSString *> *)pathsForPartNames:(NSSet<NSString *> *)partNames
{
	NSMutableDictionary	*listings		= [NSMutableDictionary dictionary];
	NSMutableDictionary	*paths			= [NSMutableDictionary dictionaryWithCapacity:[partNames count]];
	BOOL				 useOverrides	= [self overridesEnabled];

	for (NSString *partName in partNames)
	{
		@autoreleasepool
		{
			NSString *path = [self pathForPartName:partName usingOverrides:useOverrides listings:listings];

			if (path != nil)
				paths[partName] = path;
		}
	}

	return paths;

} // end pathsForPartNames:


//========== pathForPartName:usingOverrides:listings: ==========================
//
// Purpose:		Finds the part. With listings, each folder is checked in its
//				listing, which is read the first time and kept in listings.
//				Without, each file is checked on disk.
//
// Notes:		The overrides folder comes before the library, so a fix is used
//				at every resolution. In each, a high or low version comes before
//				the part itself.
//
//==============================================================================
- (NSString *)pathForPartName:(NSString *)partName
			   usingOverrides:(BOOL)useOverrides
					 listings:(NSMutableDictionary<NSString *, NSSet<NSString *> *> *)listings
{
	NSString	*prefix		= [self resolutionPrefixForPartName:partName];
	NSArray		*library	= [self searchFoldersForOverrides:NO];
	NSArray		*groups		= useOverrides ? @[[self searchFoldersForOverrides:YES], library] : @[library];
	NSString	*path		= nil;

	for (NSArray<NSString *> *folders in groups)
	{
		if (prefix != nil)
			path = [self pathForVersion:prefix ofPartName:partName inFolders:folders listings:listings];
		if (path == nil)
			path = [self pathForPartName:partName inFolders:folders listings:listings];
		if (path != nil)
			break;
	}

	return path;

} // end pathForPartName:usingOverrides:listings:


//========== resolutionPrefixForPartName: ======================================
//
// Purpose:		"48\" in High and "8\" in Low, or nil when the part itself is
//				wanted: in Normal, or for a name that already names a version.
//
//==============================================================================
- (NSString *)resolutionPrefixForPartName:(NSString *)partName
{
	LDrawResolution current = [self resolution];

	if (current == LDrawResolutionNormal || [[self class] partNameWithoutResolution:partName] != nil)
		return nil;

	return (current == LDrawResolutionHigh) ? HighPrefix : LowPrefix;

} // end resolutionPrefixForPartName:


//---------- partNameWithoutResolution: ------------------------------[static]--
//
// Purpose:		The part a high or low version is of, e.g. "s\x.dat" for
//				"48\s\x.dat", or nil when the name names no version.
//
//------------------------------------------------------------------------------
+ (NSString *)partNameWithoutResolution:(NSString *)partName
{
	NSString *name = [partName stringByReplacingOccurrencesOfString:@"/" withString:@"\\"];

	for (NSString *prefix in @[HighPrefix, LowPrefix])
	{
		if ([name length] > [prefix length]
			&& [name compare:prefix options:NSCaseInsensitiveSearch range:NSMakeRange(0, [prefix length])]
			   == NSOrderedSame)
		{
			return [name substringFromIndex:[prefix length]];
		}
	}
	return nil;

} // end partNameWithoutResolution:


//========== searchFoldersForOverrides: ========================================
//
// Purpose:		The parts and p folders of the overrides folder, or of the
//				library, in search order.
//
//==============================================================================
- (NSArray<NSString *> *)searchFoldersForOverrides:(BOOL)overrides
{
	NSArray			*folders		= nil;
	NSUInteger		generation		= 0;

	os_unfair_lock_lock(&pathsLock);
	folders		= overrides ? overridesSearchPaths : librarySearchPaths;
	generation	= pathGeneration;
	os_unfair_lock_unlock(&pathsLock);

	if (folders == nil)
	{
		// Built without the lock, because these calls take it and it does not
		// nest.
		NSArray *domains = @[@(LDrawUserOfficial), @(LDrawUserUnofficial),
							 @(LDrawInternalOfficial), @(LDrawInternalUnofficial)];

		if (overrides)
			domains = @[@(LDrawUserOverrides)];
		folders = [self foldersForDomains:domains];

		os_unfair_lock_lock(&pathsLock);
		if (pathGeneration == generation)
		{
			if (overrides)
				overridesSearchPaths = folders;
			else
				librarySearchPaths = folders;
		}
		os_unfair_lock_unlock(&pathsLock);
	}

	return folders;

} // end searchFoldersForOverrides:


//========== pathForVersion:ofPartName:inFolders: ==============================
//
// Purpose:		The last of the folders whose "48" or "8" folder has the part,
//				or nil. Only a folder whose list names the part is checked on
//				disk.
//
//==============================================================================
- (NSString *)pathForVersion:(NSString *)prefix
				  ofPartName:(NSString *)partName
				   inFolders:(NSArray<NSString *> *)folders
					listings:(NSMutableDictionary<NSString *, NSSet<NSString *> *> *)listings
{
	NSString		*subfolder	= [prefix substringToIndex:[prefix length] - 1];
	NSString		*name		= [[partName stringByReplacingOccurrencesOfString:@"\\" withString:@"/"]
								   lowercaseString];
	NSMutableArray	*holders	= [NSMutableArray array];

	for (NSString *folder in folders)
	{
		NSString *versionFolder = [folder stringByAppendingPathComponent:subfolder];

		if ([[self namesInVersionFolder:versionFolder] containsObject:name])
			[holders addObject:versionFolder];
	}

	return ([holders count] > 0) ? [self pathForPartName:partName inFolders:holders listings:listings] : nil;

} // end pathForVersion:ofPartName:inFolders:listings:


//========== namesInVersionFolder: =============================================
//
// Purpose:		The paths of the files under a "48" or "8" folder, lowercase and
//				with slashes. Empty when there is no such folder.
//
//==============================================================================
- (NSSet<NSString *> *)namesInVersionFolder:(NSString *)folder
{
	NSSet<NSString *>	*names		= nil;
	NSUInteger			 generation	= 0;

	os_unfair_lock_lock(&pathsLock);
	names		= versionNames[folder];
	generation	= pathGeneration;
	os_unfair_lock_unlock(&pathsLock);

	if (names == nil)
	{
		// Read without the lock, which is never held across a file-system call.
		NSDirectoryEnumerator		*walk		= [[[NSFileManager alloc] init] enumeratorAtPath:folder];
		NSMutableSet<NSString *>	*found		= [NSMutableSet set];
		NSString					*relative	= nil;

		while ((relative = [walk nextObject]) != nil)
			[found addObject:[relative lowercaseString]];
		names = [found copy];

		os_unfair_lock_lock(&pathsLock);
		if (pathGeneration == generation)
		{
			if (versionNames == nil)
				versionNames = [NSMutableDictionary dictionary];
			versionNames[folder] = names;
		}
		os_unfair_lock_unlock(&pathsLock);
	}

	return names;

} // end namesInVersionFolder:


//========== libraryPathForPartName: ===========================================
//
// Purpose:		The library's own file of the part, as named: no overrides
//				folder, and no high or low version.
//
//==============================================================================
- (NSString *)libraryPathForPartName:(NSString *)partName
{
	return [self pathForPartName:partName inFolders:[self searchFoldersForOverrides:NO]];

} // end libraryPathForPartName:


//========== foldersForDomains: ================================================
//
// Purpose:		The parts and primitives folders of each domain. Folders that
//				are not set are left out.
//
//==============================================================================
- (NSArray<NSString *> *)foldersForDomains:(NSArray<NSNumber *> *)domains
{
	NSMutableArray *found = [NSMutableArray arrayWithCapacity:2 * [domains count]];

	for (NSNumber *domain in domains)
	{
		NSString *parts			= [self partsPathForDomain:domain.integerValue];
		NSString *primitives	= [self primitivesPathForDomain:domain.integerValue];

		if (parts != nil)
		{
			[found addObject:parts];
		}
		if (primitives != nil)
		{
			[found addObject:primitives];
		}
	}

	return found;

} // end foldersForDomains:


//========== pathForPartName:inFolders: ========================================
//
// Purpose:		The last of the folders that has the part, or nil.
//
//==============================================================================
- (NSString *)pathForPartName:(NSString *)partName inFolders:(NSArray<NSString *> *)folders
{
	return [self pathForPartName:partName inFolders:folders listings:nil];

} // end pathForPartName:inFolders:


//========== pathForPartName:inFolders:listings: ===============================
//
// Purpose:		The last of the folders that has the part, or nil. Checked in
//				the listings when they are given, or else on disk.
//
//==============================================================================
- (NSString *)pathForPartName:(NSString *)partName
					inFolders:(NSArray<NSString *> *)folders
					 listings:(NSMutableDictionary<NSString *, NSSet<NSString *> *> *)listings
{
	NSFileManager	*fileManager	= (listings == nil) ? [[NSFileManager alloc] init] : nil;
	NSMutableString *fixedPartName	= [NSMutableString stringWithString:partName];
	NSString		*partPath		= nil;

	// LDraw references parts in subfolders by their relative pathnames in DOS 
	// (e.g., "s\765s01.dat"). Convert to UNIX for simple searching.
	[fixedPartName replaceOccurrencesOfString:@"\\" //DOS path separator (doubled for escape-sequence)
								   withString:@"/"
									  options:0
										range:NSMakeRange(0, [fixedPartName length]) ];
	
	// If we pass an empty string, we'll wind up test for directories' existences --
	// not what we want to do.
	if ([partName length] == 0)
	{
		partPath = nil;
	}
	else
	{
		// We have a file path name; try each directory. The name is split once,
		// so a listing check builds no path for a part at the top of a folder.
		NSString	*subfolder	= [fixedPartName stringByDeletingLastPathComponent];
		NSString	*fileName	= [[fixedPartName lastPathComponent] lowercaseString];

		for (NSString *basePath in folders)
		{
			NSString	*folder		= nil;
			NSString	*testPath	= nil;
			BOOL		 exists		= NO;

			if (listings != nil)
			{
				folder	= ([subfolder length] > 0) ? [basePath stringByAppendingPathComponent:subfolder] : basePath;
				exists	= [self listings:listings ofFolder:folder haveName:fileName];
			}
			else
			{
				testPath	= [basePath stringByAppendingPathComponent:fixedPartName];
				exists		= [fileManager fileExistsAtPath:testPath];
			}

			if (exists)
				partPath = testPath ?: [basePath stringByAppendingPathComponent:fixedPartName];
		}
	}

	return partPath;

} // end pathForPartName:inFolders:listings:


//========== listings:ofFolder:haveName: =======================================
//
// Purpose:		Whether the folder lists the lowercase file name. The folder is
//				read the first time it is asked about. Names are compared
//				without case, as a Mac volume compares them.
//
//==============================================================================
- (BOOL)listings:(NSMutableDictionary<NSString *, NSSet<NSString *> *> *)listings
		ofFolder:(NSString *)folder
		haveName:(NSString *)fileName
{
	NSSet<NSString *>	*names	= listings[folder];

	if (names == nil)
	{
		NSArray			*contents	= [[[NSFileManager alloc] init] contentsOfDirectoryAtPath:folder error:NULL];
		NSMutableSet	*found		= [NSMutableSet setWithCapacity:[contents count]];

		for (NSString *name in contents)
			[found addObject:[name lowercaseString]];
		names				= found;
		listings[folder]	= names;
	}

	return [names containsObject:fileName];

} // end listings:ofFolder:haveName:


//========== pathForTextureName: ===============================================
//
// Purpose:		Searches the LDraw folder for a texture with the given name.
//
//==============================================================================
- (NSString *)pathForTextureName:(NSString *)imageName
{
	NSString	*nameInTextureDirectory = [TEXTURES_DIRECTORY_NAME stringByAppendingPathComponent:imageName];
	NSString	*imagePath				= nil;
	
	// First follow regular search path with /textures prepended
	imagePath = [self pathForPartName:nameInTextureDirectory];
	
	// Follow regular search path.
	if (imagePath == nil)
	{
		imagePath = [self pathForPartName:imageName];
	}
	
	return imagePath;
	
} // end pathForTextureName:


//========== validateLDrawFolder: ==============================================
//
// Purpose:		Checks to see that the folder at path is indeed a valid LDraw 
//				folder and contains the vital Parts and P directories.
//
//==============================================================================
- (BOOL)validateLDrawFolder:(NSString *)folderPath
{
	// Check and see if this folder is any good.
	NSString *partsFolderPath		= [folderPath stringByAppendingPathComponent:PARTS_DIRECTORY_NAME];
	NSString *primitivesFolderPath	= [folderPath stringByAppendingPathComponent:PRIMITIVES_DIRECTORY_NAME];
	
	NSFileManager	*fileManager = [[NSFileManager alloc] init];
	BOOL			folderIsValid = NO;
	
	if (	[fileManager fileExistsAtPath:folderPath]
		&&	[fileManager fileExistsAtPath:partsFolderPath]
		&&	[fileManager fileExistsAtPath:primitivesFolderPath]
	   )
	{
		folderIsValid = YES;
	}
	
	return folderIsValid;
	
} // end validateLDrawFolder:


//---------- ldrawFolderChooserErrorMessageKey -----------------------[static]--
//
// Purpose:		Alert keys when validateLDrawFolder: fails. The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)ldrawFolderChooserErrorMessageKey
{
	return @"LDrawFolderChooserErrorMessage";
}


//---------- ldrawFolderChooserErrorInformativeKey ------------------[static]--
//
// Purpose:		Localization key for the informative text when the chosen
//				LDraw folder is not valid. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)ldrawFolderChooserErrorInformativeKey
{
	return @"LDrawFolderChooserErrorInformative";
}


@end
