//==============================================================================
//
//  File:       LDrawPartLibrary.h
//  Package:    LDrawCore
//
//  Purpose:    This is the centralized repository for obtaining information
//              about the contents of the LDraw folder.
//
//  Created by Allen Smith on 3/12/05.
//  Copyright 2005. All rights reserved.
//
//==============================================================================

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#import <LDrawCore/LDrawColorLibrary.h>

@class LDrawDirective;
@class LDrawModel;
@class LDrawPart;
@class LDrawTexture;
@protocol LDrawPartLibraryDelegate;

// The part catalog was regenerated from disk.
// Object is the new catalog. No userInfo.
extern NSString *LDrawPartLibraryDidChangeNotification;

// Catalog info keys
extern NSString	*PARTS_CATALOG_KEY;
extern NSString *PART_NUMBER_KEY;
extern NSString *PART_NAME_KEY;
extern NSString *PART_CATEGORY_KEY;
extern NSString *PART_KEYWORDS_KEY;
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
	NSMutableArray          *favorites;					// parts names in the "Favorites" pseduocategory
	NSMutableDictionary     *loadedFiles;				// list of LDrawFiles which have been read off disk.
	NSMutableDictionary		*loadedImages;
	NSMutableDictionary		*optimizedTextures;
	NSMutableDictionary     *optimizedRepresentations;	// access stored vertex objects by part name, then color.
	dispatch_queue_t        catalogAccessQueue;			// serial queue to mutex changes to the part catalog
	NSMutableDictionary     *parsingGroups;				// arrays of dispatch_group_t's which have requested each file currently being parsed
}

// Shared renderer instance. Renderer packages (LDrawRenderMetal,
// LDrawRenderOpenGL) call +registerSharedPartLibrary: at +load time with the
// concrete subclass singleton; model and feature code calls +sharedPartLibrary
// without knowing which renderer is active.
+ (instancetype)sharedPartLibrary;
+ (void)registerSharedPartLibrary:(LDrawPartLibrary *)library;

// Accessors
- (NSArray *)allPartCatalogRecords;
- (NSArray *)categories;
- (NSArray *)categoryHierarchy;
- (NSString *)displayNameForCategory:(NSString *)categoryName;
- (NSArray *)favoritePartNames;
- (NSArray *)favoritePartCatalogRecords;
- (NSArray *)partCatalogRecordsInCategory:(NSString *)category;
- (NSString *)categoryForPartName:(NSString *)partName;

- (void)setDelegate:(id<LDrawPartLibraryDelegate>)delegateIn;
- (void)setFavorites:(NSArray *)favoritesIn;
- (void)setPartCatalog:(NSDictionary *)newCatalog;

// Actions
- (BOOL)load;
- (void)reloadPartsWithMaxLoadCountHandler:(void (^)(NSUInteger maxPartCount))maxLoadCountHandler
				  progressIncrementHandler:(void (^)(void))progressIncrementHandler
						 completionHandler:(void (^)(BOOL success))completionHandler;

// Favorites
- (void)addPartNameToFavorites:(NSString *)partName;
- (void)removePartNameFromFavorites:(NSString *)partName;
- (void)saveFavoritesToUserDefaults;

// Finding Parts
- (void)loadImageForName:(NSString *)imageName inGroup:(dispatch_group_t)parentGroup;
- (void)loadModelForName:(NSString *)name inGroup:(dispatch_group_t)parentGroup;
- (CGImageRef)imageForTextureName:(NSString *)imageName;
- (CGImageRef)imageForTexture:(LDrawTexture *)texture;
- (CGImageRef)imageFromNeighboringFileForTexture:(LDrawTexture *)texture;
- (LDrawModel *)modelForName:(NSString *) partName;
- (LDrawModel *)modelForNameThreadSafe:(NSString *) partName;

- (LDrawDirective *)optimizedDrawableForPart:(LDrawPart *) part color:(LDrawColor *)color;

// Utilites
// Redraws a texture image into a power-of-two pixel buffer in the one format
// both Metal and OpenGL upload. The caller owns the returned buffer.
+ (uint8_t *)copyPowerOfTwoPixelsForImage:(CGImageRef)image size:(CGSize *)outSize;

- (NSString *)descriptionForPart:(LDrawPart *)part;
- (NSString *)descriptionForPartName:(NSString *)name;
- (CGImageRef)readImageAtPath:(NSString *)imagePath
			   asynchronously:(BOOL)asynchronous
			completionHandler:(void (^)(CGImageRef))completionBlock;
- (LDrawModel *)readModelAtPath:(NSString *)partPath
				 asynchronously:(BOOL)asynchronous
			  completionHandler:(void (^)(LDrawModel *))completionBlock;

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
