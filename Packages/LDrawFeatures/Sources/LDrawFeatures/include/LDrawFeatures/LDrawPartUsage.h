//==============================================================================
//
//  File:       LDrawPartUsage.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LDrawColor.h>

@class LDrawFile;
@class LDrawPart;

NS_ASSUME_NONNULL_BEGIN

/// What one used copy is.
typedef NS_ENUM(NSInteger, LDrawPartUsageKind)
{
	/// A part from the library, or a submodel that is really a part.
	LDrawPartUsageKindPart			= 0,

	/// What a `PLI BEGIN SUB` lists in place of the parts inside it.
	LDrawPartUsageKindSubstitute	= 1,

	/// An LSynth hose or band, which matches no single LEGO part.
	LDrawPartUsageKindSynthesized	= 2,

	/// A reference the library does not have.
	LDrawPartUsageKindMissing		= 3,

	/// A model from another file next to this one. Its parts belong to that
	/// file, so they are not walked here.
	LDrawPartUsageKindPeerFile		= 4
};


//------------------------------------------------------------------------------
///
/// @class      LDrawPartUsageCopy
///
/// @abstract   One physical part a model uses.
///
//------------------------------------------------------------------------------
@interface LDrawPartUsageCopy : NSObject

/// Lowercase, e.g. "3001.dat". A substitute that names an `.ldr` or `.mpd`
/// file is named as a `.dat`, since a LEGO part goes by its number. An LSynth
/// copy is named by its type.
@property (nonatomic, readonly, copy) NSString *partName;

/// The color it is built in, after color 16 takes the color of the reference
/// that brings it in. Still `LDrawCurrentColor` when nothing gives one.
@property (nonatomic, readonly) LDrawColorT colorCode;

@property (nonatomic, readonly) LDrawPartUsageKind kind;

/// Whether the copy is a LEGO part the limit can check: a part, a substitute,
/// or a part the library does not have, which goes by its name. Every other
/// kind has no data.
@property (nonatomic, readonly) BOOL isLEGOPart;

/// The directives that stand for this copy: the part itself, or the parts
/// inside a SUB range. Empty for LSynth. A part inside a submodel placed more
/// than once stands for a copy each time.
@property (nonatomic, readonly, copy) NSArray<LDrawPart *> *parts;

/// NO for a part in a submodel nothing places: it is checked, but does not
/// count toward what the model uses.
@property (nonatomic, readonly) BOOL isCounted;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawPartUsage
///
/// @abstract   Every part a model uses, in the order it is built.
///
/// @discussion The walk starts at the file's first model. A submodel is walked
///             where it is placed, once for each time, so a submodel placed
///             three times uses its parts three times. Then the models nothing
///             places are walked too, their parts not counted.
///
///             Hidden parts and parts in removed groups count: hiding is a
///             view, and a removed group was built in an earlier step. Parts
///             inside `PLI BEGIN IGN` and `PART BEGIN IGN` do not count, and a
///             `PLI BEGIN SUB` counts its substitute instead of what it holds,
///             as LPub3D's bill of materials does. Primitives and subparts
///             are not parts.
///
//------------------------------------------------------------------------------
@interface LDrawPartUsage : NSObject

/// Walks every model of the file.
+ (instancetype) usageOfFile:(LDrawFile *)file NS_SWIFT_NAME(init(file:));

/// The copies in build order, then those of the models nothing places.
@property (nonatomic, readonly, copy) NSArray<LDrawPartUsageCopy *> *copies;

@end

NS_ASSUME_NONNULL_END
