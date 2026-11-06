//==============================================================================
//
//  File:       LDrawPartLibrary.h
//  Package:    LDrawCore
//
//  Purpose:    This is the centralized repository for obtaining information
//              about the contents of the LDraw folder.
//
//  Info:       Newly scanned catalogs stamp a host-provided version string
//              (usually CFBundleVersion). This class does not look up the
//              app main bundle. Favorites stay in memory; add/remove notify
//              the delegate. The host writes FAVORITE_PARTS_KEY.
//
//  Created by Allen Smith on 3/12/05.
//  Copyright 2005. All rights reserved.
//
//==============================================================================

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#import <LDrawCore/LDrawColorLibrary.h>

@class LDrawModel;
@class LDrawPaths;
@class LDrawPart;
@class LDrawTexture;
@protocol LDrawPartLibraryDelegate;

NS_ASSUME_NONNULL_BEGIN

// The part catalog was regenerated from disk.
// Object is the new catalog. No userInfo.
extern NSString *LDrawPartLibraryDidChangeNotification;

// Catalog info keys
extern NSString	*PARTS_CATALOG_KEY;
extern NSString *PART_NUMBER_KEY;
extern NSString *PART_NAME_KEY;
extern NSString *PART_CATEGORY_KEY;
extern NSString *PART_KEYWORDS_KEY;
// YES in the record of a part only the overrides folder has.
extern NSString *PART_ONLY_IN_OVERRIDES_KEY;
extern NSString	*PARTS_LIST_KEY;
extern NSString	*VERSION_KEY;
extern NSString	*COMPATIBILITY_VERSION_KEY;

extern NSString	*CategoryNameKey;
extern NSString	*CategoryDisplayNameKey;
extern NSString	*CategoryChildrenKey;

extern NSString	*Category_All;
extern NSString	*Category_Favorites;
extern NSString	*Category_Alias;
extern NSString *Category_Moved;
extern NSString	*Category_Primitives;
extern NSString	*Category_Subparts;


//------------------------------------------------------------------------------
///
/// @class      LDrawPartLibrary
///
/// @abstract   This is the centralized repository for obtaining information
///             about the contents of the LDraw folder.
///
//------------------------------------------------------------------------------
@interface LDrawPartLibrary : NSObject
{
	id<LDrawPartLibraryDelegate> delegate;
	NSDictionary            *partCatalog;
	NSMutableArray          *favorites;					// parts names in the "Favorites" pseudocategory
	NSMutableDictionary     *loadedFiles;				// list of LDrawFiles which have been read off disk.
	NSMutableDictionary		*loadedImages;
	NSMutableDictionary		*optimizedTextures;
	NSMutableDictionary     *optimizedRepresentations;	// access stored vertex objects by part name, then color.
	NSString                *catalogVersion;			// host app version stamped into a newly built catalog
}

// Shared renderer instance. Renderer packages (LDrawRenderMetal,
// LDrawRenderOpenGL) call +registerSharedPartLibrary: at +load time with the
// concrete subclass singleton; model and feature code calls +sharedPartLibrary
// without knowing which renderer is active.
+ (instancetype)sharedPartLibrary;
+ (void)registerSharedPartLibrary:(LDrawPartLibrary *)library;

/// The shared library, or nil when none is registered. +sharedPartLibrary asserts instead.
+ (nullable instancetype)sharedPartLibraryIfRegistered;

// Accessors
// The record lists leave out the parts only the overrides folder has while it
// is turned off, and the category list the categories only those parts fill.
- (NSArray *)allPartCatalogRecords;
- (NSArray *)categories;
- (NSArray *)categoryHierarchy;
- (NSString *)displayNameForCategory:(NSString *)categoryName;
- (NSArray *)favoritePartNames;
- (NSArray *)favoritePartCatalogRecords;
- (NSArray *)partCatalogRecordsInCategory:(NSString *)category;
- (nullable NSString *)categoryForPartName:(NSString *)partName;

/// The catalog's record of the part, such as "3001.dat", or nil.
- (nullable NSDictionary *)partCatalogRecordForPartName:(NSString *)partName;

/// The records, without the parts only the overrides folder has when
/// `useOverrides` is NO.
+ (NSArray<NSDictionary *> *)partCatalogRecords:(NSArray<NSDictionary *> *)records
								 usingOverrides:(BOOL)useOverrides
	NS_SWIFT_NAME(partCatalogRecords(_:usingOverrides:));

/// The categories that one of the records is filed under, in their order.
+ (NSArray<NSString *> *)categories:(NSArray<NSString *> *)categories
					  usedByRecords:(NSArray<NSDictionary *> *)records
	NS_SWIFT_NAME(categories(_:usedBy:));

- (void)setDelegate:(nullable id<LDrawPartLibraryDelegate>)delegateIn;
- (void)setFavorites:(NSArray *)favoritesIn;
- (void)setPartCatalog:(NSDictionary *)newCatalog;

/// Host app version written into a newly scanned catalog. Nil falls back to
/// @"1.0". Does not change the on-disk catalog key name (Version).
- (nullable NSString *)catalogVersion;
- (void)setCatalogVersion:(nullable NSString *)version;

/// CFBundleVersion, else CFBundleShortVersionString, else @"1.0".
+ (NSString *)catalogVersionInBundle:(NSBundle *)bundle;

// Actions
- (BOOL)load;
/// Builds the part catalog again. It does not post LDrawPartLibraryReloaded:
/// the host does, after reading the parts whose files changed.
- (void)reloadPartsWithMaxLoadCountHandler:(nullable void (^)(NSUInteger maxPartCount))maxLoadCountHandler
				  progressIncrementHandler:(nullable void (^)(void))progressIncrementHandler
						 completionHandler:(nullable void (^)(BOOL success))completionHandler;

// Favorites
- (void)addPartNameToFavorites:(NSString *)partName;
- (void)removePartNameFromFavorites:(NSString *)partName;

// Finding Parts
- (void)loadImageForName:(NSString *)imageName inGroup:(nullable dispatch_group_t)parentGroup;
- (void)loadModelForName:(NSString *)name inGroup:(nullable dispatch_group_t)parentGroup;
- (nullable CGImageRef)imageForTextureName:(NSString *)imageName;
- (nullable CGImageRef)imageForTexture:(LDrawTexture *)texture;
- (nullable CGImageRef)imageFromNeighboringFileForTexture:(LDrawTexture *)texture;
- (nullable LDrawModel *)modelForName:(NSString *) partName;
- (nullable LDrawModel *)modelForNameThreadSafe:(NSString *) partName;

// Refreshing. Main thread only.
/// After a change to the paths, marks each loaded part that would now be read
/// from another file, and each one that uses such a part. The files are checked
/// on a background queue. The handler runs on the main queue with every marked
/// part, including ones marked before. Marked parts stay loaded, so documents
/// can draw them, until they are read again or dropped.
- (void)markPartsWhoseFilesChangedWithCompletionHandler:(void (^)(NSSet<NSString *> *partNames))handler;
/// The part, read again first when it is marked or not loaded. Nil when no
/// file has it.
- (nullable LDrawModel *)freshModelForName:(NSString *)partName;
/// Drops the marked parts that were not read again, so they are read the next
/// time they are asked for.
- (void)dropStaleParts;
/// The parts in loadedPaths that paths finds in another file now, and the parts
/// named in uses that were missing and are found now. loadedPaths maps a part
/// to its file, and uses maps a part to the names its file uses.
+ (NSSet<NSString *> *)partNamesWhoseFilesChanged:(NSDictionary<NSString *, NSString *> *)loadedPaths
											 uses:(NSDictionary<NSString *, NSSet<NSString *> *> *)uses
											paths:(LDrawPaths *)paths
	NS_SWIFT_NAME(partNamesWhoseFilesChanged(_:uses:paths:));
/// The names, and each part in uses that uses one of them, however deep.
+ (NSSet<NSString *> *)partNamesUsingPartNames:(NSSet<NSString *> *)partNames
										  uses:(NSDictionary<NSString *, NSSet<NSString *> *> *)uses
	NS_SWIFT_NAME(partNames(using:uses:));

// Utilites
// Redraws a texture image into a power-of-two pixel buffer in the one format
// both Metal and OpenGL upload. The caller owns the returned buffer.
+ (uint8_t *)copyPowerOfTwoPixelsForImage:(CGImageRef)image size:(CGSize *)outSize;

- (NSString *)descriptionForPart:(LDrawPart *)part;
- (NSString *)descriptionForPartName:(NSString *)name;
- (nullable CGImageRef)readImageAtPath:(nullable NSString *)imagePath
			   asynchronously:(BOOL)asynchronous
			completionHandler:(nullable void (^)(CGImageRef _Nullable))completionBlock;

@end


//------------------------------------------------------------------------------
///
/// @protocol   LDrawPartLibraryDelegate
///
/// @abstract   Required callbacks when the part library’s favorites list
///             changes.
///
//------------------------------------------------------------------------------
@protocol LDrawPartLibraryDelegate

- (void)partLibrary:(LDrawPartLibrary *)partLibrary didChangeFavorites:(NSArray *)newFavorites;

@end

NS_ASSUME_NONNULL_END
