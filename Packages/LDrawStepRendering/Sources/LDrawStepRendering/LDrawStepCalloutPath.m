//==============================================================================
//
//  File:       LDrawStepCalloutPath.m
//  Package:    LDrawStepRendering
//
//  Purpose:    Remembers the steps left through callouts.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import <LDrawStepRendering/LDrawStepCalloutPath.h>

#import <LDrawCore/LDrawModel.h>
#import <LDrawFeatures/LDrawStepCallout.h>


//------------------------------------------------------------------------------
///
/// @class		LDrawStepCalloutPathPoint
///
/// @abstract	One step that was left.
///
//------------------------------------------------------------------------------
@interface LDrawStepCalloutPathPoint : NSObject

@property (nonatomic, strong) LDrawModel	*model;
@property (nonatomic) NSInteger				 stepIndex;
@property (nonatomic) double				 drawnScaleRatio;

@end

@implementation LDrawStepCalloutPathPoint
@end


@implementation LDrawStepCalloutPath
{
	/// The steps left, oldest first.
	NSMutableArray<LDrawStepCalloutPathPoint *> *points;
}


//========== init ==============================================================
- (instancetype) init
{
	self = [super init];
	if (self) {
		self->points = [NSMutableArray array];
	}
	return self;

}//end init


//---------- submodelOfCallout:preferring:amongModels:otherThan: -----[static]--
+ (nullable LDrawModel *) submodelOfCallout:(LDrawStepCallout *)callout
								 preferring:(nullable LDrawModel *)clicked
								amongModels:(NSArray *)models
								  otherThan:(nullable LDrawModel *)current
{
	NSArray<LDrawModel *>			*submodels	= callout.submodels;
	NSMutableArray<LDrawModel *>	*candidates	= [NSMutableArray array];

	// The clicked one first, when it is the callout's.
	if (clicked != nil && [submodels containsObject:clicked]) {
		[candidates addObject:clicked];
	}
	[candidates addObjectsFromArray:submodels];

	for (LDrawModel *candidate in candidates) {
		if (candidate != current && [models containsObject:candidate]) {
			return candidate;
		}
	}

	return nil;

}//end submodelOfCallout:preferring:amongModels:otherThan:


//========== isEmpty ===========================================================
- (BOOL) isEmpty
{
	return self->points.count == 0;

}//end isEmpty


//========== returnModel =======================================================
- (nullable LDrawModel *) returnModel
{
	return self->points.lastObject.model;

}//end returnModel


//========== returnStepNumber ==================================================
- (NSInteger) returnStepNumber
{
	LDrawStepCalloutPathPoint *point = self->points.lastObject;

	return (point != nil) ? point.stepIndex + 1 : 0;

}//end returnStepNumber


//========== leaveModel:atStepIndex:drawnScaleRatio: ===========================
- (void) leaveModel:(LDrawModel *)model atStepIndex:(NSInteger)stepIndex drawnScaleRatio:(double)ratio
{
	LDrawStepCalloutPathPoint *point = [[LDrawStepCalloutPathPoint alloc] init];

	point.model				= model;
	point.stepIndex			= stepIndex;
	point.drawnScaleRatio	= ratio;

	[self->points addObject:point];

}//end leaveModel:atStepIndex:drawnScaleRatio:


//========== takeReturnModel:stepIndex:drawnScaleRatio:amongModels: ============
///
/// @abstract	Takes the last step left off the path.
///
/// @discussion	Its model may have been deleted, or have lost steps, since it
///				was left.
///
//==============================================================================
- (BOOL) takeReturnModel:(LDrawModel * _Nullable * _Nonnull)outModel
			   stepIndex:(NSInteger *)outStepIndex
		 drawnScaleRatio:(double *)outRatio
			 amongModels:(NSArray *)models
{
	LDrawStepCalloutPathPoint	*point		= self->points.lastObject;
	NSInteger					 stepCount	= [[point.model steps] count];

	if (point == nil) {
		return NO;
	}

	[self->points removeLastObject];

	if ([models containsObject:point.model] == NO || stepCount == 0) {
		[self->points removeAllObjects];
		return NO;
	}

	*outModel		= point.model;
	*outStepIndex	= MIN(point.stepIndex, stepCount - 1);
	*outRatio		= point.drawnScaleRatio;

	return YES;

}//end takeReturnModel:stepIndex:drawnScaleRatio:amongModels:


//========== removeAll =========================================================
- (void) removeAll
{
	[self->points removeAllObjects];

}//end removeAll

@end
