//==============================================================================
//
//  File:       LDrawPartLibrary.m
//  Package:    LDrawCore
//
//  Purpose:    This is the centralized repository for obtaining information
//              about the contents of the LDraw folder. The part library is
//              first created by scanning the LDraw folder and collecting all
//              the part names, categories, and drawing instructions for each
//              part. This information is then saved into an XML file and
//              retrieved each time the program is relaunched. During runtime,
//              other objects query the part library to draw and display
//              information about parts.
//
//  Created by Allen Smith on 3/12/05.
//  Copyright 2005. All rights reserved.
//
//==============================================================================

#import <LDrawCore/LDrawPartLibrary.h>

#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawKeywords.h>
#import <LDrawCore/LDrawLocalization.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawPathNames.h>
#import <LDrawCore/LDrawPaths.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LDrawTexture.h>
#import <LDrawCore/LDrawUtilities.h>
#import <LDrawCore/LDrawKeys.h>
#import "PartCatalogBuilder.h"
#import <LDrawCore/NSString+LDraw.h>


// The part catalog was regenerated from disk.
// Object is the new catalog. No userInfo.
NSString *LDrawPartLibraryDidChangeNotification = @"LDrawPartLibraryDidChangeNotification";


// The parts list file is stored at LDraw/PARTS_LIST_NAME.
// It contains a dictionary of parts. Each element in the dictionary 
// is an array of parts for a category; the key under which the array 
// is stored is the category name.
//
// The part catalog is a dictionary of parts filed by Category name.
NSString	*PARTS_CATALOG_KEY	= @"Part Catalog";
	// subdictionary keys.
NSString	*PART_NUMBER_KEY	= @"Part Number";
NSString	*PART_NAME_KEY		= @"Part Name";
NSString	*PART_CATEGORY_KEY	= @"Category";
NSString	*PART_KEYWORDS_KEY	= @"Keywords";
NSString	*PART_ONLY_IN_OVERRIDES_KEY	= @"Only In Overrides";

// Raw dictionary containing each part filed by number.
NSString	*PARTS_LIST_KEY				= @"Part List";
	// subdictionary keys.
	// PART_NUMBER_KEY							(defined above)
	// PART_NAME_KEY							(defined above)

NSString	*VERSION_KEY				= @"Version";
NSString	*COMPATIBILITY_VERSION_KEY	= @"CompatibilityVersion";

NSString	*CategoryNameKey			= @"Name";
NSString	*CategoryDisplayNameKey 	= @"DisplayName";
NSString	*CategoryChildrenKey		= @"Children";

NSString	*Category_All				= @"AllCategories";
NSString	*Category_Favorites 		= @"Favorites";
NSString	*Category_Alias 			= @"Alias";
NSString	*Category_Moved 			= @"Moved";
NSString	*Category_Primitives		= @"Primitives";
NSString	*Category_Subparts			= @"Subparts";

@interface LDrawPartLibrary ()
{
	// Each loaded part, and the names of the parts its file uses. Loaded parts
	// are flattened, so this is the only record of what they are made of.
	NSMutableDictionary<NSString *, NSSet<NSString *> *>	*usedPartNames;

	// Each loaded part, and the file it was read from.
	NSMutableDictionary<NSString *, NSString *>				*loadedPaths;

	// Loaded parts whose files changed. They are kept, so documents can still
	// draw them, and are read again when a part file uses them.
	NSMutableSet<NSString *>								*staleNames;
}
- (void)notifyDelegateFavoritesChanged;
- (nullable LDrawModel *)readModelNamed:(NSString *)partName;
- (void)forgetPartNames:(NSArray<NSString *> *)partNames;
@end

@implementation LDrawPartLibrary

// Shared renderer instance. Populated by +registerSharedPartLibrary: at
// renderer +load time (LDrawRenderMetal or LDrawRenderOpenGL category).
static LDrawPartLibrary *PartLibrary_sharedInstance = nil;

//========== sharedPartLibrary =================================================
//
// Purpose:		Returns the registered renderer's LDrawPartLibrary singleton. Model
//				and feature code calls this without knowing the concrete
//				subclass. The Metal or OpenGL renderer registers itself in its
//				`+load` method.
//
//==============================================================================
+ (instancetype)sharedPartLibrary
{
	NSAssert(PartLibrary_sharedInstance != nil,
		@"No LDrawPartLibrary renderer has registered itself. Either the Metal or "
		@"OpenGL package must call +registerSharedPartLibrary: before any "
		@"model code accesses the shared library.");
	return PartLibrary_sharedInstance;
} // end sharedPartLibrary


//========== sharedPartLibraryIfRegistered =====================================
//
// Purpose:		The shared library, or nil when none is registered.
//
//==============================================================================
+ (nullable instancetype)sharedPartLibraryIfRegistered
{
	return PartLibrary_sharedInstance;

} // end sharedPartLibraryIfRegistered


//========== registerSharedPartLibrary: ========================================
//
// Purpose:		Registers the given (typically renderer-specific) LDrawPartLibrary
//				instance as the process-wide shared library. Renderers call
//				this from their `+load` method.
//
//==============================================================================
+ (void)registerSharedPartLibrary:(LDrawPartLibrary *)library
{
	PartLibrary_sharedInstance = library;
} // end registerSharedPartLibrary:


//========== init ==============================================================
//
// Purpose:		Creates a part library with no parts loaded.
//
//==============================================================================
- (id)init
{
	self = [super init];
	
	loadedFiles                 = [NSMutableDictionary dictionaryWithCapacity:400];
	usedPartNames				= [NSMutableDictionary dictionaryWithCapacity:400];
	loadedPaths					= [NSMutableDictionary dictionaryWithCapacity:400];
	staleNames					= [NSMutableSet set];
	loadedImages				= [[NSMutableDictionary alloc] init];
	optimizedRepresentations    = [NSMutableDictionary dictionaryWithCapacity:400];
	optimizedTextures			= [[NSMutableDictionary alloc] init];
	
	favorites                   = [[NSMutableArray alloc] init];
	
	[self setPartCatalog:@{}];
	
	return self;
	
} // end init


#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

//========== allPartCatalogRecords =============================================
//
// Purpose:		Returns all the part numbers in the library.
//
//==============================================================================
- (NSArray *)allPartCatalogRecords
{
	NSDictionary	*partList	= [self->partCatalog objectForKey:PARTS_LIST_KEY];

	// all the reference numbers for parts.
	return [self recordsInUse:[partList allValues]];

} // end allPartCatalogRecords


//========== recordsInUse: =====================================================
//
// Purpose:		Leaves out the parts only the overrides folder has while it is
//				turned off.
//
//==============================================================================
- (NSArray *)recordsInUse:(NSArray *)records
{
	return [[self class] partCatalogRecords:records
							 usingOverrides:[[LDrawPaths sharedPaths] overridesEnabled]];

} // end recordsInUse:


//---------- partCatalogRecords:usingOverrides: ----------------------[static]--
//
// Purpose:		The records, without the parts only the overrides folder has
//				when it is not used.
//
//------------------------------------------------------------------------------
+ (NSArray<NSDictionary *> *)partCatalogRecords:(NSArray<NSDictionary *> *)records
								 usingOverrides:(BOOL)useOverrides
{
	NSIndexSet *kept = nil;

	if (useOverrides)
		return records;

	kept = [records indexesOfObjectsPassingTest:^BOOL(NSDictionary *record, NSUInteger index, BOOL *stop) {
		return [[record objectForKey:PART_ONLY_IN_OVERRIDES_KEY] boolValue] == NO;
	}];
	return [records objectsAtIndexes:kept];

} // end partCatalogRecords:usingOverrides:


//========== categories ========================================================
//
// Purpose:		Returns all the categories in the library, sorted in no
//				particular order. While the overrides folder is off, a category
//				that only its parts fill is left out.
//
//==============================================================================
- (NSArray *)categories
{
	NSArray *names = [[self->partCatalog objectForKey:PARTS_CATALOG_KEY] allKeys];

	if ([[LDrawPaths sharedPaths] overridesEnabled] == NO)
		names = [[self class] categories:names usedByRecords:[self allPartCatalogRecords]];

	return names;

} // end categories


//---------- categories:usedByRecords: -------------------------------[static]--
//
// Purpose:		The categories that one of the records is filed under.
//
//------------------------------------------------------------------------------
+ (NSArray<NSString *> *)categories:(NSArray<NSString *> *)categories
					  usedByRecords:(NSArray<NSDictionary *> *)records
{
	NSMutableSet	*used	= [NSMutableSet setWithCapacity:[categories count]];
	NSIndexSet		*kept	= nil;

	for (NSDictionary *record in records)
	{
		NSString *category = [record objectForKey:PART_CATEGORY_KEY];

		if (category != nil)
			[used addObject:category];
	}

	kept = [categories indexesOfObjectsPassingTest:^BOOL(NSString *name, NSUInteger index, BOOL *stop) {
		return [used containsObject:name];
	}];
	return [categories objectsAtIndexes:kept];

} // end categories:usedByRecords:


//========== categoryHierarchy =================================================
//
// Purpose:		Returns an outline-conducive list of all available categories.
//
//==============================================================================
- (NSArray *)categoryHierarchy
{
	NSMutableArray  *fullCategoryList   = [NSMutableArray array];
	NSMutableArray	*libraryItems		= [NSMutableArray array];
	NSMutableArray	*categoryItems		= [NSMutableArray array];
	NSMutableArray	*otherItems			= [NSMutableArray array];
	
	// Library group
	[libraryItems addObject:@{
		CategoryNameKey: Category_All,
		CategoryDisplayNameKey: [self displayNameForCategory:Category_All],
	}];
	
	[libraryItems addObject:@{
		CategoryNameKey: Category_Favorites,
		CategoryDisplayNameKey: [self displayNameForCategory:Category_Favorites],
	}];
							 
	[fullCategoryList addObject:@{
		CategoryNameKey: @"Library",
		CategoryDisplayNameKey: [LDrawLocalization stringForKey:@"CategoryGroup_Library"],
		CategoryChildrenKey: libraryItems,
	}];
	
	// Main categories
	NSArray *categories = [[self categories] sortedArrayUsingSelector:@selector(compare:)];
	for (NSString *name in categories)
	{
		if (	[name isEqualToString:Category_Alias] == NO
		   &&	[name isEqualToString:Category_Moved] == NO
		   &&	[name isEqualToString:Category_Primitives] == NO
		   &&	[name isEqualToString:Category_Subparts] == NO )
		{
			[categoryItems addObject:@{
				CategoryNameKey: name,
				CategoryDisplayNameKey: [self displayNameForCategory:name],
			}];
		}
	}
	[fullCategoryList addObject:@{
		CategoryNameKey: @"Part Categories",
		CategoryDisplayNameKey: [LDrawLocalization stringForKey:@"CategoryGroup_PartCategories"],
		CategoryChildrenKey: categoryItems,
	}];
	
	// Other categories
	
	[otherItems addObject:@{
		CategoryNameKey: Category_Alias,
		CategoryDisplayNameKey: [self displayNameForCategory:Category_Alias],
	}];
	
	[otherItems addObject:@{
		CategoryNameKey: Category_Moved,
		CategoryDisplayNameKey: [self displayNameForCategory:Category_Moved],
	}];
	
	[otherItems addObject:@{
		CategoryNameKey: Category_Primitives,
		CategoryDisplayNameKey: [self displayNameForCategory:Category_Primitives],
	}];
	
	[otherItems addObject:@{
		CategoryNameKey: Category_Subparts,
		CategoryDisplayNameKey: [self displayNameForCategory:Category_Subparts],
	}];
	
	[fullCategoryList addObject:@{
		CategoryNameKey: @"Other",
		CategoryDisplayNameKey: [LDrawLocalization stringForKey:@"CategoryGroup_Other"],
		CategoryChildrenKey: otherItems,
	}];
								 
	return fullCategoryList;
	
} // end categoryHierarchy


//========== categoryForPartName: ==============================================
//
// Purpose:		Returns the part's category.
//
//==============================================================================
- (NSString *)categoryForPartName:(NSString *)partName
{
	NSDictionary	*partList		= [self->partCatalog objectForKey:PARTS_LIST_KEY];
	NSDictionary	*catalogInfo	= [partList objectForKey:partName];
	NSString		*category		= [catalogInfo objectForKey:PART_CATEGORY_KEY];
	
	return category;
}


//========== partCatalogRecordForPartName: =====================================
//
// Purpose:		Returns the catalog's record of the part, or nil.
//
//==============================================================================
- (NSDictionary *)partCatalogRecordForPartName:(NSString *)partName
{
	return [[self->partCatalog objectForKey:PARTS_LIST_KEY] objectForKey:partName];
}


//========== favoritePartNames =================================================
//
// Purpose:		Returns all the part names the user has bookmarked as his 
//				favorites. 
//
//==============================================================================
- (NSArray *)favoritePartNames
{
	return self->favorites;
	
} // end favoritePartNames


//========== displayNameForCategory: ===========================================
//
// Purpose:		Returns the human-friendly category name
//
//==============================================================================
- (NSString *)displayNameForCategory:(NSString *)categoryName
{
	NSString *displayName = nil;
	
	if ([categoryName isEqualToString:Category_All])
	{
		displayName = [LDrawLocalization stringForKey:@"AllCategories"];
	}
	else if ([categoryName isEqualToString:Category_Favorites])
	{
		displayName = [LDrawLocalization stringForKey:@"FavoritesCategory"];
	}
	else
	{
		displayName = [LDrawLocalization stringForKey:categoryName];
	}
	return displayName;
}


//========== favoritePartCatalogRecords ========================================
//
// Purpose:		Returns all the part info records the user has bookmarked as his 
//				favorites. 
//
//==============================================================================
- (NSArray *)favoritePartCatalogRecords
{
	NSDictionary	*partList		= [self->partCatalog objectForKey:PARTS_LIST_KEY];
	NSMutableArray	*parts			= [NSMutableArray array];
	NSDictionary	*partInfo		= nil;
	
	for (NSString *partName in self->favorites)
	{
		partInfo = [partList objectForKey:partName];
		
		if (partInfo)
			[parts addObject:partInfo];
	}

	return [self recordsInUse:parts];

} // end favoritePartNames


//========== partCatalogRecordsInCategory: =====================================
//
// Purpose:		Returns all the parts in the given category. Returns nil if the 
//				category doesn't exist. 
//
//==============================================================================
- (NSArray *)partCatalogRecordsInCategory:(NSString *)categoryName
{
	NSArray	*parts		= nil;
	
	if ([categoryName isEqualToString:Category_All])
	{
		// Retrieve all parts. We can do this by getting the entire (unsorted) 
		// contents of PARTS_LIST_KEY in the partCatalog, which is actually 
		// a dictionary of all parts.
		parts = [self allPartCatalogRecords];
		
	}
	else if ([categoryName isEqualToString:Category_Favorites])
	{
		parts = [self favoritePartCatalogRecords];
	}
	else
	{
		NSArray 		*category			= [[partCatalog objectForKey:PARTS_CATALOG_KEY] objectForKey:categoryName];
		NSDictionary	*partList			= [self->partCatalog objectForKey:PARTS_LIST_KEY];
		NSMutableArray	*partsInCategory	= [NSMutableArray array];
		NSString		*partName			= nil;
		NSDictionary	*partInfo			= nil;

		for (NSDictionary* categoryRecord in category)
		{
			partName = [categoryRecord objectForKey:PART_NUMBER_KEY];
			partInfo = [partList objectForKey:partName];
			
			if (partInfo)
				[partsInCategory addObject:partInfo];
		}

		parts = [self recordsInUse:partsInCategory];
	}
	
	return parts;

} // end partCatalogRecordsInCategory:


#pragma mark -

//========== setDelegate: ======================================================
//
// Purpose:		Set the object responsible for receiving important notifications 
//				from us. 
//
//==============================================================================
- (void)setDelegate:(id<LDrawPartLibraryDelegate>)delegateIn
{
	self->delegate = delegateIn;
}


//========== setFavorites: =====================================================
//
// Purpose:		Sets the parts which should appear in the Favorites category. 
//				This list should have been saved in preferences and loaded by 
//				the part library controller. 
//
//==============================================================================
- (void)setFavorites:(NSArray *)favoritesIn
{
	[self->favorites removeAllObjects];
	[self->favorites addObjectsFromArray:favoritesIn];
}


//========== setPartCatalog ====================================================
//
// Purpose:		Saves the local instance of the part catalog, which should be 
//				the only copy of it in the program. Use +setSharedPartCatalog to 
//				update it outside this class.
//
// Notes:		The Part Catalog is structured as follows:
//
//				partCatalog
//				|
//				|--> PARTS_CATALOG_KEY <NSDictionary>
//				|		|
//				|		Keys  are category names, e.g., "Brick"
//				|		<NSArray>
//				|			|
//				|			<NSDictionary>
//				|				|--> PART_NUMBER_KEY <NSString> (e.g., "3001.dat")
//				|
//				|--> PARTS_LIST_KEY <NSDictionary>
//						|
//						Keys are part reference numbers, e.g., "3001.dat"
//						<NSDictionary>
//							|--> PART_NUMBER_KEY
//							|--> PART_NAME_KEY
//
//				This data structure is PRIVATE. There is no get accessor. Query 
//				this object for its part lists and build your own records.
//
//==============================================================================
- (void)setPartCatalog:(NSDictionary *)newCatalog
{
	partCatalog = newCatalog;
	
	// Inform any open parts browsers of the change.
	[[NSNotificationCenter defaultCenter] 
			postNotificationName: LDrawPartLibraryDidChangeNotification
						  object: self ];
	
} // end setPartCatalog


//========== catalogVersion ====================================================
//
// Purpose:		Host app version stamped into a newly scanned catalog.
//
//==============================================================================
- (NSString *)catalogVersion
{
	return self->catalogVersion;
}


//========== setCatalogVersion: ================================================
//
// Purpose:		Set the version string written when scanning parts. Does not
//				look up the app main bundle.
//
//==============================================================================
- (void)setCatalogVersion:(NSString *)version
{
	self->catalogVersion = [version copy];
}


//---------- catalogVersionInBundle: ---------------------------------[static]--
//
// Purpose:		CFBundleVersion, else CFBundleShortVersionString, else @"1.0".
//
//------------------------------------------------------------------------------
+ (NSString *)catalogVersionInBundle:(NSBundle *)bundle
{
	NSDictionary *infoDict = [bundle infoDictionary];
	NSString     *version  = [infoDict objectForKey:@"CFBundleVersion"];

	if (version == nil)
		version = [infoDict objectForKey:@"CFBundleShortVersionString"];
	if (version == nil)
		version = @"1.0";
	return version;
}


#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== load ==============================================================
//
// Purpose:		Loads the catalog from the part list stashed in the LDraw 
//				folder. 
//
// Returns:		NO if no part list exists. (You need to call -reloadParts: in 
//				PartLibraryController then.) 
//
//==============================================================================
- (BOOL)load
{
	NSFileManager   *fileManager    = [[NSFileManager alloc] init];
	NSString        *catalogPath    = [[LDrawPaths sharedPaths] partCatalogPath];
	BOOL            partsListExists = NO;
	NSString		*version		= nil;
	NSDictionary    *newCatalog     = nil;
	
	// Do we have an LDraw folder?
	if (catalogPath != nil)
	{
		if ([fileManager fileExistsAtPath:catalogPath])
			partsListExists = YES;
	}
	
	// Do we have a part list already? 
	if (partsListExists == YES)
	{
		newCatalog	= [NSDictionary dictionaryWithContentsOfFile:catalogPath];
		version 	= [newCatalog objectForKey:VERSION_KEY];
		
		if (version)
		{
			[self setPartCatalog:newCatalog];
		}
		else
		{
			// Older part catalogs don't have enough info in them
			partsListExists = NO;
		}

	}
	
	return partsListExists;

} // end load


//========== reloadParts: ======================================================
//
// Purpose:		Scans the contents of the LDraw/ folder and produces a 
//				Mac-friendly index of parts.
//
//==============================================================================
- (void)reloadPartsWithMaxLoadCountHandler:(void (^)(NSUInteger maxPartCount))maxLoadCountHandler
				  progressIncrementHandler:(void (^)(void))progressIncrementHandler
						 completionHandler:(void (^)(BOOL success))completionHandler
{
	PartCatalogBuilder* catalogBuilder = [[PartCatalogBuilder alloc] init];
	[catalogBuilder setCatalogVersion:self->catalogVersion];
	
	[catalogBuilder makePartCatalogWithMaxLoadCountHandler:maxLoadCountHandler
								  progressIncrementHandler:progressIncrementHandler
										 completionHandler:
	 ^(NSDictionary<NSString *,id> *newPartCatalog)
	 {
		dispatch_async(dispatch_get_main_queue(), ^{
			// The host posts LDrawPartLibraryReloaded once the changed parts
			// are read, so documents do not read them all on their next draw.
			if (newPartCatalog)
				[self setPartCatalog:newPartCatalog];
			
			if (completionHandler)
			{
				completionHandler(newPartCatalog != nil);
			}
		});
	}
	 ];
	
} // end reloadParts:


#pragma mark -
#pragma mark FAVORITES
#pragma mark -

//========== addPartNameToFavorites: ===========================================
//
// Purpose:		Adds the given part name to the "Favorites" category.
//
//==============================================================================
- (void)addPartNameToFavorites:(NSString *)partName
{
	[self->favorites addObject:partName];
	[self notifyDelegateFavoritesChanged];
	
	// Inform any open parts browsers of the change.
	[[NSNotificationCenter defaultCenter] 
			postNotificationName: LDrawPartLibraryDidChangeNotification
						  object: self ];
	
} // end addPartNameToFavorites:


//========== removePartNameFromFavorites: ======================================
//
// Purpose:		Removes the given part name to the "Favorites" category.
//
//==============================================================================
- (void)removePartNameFromFavorites:(NSString *)partName
{
	[self->favorites removeObject:partName];
	[self notifyDelegateFavoritesChanged];
	
	// Inform any open parts browsers of the change.
	[[NSNotificationCenter defaultCenter] 
			postNotificationName: LDrawPartLibraryDidChangeNotification
						  object: self ];
	
} // end removePartNameFromFavorites:


//========== notifyDelegateFavoritesChanged ====================================
//
// Purpose:		Tell the host the in-memory favorites list changed. The host
//				writes FAVORITE_PARTS_KEY; this class does not.
//
//==============================================================================
- (void)notifyDelegateFavoritesChanged
{
	[self->delegate partLibrary:self didChangeFavorites:(self->favorites)];
	
} // end notifyDelegateFavoritesChanged


#pragma mark -
#pragma mark FINDING PARTS
#pragma mark -

//========== loadImageForName:inGroup: =========================================
//
// Purpose:		This is a thread-safe method which causes the texture image of 
//				the given name to be loaded out of the LDraw folder. 
//
//==============================================================================
- (void)loadImageForName:(NSString *)imageName
				 inGroup:(dispatch_group_t)parentGroup
{
	(void)parentGroup;
	CGImageRef image = (__bridge CGImageRef)[self->loadedImages objectForKey:imageName];
	if (image == nil)
	{
		NSString *imagePath = [[LDrawPaths sharedPaths] pathForTextureName:imageName];
		image = (CGImageRef)[self readImageAtPath:imagePath asynchronously:NO completionHandler:NULL];
		if (image != nil)
		{
			[self->loadedImages setObject:(__bridge id)image forKey:imageName];
		}
	}
	
} // end loadImageForName:


//========== loadModelForName:inGroup: =========================================
//
// Purpose:		This is a thread-safe method which causes the model of the given 
//				name to be loaded out of the LDraw folder. 
//
//==============================================================================
- (void)loadModelForName:(NSString *)partName
				 inGroup:(dispatch_group_t)parentGroup
{
	(void)parentGroup;
	// A part whose file changed is read again here, so the part file being
	// read is flattened with the new one.
	if ([self->loadedFiles objectForKey:partName] == nil || [self->staleNames containsObject:partName])
		[self readModelNamed:partName];

} // end loadModelForName:


//========== imageForTextureName: ==============================================
//
// Purpose:		Returns an image from our library cache.
//
//==============================================================================
- (CGImageRef)imageForTextureName:(NSString *)imageName
{
	CGImageRef	image		= NULL;
	NSString	*imagePath	= nil;
	
	// Has it already been parsed?
	image = (__bridge CGImageRef)[self->loadedImages objectForKey:imageName];
	
	if (image == nil)
	{
		// Well, this means we have to try getting it off the disk!
		imagePath	= [[LDrawPaths sharedPaths] pathForTextureName:imageName];
		image		= [self readImageAtPath:imagePath asynchronously:NO completionHandler:NULL];
		
		if (image != nil)
			[self->loadedImages setObject:(__bridge id)image forKey:imageName];
	}
	
	return image;
	
}


//========== imageForTexture: ==================================================
//
// Purpose:		Returns the image specified by the texture object.
//
//==============================================================================
- (CGImageRef)imageForTexture:(LDrawTexture *)texture
{
	NSString	*imageName	= [texture imageReferenceName];
	CGImageRef	image		= NULL;
	
	// Try to get a live link if we have parsed this part off disk already.
	image = [self imageForTextureName:imageName];
	
	if (image == nil) {
		// we're grasping at straws. See if this is a reference to an external 
		// file in the same folder.
		image = [self imageFromNeighboringFileForTexture:texture];
	}
	
	return image;
	
} // end imageForTexture:


//========== imageFromNeighboringFileForTexture: ===============================
//
// Purpose:		Attempts to resolve the texture's name reference against a file 
//				located in the same parent folder as the file in which the part 
//				is contained.
//
//				This should be a method of last resort, after searching the part 
//				library.
//
// Note:		This is BAD CODE. It caches things permanently. We need to move 
//				to the new model manager to track when to get rid of images. 
//
//==============================================================================
- (CGImageRef)imageFromNeighboringFileForTexture:(LDrawTexture *)texture
{
	LDrawFile		*enclosingFile	= [texture enclosingFile];
	NSString		*filePath		= [enclosingFile path];
	NSString		*fileDirectory	= nil;
	NSString		*imageName		= nil;
	NSString		*testPath		= nil;
	NSString		*imagePath		= nil;
	CGImageRef		image			= nil;
	NSFileManager	*fileManager	= nil;
	
	if (filePath != nil)
	{
		fileManager		= [[NSFileManager alloc] init];
		fileDirectory	= [filePath stringByDeletingLastPathComponent];
		imageName		= [texture imageDisplayName]; // handle case-sensitive filesystem
		
		// look at path = parentFolder/textures/name
		{
			testPath = [fileDirectory stringByAppendingPathComponent:TEXTURES_DIRECTORY_NAME];
			testPath = [testPath stringByAppendingPathComponent:imageName];
			if ([fileManager fileExistsAtPath:testPath])
			{
				imagePath = testPath;
			}
		}
		
		// look at path = parentFolder/name
		if (imagePath == nil)
		{
			testPath = [fileDirectory stringByAppendingPathComponent:imageName];
			if ([fileManager fileExistsAtPath:testPath])
			{
				imagePath = testPath;
			}
		}
		
		// Load if we found something
		if (imagePath)
		{
			image = [self readImageAtPath:testPath asynchronously:NO completionHandler:NULL];
			if (image != nil)
				[self->loadedImages setObject:(__bridge id)image forKey:imageName];
		}
	}
	
	return image;
	
} // end imageFromNeighboringFileForTexture:


//========== copyPowerOfTwoPixelsForImage:size: ================================
//
// Purpose:		Redraws the image into a freshly allocated pixel buffer whose
//				dimensions are powers of two, which is what Metal and OpenGL
//				need before they can upload the pixels.
//
// Notes:		The caller owns the returned buffer. Shared by LDrawPartLibraryMTL
//				and LDrawPartLibraryGL, which differ only in what they do with the
//				pixels afterwards.
//
//==============================================================================
+ (uint8_t *)copyPowerOfTwoPixelsForImage:(CGImageRef)image size:(CGSize *)outSize
{
	CGRect			canvasRect		= CGRectMake( 0, 0, FloorPowerOfTwo(CGImageGetWidth(image)), FloorPowerOfTwo(CGImageGetHeight(image)) );
	uint8_t 		*imageBuffer	= malloc( (canvasRect.size.width) * (canvasRect.size.height) * 4 );
	CGColorSpaceRef colorSpace		= CGColorSpaceCreateDeviceRGB();
	CGContextRef	bitmapContext	= CGBitmapContextCreate(imageBuffer,
															canvasRect.size.width,
															canvasRect.size.height,
															8, // bits per component
															canvasRect.size.width * 4, // bytes per row
															colorSpace,
															kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst
															);
	
	// Draw the image into the bitmap context. By doing so, we use the mighty
	// power of Quartz handle the nasty conversion details necessary to fill up
	// a pixel buffer in a GPU-friendly storage format and color space.
	CGContextSetBlendMode(bitmapContext, kCGBlendModeCopy);
	CGContextDrawImage(bitmapContext, canvasRect, image);
	
	CFRelease(colorSpace);
	CFRelease(bitmapContext);
	
	*outSize = canvasRect.size;
	
	return imageBuffer;
	
} // end copyPowerOfTwoPixelsForImage:size:


//========== modelForName: =====================================================
//
// Purpose:		Attempts to find the part based only on the given name.
//				This method can only find parts in the LDraw folder; it returns 
//				nil if fed an MPD submodel name.
//
//				NOT THREAD SAFE!
//
// Notes:		The part is looked up by the name specified in the part command. 
//				For regular parts and primitives, this is simply the filename 
//				as found in LDraw/parts or LDraw/p. But for subparts found in 
//				LDraw/parts/s, the filename is "s\partname.dat". (Same goes for 
//				LDraw/p/48.) This icky inconsistency is handled in 
//				-pathForFileName:.
//
//==============================================================================
- (LDrawModel *)modelForName:(NSString *) imageName
{
	// Has it already been parsed? A part whose file changed is still returned,
	// so documents draw it until all changed parts are read.
	LDrawModel *model = [self->loadedFiles objectForKey:imageName];

	// This case is only hit when a library part uses another library part, e.g.
	// a brick grabs a collection-of-studs part.
	if (model == nil)
		model = [self readModelNamed:imageName];

	return model;
	
} // end modelForName


//========== modelForPartInternal: =====================================================
//
// Purpose:		Returns the model to which this part refers. You can then ask
//				the model to draw itself.
//
//				NOT THREAD SAFE!
//
// Notes:		The part is looked up by the name specified in the part command. 
//				For regular parts and primitives, this is simply the filename 
//				as found in LDraw/parts or LDraw/p. But for subparts found in 
//				LDraw/parts/s, the filename is "s\partname.dat". (Same goes for 
//				LDraw/p/48.) This icky inconsistency is handled in 
//				-pathForFileName:.
//
//				This has been marked "internal" because the API is now only used
//				_within_ the part library, not by public clients.
//
//==============================================================================
- (LDrawModel *)modelForPartInternal:(LDrawPart *) part
{
	NSString	*imageName	= [part referenceName];
	LDrawModel	*model		= nil;
	
	// Try to get a live link if we have parsed this part off disk already.
	// Ben sez: This routine is currently authorized to load on demand, but 
	// I never see that code run and I don't think it is supposed to.
	model = [self modelForName:imageName];
	
	if (model == nil) {
		// We didn't find it in the LDraw folder. Hopefully this is a reference 
		// to another model in an MPD file. 
		model = [part referencedMPDSubmodel];
	}
	
	return model;
	
} // end modelForPartInternal:


//========== modelForNameThreadSafe: ==========================================
//
// Purpose:		Returns the model to which this part name refers from the 
//				already-loaded cache. Does not read from disk.
//
//==============================================================================
- (LDrawModel *)modelForNameThreadSafe:(NSString *)imageName
{
	return [self->loadedFiles objectForKey:imageName];
}


#pragma mark -
#pragma mark REFRESHING
#pragma mark -

//========== markPartsWhoseFilesChangedWithCompletionHandler: ==================
//
// Purpose:		Marks each loaded part that would now be read from another file,
//				and each loaded part that uses one, however deep. The files are
//				checked on a background queue, against a copy of the paths.
//
// Notes:		The handler runs on the main queue with every marked part,
//				including ones marked before and not read yet. Marked parts stay
//				loaded until they are read again or dropped.
//
//==============================================================================
- (void)markPartsWhoseFilesChangedWithCompletionHandler:(void (^)(NSSet<NSString *> *partNames))handler
{
	NSDictionary	*paths		= [self->loadedPaths copy];
	NSDictionary	*uses		= [self->usedPartNames copy];
	LDrawPaths		*settings	= [[LDrawPaths sharedPaths] copy];

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSSet *changed = [[self class] partNamesWhoseFilesChanged:paths uses:uses paths:settings];

		// The users are found from the parts loaded now, since a part read
		// meanwhile may use a changed one.
		dispatch_async(dispatch_get_main_queue(), ^{
			[self->staleNames unionSet:[[self class] partNamesUsingPartNames:changed uses:self->usedPartNames]];
			handler([self->staleNames copy]);
		});
	});

} // end markPartsWhoseFilesChangedWithCompletionHandler:


//========== freshModelForName: ================================================
//
// Purpose:		The part, read again first when it is marked or not loaded.
//
//==============================================================================
- (LDrawModel *)freshModelForName:(NSString *)partName
{
	[self loadModelForName:partName inGroup:NULL];
	return [self->loadedFiles objectForKey:partName];

} // end freshModelForName:


//========== dropStaleParts ====================================================
//
// Purpose:		Drops the marked parts that were not read again, so they are
//				read the next time they are asked for.
//
//==============================================================================
- (void)dropStaleParts
{
	[self forgetPartNames:[self->staleNames allObjects]];
	[self->staleNames removeAllObjects];

} // end dropStaleParts


//========== forgetPartNames: ==================================================
//
// Purpose:		Removes the parts and what is recorded about them.
//
//==============================================================================
- (void)forgetPartNames:(NSArray<NSString *> *)partNames
{
	[self->loadedFiles removeObjectsForKeys:partNames];
	[self->usedPartNames removeObjectsForKeys:partNames];
	[self->loadedPaths removeObjectsForKeys:partNames];

} // end forgetPartNames:


//---------- partNamesWhoseFilesChanged:uses:paths: ------------------[static]--
//
// Purpose:		The loaded parts that paths now finds in another file, and the
//				used parts that were missing and are now found.
//
//------------------------------------------------------------------------------
+ (NSSet<NSString *> *)partNamesWhoseFilesChanged:(NSDictionary<NSString *, NSString *> *)loadedPaths
											 uses:(NSDictionary<NSString *, NSSet<NSString *> *> *)uses
											paths:(LDrawPaths *)paths
{
	NSMutableSet<NSString *>	*changed	= [NSMutableSet set];
	NSMutableSet<NSString *>	*missing	= [NSMutableSet set];

	[loadedPaths enumerateKeysAndObjectsUsingBlock:^(NSString *partName, NSString *path, BOOL *stop) {
		if ([path isEqualToString:[paths pathForPartName:partName]] == NO)
			[changed addObject:partName];
	}];

	for (NSSet<NSString *> *usedNames in [uses objectEnumerator])
		[missing unionSet:usedNames];
	[missing minusSet:[NSSet setWithArray:[loadedPaths allKeys]]];

	for (NSString *partName in missing)
	{
		if ([paths pathForPartName:partName] != nil)
			[changed addObject:partName];
	}

	return changed;

} // end partNamesWhoseFilesChanged:uses:paths:


//---------- partNamesUsingPartNames:uses: ---------------------------[static]--
//
// Purpose:		The given names, and each name in uses that uses one of them,
//				however deep. uses maps a part to the names its file uses.
//
//------------------------------------------------------------------------------
+ (NSSet<NSString *> *)partNamesUsingPartNames:(NSSet<NSString *> *)partNames
										  uses:(NSDictionary<NSString *, NSSet<NSString *> *> *)uses
{
	NSMutableDictionary<NSString *, NSMutableArray<NSString *> *>	*users	= [NSMutableDictionary dictionary];
	NSMutableSet<NSString *>										*found	= [partNames mutableCopy];
	NSMutableArray<NSString *>										*queue	= [[partNames allObjects] mutableCopy];

	[uses enumerateKeysAndObjectsUsingBlock:^(NSString *user, NSSet<NSString *> *usedNames, BOOL *stop) {
		for (NSString *used in usedNames)
		{
			if (users[used] == nil)
				users[used] = [NSMutableArray array];
			[users[used] addObject:user];
		}
	}];

	while ([queue count] > 0)
	{
		NSString *partName = [queue lastObject];

		[queue removeLastObject];
		for (NSString *user in users[partName])
		{
			if ([found containsObject:user] == NO)
			{
				[found addObject:user];
				[queue addObject:user];
			}
		}
	}

	return found;

} // end partNamesUsingPartNames:uses:


#pragma mark -
#pragma mark UTILITIES
#pragma mark -

//========== descriptionForPart: ===============================================
//
// Purpose:		Returns the description of the given part based on its name.
//
//==============================================================================
- (NSString *)descriptionForPart:(LDrawPart *)part
{
	// Look up the verbose part description in the scanned part catalog.
	NSDictionary	*partList			= [self->partCatalog	objectForKey:PARTS_LIST_KEY];
	NSDictionary	*partRecord			= [partList				objectForKey:[part referenceName]];
	NSString		*partDescription	= [partRecord			objectForKey:PART_NAME_KEY];
	
	// Maybe it's an MPD reference?
	if (partDescription == nil)
	{
		partDescription = [[part referencedMPDSubmodel] browsingDescription];
	}
	
	// If the part STILL isn't known, all we can really do is just display the 
	// number. 
	if (partDescription == nil)
	{
		partDescription = [part displayName];
	}
	
	return partDescription;
	
} // end descriptionForPart:


//========== descriptionForPartName: ===========================================
//
// Purpose:		Returns the description associated with the given part name. 
//				For example, passing "3001.dat" returns "Brick 2 x 4".
//				If the name isn't known to the Part Library, we just return name.
//
// Note:		If you have a reference to the LDrawPart itself, you should pass 
//				it to -descriptionForPart instead.
//
//==============================================================================
- (NSString *)descriptionForPartName:(NSString *)name
{
	// Look up the verbose part description in the scanned part catalog.
	NSDictionary	*partList			= [self->partCatalog	objectForKey:PARTS_LIST_KEY];
	NSDictionary	*partRecord			= [partList				objectForKey:name];
	NSString		*partDescription	= [partRecord			objectForKey:PART_NAME_KEY];
	// If the part isn't known, all we can really do is just display the number.
	if (partDescription == nil)
		partDescription = name;
	
	return partDescription;
	
} // end descriptionForPartName:


//========== readImageAtPath: ==================================================
//
// Purpose:		Parses the model found at the given path, adds it to the list of 
//				loaded parts, and returns the model.
//
// Notes:		The model is returned from the method if asynchronous is NO.
//				Otherwise, returns nil and passes the completed model via the 
//				block instead. 
//
//==============================================================================
- (CGImageRef)readImageAtPath:(NSString *)imagePath
			   asynchronously:(BOOL)asynchronous
			completionHandler:(void (^)(CGImageRef))completionBlock
{
	(void)asynchronous;
	(void)completionBlock;
	return [LDrawUtilities imageAtPath:imagePath];
	
} // end readImageAtPath:


//========== readModelNamed: ===================================================
//
// Purpose:		Reads, flattens and keeps the library part of the given name.
//				Records its file and the names of the parts it uses, read
//				before flattening.
//
// Returns:		The model, or nil when no file has the part. Then a part kept
//				from an old file is dropped.
//
//==============================================================================
- (LDrawModel *)readModelNamed:(NSString *)partName
{
	NSString		*partPath	= [[LDrawPaths sharedPaths] pathForPartName:partName];
	NSString		*contents	= nil;
	NSArray			*lines		= nil;
	LDrawFile		*parsedFile	= nil;
	LDrawModel		*model		= nil;
	NSMutableSet	*used		= [NSMutableSet set];

	// Unmarked first, so a file that uses itself is not read again.
	[self->staleNames removeObject:partName];

	if (partPath == nil)
	{
		[self forgetPartNames:@[partName]];
		return nil;
	}

	contents	= [LDrawUtilities stringFromFile:partPath];
	lines		= [contents separateByLine];
	parsedFile	= [[LDrawFile alloc] initWithLines:lines
										   inRange:NSMakeRange(0, [lines count])
									   parentGroup:NULL];

	for (LDrawDirective *directive in [parsedFile allEnclosedElements])
	{
		if ([directive isKindOfClass:[LDrawPart class]])
			[used addObject:[(LDrawPart *)directive referenceName]];
	}

	[parsedFile optimizeStructure];
	model = [[parsedFile submodels] firstObject];
	// We are "leaking" the enclosing file, but returning an internal model 
	// without disconnecting it from its file is pretty dodgy and it would 
	// be easy to code a bug in.

	if (model != nil)
	{
		[self->loadedFiles setObject:model forKey:partName];
		[self->usedPartNames setObject:[used copy] forKey:partName];
		[self->loadedPaths setObject:partPath forKey:partName];
	}
	else
		[self forgetPartNames:@[partName]];

	return model;

} // end readModelNamed:


@end
