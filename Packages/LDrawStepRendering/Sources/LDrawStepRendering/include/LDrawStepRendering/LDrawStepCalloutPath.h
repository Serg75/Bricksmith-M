//==============================================================================
//
//  File:       LDrawStepCalloutPath.h
//  Package:    LDrawStepRendering
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import <Foundation/Foundation.h>

@class LDrawModel;
@class LDrawStepCallout;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepCalloutPath
///
/// @abstract   Remembers the steps a host left to show a called-out submodel,
///             so it can lead back to each of them.
///
/// @discussion The host owns which model is on display. It asks here which
///             submodel a callout leads to, notes the step it leaves, and
///             takes the last one back when its way back is chosen.
///
//------------------------------------------------------------------------------
@interface LDrawStepCalloutPath : NSObject

/// The submodel a callout leads to. A submodel can be shown when it is one of
/// `models`, the models a host can put on display, and is not `current`, the
/// model on display. `clicked` is the one the callout's box shows where it
/// was clicked, and is taken when it can be shown. Else it is the first of
/// the callout's submodels that can be. Nil when there is none.
+ (nullable LDrawModel *) submodelOfCallout:(LDrawStepCallout *)callout
								 preferring:(nullable LDrawModel *)clicked
								amongModels:(NSArray *)models
								  otherThan:(nullable LDrawModel *)current
	NS_SWIFT_NAME(submodel(of:preferring:among:otherThan:));

/// YES when no step was left.
@property (nonatomic, readonly) BOOL isEmpty;

/// The model and the step the way back leads to. Nil and 0 when no step was
/// left. The step is counted from 1, as a host shows it.
@property (nonatomic, readonly, nullable) LDrawModel *returnModel;
@property (nonatomic, readonly) NSInteger returnStepNumber;

/// Notes the step being left: its model, its index, and how much bigger the
/// model is drawn than the zoom alone says, which the page anchor keeps.
- (void) leaveModel:(LDrawModel *)model atStepIndex:(NSInteger)stepIndex drawnScaleRatio:(double)ratio
	NS_SWIFT_NAME(leave(_:atStepIndex:drawnScaleRatio:));

/// Takes the last step left off the path, for the host to show again. The
/// index is cut down to the steps the model has now. Returns NO, and empties
/// the path, when no step was left or its model is not one of `models` any
/// more or has no steps.
- (BOOL) takeReturnModel:(LDrawModel * _Nullable * _Nonnull)outModel
			   stepIndex:(NSInteger *)outStepIndex
		 drawnScaleRatio:(double *)outRatio
			 amongModels:(NSArray *)models
	NS_SWIFT_NAME(takeReturn(model:stepIndex:drawnScaleRatio:among:));

/// Forgets every step left. Call it when a model is chosen any other way, so
/// that no way back is offered along a path that was left.
- (void) removeAll;

@end

NS_ASSUME_NONNULL_END
