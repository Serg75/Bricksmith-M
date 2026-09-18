//==============================================================================
//
//  File:       LDrawStepPartListEdit.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-09-10.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LPubPliConstrain.h>

@class LDrawModel;
@class LDrawStep;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @enum       LDrawStepPartListEditKind
///
/// @abstract   What committing a resize turns out to mean for the document.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LDrawStepPartListEditKind) {
	/// The document already says this, so nothing is changed.
	LDrawStepPartListEditKindNone	= 0,
	LDrawStepPartListEditKindInsert	= 1,
	LDrawStepPartListEditKindUpdate	= 2,
	LDrawStepPartListEditKindRemove	= 3
};


//------------------------------------------------------------------------------
///
/// @class      LDrawStepPartListEdit
///
/// @abstract   Decides what a committed frame resize does to the document,
///             without doing it.
///
/// @discussion The host owns the undo manager and makes the change. A resize
///             updates the step's own line, the one that holds for this step
///             alone, and removes it when the size asked for is the one the
///             step would inherit. A line that carries on to later steps is
///             never changed.
///
//------------------------------------------------------------------------------
@interface LDrawStepPartListEdit : NSObject

@property (nonatomic, readonly) LDrawStepPartListEditKind kind;

/// The directive to insert, for `Insert`. Already carries the new value.
@property (nonatomic, readonly, nullable) LPubPliConstrain *directiveToInsert;

/// Where Insert puts the line: just after the step's last CONSTRAIN, else
/// first. A line above one of those would be overridden by it.
@property (nonatomic, readonly) NSUInteger insertIndex;

/// The directive in the step to change or delete, for `Update` and `Remove`.
@property (nonatomic, readonly, nullable) LPubPliConstrain *existingDirective;

/// The state to put the existing directive into, for `Update`. The scope is
/// always LOCAL, because a resize applies to this step only.
@property (nonatomic, readonly) LPubPliConstrainMode	targetMode;
@property (nonatomic, readonly) double					targetInches;

/// Undo action key; the host localizes it. Set and reset use different keys,
/// so the Edit menu says which one happened.
@property (nonatomic, readonly, copy) NSString *undoActionKey;

/// Whether the step is left with no line of its own on this axis. A host can
/// show the pin from this during a drag.
@property (nonatomic, readonly) BOOL resetsAxis;

/// The edit that pins one axis of a step's frame to a size.
///
/// `inheritedInches` is the size the step is pinned to with no directive of its
/// own, or 0 for none. Asking for that size gives a `Remove`, whatever the
/// step's own line pins.
+ (instancetype) editSettingAxis:(LPubPliAxis)axis
						toInches:(double)inches
						  inStep:(nullable LDrawStep *)step
				 inheritedInches:(double)inheritedInches
	NS_SWIFT_NAME(edit(settingAxis:toInches:inStep:inheritedInches:));

/// The edit a resize drag on the model's visible step would make if it ended
/// at this size, measured against the size the step inherits.
+ (instancetype) editForDraggingAxis:(LPubPliAxis)axis
							toInches:(double)inches
							 inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(edit(draggingAxis:toInches:inModel:));

/// The edit that removes the step's own pin on one axis.
+ (instancetype) editClearingAxis:(LPubPliAxis)axis
						   inStep:(nullable LDrawStep *)step
	NS_SWIFT_NAME(edit(clearingAxis:inStep:));

@end

NS_ASSUME_NONNULL_END
