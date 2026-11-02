//==============================================================================
//
//  File:       LDrawInventoryJSON.h
//  Package:    LDrawInventory
//
//  Purpose:    Reading values out of parsed JSON without trusting their types,
//              and reading and writing JSON files.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The version every file of the store is written with. A reader takes any
/// version and skips the keys it does not know.
extern const NSInteger LDrawInventoryFileVersion;

/// The value when it is a non-empty string, else nil.
NSString * _Nullable LDrawJSONString(id _Nullable value);

/// A whole number from a number or a string of digits, else the fallback. A
/// boolean is not a number.
NSInteger LDrawJSONInteger(id _Nullable value, NSInteger fallback);

/// The value when it is a boolean or a number, else the fallback.
BOOL LDrawJSONBool(id _Nullable value, BOOL fallback);

/// The value when it is an array, else nil.
NSArray * _Nullable LDrawJSONArray(id _Nullable value);

/// The value when it is a dictionary, else nil.
NSDictionary * _Nullable LDrawJSONDictionary(id _Nullable value);

/// A date written as an ISO 8601 string, or nil.
NSDate * _Nullable LDrawJSONDate(id _Nullable value);
NSString *LDrawJSONStringFromDate(NSDate *date);

/// Color links, Rebrickable color id → LDraw codes. An id may be a number or a
/// string, and a value one code or a list. Anything else, and a code listed
/// twice, is dropped.
NSDictionary<NSNumber *, NSArray<NSNumber *> *> *LDrawJSONColorLinks(id _Nullable value);

/// Color links for a JSON file, whose keys must be strings.
NSDictionary<NSString *, NSArray<NSNumber *> *> *LDrawJSONColorLinksObject(
	NSDictionary<NSNumber *, NSArray<NSNumber *> *> *links);

/// The top-level dictionary of a JSON file, or nil when the file is missing or
/// holds something else.
NSDictionary * _Nullable LDrawJSONReadFile(NSURL *url);

/// Writes a dictionary as JSON, atomically, making the folder first. A pretty
/// file, meant to be read, also has its keys sorted.
BOOL LDrawJSONWriteFile(NSDictionary *dictionary, NSURL *url, BOOL pretty, NSError **error);

NS_ASSUME_NONNULL_END
