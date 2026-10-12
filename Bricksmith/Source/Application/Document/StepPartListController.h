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

@end

NS_ASSUME_NONNULL_END
