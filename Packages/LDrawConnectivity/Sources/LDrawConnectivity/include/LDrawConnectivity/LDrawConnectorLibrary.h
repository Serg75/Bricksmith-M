//==============================================================================
//
//  File:       LDrawConnectorLibrary.h
//  Package:    LDrawConnectivity
//
//  Purpose:    Finds the connectors of library parts and caches them by part
//              name.
//
//  Notes:      Connectors come from the LDCad shadow library. A part also
//              gets the connectors of its subparts and primitives. A stud
//              primitive with no shadow file gives a male stud.
//
//  Created by Sergey Slobodenyuk on 2026-09-19.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawPaths.h>

#import <LDrawConnectivity/LDrawConnectorSet.h>

NS_ASSUME_NONNULL_BEGIN

@interface LDrawConnectorLibrary : NSObject

- (instancetype)initWithShadowLibraryPath:(nullable NSString *)shadowLibraryPath;

/// Reads the LDraw library through the given paths, or the shared ones when
/// none are given.
- (instancetype)initWithPaths:(nullable LDrawPaths *)paths
			shadowLibraryPath:(nullable NSString *)shadowLibraryPath NS_DESIGNATED_INITIALIZER;

/// The root of the LDCad shadow library, with "parts" and "p" folders like
/// the LDraw library's. Without it only male studs from stud primitives are
/// found. Setting it forgets every set built so far.
@property (nonatomic, copy, nullable) NSString *shadowLibraryPath;

/// The connectors of a part such as "3001.dat", built on first use. Nil when
/// the library cannot find the part.
- (nullable LDrawConnectorSet *)connectorSetForPartNamed:(NSString *)partName;

/// Forgets every set built so far, for when the part library changes.
- (void)removeAllConnectorSets;

@end

NS_ASSUME_NONNULL_END
