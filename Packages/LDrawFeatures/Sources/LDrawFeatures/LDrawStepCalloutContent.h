//==============================================================================
//
//  File:       LDrawStepCalloutContent.h
//  Package:    LDrawFeatures
//
//  Purpose:    What goes inside a callout's box, before the box is placed.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import <LDrawFeatures/LDrawStepCalloutBox.h>

@class LDrawColor;
@class LDrawFile;
@class LDrawPart;
@class LDrawStepCalloutStyle;

NS_ASSUME_NONNULL_BEGIN

/// A box moved by an offset.
extern Box2 LDrawStepCalloutMovedBox(Box2 box, Point2 offset);

/// Adds the turn a matrix makes to a picture's key.
extern void LDrawStepCalloutAppendRotation(NSMutableString *key, Matrix4 matrix);


@interface LDrawStepCalloutPicture ()

/// A picture of what `assembly` has built up to and including one of its
/// steps, seen from `viewTransform`. Its parts in the main color take `color`.
/// `subjectKey` names what it shows whatever its size.
- (instancetype) initWithRect:(Box2)rect
					 assembly:(LDrawModel *)assembly
				  throughStep:(NSUInteger)lastStepIndex
				viewTransform:(Matrix4)viewTransform
						color:(nullable LDrawColor *)color
			   zoomPercentage:(double)zoomPercentage
					   center:(Point3)center
				   subjectKey:(NSString *)subjectKey;

/// A picture of a packed layout, with its top left corner at `origin`. `file`
/// is the file the layout's submodels are found in.
- (instancetype) initWithLayout:(LDrawStepPartListLayout *)layout
				  viewTransform:(Matrix4)viewTransform
						   file:(nullable LDrawFile *)file
						 origin:(Point2)origin
					isPartsList:(BOOL)isPartsList;

- (void) moveBy:(Point2)offset;

@end


@interface LDrawStepCalloutLabel ()

- (instancetype) initWithRect:(Box2)rect text:(NSString *)text isStepNumber:(BOOL)isStepNumber;

- (void) moveBy:(Point2)offset;

@end


@interface LDrawStepCalloutStep ()

/// `dividerRect` is the room between the step's column or row and the one
/// before it, for a step that starts one. Empty for any other step.
- (instancetype) initWithStep:(LDrawStep *)step
					   number:(NSUInteger)number
						 rect:(Box2)rect
				  dividerRect:(Box2)dividerRect
			isFirstOfSubmodel:(BOOL)isFirstOfSubmodel
			 hasDividerBefore:(BOOL)hasDividerBefore;

@property (nonatomic, readonly) Box2 dividerRect;

- (void) moveBy:(Point2)offset;

@end


@interface LDrawStepCalloutBox ()

/// YES when LPub3D centers the box on the page together with the assembly: it
/// is placed against the assembly and has not been dragged, so its PLACEMENT
/// line has no offset.
@property (nonatomic, readonly) BOOL isCenteredWithAssembly;

/// YES when the box is placed against the step's assembly, or against it in
/// place of something that is not drawn. Such a box moves with the assembly.
@property (nonatomic, readonly) BOOL isPlacedAgainstAssembly;

/// How far the assembly will move in the view once the box has been dragged
/// and the step is centered again with the page where it is. The presentation
/// sets it for a box placed against the assembly.
@property (nonatomic) Point2 assemblyShiftAfterDrag;

/// Shows a drag in progress: the box with its corner at `origin`.
- (void) previewOrigin:(Point2)origin;

/// The corner of a box of `size` put at a side or corner of `anchor`, as
/// LPub3D places one thing against another, `margin` away from it.
+ (Point2) originForSize:(Size2)size
				position:(LPubPlacementPosition)position
		   justification:(LPubPlacementPosition)justification
				isInside:(BOOL)isInside
				  anchor:(Box2)anchor
				  margin:(Size2)margin;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawStepCalloutContent
///
/// @abstract   The pictures, labels and lines of one callout, measured from the
///             top left corner of the area inside the box's padding.
///
//------------------------------------------------------------------------------
@interface LDrawStepCalloutContent : NSObject

@property (nonatomic) Size2				size;
@property (nonatomic, readonly) NSMutableArray<LDrawStepCalloutPicture *>	*pictures;
@property (nonatomic, readonly) NSMutableArray<LDrawStepCalloutLabel *>		*labels;

/// The lines between groups of steps, as Box2 values.
@property (nonatomic, readonly) NSMutableData	*dividers;

/// The steps of a strip, in order. A summary has none.
@property (nonatomic, readonly) NSMutableArray<LDrawStepCalloutStep *>		*steps;

/// Where each submodel is shown: the room of each of its steps in a strip, or
/// of its row in a summary, as Box2 values. `areaSubmodels` has the submodel
/// of each.
@property (nonatomic, readonly) NSMutableData	*submodelAreas;
@property (nonatomic, readonly) NSMutableArray<LDrawModel *>				*areaSubmodels;

- (void) moveSubmodelAreasBy:(Point2)offset;

@property (nonatomic) NSUInteger		summarizedStepCount;

/// Each submodel finished, with how many times it is placed, over the parts
/// the box lists itself. Nil with nothing to draw.
+ (nullable instancetype) summaryOfCallout:(LDrawStepCallout *)callout
								   inModel:(nullable LDrawModel *)model
								   options:(LDrawStepCalloutBoxOptions)options;

/// The submodels step by step, as LPub3D lays a callout out, with the room
/// the style asks for between them. Nil with nothing to draw.
+ (nullable instancetype) stripOfCallout:(LDrawStepCallout *)callout
								 inModel:(nullable LDrawModel *)model
								 options:(LDrawStepCalloutBoxOptions)options
								   style:(LDrawStepCalloutStyle *)style;

/// The view a submodel shown finished is seen from.
+ (Matrix4) viewTransformForSubmodel:(LDrawModel *)submodel
							   entry:(LDrawStepPartListEntry *)entry
							 callout:(LDrawStepCallout *)callout
							 inModel:(nullable LDrawModel *)model;

@end

NS_ASSUME_NONNULL_END
