//==============================================================================
//
//  File:       LDrawLocalization.h
//  Package:    LDrawCore
//
//  Purpose:    Looks up display strings from a host-provided strings table.
//
//  Info:       The host sets the strings bundle (usually the app main bundle)
//              at launch. This class does not call NSLocalizedString, which
//              would always use the app process table.
//
//  Created by Sergey Slobodenyuk on 2026-09-01.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawLocalization
///
/// @abstract   Looks up display strings from a host-provided strings table.
///
//------------------------------------------------------------------------------
@interface LDrawLocalization : NSObject

/// Host Localizable.strings table. Nil means stringForKey: returns the key.
+ (nullable NSBundle *)stringsBundle;
+ (void)setStringsBundle:(nullable NSBundle *)bundle;

/// localizedStringForKey:value:table: on the strings bundle. Returns key
/// when no bundle is installed or the key is missing.
+ (NSString *)stringForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
