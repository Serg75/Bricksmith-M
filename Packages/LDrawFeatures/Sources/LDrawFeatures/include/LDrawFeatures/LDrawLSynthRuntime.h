//==============================================================================
//
//  File:       LDrawLSynthRuntime.h
//  Package:    LDrawFeatures
//
//  Purpose:    NSUserDefaults-backed LSynth runtime: lsynthcp path, custom
//              config file, and selection-tint settings.
//
//  Info:       The host passes a defaults store and the bundled lsynthcp path
//              (usually +bundledExecutablePathInBundle:). Live preference
//              changes are visible because this object reads the store on each
//              query. LDrawCore does not look up mainBundle or
//              standardUserDefaults.
//
//  Created by Sergey Slobodenyuk on 2026-09-01.
//
//==============================================================================

#import <Foundation/Foundation.h>
#import <LDrawCore/LDrawLSynthRuntimeSource.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawLSynthRuntime
///
/// @abstract   NSUserDefaults-backed LSynth executable/config paths and
///             selection-tint settings for LDrawLSynthRuntimeSource.
///
//------------------------------------------------------------------------------
@interface LDrawLSynthRuntime : NSObject <LDrawLSynthRuntimeSource>

/// Bundled lsynthcp auxiliary executable, or nil if the bundle has none.
+ (nullable NSString *)bundledExecutablePathInBundle:(NSBundle *)bundle;

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults
			 bundledExecutablePath:(nullable NSString *)bundledPath;

@end

NS_ASSUME_NONNULL_END
