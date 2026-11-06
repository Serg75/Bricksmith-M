//==============================================================================
//
//  File:       LDrawPartOverridePresentation.h
//  Package:    LDrawFeatures
//
//  Purpose:    How a host shows the parts in the overrides folder, and which
//              of them it has reported as outdated.
//
//  Created by Sergey Slobodenyuk on 2026-11-06.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawPartOverride;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawPartOverridePresentation
///
/// @abstract   The text a host shows about the overrides folder, and the
///             record of the outdated overrides it has reported.
///
/// @discussion An override is outdated when the library's file of the part is
///             from a later release. Text is looked up through
///             LDrawLocalization, in the bundle the host names.
///
//------------------------------------------------------------------------------
@interface LDrawPartOverridePresentation : NSObject

/// The overrides the library has newer versions of, in the same order.
+ (NSArray<LDrawPartOverride *> *)outdatedOverrides:(NSArray<LDrawPartOverride *> *)overrides
	NS_SWIFT_NAME(outdated(_:));

/// The part's name and the release of each side, such as
/// "4592.dat: yours 2005-01, library 2022-01".
+ (NSString *)releasesOfOverride:(LDrawPartOverride *)override NS_SWIFT_NAME(releases(of:));

/// How many parts the folder has, and the names of the first outdated ones.
+ (NSString *)summaryOfOverrides:(NSArray<LDrawPartOverride *> *)overrides NS_SWIFT_NAME(summary(of:));

/// The releases of each outdated override, one per line, or nil for none.
+ (nullable NSString *)detailsOfOverrides:(NSArray<LDrawPartOverride *> *)overrides
	NS_SWIFT_NAME(details(of:));

/// The releases of the first `limit` outdated overrides, one per line, and
/// how many more there are.
+ (NSString *)listOfOutdatedOverrides:(NSArray<LDrawPartOverride *> *)outdated limit:(NSUInteger)limit
	NS_SWIFT_NAME(list(ofOutdated:limit:));

/// A side of a comparison: the file, and its release when the header names
/// one. Says the library lacks the part for nil.
+ (NSString *)noteForFileAtPath:(nullable NSString *)path NS_SWIFT_NAME(note(forFileAtPath:));

/// The parts that differ between the two sides of a comparison, in a line.
+ (NSString *)lineForChangedPartNames:(NSArray<NSString *> *)partNames NS_SWIFT_NAME(line(forChangedPartNames:));

/// Saves the outdated overrides as reported in PART_OVERRIDES_REPORTED_KEY.
/// Returns YES when one of them was not saved before. A later library release
/// of a part counts as not saved, so it is reported again. A saved part that is
/// not in `overrides` keeps its entry, so an unreadable folder clears nothing.
+ (BOOL)recordOutdatedOverrides:(NSArray<LDrawPartOverride *> *)overrides
					 inDefaults:(NSUserDefaults *)userDefaults NS_SWIFT_NAME(recordOutdated(_:in:));

@end

NS_ASSUME_NONNULL_END
