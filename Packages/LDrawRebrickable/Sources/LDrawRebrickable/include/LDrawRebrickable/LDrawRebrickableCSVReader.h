//==============================================================================
//
//  File:       LDrawRebrickableCSVReader.h
//  Package:    LDrawRebrickable
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Errors of the LDrawRebrickable package.
extern NSString * const LDrawRebrickableErrorDomain;

typedef NS_ERROR_ENUM(LDrawRebrickableErrorDomain, LDrawRebrickableError)
{
	/// A file could not be read, or did not inflate.
	LDrawRebrickableErrorUnreadableFile		= 1,

	/// A file lacks a column it needs.
	LDrawRebrickableErrorMissingColumn		= 2,

	/// The API refused the key.
	LDrawRebrickableErrorBadKey				= 3,

	/// The API has no such set or part.
	LDrawRebrickableErrorNotFound			= 4,

	/// The API kept asking to slow down.
	LDrawRebrickableErrorTooManyRequests	= 5,

	/// The server answered with something unexpected.
	LDrawRebrickableErrorBadResponse		= 6,

	/// The work was cancelled.
	LDrawRebrickableErrorCancelled			= 7
};


//------------------------------------------------------------------------------
///
/// @class      LDrawRebrickableCSVReader
///
/// @abstract   Reads a CSV file of Rebrickable's downloads a row at a time,
///             gzipped or not.
///
/// @discussion The file is inflated and read in pieces, so a file of a million
///             rows never sits in memory whole. Quoted fields may hold commas,
///             doubled quotes and line breaks. The first row names the
///             columns; look them up by name, since Rebrickable adds columns
///             now and then.
///
//------------------------------------------------------------------------------
@interface LDrawRebrickableCSVReader : NSObject

/// Reads the file's first row. Nil, with an error, when the file cannot be
/// read or has no rows.
- (nullable instancetype) initWithURL:(NSURL *)url error:(NSError **)error NS_DESIGNATED_INITIALIZER;

- (instancetype) init NS_UNAVAILABLE;

@property (nonatomic, readonly, copy) NSArray<NSString *> *columnNames;

/// The column's index, or `NSNotFound`.
- (NSUInteger) indexOfColumn:(NSString *)name;

/// The indexes of these columns, in order. Nil, with an error, when one is
/// missing.
- (nullable NSArray<NSNumber *> *) indexesOfColumns:(NSArray<NSString *> *)names error:(NSError **)error;

/// The highest of these column indexes, so a row with more fields than that has
/// them all. 0 for none.
+ (NSUInteger) lastIndexOfColumns:(nullable NSArray<NSNumber *> *)indexes;

/// Calls the block once for each row after the first. A row may have fewer
/// fields than the first row; check the count. Returns NO, with an error,
/// when the file stops reading partway.
- (BOOL) enumerateRowsUsingBlock:(void (NS_NOESCAPE ^)(NSArray<NSString *> *fields, BOOL *stop))block
						   error:(NSError **)error NS_SWIFT_NAME(enumerateRows(_:));

@end

NS_ASSUME_NONNULL_END
