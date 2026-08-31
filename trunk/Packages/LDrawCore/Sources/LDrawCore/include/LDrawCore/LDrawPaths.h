//==============================================================================
//
//  File:       LDrawPaths.h
//  Package:    LDrawCore
//
//  Purpose:    Looks up LDraw-related file locations.
//
//  Modified:   05/03/2011 Allen Smith. Creation Date.
//
//==============================================================================

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, LDrawDomain)
{
	LDrawUserOfficial		= 0,
	LDrawUserUnofficial		= 1,
	LDrawInternalOfficial	= 2,
	LDrawInternalUnofficial	= 3,

};


NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawPaths
///
/// @abstract   Looks up LDraw-related file locations.
///
//------------------------------------------------------------------------------
@interface LDrawPaths : NSObject
{
	NSString	*preferredLDrawPath;
}

+ (LDrawPaths *)sharedPaths;

// Accessors
- (NSString *)internalLDrawPath;
- (nullable NSString *)preferredLDrawPath;
- (void)setPreferredLDrawPath:(nullable NSString *)pathIn;

// Standard paths
- (NSString *)partsPathForDomain:(LDrawDomain)domain;
- (NSString *)primitivesPathForDomain:(LDrawDomain)domain;
- (NSString *)primitives48PathForDomain:(LDrawDomain)domain;
- (NSString *)ldconfigPath;
- (NSString *)MLCadIniPath;
- (NSString *)partCatalogPath;
- (NSString *)subpartsPathForDomain:(LDrawDomain)domain;

// Utilities
- (nullable NSString *)findLDrawPath;
- (nullable NSString *)pathForPartName:(NSString *)partName;
- (nullable NSString *)pathForTextureName:(NSString *)imageName;
- (BOOL)validateLDrawFolder:(NSString *)folderPath;

/// Alert keys when validateLDrawFolder: fails. The host still localizes.
+ (NSString *)ldrawFolderChooserErrorMessageKey;
+ (NSString *)ldrawFolderChooserErrorInformativeKey;

@end

NS_ASSUME_NONNULL_END
