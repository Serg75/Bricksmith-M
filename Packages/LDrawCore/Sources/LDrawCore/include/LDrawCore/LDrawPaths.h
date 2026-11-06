//==============================================================================
//
//  File:       LDrawPaths.h
//  Package:    LDrawCore
//
//  Purpose:    Looks up LDraw-related file locations.
//
//  Info:       The host sets the preferred LDraw folder, the bundled unofficial
//              LDraw tree, the overrides folder, and the bundled ldconfig path.
//              Search for an LDraw folder takes the application path. This
//              class does not look up the app main bundle or
//              standardUserDefaults.
//
//              All methods are safe to call from any thread. That matters for
//              +sharedPaths, whose paths the host can change (from Preferences,
//              on the main thread) while background part loads and catalog
//              scans are reading them. Each call still reads the paths as they
//              stand at that moment; a caller that needs a stable view across
//              several lookups should work on a copy.
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

	/// The user's folder of parts that replace library parts of the same name.
	/// It has the LDraw folder's layout, without Unofficial.
	LDrawUserOverrides		= 4,

};

/// Which version of a part is drawn. LDraw keeps 48-segment primitives in
/// p/48 and 8-segment ones in p/8, under the primitives' own names.
typedef NS_ENUM(NSInteger, LDrawResolution)
{
	LDrawResolutionNormal	= 0,
	LDrawResolutionLow		= 1,
	LDrawResolutionHigh		= 2,
};


NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawPaths
///
/// @abstract   Looks up LDraw-related file locations.
///
//------------------------------------------------------------------------------
@interface LDrawPaths : NSObject <NSCopying>

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
/// The folder whose parts win over the library's. Nil for none.
- (nullable NSString *)overridesPath;
- (void)setOverridesPath:(nullable NSString *)pathIn;
/// Whether pathForPartName: uses the overrides folder. Turning it off keeps the
/// path. YES at first. Setting it, or the resolution, reads the "48" and "8"
/// folders again.
- (BOOL)overridesEnabled;
- (void)setOverridesEnabled:(BOOL)flag;
/// High finds "48\x.dat" in place of "x.dat" when it exists, Low "8\x.dat".
/// Normal at first, and for a value that is none of the three.
- (LDrawResolution)resolution;
- (void)setResolution:(LDrawResolution)newResolution;
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
/// The file found with or without the overrides folder, whether or not it is
/// turned off. The overrides folder comes before the library, and in each, the
/// resolution's version of the part comes before the part itself.
- (nullable NSString *)pathForPartName:(NSString *)partName usingOverrides:(BOOL)useOverrides;
/// The library's own file of the part as named: no overrides folder, and no
/// high or low version.
- (nullable NSString *)libraryPathForPartName:(NSString *)partName;
/// The part a high or low version is of, e.g. "s\x.dat" for "48\s\x.dat", or
/// nil when the name names no version.
+ (nullable NSString *)partNameWithoutResolution:(NSString *)partName;
- (nullable NSString *)pathForTextureName:(NSString *)imageName;
- (BOOL)validateLDrawFolder:(NSString *)folderPath;

/// Alert keys when validateLDrawFolder: fails. The host still localizes.
+ (NSString *)ldrawFolderChooserErrorMessageKey;
+ (NSString *)ldrawFolderChooserErrorInformativeKey;

@end

NS_ASSUME_NONNULL_END
