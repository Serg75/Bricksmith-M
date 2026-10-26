//==============================================================================
//
//  File:       LDrawInventoryPartsFile.h
//  Package:    LDrawInventory
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawInventoryItem;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const LDrawInventoryErrorDomain;

typedef NS_ERROR_ENUM(LDrawInventoryErrorDomain, LDrawInventoryError)
{
	/// The file could not be read as text.
	LDrawInventoryErrorUnreadableFile	= 1,

	/// The text is not a parts list this reader knows.
	LDrawInventoryErrorUnknownFormat	= 2
};


//------------------------------------------------------------------------------
///
/// @class      LDrawInventoryPartsFile
///
/// @abstract   Reads loose parts from a parts list file, for a combined
///             inventory.
///
/// @discussion Two formats are read:
///             - Bricksmith's piece count export: tab-separated quantity, LDraw
///               part, LDraw color and description, after a header line.
///             - A Rebrickable parts list in CSV, with Part, Color and Quantity
///               columns, and an optional Is Spare column.
///
///             The same part and color listed twice is one item, in the order
///             first listed.
///
//------------------------------------------------------------------------------
@interface LDrawInventoryPartsFile : NSObject

+ (nullable NSArray<LDrawInventoryItem *> *) itemsFromString:(NSString *)text
													   error:(NSError **)error NS_SWIFT_NAME(items(from:));

+ (nullable NSArray<LDrawInventoryItem *> *) itemsFromFileAtURL:(NSURL *)url
														  error:(NSError **)error NS_SWIFT_NAME(items(contentsOf:));

@end

NS_ASSUME_NONNULL_END
