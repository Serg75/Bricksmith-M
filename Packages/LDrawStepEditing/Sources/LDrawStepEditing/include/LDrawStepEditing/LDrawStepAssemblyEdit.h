//==============================================================================
//
//  File:       LDrawStepAssemblyEdit.h
//  Package:    LDrawStepEditing
//
//  Created by Sergey Slobodenyuk on 2026-10-20.
//
//==============================================================================

#import <Foundation/Foundation.h>
#import <LDrawCore/MatrixMath.h>

#import <LDrawCore/LPubPlacement.h>
#import <LDrawStepEditing/LDrawStepCalloutEdit.h>

@class LDrawModel;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @enum       LDrawStepAssemblyScope
///
/// @abstract   Which steps a change to the assembly is for.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LDrawStepAssemblyScope) {
	/// The step on display alone: LOCAL lines.
	LDrawStepAssemblyScopeStep			= 0,
	/// The step and the ones after it, until another line: lines with no
	/// scope, and ROTSTEP.
	LDrawStepAssemblyScopeLaterSteps	= 1,
	/// Every step: GLOBAL lines in the header of the file's first model.
	LDrawStepAssemblyScopeModel			= 2
};


//------------------------------------------------------------------------------
///
/// @enum       LDrawStepQuickTurn
///
/// @abstract   A turn of the parts from where they are, as instructions show
///             one with an arrow.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LDrawStepQuickTurn) {
	/// A quarter turn about the parts' own up axis. The side facing the
	/// viewer goes to the left, as a drag to the left turns it.
	LDrawStepQuickTurnLeft			= 0,
	/// A quarter turn the other way.
	LDrawStepQuickTurnRight			= 1,
	/// A half turn about the up axis, so the back faces the viewer.
	LDrawStepQuickTurnAround		= 2,
	/// A half turn about the front to back axis, so the bottom is on top.
	LDrawStepQuickTurnUpsideDown	= 3
};


//------------------------------------------------------------------------------
///
/// @class      LDrawStepAssemblyEdit
///
/// @abstract   Decides what a change to the visible step's assembly writes to
///             the document: its size, its place on the page, or its angle.
///             The place of the step's parts list too.
///
/// @discussion The host owns the undo manager and makes the change through
///             the same three calls a callout's edit uses. A value the step
///             would have anyway takes the step's own line out instead of
///             writing one.
///
///             The size is `ASSEM MODEL_SCALE`, the place the offset of
///             `ASSEM PLACEMENT`, as a share of the page. The angle is the
///             step's ROTSTEP. A turn takes the step's own `ASSEM
///             CAMERA_ANGLES` lines out. For the whole model only the `GLOBAL`
///             line in the header changes, as LPub3D writes it.
///
//------------------------------------------------------------------------------
@interface LDrawStepAssemblyEdit : NSObject

- (instancetype) init NS_UNAVAILABLE;

/// YES when the document already says this, and applying changes nothing.
@property (nonatomic, readonly) BOOL isEmpty;

/// Undo action key. The host localizes it.
@property (nonatomic, readonly, copy) NSString *undoActionKey;

/// Makes the change through a host: lines out first, then lines changed, then
/// lines in, then rotations. Returns NO when nothing was changed.
- (BOOL) applyWithHost:(id<LDrawStepCalloutEditHost>)host NS_SWIFT_NAME(apply(host:));

/// The edit that draws the assembly at `scale` times life size.
+ (instancetype) editSettingScale:(double)scale
							scope:(LDrawStepAssemblyScope)scope
						  inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(edit(settingScale:scope:inModel:));

/// The edit that moves the step by `offset` from where it is centered on the
/// page, as shares of the page. The placement's other words are kept.
+ (instancetype) editSettingOffset:(Point2)offset
							 scope:(LDrawStepAssemblyScope)scope
						   inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(edit(settingOffset:scope:inModel:));

/// The edit that shows the assembly at a viewport's viewing angle, in degrees.
/// A turn is a REL ROTSTEP on the step, and the step's own camera lines go.
/// For the step alone the next step gets back the rotation that held. Nil for
/// a turn of the whole model, which a ROTSTEP cannot say: the whole model takes
/// only the angle the step has, and writes nothing for it.
+ (nullable instancetype) editSettingViewingAngle:(Tuple3)angle
											scope:(LDrawStepAssemblyScope)scope
										  inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(edit(settingViewingAngle:scope:inModel:));

/// The same, writing the ROTSTEP with these numbers, in degrees, when they say
/// the turn, as typed ones do.
+ (nullable instancetype) editSettingViewingAngle:(Tuple3)angle
										 rotation:(Tuple3)rotation
											scope:(LDrawStepAssemblyScope)scope
										  inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(edit(settingViewingAngle:rotation:scope:inModel:));

/// What the visible step has without its own lines: the scale, and the
/// viewing angle in degrees. A ROTSTEP stays: it holds for later steps too.
+ (double) inheritedScaleInModel:(nullable LDrawModel *)model NS_SWIFT_NAME(inheritedScale(in:));
+ (Tuple3) inheritedViewingAngleInModel:(nullable LDrawModel *)model NS_SWIFT_NAME(inheritedViewingAngle(in:));

/// The viewing angle Reset Angle puts back, in degrees. For one step or later
/// steps it is the step without its own camera lines and ROTSTEP. Set at that
/// angle, the edit takes them out, and for one step the next step gets a copy
/// of the ROTSTEP, so later steps keep their rotation. The whole model leaves
/// the step's lines alone, so for it the reset is the angle the step has.
+ (Tuple3) resetViewingAngleForScope:(LDrawStepAssemblyScope)scope inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(resetViewingAngle(scope:in:));

/// The scale and the offset Reset puts back, by the same rule: what the step
/// has without its own lines, or for the whole model what it has. The offset
/// says NO for one step or later steps when no offset can say it.
+ (double) resetScaleForScope:(LDrawStepAssemblyScope)scope inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(resetScale(scope:in:));
+ (BOOL) getResetOffset:(Point2 *)offset
			   forScope:(LDrawStepAssemblyScope)scope
				inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(getResetOffset(_:scope:in:));

/// The offset the visible step has without its own placement line, as shares
/// of the page. NO when that line puts the step at another place before its
/// offset, which an offset from the step's own place cannot say.
+ (BOOL) getInheritedOffset:(Point2 *)offset inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(getInheritedOffset(_:in:));

/// The viewing angle of LPub3D's camera at these angles, looking at the parts
/// with no rotation, as a named view shows them.
+ (Tuple3) viewingAngleForLatitude:(double)latitude longitude:(double)longitude
	NS_SWIFT_NAME(viewingAngle(latitude:longitude:));

/// A viewing angle after a quick turn of the parts, in degrees.
+ (Tuple3) viewingAngle:(Tuple3)angle afterTurn:(LDrawStepQuickTurn)turn
	NS_SWIFT_NAME(viewingAngle(_:afterTurn:));

/// A viewing angle of the visible step as the REL ROTSTEP a turn writes, in
/// degrees: the rotation the camera in force looks through, without the step's
/// own camera lines. The numbers of the REL ROTSTEP in force come back when
/// they say the same turn, and with `preferred`, those numbers first.
+ (Tuple3) rotationForViewingAngle:(Tuple3)angle inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(rotation(forViewingAngle:inModel:));
+ (Tuple3) rotationForViewingAngle:(Tuple3)angle
						preferring:(Tuple3)preferred
						   inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(rotation(forViewingAngle:preferring:inModel:));

/// The viewing angle a REL ROTSTEP of the visible step gives, in degrees.
+ (Tuple3) viewingAngleForRotation:(Tuple3)rotation inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(viewingAngle(forRotation:inModel:));

/// The edits that place the visible step's parts list with a `PLI PLACEMENT`
/// line: at one of the page's nine places, moved by `offset` as shares of the
/// page, or outside the assembly on one of its sides. A line is always
/// written, since with none LPub3D puts the list beside the step number.
+ (instancetype) editPlacingListOnPageAt:(LPubPlacementPosition)position
								  offset:(Point2)offset
								   scope:(LDrawStepAssemblyScope)scope
								 inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(edit(placingListOnPageAt:offset:scope:inModel:));
+ (instancetype) editPlacingListBesideAssemblyAt:(LPubPlacementPosition)side
										   scope:(LDrawStepAssemblyScope)scope
										 inModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(edit(placingListBesideAssemblyAt:scope:inModel:));

/// The edit that takes the step's own `PLI PLACEMENT` lines out.
+ (instancetype) editResettingListPlacementInModel:(nullable LDrawModel *)model
	NS_SWIFT_NAME(edit(resettingListPlacementIn:));

/// Several edits made as one, under one undo name. Each must have been made
/// for the document as it is, and for a different value.
+ (instancetype) editCombiningEdits:(NSArray<LDrawStepAssemblyEdit *> *)edits NS_SWIFT_NAME(edit(combining:));

@end

NS_ASSUME_NONNULL_END
