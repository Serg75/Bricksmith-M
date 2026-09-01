//==============================================================================
//
//  File:       LDrawPaths.h
//  Package:    LDrawCore
//
//  Purpose:    Looks up LDraw-related file locations.
//
//  Info:       The host sets the preferred LDraw folder, the bundled unofficial
//              LDraw tree, and the bundled ldconfig path. Search for an LDraw
//              folder takes the application path. This class does not look up
//              the app main bundle or standardUserDefaults.
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

/// Bundled unofficial LDraw tree: <bundle>/Resources/LDraw.
+ (NSString *)internalLDrawPathInBundle:(NSBundle *)bundle;

/// Bundled LDConfig.ldr, or nil if the bundle has no such resource.
+ (nullable NSString *)bundledLdconfigPathInBundle:(NSBundle *)bundle;

// Accessors
- (nullable NSString *)internalLDrawPath;
- (void)setInternalLDrawPath:(nullable NSString *)pathIn;
- (nullable NSString *)preferredLDrawPath;
- (void)setPreferredLDrawPath:(nullable NSString *)pathIn;
- (void)setBundledLdconfigPath:(nullable NSString *)pathIn;

// Standard paths
- (NSString *)partsPathForDomain:(LDrawDomain)domain;
- (NSString *)primitivesPathForDomain:(LDrawDomain)domain;
- (NSString *)primitives48PathForDomain:(LDrawDomain)domain;
- (nullable NSString *)ldconfigPath;
- (nullable NSString *)MLCadIniPathWithBundledPath:(nullable NSString *)bundledPath;
- (NSString *)partCatalogPath;
- (NSString *)subpartsPathForDomain:(LDrawDomain)domain;

// Utilities
/// Looks for a valid LDraw folder: saved preferred path, then LDraw next to
/// the application (and its parent), then Application Support and Library.
/// applicationPath is the host app bundle path; nil skips those two candidates.
- (nullable NSString *)findLDrawPathRelativeToApplicationPath:(nullable NSString *)applicationPath;
- (nullable NSString *)pathForPartName:(NSString *)partName;
- (nullable NSString *)pathForTextureName:(NSString *)imageName;
- (BOOL)validateLDrawFolder:(NSString *)folderPath;

/// Alert keys when validateLDrawFolder: fails. The host still localizes.
+ (NSString *)ldrawFolderChooserErrorMessageKey;
+ (NSString *)ldrawFolderChooserErrorInformativeKey;

@end

NS_ASSUME_NONNULL_END
