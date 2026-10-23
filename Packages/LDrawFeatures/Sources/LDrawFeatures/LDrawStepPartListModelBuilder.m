//==============================================================================
//
//  File:       LDrawStepPartListModelBuilder.m
//  Package:    LDrawFeatures
//
//  Purpose:    Turns a packed layout into a throwaway LDrawModel.
//
//  Created by Sergey Slobodenyuk on 2026-09-10.
//
//==============================================================================

#import <LDrawFeatures/LDrawStepPartListModelBuilder.h>

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawModelManager.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LDrawStepPartListEntry.h>

#import <LDrawFeatures/LDrawStepPartListLayout.h>


//------------------------------------------------------------------------------
///
/// @class		LDrawStepPartListSubmodelReference
///
/// @abstract	A part that draws a submodel it is handed, not one found by
/// 			name.
///
/// @discussion	The icon model has no file to look a name up in.
///
//------------------------------------------------------------------------------
@interface LDrawStepPartListSubmodelReference : LDrawPart

@property (nonatomic, weak, nullable) LDrawModel *submodel;

@end


@implementation LDrawStepPartListSubmodelReference

//========== referencedMPDSubmodel =============================================
///
/// @abstract	The submodel this part was handed, instead of one looked up by
///				name.
///
//==============================================================================
- (LDrawModel *) referencedMPDSubmodel
{
	return self.submodel;

}//end referencedMPDSubmodel

@end


@implementation LDrawStepPartListModelBuilder

//---------- modelForLayout:viewTransform:submodelsFromFile: ---------[static]--
///
/// @abstract	A model holding one positioned part per drawable placement.
/// 			Submodel entries draw the document's own submodels.
///
//------------------------------------------------------------------------------
+ (LDrawModel *) modelForLayout:(LDrawStepPartListLayout *)layout
				  viewTransform:(Matrix4)viewTransform
			  submodelsFromFile:(LDrawFile *)file
{
	LDrawModel	*model	= [LDrawModel new];
	LDrawStep	*step	= [model addStep];

	if (layout.scale <= 0.0) {
		return model;
	}

	for (LDrawStepPartListPlacement *placement in layout.placements) {

		if ([self isDrawablePlacement:placement] == NO) {
			continue;
		}

		LDrawPart *part = [self partForEntry:placement.entry submodelsFromFile:file];

		// parse:NO, because the draw path resolves the name on demand.
		[part setDisplayName:placement.entry.partName parse:NO inGroup:NULL];

		if (placement.entry.color != nil) {
			[part setLDrawColor:placement.entry.color];
		}

		Matrix4 transformation = [self transformForPlacement:placement
													  layout:layout
											   viewTransform:viewTransform];
		[part setTransformationMatrix:&transformation];

		[step addDirective:part];
	}

	return model;

}//end modelForLayout:viewTransform:submodelsFromFile:


//---------- iconKeyForLayout:viewTransform: -------------------------[static]--
///
/// @abstract	Each drawable placement's name, kind, color and transform, then
/// 			the camera's zoom and center: all the icon model is built from.
///
//------------------------------------------------------------------------------
+ (NSData *) iconKeyForLayout:(LDrawStepPartListLayout *)layout viewTransform:(Matrix4)viewTransform
{
	NSMutableData *key = [NSMutableData data];

	for (LDrawStepPartListPlacement *placement in layout.placements) {
		if ([self isDrawablePlacement:placement] == NO) {
			continue;
		}

		LDrawStepPartListEntry	*entry		= placement.entry;
		NSData					*name		= [entry.partName dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
		LDrawColorT				 colorCode	= (entry.color != nil) ? [entry.color colorCode] : LDrawColorBogus;
		BOOL					 isSubmodel	= entry.isSubmodel;
		Matrix4					 transform	= [self transformForPlacement:placement
																 layout:layout
														  viewTransform:viewTransform];

		[key appendData:name];
		[key appendBytes:"" length:1];
		[key appendBytes:&isSubmodel length:sizeof(isSubmodel)];
		[key appendBytes:&colorCode length:sizeof(colorCode)];
		[key appendBytes:&transform length:sizeof(transform)];
	}

	double	zoom	= [self zoomPercentageForLayout:layout];
	Point3	center	= [self centerPointForLayout:layout];

	[key appendBytes:&zoom length:sizeof(zoom)];
	[key appendBytes:&center length:sizeof(center)];

	return key;

}//end iconKeyForLayout:viewTransform:


//---------- modelForModel:throughStep:viewTransform:color: ----------[static]--
///
/// @abstract	A model of what `model` has built up to and including a step,
/// 			turned by `viewTransform`.
///
/// @discussion	Each part is drawn by a copy, because a part belongs to one
/// 			model. A copy that places a submodel is handed that submodel,
/// 			since the new model has no file to look a name up in.
///
//------------------------------------------------------------------------------
+ (LDrawModel *) modelForModel:(LDrawModel *)model
				   throughStep:(NSUInteger)lastStepIndex
				 viewTransform:(Matrix4)viewTransform
						 color:(nullable LDrawColor *)color
{
	LDrawModel	*built	= [LDrawModel new];
	LDrawStep	*step	= [built addStep];
	NSArray		*steps	= [model steps];

	if (steps.count == 0) {
		return built;
	}

	lastStepIndex = MIN(lastStepIndex, steps.count - 1);

	for (NSUInteger index = 0; index <= lastStepIndex; index++) {

		[(LDrawStep *)steps[index] applyToAllParts:^(LDrawPart *part) {

			if ([part isOmitted]) {
				return;
			}

			LDrawModel	*placed	= [part referencedMPDSubmodel];
			LDrawPart	*copy	= nil;

			if (placed != nil) {
				LDrawStepPartListSubmodelReference *reference = [LDrawStepPartListSubmodelReference new];

				reference.submodel	= placed;
				copy				= reference;
			}
			else {
				copy = [LDrawPart new];
			}

			// parse:NO, because the draw path resolves the name on demand.
			[copy setDisplayName:[part referenceName] parse:NO inGroup:NULL];

			LDrawColor *partColor = [part LDrawColor];

			if (color != nil && [partColor colorCode] == LDrawCurrentColor) {
				partColor = color;
			}
			if (partColor != nil) {
				[copy setLDrawColor:partColor];
			}

			Matrix4 transformation = Matrix4Multiply([part transformationMatrix], viewTransform);

			[copy setTransformationMatrix:&transformation];
			[step addDirective:copy];
		}];
	}

	return built;

}//end modelForModel:throughStep:viewTransform:color:


//---------- partForEntry:submodelsFromFile: -------------------------[static]--
///
/// @abstract	A fresh part for one entry. A submodel reference when the entry
/// 			names a submodel of the file or a peer file beside it, an
/// 			ordinary part otherwise.
///
//------------------------------------------------------------------------------
+ (LDrawPart *) partForEntry:(LDrawStepPartListEntry *)entry
		   submodelsFromFile:(nullable LDrawFile *)file
{
	LDrawModel *submodel = nil;

	if (entry.isSubmodel && file != nil) {
		submodel = [file modelWithName:entry.partName]
				?: [[LDrawModelManager sharedModelManager] requestModel:entry.partName withDocument:file];
	}

	if (submodel == nil) {
		return [LDrawPart new];
	}

	LDrawStepPartListSubmodelReference *reference = [LDrawStepPartListSubmodelReference new];

	reference.submodel = submodel;

	return reference;

}//end partForEntry:submodelsFromFile:


//---------- transformForPlacement:layout:viewTransform: -------------[static]--
///
/// @abstract	Where and how big one part is drawn.
///
/// @discussion	The steps run in order: scale the part, turn it to the list's
/// 			viewing angle, then move the middle of what the packer measured
/// 			onto the cell's center.
///
/// 			The measured middle is used, not the part's origin, so the
/// 			drawing sits in the middle of its cell. LDraw part origins can
/// 			be anywhere, often at a stud.
///
//------------------------------------------------------------------------------
+ (Matrix4) transformForPlacement:(LDrawStepPartListPlacement *)placement
						   layout:(LDrawStepPartListLayout *)layout
					viewTransform:(Matrix4)viewTransform
{
	Point3 measured = [LDrawStepPartListLayout projectedCenterOfEntry:placement.entry viewTransform:viewTransform];

	// A capped entry draws smaller. The rest sit at the common scale, which
	// the camera already supplies.
	double relativeScale = placement.scale / layout.scale;

	// Middle of the cell's icon area, in layout LDU rather than points.
	Point3 cellCenter = V3Make((placement.iconFrame.origin.x + placement.iconFrame.size.width  / 2.0) / layout.scale,
							   (placement.iconFrame.origin.y + placement.iconFrame.size.height / 2.0) / layout.scale,
							   0.0);

	Matrix4 transformation = IdentityMatrix4;

	transformation = Matrix4Scale(transformation, V3Make(relativeScale, relativeScale, relativeScale));
	transformation = Matrix4Multiply(transformation, [LDrawStepPartListLayout transformForEntry:placement.entry
																				  viewTransform:viewTransform]);
	transformation = Matrix4Translate(transformation, V3Make(cellCenter.x - measured.x * relativeScale,
															 cellCenter.y - measured.y * relativeScale,
															 cellCenter.z - measured.z * relativeScale));

	return transformation;

}//end transformForPlacement:layout:viewTransform:


//---------- isDrawablePlacement: ------------------------------------[static]--
///
/// @abstract	Whether this placement gets a part in the model. Everything
/// 			but a broken reference does.
///
//------------------------------------------------------------------------------
+ (BOOL) isDrawablePlacement:(LDrawStepPartListPlacement *)placement
{
	return placement.entry.isMissing == NO;

}//end isDrawablePlacement:


//---------- zoomPercentageForLayout: --------------------------------[static]--
///
/// @abstract	The zoom that makes one LDU cover exactly `layout.scale`
/// 			points.
///
/// @discussion	The camera divides the model size by zoom/100, so at 100% one
/// 			LDU is one point. The layout's scale is points per LDU, which
/// 			is the same ratio.
///
//------------------------------------------------------------------------------
+ (double) zoomPercentageForLayout:(LDrawStepPartListLayout *)layout
{
	return layout.scale * 100.0;

}//end zoomPercentageForLayout:


//---------- centerPointForLayout: -----------------------------------[static]--
///
/// @abstract	The middle of the content box, in layout LDU.
///
//------------------------------------------------------------------------------
+ (Point3) centerPointForLayout:(LDrawStepPartListLayout *)layout
{
	if (layout.scale <= 0.0) {
		return ZeroPoint3;
	}

	return V3Make(layout.contentSize.width  / 2.0 / layout.scale,
				  layout.contentSize.height / 2.0 / layout.scale,
				  0.0);

}//end centerPointForLayout:


@end
