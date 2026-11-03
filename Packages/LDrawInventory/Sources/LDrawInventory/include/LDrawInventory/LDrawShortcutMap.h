//==============================================================================
//
//  File:       LDrawShortcutMap.h
//  Package:    LDrawInventory
//
//  Created by Sergey Slobodenyuk on 2026-10-28.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawColor.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawShortcutPiece
///
/// @abstract   One part of an assembly, in its color.
///
//------------------------------------------------------------------------------
@interface LDrawShortcutPiece : NSObject

/// The part's file name, lowercase, e.g. "2429.dat".
@property (nonatomic, readonly, copy) NSString *partName;

/// Its color. 16 takes the color of the assembly.
@property (nonatomic, readonly) LDrawColorT colorCode;

/// Its color in an assembly of this color.
- (LDrawColorT) colorCodeInAssemblyColor:(LDrawColorT)assemblyColor;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawShortcutMap
///
/// @abstract   The parts an LDraw shortcut is made of, so an assembly and its
///             parts can be counted alike.
///
/// @discussion A shortcut is a part file marked "!LDRAW_ORG Shortcut", such as
///             a hinge made of its two halves, or minifigure hips and legs. A
///             part file "~Moved to" another is followed. Shortcuts inside a
///             shortcut are opened too, so the pieces are never shortcuts.
///
///             The map reads part files through the host's reader, each once,
///             and only up to the end of the header of a part that is not a
///             shortcut. A host can read every part on a background thread
///             first, then hand the map over. Use it on one thread at a time.
///
//------------------------------------------------------------------------------
@interface LDrawShortcutMap : NSObject

/// `reader` returns the text of a part file, given its name such as
/// "73983.dat", or nil when the library has no such part.
- (instancetype) initWithFileReader:(NSString * _Nullable (^)(NSString *partName))reader NS_DESIGNATED_INITIALIZER;
- (instancetype) init NS_UNAVAILABLE;

/// A map that reads the LDraw library's parts through `LDrawPaths`, only
/// those named in `partNames`, such as every part in the part catalog.
+ (instancetype) libraryMapWithPartNames:(NSSet<NSString *> *)partNames
	NS_SWIFT_NAME(library(partNames:));

/// Reads these parts now, so later lookups of them read no files. Can run on
/// a background thread before the map is handed over.
- (void) readPartsNamed:(NSSet<NSString *> *)partNames;

/// The pieces of a shortcut, in file order, a piece placed twice listed twice.
/// Nil for a part that is not a shortcut.
- (nullable NSArray<LDrawShortcutPiece *> *) piecesOfPartNamed:(NSString *)partName
	NS_SWIFT_NAME(pieces(ofPartNamed:));

/// Whether the library has the part, shortcut or not.
- (BOOL) hasPartNamed:(NSString *)partName NS_SWIFT_NAME(hasPart(named:));

@end

NS_ASSUME_NONNULL_END
