//==============================================================================
//
//  File:       LDrawLibraryNewParts.h
//  Package:    LDrawLibraryUpdate
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawLibraryNewParts
///
/// @abstract   The parts an update added to an LDraw folder. A host keeps them
///             in its defaults until the next update.
///
//------------------------------------------------------------------------------
@interface LDrawLibraryNewParts : NSObject

- (instancetype) initWithPartNames:(NSArray<NSString *> *)partNames
				 releaseIdentifier:(NSString *)releaseIdentifier
						folderPath:(NSString *)folderPath NS_DESIGNATED_INITIALIZER;

/// The parts read back from a dictionaryRepresentation, or nil when the
/// dictionary is not one.
- (nullable instancetype) initWithDictionary:(nullable NSDictionary *)dictionary;
- (instancetype) init NS_UNAVAILABLE;

/// Such as "3001.dat".
@property (nonatomic, readonly, copy) NSArray<NSString *> *partNames;

/// The update that added them, such as "2026-11".
@property (nonatomic, readonly, copy) NSString *releaseIdentifier;

/// The LDraw folder they were added to.
@property (nonatomic, readonly, copy) NSString *folderPath;

/// The folder, the update and the part names, as property list values.
- (NSDictionary<NSString *, id> *) dictionaryRepresentation;

/// Whether the parts were added to the folder. One folder can be written
/// several ways, such as with a slash at the end.
- (BOOL) isOfFolderPath:(nullable NSString *)folderPath NS_SWIFT_NAME(isOf(folderPath:));

@end

NS_ASSUME_NONNULL_END
