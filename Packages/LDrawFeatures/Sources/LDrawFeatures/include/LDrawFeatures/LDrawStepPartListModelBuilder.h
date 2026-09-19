//==============================================================================
//
//  File:       LDrawStepPartListModelBuilder.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-09-10.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>

@class LDrawFile;
@class LDrawModel;
@class LDrawStepPartListLayout;
@class LDrawStepPartListPlacement;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepPartListModelBuilder
///
/// @abstract   Turns a packed layout into a throwaway `LDrawModel` whose parts
///             sit where the layout put them.
///
/// @discussion Each part already carries the view rotation, so the camera must
///             not be rotated. Point it straight down -Z, make it orthographic,
///             and set its zoom from `+zoomPercentageForLayout:`.
///
///             The model is in layout LDU: points divided by the layout's
///             scale. X runs right and Y runs down.
///
//------------------------------------------------------------------------------
@interface LDrawStepPartListModelBuilder : NSObject

/// A model holding one positioned part per drawable placement. A broken
/// reference gets no part.
///
/// A submodel entry draws the submodel or peer file of that name, found from
/// `file`, the file the step belongs to. The submodel is not moved or copied.
/// With no file, or an unknown name, the part draws nothing.
///
/// `viewTransform` must be the rotation the layout was packed with, or the
/// icons will not match their cells.
+ (LDrawModel *) modelForLayout:(LDrawStepPartListLayout *)layout
				  viewTransform:(Matrix4)viewTransform
			  submodelsFromFile:(nullable LDrawFile *)file
	NS_SWIFT_NAME(model(forLayout:viewTransform:submodelsFrom:));

/// Whether this placement gets a part in the model: everything but a broken
/// reference. The chrome draws a placeholder in the other cells.
+ (BOOL) isDrawablePlacement:(LDrawStepPartListPlacement *)placement;

/// The zoom percentage that makes one LDU cover exactly `layout.scale` points.
+ (double) zoomPercentageForLayout:(LDrawStepPartListLayout *)layout
	NS_SWIFT_NAME(zoomPercentage(forLayout:));

/// The model point to center the view on: the middle of the content box.
+ (Point3) centerPointForLayout:(LDrawStepPartListLayout *)layout
	NS_SWIFT_NAME(centerPoint(forLayout:));

@end

NS_ASSUME_NONNULL_END
