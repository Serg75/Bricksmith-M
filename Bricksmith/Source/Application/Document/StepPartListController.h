//==============================================================================
//
// File:		StepPartListController.h
//
// Purpose:		Owns the step parts list overlay for one document: attaches it
//				to a viewport, keeps it in step with the model, and takes it
//				down again.
//
// Created by Sergey Slobodenyuk on 2026-09-10.
//
//==============================================================================
#import <Cocoa/Cocoa.h>

#import <LDrawStepEditing/LDrawStepAssemblyEdit.h>

@class LDrawModel;
@class LDrawStep;
@class LDrawStepCallout;
@class LDrawStepCalloutEdit;
@class LDrawStepPartListEdit;
@class LDrawStepPartListPageAnchor;
@class LDrawView;
@class StepPartListController;

NS_ASSUME_NONNULL_BEGIN

////////////////////////////////////////////////////////////////////////////////
//
// protocol StepPartListControllerDelegate
//
////////////////////////////////////////////////////////////////////////////////

/// The controller works out what a resize means, and the document applies it.
/// The document owns the undo manager, so the change takes the same path as
/// any other edit. The document also owns which model is on display, so it
/// follows a callout and finds the way back.
@protocol StepPartListControllerDelegate <NSObject>

- (void) stepPartListController:(StepPartListController *)controller
					  applyEdit:(LDrawStepPartListEdit *)edit
						 toStep:(LDrawStep *)step;

/// A callout was dragged or changed from its menu: write what the edit says.
/// `step` is the step on display, which the callout is in.
- (void) stepPartListController:(StepPartListController *)controller
			   applyCalloutEdit:(LDrawStepCalloutEdit *)edit
						 toStep:(LDrawStep *)step;

/// A callout's box was clicked: show the steps of the submodel it calls out.
/// `submodel` is the one the box shows where the click was, which matters for
/// a callout of several.
- (void) stepPartListController:(StepPartListController *)controller
			   didChooseCallout:(LDrawStepCallout *)callout
					   submodel:(nullable LDrawModel *)submodel;

/// The button that leads back was clicked.
- (void) stepPartListControllerDidChooseReturn:(StepPartListController *)controller;

/// Return was pressed while arranging: write what was arranged.
- (void) stepPartListControllerDidFinishArranging:(StepPartListController *)controller;

/// Escape was pressed while arranging: drop what was arranged.
- (void) stepPartListControllerDidCancelArranging:(StepPartListController *)controller;

/// The page was Command-clicked: start arranging the step.
- (void) stepPartListControllerDidAskToArrange:(StepPartListController *)controller;

/// The step was laid out while arranging: what was arranged may have changed.
- (void) stepPartListControllerDidArrange:(StepPartListController *)controller;

/// Arranging ended by itself, since another step is on display, and nothing
/// was written. `pageScale` is the inch the page was held at, so the page can
/// keep its size while the view goes back to the step.
- (void) stepPartListController:(StepPartListController *)controller
  didStopArrangingWithPageScale:(double)pageScale;

/// Write this edit: the parts list was moved, or the turned view's angle is to
/// be the step's.
- (void) stepPartListController:(StepPartListController *)controller
			  applyAssemblyEdit:(LDrawStepAssemblyEdit *)edit;

/// The turned view's strip asked to see the step at its own angle again.
- (void) stepPartListControllerDidAskForStepAngle:(StepPartListController *)controller;

@end

////////////////////////////////////////////////////////////////////////////////
//
// class StepPartListController
//
////////////////////////////////////////////////////////////////////////////////
@interface StepPartListController : NSObject

/// The model whose visible step is listed. Setting it schedules a reload.
@property (nonatomic, weak, nullable) LDrawModel *model;

@property (nonatomic, weak, nullable) id<StepPartListControllerDelegate> delegate;

/// Where the page is pinned. The controller starts with its own, and the
/// document gives it the shared one so both use the same points.
@property (nonatomic, strong) LDrawStepPartListPageAnchor *pageAnchor;

/// The viewport the overlay is on, or nil while detached.
@property (nonatomic, weak, readonly, nullable) LDrawView *hostView;

/// What the button that leads back says, or nil to show none. The document
/// sets it while a called-out submodel is on display.
@property (nonatomic, copy, nullable) NSString *returnTitle;

/// Attaches the overlay to a viewport, detaching from any previous one.
/// Passing nil just detaches.
- (void) attachToView:(nullable LDrawView *)view;

/// Puts the visible step in its place on LPub3D's page again, and keeps where
/// the middle of the page is in the page anchor. The camera is not moved: the
/// caller scrolls when the page has to stay where it was on screen. Does
/// nothing while detached or off the page.
- (void) centerPageOnStep;

- (void) detach;

/// Whether the camera's moves change the step's assembly on LPub3D's page
/// instead of the view.
@property (nonatomic, readonly) BOOL isArranging;

/// Starts arranging the visible step, with the page held where it is drawn.
/// NO off the page or while detached.
- (BOOL) beginArranging;

/// The edit that writes what was arranged, for these steps, or nil when not
/// arranging. An angle the scope cannot say is left out.
- (nullable LDrawStepAssemblyEdit *) arrangedEditWithScope:(LDrawStepAssemblyScope)scope;

/// Whether what was arranged can be written for these steps. The whole model
/// takes no new angle.
- (BOOL) canWriteArrangedScope:(LDrawStepAssemblyScope)scope;

/// The step as arranged: the assembly's MODEL_SCALE, its offset from where it
/// is centered on the page in page inches, and the camera's angle. Setting one
/// moves the model to it at once, with the page held.
@property (nonatomic) double arrangedScale;
@property (nonatomic) Vector2 arrangedOffsetInches;
@property (nonatomic) Tuple3 arrangedViewingAngle;

/// What the arranged step has without its own lines: its scale, and its offset
/// in page inches, which says NO when the step has none to give.
@property (nonatomic, readonly) double inheritedScale;
- (BOOL) getInheritedOffsetInches:(Vector2 *)offset;

/// The arranged angle as the REL ROTSTEP Done writes for it, in degrees: the
/// file's numbers while the step is not turned, else the numbers typed while
/// they still say the turn. Setting it turns the camera.
@property (nonatomic) Tuple3 arrangedRotation;

/// Puts back the angle, the scale, or the place on the page, while arranging.
/// For one step or later steps it is what the step has without its own lines,
/// and without its own ROTSTEP for the angle, which Done then takes out. The
/// whole model leaves the step's lines alone, so for it Reset puts back what
/// the file shows for the step. Nothing is written until Done.
- (void) resetArrangedViewingAngleForScope:(LDrawStepAssemblyScope)scope;
- (void) resetArrangedScaleForScope:(LDrawStepAssemblyScope)scope;
- (void) resetArrangedOffsetForScope:(LDrawStepAssemblyScope)scope;

/// Whether Reset Angle would turn the step: NO when it is at that angle.
- (BOOL) canResetArrangedViewingAngleForScope:(LDrawStepAssemblyScope)scope;

/// Whether the place can be put back. For one step or later steps, NO when the
/// step's own placement line puts it at another place than the line it
/// inherits.
- (BOOL) canResetArrangedOffsetForScope:(LDrawStepAssemblyScope)scope;

/// Whether the step can be lined up with the previous one, whose outline is
/// shown on the page while arranging.
@property (nonatomic, readonly) BOOL canAlignArrangedStepWithPreviousStep;

/// Moves the step so the parts from earlier steps sit where the previous step
/// had them on its page.
- (void) alignArrangedStepWithPreviousStep;

/// Moves the step so the middle of its box is on the middle of the page.
- (void) centerArrangedStepOnPage;

/// Whether the previous step is shown faintly while arranging, as the scope
/// bar's checkbox says. NO to begin with. Tapping P switches it.
@property (nonatomic) BOOL showsPreviousStep;

/// Whether it is shown now: as set, or while P is held.
@property (nonatomic, readonly) BOOL isShowingPreviousStep;

/// Whether the step on display has a step before it to show. NO for the
/// model's first step.
@property (nonatomic, readonly) BOOL hasPreviousStep;

/// Holds the page where it is drawn now, after the host zoomed or scrolled
/// the page and the model together. What was arranged stays.
- (void) holdArrangedPage;

/// Fits the arranged page in the view, the model growing with it. What was
/// arranged stays.
- (void) fitArrangedPage;

/// How many points an inch of the page covers while arranging, or 0.
@property (nonatomic, readonly) double arrangedPointsPerPageInch;

/// Stops arranging without writing anything. The step goes back to where its
/// lines put it on the next reload.
- (void) endArranging;

@end

NS_ASSUME_NONNULL_END
