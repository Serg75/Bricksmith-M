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

#import <LDrawCore/LDrawPathNames.h>

@interface LDrawPaths ()
{
	NSString *internalLDrawPath;
	NSString *bundledLdconfigPath;
}
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
// Purpose:		Bundled unofficial LDraw tree used for Bricksmith-distributed
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
	return self;
}


#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

//========== internalLDrawPath =================================================
//
// Purpose:		References an LDraw folder baked into Bricksmith to distribute 
//				some unofficial parts. 
//
//==============================================================================
- (NSString *)internalLDrawPath
{
	return self->internalLDrawPath;
}


//========== setInternalLDrawPath: =============================================
//
// Purpose:		Bundled unofficial LDraw tree (host Resources/LDraw).
//
//==============================================================================
- (void)setInternalLDrawPath:(NSString *)pathIn
{
	self->internalLDrawPath = pathIn;
}


//========== preferredLDrawPath ================================================
//==============================================================================
- (NSString *)preferredLDrawPath
{
	return self->preferredLDrawPath;
}


//========== setPreferredLDrawPath: ============================================
//
// Purpose:		Sets the user's preferred location for the LDraw directory.
//
//==============================================================================
- (void)setPreferredLDrawPath:(NSString *)pathIn
{
	self->preferredLDrawPath = pathIn;
}


//========== setBundledLdconfigPath: ===========================================
//
// Purpose:		Fallback LDConfig.ldr when LDraw/LDConfig.ldr is missing.
//
//==============================================================================
- (void)setBundledLdconfigPath:(NSString *)pathIn
{
	self->bundledLdconfigPath = pathIn;
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
	
	if (domain == LDrawUserOfficial || domain == LDrawUserUnofficial)
	{
		baseLDrawPath = self->preferredLDrawPath;
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
	
	if (domain == LDrawUserOfficial || domain == LDrawUserUnofficial)
	{
		baseLDrawPath = self->preferredLDrawPath;
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
	installedPath	= [self->preferredLDrawPath stringByAppendingPathComponent:LDCONFIG_FILE_NAME];
	
	if (installedPath != nil) // could be nil if no LDraw folder is set in prefs
	{
		if ([fileManager fileExistsAtPath:installedPath] == YES)
		{
			ldconfigPath = installedPath;
		}
	}
	
	// Try the host-provided bundled copy
	if (ldconfigPath == nil)
		ldconfigPath = self->bundledLdconfigPath;

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
	
	// Do we have an LDraw folder?
	if (self->preferredLDrawPath != nil)
	{
		pathToPartList = [self->preferredLDrawPath stringByAppendingPathComponent:PART_CATALOG_NAME];
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
	NSString    *preferencePath         = self->preferredLDrawPath;
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
	NSFileManager	*fileManager	= [[NSFileManager alloc] init];
	static NSArray	*searchPaths	= nil;
	NSMutableString *fixedPartName	= [NSMutableString stringWithString:partName];
	NSString		*partPath		= nil;
	
	if (searchPaths == nil)
	{
		searchPaths = [[NSArray alloc] initWithObjects:
							[self partsPathForDomain:LDrawUserOfficial],
							[self primitivesPathForDomain:LDrawUserOfficial],
							[self partsPathForDomain:LDrawUserUnofficial],
							[self primitivesPathForDomain:LDrawUserUnofficial],
							[self partsPathForDomain:LDrawInternalOfficial],
							[self primitivesPathForDomain:LDrawInternalOfficial],
							[self partsPathForDomain:LDrawInternalUnofficial],
							[self primitivesPathForDomain:LDrawInternalUnofficial],
							nil];
	}
	
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
		// We have a file path name; try each directory.
		
		for (NSString *basePath in searchPaths)
		{
			NSString *testPath = [basePath stringByAppendingPathComponent:fixedPartName];
			
			if ([fileManager fileExistsAtPath:testPath])
				partPath = testPath;
		}
	}
	
	return partPath;
	
} // end pathForPartName:


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
