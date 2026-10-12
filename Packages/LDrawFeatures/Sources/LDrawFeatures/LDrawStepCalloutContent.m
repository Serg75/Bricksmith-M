//==============================================================================
//
//  File:       LDrawStepCalloutContent.m
//  Package:    LDrawFeatures
//
//  Purpose:    Lays out what goes inside a callout's box.
//
//  Notes:      There are two forms. The summary shows each submodel finished,
//              and is packed like a small parts list. The strip shows the
//              submodels step by step, in the rows and columns LPub3D prints.
//
//  Created by Sergey Slobodenyuk on 2026-10-03.
//
//==============================================================================

#import "LDrawStepCalloutContent.h"

#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LDrawStepPartListEntry.h>
#import <LDrawCore/LDrawUtilities.h>
#import <LDrawCore/LPubCallout.h>

#import <LDrawFeatures/LDrawStepCallout.h>
#import <LDrawFeatures/LDrawStepCalloutStyle.h>

#import "LDrawStepPartListInternal.h"


/// The most of the host a summary may cover on each axis. A bigger submodel is
/// drawn smaller.
static const double MAXIMUM_BOX_WIDTH_FRACTION	= 0.35;
static const double MAXIMUM_BOX_HEIGHT_FRACTION	= 0.35;

/// The side, in LDU, of a step's picture that cannot be measured: there is no
/// part catalog to measure with.
static const double FALLBACK_EXTENT_LDU = 20.0;


//========== ScaledSize() ======================================================
static Size2 ScaledSize(Size2 size, double scale)
{
	return V2MakeSize(size.width * scale, size.height * scale);

}//end ScaledSize


//========== RotationOfTransform() =============================================
///
/// @abstract	The turn a placement gives its part, with the move and any
/// 			scaling taken out.
///
//==============================================================================
static Matrix4 RotationOfTransform(Matrix4 transform)
{
	Matrix4 rotation = IdentityMatrix4;

	for (int row = 0; row < 3; row++) {
		double length = sqrt(transform.element[row][0] * transform.element[row][0]
							 + transform.element[row][1] * transform.element[row][1]
							 + transform.element[row][2] * transform.element[row][2]);

		if (length <= 0.0) {
			return IdentityMatrix4;
		}

		for (int column = 0; column < 3; column++) {
			rotation.element[row][column] = transform.element[row][column] / length;
		}
	}

	return rotation;

}//end RotationOfTransform


//------------------------------------------------------------------------------
///
/// @class		LDrawStepCalloutCell
///
/// @abstract	One step of a strip: its picture, and what goes with it.
///
/// @discussion	Frames are measured from the cell's own top left corner.
///
//------------------------------------------------------------------------------
@interface LDrawStepCalloutCell : NSObject

/// The submodel, and the last of its steps the picture shows.
@property (nonatomic, strong) LDrawModel				*submodel;
@property (nonatomic) NSUInteger						lastStepIndex;

/// The step whose parts the cell lists, or nil for a submodel shown whole.
@property (nonatomic, strong, nullable) LDrawStep		*step;

/// The submodel's row in the callout: its name, color and count.
@property (nonatomic, strong) LDrawStepPartListEntry	*entry;

/// The view the picture is seen from.
@property (nonatomic) Matrix4							view;

/// The points the parts in the picture reach furthest out to, as Point3 values.
@property (nonatomic, strong, nullable) NSData			*outlinePoints;

/// The step's number among those shown, from 1. The count goes in the last
/// cell of a submodel placed more than once, and is 0 in every other cell.
@property (nonatomic) NSUInteger						number;
@property (nonatomic) NSUInteger						quantity;

/// Whether the cell is the first of its submodel, and whether a DIVIDER line
/// makes it start a group.
@property (nonatomic) BOOL								isFirstOfSubmodel;
@property (nonatomic) BOOL								hasDividerBefore;

// Measured
@property (nonatomic) Size2								size;
@property (nonatomic) Point2							origin;

/// The cell's share of the strip: the cell and the room around it. The shares
/// of a group fill it. `dividerBand` is the room between the cell's group and
/// the one before, for the first cell of a group that has one before it.
@property (nonatomic) Box2								slot;
@property (nonatomic) Box2								dividerBand;
@property (nonatomic) Box2								pictureFrame;
@property (nonatomic) Point3							pictureCenter;
@property (nonatomic, strong, nullable) LDrawStepPartListLayout *list;
@property (nonatomic) Point2							listOrigin;
@property (nonatomic, copy, nullable) NSString			*numberText;
@property (nonatomic) Box2								numberFrame;
@property (nonatomic, copy, nullable) NSString			*countText;
@property (nonatomic) Box2								countFrame;

@end


/// The cells of a strip, in groups. A group is one column of a callout whose
/// steps run down, or one row of a callout whose steps run across.
typedef NSMutableArray<NSMutableArray<LDrawStepCalloutCell *> *> LDrawStepCalloutCellGroups;


@implementation LDrawStepCalloutCell

//========== measureWithOptions:style:showsNumber:listsParts: ==================
///
/// @abstract	Sizes the cell: the number and the step's parts above the
/// 			picture, and the count beside or below it.
///
/// @discussion	Two things next to each other are kept apart by the larger of
/// 			their two margins, as in LPub3D. The cell has no room of its own
/// 			around them.
///
//==============================================================================
- (void) measureWithOptions:(LDrawStepCalloutBoxOptions)options
					  style:(LDrawStepCalloutStyle *)style
				showsNumber:(BOOL)showsNumber
				 listsParts:(BOOL)listsParts
{
	double	scale		= options.pointsPerPageInch;
	Size2	picture		= [self measurePictureAtScale:options.assemblyScale];
	Size2	number		= ZeroSize2;
	Size2	list		= ZeroSize2;
	Size2	topMargins	= ZeroSize2;

	if (showsNumber && self.number > 0) {
		self.numberText	= [NSString stringWithFormat:@"%lu", (unsigned long)self.number];
		number			= ScaledSize([style.stepNumberText sizeForCharacterCount:self.numberText.length], scale);
		topMargins		= style.stepNumberMargins;
	}

	if (listsParts && self.step != nil) {
		self.list = [self listWithOptions:options];

		if (self.list != nil) {
			list		= self.list.contentSize;
			topMargins	= V2MakeSize(MAX(topMargins.width, style.partsListMargins.width),
									 MAX(topMargins.height, style.partsListMargins.height));
		}
	}

	BOOL	hasBoth		= (number.width > 0.0 && list.width > 0.0);
	double	topWidth	= number.width + list.width + (hasBoth ? topMargins.width * scale : 0.0);
	double	topHeight	= MAX(number.height, list.height);
	double	topGap		= MAX(topMargins.height, style.assemblyMargins.height) * scale;
	double	width		= MAX(picture.width, topWidth);
	double	pictureTop	= (topHeight > 0.0) ? topHeight + topGap : 0.0;
	double	height		= pictureTop + picture.height;

	self.numberFrame	= V2MakeBox(0.0, 0.0, number.width, number.height);
	self.listOrigin		= V2Make(topWidth - list.width, 0.0);
	self.pictureFrame	= V2MakeBox((width - picture.width) / 2.0, pictureTop, picture.width, picture.height);

	if (self.quantity >= 2) {
		// LPub3D puts the sign before the number here.
		NSString	*text	= [NSString stringWithFormat:@"×%lu", (unsigned long)self.quantity];
		Size2		 count	= ScaledSize([style.countText sizeForCharacterCount:text.length], scale);
		Size2		 gap	= ScaledSize(style.countMargins, scale);

		self.countText = text;

		// The count goes beside the picture or below it, whichever adds less
		// area to the cell, as in LPub3D.
		if ((count.width + gap.width) * height < (count.height + gap.height) * width) {
			self.countFrame	= V2MakeBox(width + gap.width, MAX(height - count.height, 0.0), count.width, count.height);
			width			+= gap.width + count.width;
			height			= MAX(height, count.height);
		}
		else {
			self.countFrame	= V2MakeBox(MAX(width - count.width, 0.0), height + gap.height, count.width, count.height);
			height			+= gap.height + count.height;
			width			= MAX(width, count.width);
		}
	}

	self.size = V2MakeSize(width, height);

}//end measureWithOptions:style:showsNumber:listsParts:


//========== measurePictureAtScale: ============================================
///
/// @abstract	The size of the picture, in points, and the point of its model
/// 			that goes in the middle.
///
/// @discussion	Measured by the points its parts reach furthest out to, as the
/// 			view sees them. That fits closer than one box around the whole
/// 			assembly.
///
//==============================================================================
- (Size2) measurePictureAtScale:(double)scale
{
	const Point3	*points	= self.outlinePoints.bytes;
	NSUInteger		 count	= self.outlinePoints.length / sizeof(Point3);
	Box3			 box	= InvalidBox;

	for (NSUInteger index = 0; index < count; index++) {
		box = V3UnionBoxAndPoint(box, V3MulPointByProjMatrix(points[index], self.view));
	}

	if (count == 0) {
		double half = FALLBACK_EXTENT_LDU / 2.0;

		box.min = V3Make(-half, -half, -half);
		box.max = V3Make(half, half, half);
	}

	self.pictureCenter = V3Midpoint(box.min, box.max);

	return V2MakeSize(MAX(box.max.x - box.min.x, 1.0) * scale,
					  MAX(box.max.y - box.min.y, 1.0) * scale);

}//end measurePictureAtScale:


//========== listWithOptions: ==================================================
///
/// @abstract	The step's parts, packed. Nil when it lists none.
///
//==============================================================================
- (nullable LDrawStepPartListLayout *) listWithOptions:(LDrawStepCalloutBoxOptions)options
{
	NSArray<LDrawStepPartListEntry *> *entries = [LDrawStepPartList entriesForStep:self.step
																   inheritingColor:self.entry.color];

	if (entries.count == 0) {
		return nil;
	}

	LDrawStepPartListConstraint	constraint	= [LDrawStepPartListLayout defaultConstraint];
	LDrawStepPartListLayout		*list		= [LDrawStepPartListLayout layoutForEntries:entries
																			 constraint:constraint
																		  viewTransform:options.listViewTransform
																				metrics:options.metrics];

	return (list.placements.count > 0) ? list : nil;

}//end listWithOptions:


//========== subjectKey ========================================================
///
/// @abstract	Names what the cell's picture shows, whatever its size: the
/// 			submodel, its color, the step it stops at and its turn.
///
//==============================================================================
- (NSString *) subjectKey
{
	NSMutableString *key = [NSMutableString stringWithFormat:@"steps|%p|%@|%lu",
							self.submodel, self.entry.groupKey, (unsigned long)self.lastStepIndex];

	LDrawStepCalloutAppendRotation(key, self.view);

	return key;

}//end subjectKey

@end


// MARK: -

@implementation LDrawStepCalloutContent

//========== init ==============================================================
- (instancetype) init
{
	self = [super init];
	if (self) {
		self->_pictures	= [NSMutableArray array];
		self->_labels	= [NSMutableArray array];
		self->_dividers	= [NSMutableData data];
		self->_steps	= [NSMutableArray array];

		self->_submodelAreas	= [NSMutableData data];
		self->_areaSubmodels	= [NSMutableArray array];
	}
	return self;

}//end init


//========== addArea:ofSubmodel: ===============================================
- (void) addArea:(Box2)area ofSubmodel:(LDrawModel *)submodel
{
	[self.submodelAreas appendBytes:&area length:sizeof(Box2)];
	[self.areaSubmodels addObject:submodel];

}//end addArea:ofSubmodel:


//========== moveSubmodelAreasBy: ==============================================
- (void) moveSubmodelAreasBy:(Point2)offset
{
	Box2 *areas = self.submodelAreas.mutableBytes;

	for (NSUInteger index = 0; index < self.areaSubmodels.count; index++) {
		areas[index] = LDrawStepCalloutMovedBox(areas[index], offset);
	}

}//end moveSubmodelAreasBy:


// MARK: - THE SUMMARY -


//---------- summaryOfCallout:inModel:options: -----------------------[static]--
///
/// @abstract	Each submodel finished, with how many times it is placed, over
/// 			the parts the box lists itself.
///
/// @discussion	Each submodel is turned by its own view, so they are packed with
/// 			no view of their own.
///
//------------------------------------------------------------------------------
+ (nullable instancetype) summaryOfCallout:(LDrawStepCallout *)callout
								   inModel:(nullable LDrawModel *)model
								   options:(LDrawStepCalloutBoxOptions)options
{
	LDrawStepPartListMetrics					 metrics	= options.metrics;
	Size2										 hostSize	= options.hostRect.size;
	NSArray<LDrawStepPartListEntry *>			*collected	= callout.entries;
	NSArray<LDrawModel *>						*submodels	= callout.submodels;
	NSMutableArray<LDrawStepPartListEntry *>	*entries	= [NSMutableArray array];

	for (NSUInteger index = 0; index < collected.count; index++) {
		Matrix4 view = [self viewTransformForSubmodel:submodels[index]
												entry:collected[index]
											  callout:callout
											  inModel:model];

		[entries addObject:[collected[index] entryWithListOrientation:view]];
	}

	// The budget is content height, so it leaves room for the padding.
	metrics.maximumHeight = MAX(1.0, hostSize.height * MAXIMUM_BOX_HEIGHT_FRACTION - 2.0 * metrics.framePadding);

	double					 widest		= hostSize.width * MAXIMUM_BOX_WIDTH_FRACTION;
	LDrawStepPartListLayout	*finished	= [self layoutForEntries:entries
												   viewTransform:IdentityMatrix4
														 metrics:metrics
											   maximumFrameWidth:widest];

	if (finished.placements.count == 0) {
		return nil;
	}

	LDrawStepCalloutContent	*content	= [LDrawStepCalloutContent new];
	LDrawFile				*file		= [model enclosingFile];
	NSUInteger				 stepCount	= callout.stepCount;
	LDrawStepCalloutPicture	*picture	= [[LDrawStepCalloutPicture alloc] initWithLayout:finished
																			viewTransform:IdentityMatrix4
																					 file:file
																				   origin:ZeroPoint2
																			  isPartsList:NO];

	[content.pictures addObject:picture];

	for (LDrawStepPartListPlacement *placement in finished.placements) {
		NSUInteger index = [collected indexOfObjectPassingTest:
							^BOOL(LDrawStepPartListEntry *entry, NSUInteger entryIndex, BOOL *stop) {
			return [entry.groupKey isEqualToString:placement.entry.groupKey];
		}];

		if (index != NSNotFound) {
			[content addArea:placement.cellFrame ofSubmodel:submodels[index]];
		}
	}

	content.size				= finished.contentSize;
	content.summarizedStepCount	= (stepCount >= 2) ? stepCount : 0;

	NSArray<LDrawStepPartListEntry *> *parts = options.showsLists ? callout.partEntries : @[];

	if (parts.count == 0) {
		return content;
	}

	LDrawStepPartListLayout *list = [self layoutForEntries:parts
											 viewTransform:options.listViewTransform
												   metrics:metrics
										 maximumFrameWidth:widest];

	if (list.placements.count == 0) {
		return content;
	}

	// The finished submodels sit in the middle, over their parts.
	double	width		= MAX(finished.contentSize.width, list.contentSize.width);
	Point2	centered	= V2Make((width - finished.contentSize.width) / 2.0, 0.0);
	Point2	origin		= V2Make((width - list.contentSize.width) / 2.0,
								 finished.contentSize.height + metrics.rowGap);

	[picture moveBy:centered];
	[content moveSubmodelAreasBy:centered];

	LDrawStepCalloutPicture *listed = [[LDrawStepCalloutPicture alloc] initWithLayout:list
																		viewTransform:options.listViewTransform
																				 file:file
																			   origin:origin
																		  isPartsList:YES];
	[content.pictures addObject:listed];

	content.size = V2MakeSize(width, origin.y + list.contentSize.height);

	return content;

}//end summaryOfCallout:inModel:options:


//---------- layoutForEntries:viewTransform:metrics:maximumFrameWidth: --[static]--
///
/// @abstract	Packs entries as wide as they like, or at the widest frame
/// 			allowed when that is too wide. A long one is then drawn smaller.
///
//------------------------------------------------------------------------------
+ (LDrawStepPartListLayout *) layoutForEntries:(NSArray<LDrawStepPartListEntry *> *)entries
								 viewTransform:(Matrix4)viewTransform
									   metrics:(LDrawStepPartListMetrics)metrics
							 maximumFrameWidth:(double)maximumFrameWidth
{
	LDrawStepPartListConstraint	constraint	= [LDrawStepPartListLayout defaultConstraint];
	LDrawStepPartListLayout		*layout		= [LDrawStepPartListLayout layoutForEntries:entries
																			 constraint:constraint
																		  viewTransform:viewTransform
																				metrics:metrics];

	if (layout.frameSize.width > maximumFrameWidth && metrics.pointsPerInch > 0.0) {
		constraint.mode		= LPubPliConstrainModeWidth;
		constraint.inches	= (float)(maximumFrameWidth / metrics.pointsPerInch);

		layout = [LDrawStepPartListLayout layoutForEntries:entries
												constraint:constraint
											 viewTransform:viewTransform
												   metrics:metrics];
	}

	return layout;

}//end layoutForEntries:viewTransform:metrics:maximumFrameWidth:


//---------- viewTransformForSubmodel:entry:callout:inModel: ---------[static]--
///
/// @abstract	The view a submodel shown finished is seen from.
///
/// @discussion	A rotated callout shows the submodel as it sits in the step: the
/// 			placement's turn, then the step's own view. An assembled one
/// 			uses the default view. Any other shows the submodel as its last
/// 			step does.
///
//------------------------------------------------------------------------------
+ (Matrix4) viewTransformForSubmodel:(LDrawModel *)submodel
							   entry:(LDrawStepPartListEntry *)entry
							 callout:(LDrawStepCallout *)callout
							 inModel:(nullable LDrawModel *)model
{
	Tuple3 angle = [LDrawUtilities angleForViewOrientation:LDrawViewOrientation3D];

	if (callout.mode == LPubCalloutModeRotated && model != nil) {
		Matrix4 placed = IdentityMatrix4;

		// The first placement of the entry's own row: the same submodel in
		// another color is another row, with a turn of its own.
		for (LDrawPart *part in callout.placements) {
			if ([LDrawStepPartList assemblyPlacedByPart:part] != submodel) {
				continue;
			}

			if ([[LDrawStepPartList rowKeyOfPlacement:part] isEqualToString:entry.groupKey]) {
				placed = RotationOfTransform([part transformationMatrix]);
				break;
			}
		}

		angle = [model rotationAngleForStepAtIndex:[model maximumStepIndexForStepDisplay]];

		return Matrix4Multiply(placed, [LDrawStepPartListLayout viewTransformForAngle:angle]);
	}

	if (callout.mode == LPubCalloutModeUnassembled) {
		NSUInteger stepCount = [[submodel steps] count];

		angle = [submodel rotationAngleForStepAtIndex:(stepCount > 0) ? stepCount - 1 : 0];
	}

	return [LDrawStepPartListLayout viewTransformForAngle:angle];

}//end viewTransformForSubmodel:entry:callout:inModel:


// MARK: - THE STRIP -


//---------- stripOfCallout:inModel:options:style: -------------------[static]--
///
/// @abstract	The submodels step by step, as LPub3D lays a callout out.
///
/// @discussion	A callout that shows its submodels finished gets one picture for
/// 			each. Steps are numbered only when there is more than one, as in
/// 			LPub3D.
///
//------------------------------------------------------------------------------
+ (nullable instancetype) stripOfCallout:(LDrawStepCallout *)callout
								 inModel:(nullable LDrawModel *)model
								 options:(LDrawStepCalloutBoxOptions)options
								   style:(LDrawStepCalloutStyle *)style
{
	LDrawStepCalloutCellGroups	*groups		= [self cellGroupsOfCallout:callout inModel:model];
	NSUInteger					 cellCount	= 0;

	for (NSArray<LDrawStepCalloutCell *> *group in groups) {
		cellCount += group.count;
	}

	if (cellCount == 0) {
		return nil;
	}

	BOOL showsSteps		= (callout.mode == LPubCalloutModeUnassembled);
	BOOL showsNumbers	= showsSteps && cellCount > 1 && callout.showsStepNumbers;
	BOOL listsParts		= showsSteps && options.showsLists && callout.listsOwnParts;

	for (NSArray<LDrawStepCalloutCell *> *group in groups) {
		for (LDrawStepCalloutCell *cell in group) {
			[cell measureWithOptions:options style:style showsNumber:showsNumbers listsParts:listsParts];
		}
	}

	LDrawStepCalloutContent	*content	= [LDrawStepCalloutContent new];
	LDrawFile				*file		= [model enclosingFile];
	double					 scale		= options.pointsPerPageInch;

	[content arrangeGroups:groups
				isVertical:callout.isVertical
				   stepGap:ScaledSize(style.assemblyMargins, scale)
				   lineGap:ScaledSize(style.separatorMargins, scale)
			 lineThickness:style.separatorThickness * scale];

	for (NSArray<LDrawStepCalloutCell *> *group in groups) {
		for (LDrawStepCalloutCell *cell in group) {
			[content addCell:cell file:file options:options];
		}
	}

	return content;

}//end stripOfCallout:inModel:options:style:


//---------- cellGroupsOfCallout:inModel: ----------------------------[static]--
///
/// @abstract	A cell for each step the callout shows, in groups.
///
//------------------------------------------------------------------------------
+ (LDrawStepCalloutCellGroups *) cellGroupsOfCallout:(LDrawStepCallout *)callout
											 inModel:(nullable LDrawModel *)model
{
	LDrawStepCalloutCellGroups			*groups		= [NSMutableArray array];
	NSArray<LDrawModel *>				*submodels	= callout.submodels;
	NSArray<LDrawStepPartListEntry *>	*entries	= callout.entries;

	for (NSUInteger index = 0; index < submodels.count; index++) {
		LDrawModel				*submodel	= submodels[index];
		LDrawStepPartListEntry	*entry		= entries[index];
		LDrawStepCalloutCell	*last		= nil;
		NSUInteger				 quantity	= entry.quantity;

		if (callout.mode == LPubCalloutModeUnassembled) {
			// A submodel placed in several colors has a row for each, and is
			// built once. Its steps go with its first row.
			if ([submodels indexOfObjectIdenticalTo:submodel] != index) {
				continue;
			}

			quantity	= [self placementCountOfSubmodel:submodel inCallout:callout];
			last		= [self addStepsOfSubmodel:submodel entry:entry toGroups:groups];
		}
		else {
			last = [self cellForSubmodel:submodel entry:entry];

			last.lastStepIndex	= NSUIntegerMax;
			last.view			= [self viewTransformForSubmodel:submodel
														   entry:entry
														 callout:callout
														 inModel:model];
			last.outlinePoints	= [LDrawStepPartList outlinePointsOfModel:submodel];

			[groups addObject:[NSMutableArray arrayWithObject:last]];
		}

		// One of something needs no count.
		last.quantity = (quantity >= 2) ? quantity : 0;
	}

	return groups;

}//end cellGroupsOfCallout:inModel:


//---------- placementCountOfSubmodel:inCallout: ---------------------[static]--
///
/// @abstract	How many times a callout places a submodel, in any color.
///
//------------------------------------------------------------------------------
+ (NSUInteger) placementCountOfSubmodel:(LDrawModel *)submodel inCallout:(LDrawStepCallout *)callout
{
	NSArray<LDrawModel *>				*submodels	= callout.submodels;
	NSArray<LDrawStepPartListEntry *>	*entries	= callout.entries;
	NSUInteger							 count		= 0;

	for (NSUInteger index = 0; index < submodels.count; index++) {
		if (submodels[index] == submodel) {
			count += entries[index].quantity;
		}
	}

	return count;

}//end placementCountOfSubmodel:inCallout:


//---------- addStepsOfSubmodel:entry:toGroups: ----------------------[static]--
///
/// @abstract	Adds a cell for each step of a submodel that builds something,
/// 			and returns the last one, or nil when there is none.
///
/// @discussion	A submodel starts a group of its own, and so does the step after
/// 			a `CALLOUT DIVIDER` line.
///
//------------------------------------------------------------------------------
+ (nullable LDrawStepCalloutCell *) addStepsOfSubmodel:(LDrawModel *)submodel
												 entry:(LDrawStepPartListEntry *)entry
											  toGroups:(LDrawStepCalloutCellGroups *)groups
{
	NSArray<LDrawStep *>					*steps			= [submodel steps];
	NSMutableArray<LDrawStepCalloutCell *>	*group			= nil;
	NSMutableData							*outlinePoints	= [NSMutableData data];
	LDrawStepCalloutCell					*last			= nil;

	for (NSUInteger stepIndex = 0; stepIndex < steps.count; stepIndex++) {
		LDrawStep *step = steps[stepIndex];

		if ([LDrawStepCallout stepBuildsSomething:step] == NO) {
			continue;
		}

		BOOL isDivided = (last != nil) && [LDrawStepCallout dividerLinesBeforeStep:step].count > 0;

		if (group == nil || isDivided) {
			group = [NSMutableArray array];
			[groups addObject:group];
		}

		[outlinePoints appendData:[LDrawStepPartList outlinePointsOfStep:step]];

		LDrawStepCalloutCell	*cell	= [self cellForSubmodel:submodel entry:entry];
		Tuple3					 angle	= [submodel rotationAngleForStepAtIndex:stepIndex];

		cell.step				= step;
		cell.lastStepIndex		= stepIndex;
		cell.number				= (last != nil) ? last.number + 1 : 1;
		cell.view				= [LDrawStepPartListLayout viewTransformForAngle:angle];
		cell.outlinePoints		= [outlinePoints copy];
		cell.isFirstOfSubmodel	= (last == nil);
		cell.hasDividerBefore	= isDivided;

		[group addObject:cell];

		last = cell;
	}

	return last;

}//end addStepsOfSubmodel:entry:toGroups:


//---------- cellForSubmodel:entry: ----------------------------------[static]--
+ (LDrawStepCalloutCell *) cellForSubmodel:(LDrawModel *)submodel entry:(LDrawStepPartListEntry *)entry
{
	LDrawStepCalloutCell *cell = [LDrawStepCalloutCell new];

	cell.submodel	= submodel;
	cell.entry		= entry;
	cell.view		= IdentityMatrix4;

	return cell;

}//end cellForSubmodel:entry:


//========== arrangeGroups:isVertical:stepGap:lineGap:lineThickness: ===========
///
/// @abstract	Puts every cell in its place and sizes the content.
///
/// @discussion	The steps of a group follow each other one way, `stepGap` apart,
/// 			and the groups the other way, with a line between two groups and
/// 			`lineGap` on each side of it. A group shorter than the longest
/// 			spreads its steps over that length.
///
//==============================================================================
- (void) arrangeGroups:(LDrawStepCalloutCellGroups *)groups
			isVertical:(BOOL)isVertical
			   stepGap:(Size2)stepGap
			   lineGap:(Size2)lineGap
		 lineThickness:(double)thickness
{
	double gap		= isVertical ? stepGap.height : stepGap.width;
	double sideGap	= isVertical ? lineGap.width : lineGap.height;
	double longest	= 0.0;

	for (NSArray<LDrawStepCalloutCell *> *group in groups) {
		longest = MAX(longest, [LDrawStepCalloutContent lengthOfGroup:group isVertical:isVertical gap:gap]);
	}

	// Along is the way the steps of a group run. Across is the way the groups
	// follow each other.
	double across = 0.0;

	for (NSArray<LDrawStepCalloutCell *> *group in groups) {

		if (group.count == 0) {
			continue;
		}

		if (across > 0.0) {
			double	room = 2.0 * sideGap + thickness;
			Box2	line = isVertical ? V2MakeBox(across + sideGap, 0.0, thickness, longest)
									  : V2MakeBox(0.0, across + sideGap, longest, thickness);

			[self.dividers appendBytes:&line length:sizeof(Box2)];

			group.firstObject.dividerBand = isVertical ? V2MakeBox(across, 0.0, room, longest)
													   : V2MakeBox(0.0, across, longest, room);
			across += room;
		}

		double breadth = 0.0;

		for (LDrawStepCalloutCell *cell in group) {
			breadth = MAX(breadth, isVertical ? cell.size.width : cell.size.height);
		}

		double length		= [LDrawStepCalloutContent lengthOfGroup:group isVertical:isVertical gap:gap];
		double lead			= (longest - length) / (2.0 * group.count);
		double along		= 0.0;
		double slotStart	= 0.0;

		for (LDrawStepCalloutCell *cell in group) {
			double cellAlong	= isVertical ? cell.size.height : cell.size.width;
			double cellAcross	= isVertical ? cell.size.width : cell.size.height;
			double middled		= across + (breadth - cellAcross) / 2.0;

			along		+= lead;
			cell.origin	= isVertical ? V2Make(middled, along) : V2Make(along, middled);
			along		+= cellAlong + lead;

			// A cell's share runs to the middle of the gap after it, and the
			// last one's to the end of the group.
			double slotEnd = (cell == group.lastObject) ? longest : along + gap / 2.0;

			cell.slot	= isVertical ? V2MakeBox(across, slotStart, breadth, slotEnd - slotStart)
									 : V2MakeBox(slotStart, across, slotEnd - slotStart, breadth);
			slotStart	= slotEnd;
			along		+= gap;
		}

		across += breadth;
	}

	self.size = isVertical ? V2MakeSize(across, longest) : V2MakeSize(longest, across);

}//end arrangeGroups:isVertical:stepGap:lineGap:lineThickness:


//---------- lengthOfGroup:isVertical:gap: ---------------------------[static]--
///
/// @abstract	How long a group's steps are when they touch, gaps included.
///
//------------------------------------------------------------------------------
+ (double) lengthOfGroup:(NSArray<LDrawStepCalloutCell *> *)group isVertical:(BOOL)isVertical gap:(double)gap
{
	double length = 0.0;

	for (LDrawStepCalloutCell *cell in group) {
		length += isVertical ? cell.size.height : cell.size.width;
	}

	return length + gap * MAX((double)group.count - 1.0, 0.0);

}//end lengthOfGroup:isVertical:gap:


//========== addCell:file:options: =============================================
///
/// @abstract	Adds a placed cell's picture, parts and labels.
///
//==============================================================================
- (void) addCell:(LDrawStepCalloutCell *)cell
			file:(nullable LDrawFile *)file
		 options:(LDrawStepCalloutBoxOptions)options
{
	double					 scale		= options.assemblyScale;
	Box2					 frame		= LDrawStepCalloutMovedBox(cell.pictureFrame, cell.origin);
	LDrawStepCalloutPicture	*picture	= [[LDrawStepCalloutPicture alloc] initWithRect:frame
																			   assembly:cell.submodel
																			throughStep:cell.lastStepIndex
																		  viewTransform:cell.view
																				  color:cell.entry.color
																		 zoomPercentage:scale * 100.0
																				 center:cell.pictureCenter
																			 subjectKey:[cell subjectKey]];
	[self.pictures addObject:picture];
	[self addArea:cell.slot ofSubmodel:cell.submodel];

	if (cell.list != nil) {
		Point2					 origin	= V2Add(cell.origin, cell.listOrigin);
		LDrawStepCalloutPicture	*listed	= [[LDrawStepCalloutPicture alloc] initWithLayout:cell.list
																			viewTransform:options.listViewTransform
																					 file:file
																				   origin:origin
																			  isPartsList:YES];
		[self.pictures addObject:listed];
	}

	if (cell.numberText != nil) {
		Box2 rect = LDrawStepCalloutMovedBox(cell.numberFrame, cell.origin);

		[self.labels addObject:[[LDrawStepCalloutLabel alloc] initWithRect:rect text:cell.numberText isStepNumber:YES]];
	}

	if (cell.countText != nil) {
		Box2 rect = LDrawStepCalloutMovedBox(cell.countFrame, cell.origin);

		[self.labels addObject:[[LDrawStepCalloutLabel alloc] initWithRect:rect text:cell.countText isStepNumber:NO]];
	}

	if (cell.step != nil) {
		LDrawStepCalloutStep *shown = [[LDrawStepCalloutStep alloc] initWithStep:cell.step
																		  number:cell.number
																			rect:cell.slot
																	 dividerRect:cell.dividerBand
															   isFirstOfSubmodel:cell.isFirstOfSubmodel
																hasDividerBefore:cell.hasDividerBefore];

		[self.steps addObject:shown];
	}

}//end addCell:file:options:


@end
