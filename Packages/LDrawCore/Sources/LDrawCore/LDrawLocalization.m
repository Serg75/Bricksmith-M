//==============================================================================
//
//  File:       LDrawLocalization.m
//  Package:    LDrawCore
//
//  Purpose:    Looks up display strings from a host-provided strings table.
//
//  Created by Sergey Slobodenyuk on 2026-09-01.
//
//==============================================================================

#import <LDrawCore/LDrawLocalization.h>


@implementation LDrawLocalization

static NSBundle *localizationStringsBundle = nil;


//---------- stringsBundle -------------------------------------------[static]--
//
// Purpose:		Host Localizable.strings table, or nil if none is installed.
//
//------------------------------------------------------------------------------
+ (NSBundle *)stringsBundle
{
	return localizationStringsBundle;
}


//---------- setStringsBundle: ---------------------------------------[static]--
//
// Purpose:		Install the host’s strings table. Pass the app main bundle.
//				Nil makes stringForKey: return the key unchanged.
//
//------------------------------------------------------------------------------
+ (void)setStringsBundle:(NSBundle *)bundle
{
	localizationStringsBundle = bundle;
}


//---------- stringForKey: -------------------------------------------[static]--
//
// Purpose:		Look up a Localizable.strings entry. Missing keys and a missing
//				bundle both yield the key itself, matching NSLocalizedString
//				when the table has no translation.
//
//------------------------------------------------------------------------------
+ (NSString *)stringForKey:(NSString *)key
{
	NSBundle *bundle = localizationStringsBundle;
	if (bundle == nil)
		return key;
	return [bundle localizedStringForKey:key value:key table:nil];
}

@end
