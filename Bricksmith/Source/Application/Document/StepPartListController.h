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
/// any other edit.
@protocol StepPartListControllerDelegate <NSObject>

- (void) stepPartListController:(StepPartListController *)controller
					  applyEdit:(LDrawStepPartListEdit *)edit
						 toStep:(LDrawStep *)step;

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
/// document gives it the shared one so both use the same point.
@property (nonatomic, strong) LDrawStepPartListPageAnchor *pageAnchor;

/// The viewport the overlay is on, or nil while detached.
@property (nonatomic, weak, readonly, nullable) LDrawView *hostView;

/// Attaches the overlay to a viewport, detaching from any previous one.
/// Passing nil just detaches.
- (void) attachToView:(nullable LDrawView *)view;

- (void) detach;

@end

NS_ASSUME_NONNULL_END
