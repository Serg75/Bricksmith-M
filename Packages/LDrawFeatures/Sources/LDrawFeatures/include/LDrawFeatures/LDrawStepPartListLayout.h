//==============================================================================
//
//  File:       LDrawStepPartListLayout.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-09-10.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LPubPliConstrain.h>
#import <LDrawCore/MatrixMath.h>

@class LDrawStepPartListEntry;

NS_ASSUME_NONNULL_BEGIN

////////////////////////////////////////////////////////////////////////////////
//
// Inputs
//
////////////////////////////////////////////////////////////////////////////////

//------------------------------------------------------------------------------
///
/// @struct     LDrawStepPartListConstraint
///
/// @abstract   How the box is packed: the parsed content of an
///             `0 !LPUB PLI CONSTRAIN`, with the scope already resolved.
///
//------------------------------------------------------------------------------
typedef struct LDrawStepPartListConstraint
{
	LPubPliConstrainMode	mode;
	/// For the Width and Height modes.
	float					inches;
	/// For the Columns mode.
	NSInteger				columns;

} LDrawStepPartListConstraint;


//------------------------------------------------------------------------------
///
/// @struct     LDrawStepPartListMetrics
///
/// @abstract   Everything the packer needs to know that is not the parts or the
///             constraint. All lengths are in points.
///
/// @discussion These are values, not preferences. Whoever calls the packer
///             turns the preferences into metrics, so the layout depends only
///             on what it is given.
///
//------------------------------------------------------------------------------
typedef struct LDrawStepPartListMetrics
{
	/// Points per inch the constraint's WIDTH and HEIGHT are read at. 150 is
	/// LPub3D's default resolution.
	double	pointsPerInch;

	/// Points per LDU before any shrinking. One stud is 20 LDU.
	double	baseScale;

	/// Points per LDU below which an icon is too small to read. Shrinking stops
	/// here and the list overflows instead.
	double	minimumScale;

	/// Blank points around an icon inside its cell.
	double	cellPadding;

	/// Height of the "3×" multiplier, and of the strip kept below the icon when
	/// it has no room beside the part.
	double	labelHeight;

	/// Height of the strip kept above the icon for the size badge. The packer
	/// takes the badge itself as two points shorter.
	double	annotationHeight;

	/// Rough width of one character of the multiplier and of the badge. The
	/// packer has no fonts, so set these a little wide.
	double	labelCharacterWidth;
	double	annotationCharacterWidth;

	/// Clear points kept between a label placed beside a part and the part's
	/// outline.
	double	decorationGap;

	/// Blank points between one shelf and the next. A cell has no margin of its
	/// own, so without this the shelves would touch.
	double	rowGap;

	/// Points between the frame's outer edge and its content. The border line
	/// is drawn inside them.
	double	framePadding;

	/// The widest a padded icon may be, as a fraction of a pinned width. A wider
	/// one is drawn smaller on its own, so one long part does not shrink the rest.
	double	maximumCellWidthFraction;

	/// Points of content height available, or 0 for unbounded. The only thing
	/// that shrinks icons, down to `minimumScale`, or drops shelves after that.
	double	maximumHeight;

} LDrawStepPartListMetrics;


////////////////////////////////////////////////////////////////////////////////
//
// Output
//
////////////////////////////////////////////////////////////////////////////////

//------------------------------------------------------------------------------
///
/// @class      LDrawStepPartListPlacement
///
/// @abstract   Where one entry's icon goes.
///
/// @discussion Coordinates are points in the content box, origin top-left, y
///             growing downward. The drawing code converts to its own
///             convention.
///
//------------------------------------------------------------------------------
@interface LDrawStepPartListPlacement : NSObject

@property (nonatomic, readonly) LDrawStepPartListEntry *entry;

/// The whole cell: icon, its padding, and any strips kept for labels. Never
/// narrower than a label in a strip. A cell slid into the one before it
/// overlaps that cell.
@property (nonatomic, readonly) Box2 cellFrame;

/// Just the icon, at its own size: inside the cell's padding, below any badge
/// strip, above any label strip, and centered in a wider cell.
@property (nonatomic, readonly) Box2 iconFrame;

/// Where the size badge goes, or empty when there is none. On the top line of
/// the icon's box next to the part, on the side with more room; without room
/// there, centered in a strip above the box and let down until just clear of
/// the part. A badge on the top line that comes too near another part moves
/// along the top of its own part, and can rise out of `cellFrame`.
@property (nonatomic, readonly) Box2 annotationFrame;

/// Where the "3×" multiplier goes: on the bottom line of the icon's box next to
/// the part, on the side with more room, or in a strip below it, under the
/// part's lowest corner. Decided per shelf, so the counts on a shelf sit on one
/// line. Sized for the text, which is drawn centered in it. A count beside a
/// part that comes too near another part moves along the bottom of its own
/// part, and can sink below `cellFrame`; the other counts on the shelf then
/// move down to its line. Empty when there is no count.
@property (nonatomic, readonly) Box2 labelFrame;

/// Whether the cell has a "3×" multiplier. A list of nothing but one submodel
/// placed once has none, and keeps no room for it.
@property (nonatomic, readonly) BOOL showsCount;

/// Points per LDU for this entry. Same as the layout's scale unless this
/// entry was too wide and got capped.
@property (nonatomic, readonly) double scale;

/// This entry alone was scaled down to fit. The cell marks it, so a part
/// drawn small is not read as a small part.
@property (nonatomic, readonly) BOOL isScaledDown;

/// Which shelf this cell sits on, counting from the top.
@property (nonatomic, readonly) NSUInteger rowIndex;

/// The badge text, or nil when no room was kept for one. Given to a part over
/// four studs long, a tile over two, and any part drawn smaller on its own.
@property (nonatomic, readonly, copy, nullable) NSString *annotationText;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawStepPartListLayout
///
/// @abstract   A packed parts list: one common scale, and a cell for each entry
///             that fits.
///
/// @discussion The same inputs always give the same layout, so a caller can
///             cache one.
///
///             Cells are sorted tallest first and laid on shelves next-fit: a
///             new shelf starts when the next cell does not fit. On a shelf
///             each cell slides left into the empty corners of the cells
///             before it, so cells can overlap while their parts and labels
///             do not. Shelves are stacked heaviest at the bottom, and dropped
///             lightest first when the list overflows. A shelf of one part
///             under a shelf of one part rises toward it.
///
///             The box is as wide as its widest shelf, as in LPub3D. A WIDTH
///             only sets where the shelves wrap.
///
//------------------------------------------------------------------------------
@interface LDrawStepPartListLayout : NSObject

/// The packed content, excluding the frame padding.
@property (nonatomic, readonly) Size2 contentSize;

/// What the frame occupies: `contentSize` plus the padding on all four sides.
@property (nonatomic, readonly) Size2 frameSize;

/// The placement under a point of the content, or nil. A label can stand
/// outside its cell, so labels are tried first; of overlapping cells, the one
/// whose icon's middle is nearest wins.
- (nullable LDrawStepPartListPlacement *) placementAtPoint:(Point2)point NS_SWIFT_NAME(placement(at:));

/// Points per inch the layout was packed at. Code that turns points back into
/// inches, such as a resize drag, must use this and not a default.
@property (nonatomic, readonly) double pointsPerInch;

/// The narrowest WIDTH, in points with the frame padding, that packs every
/// part on one shelf at full size. The frame drawn there can be narrower. A
/// width drag stops here. 0 with no entries.
@property (nonatomic, readonly) double oneRowFrameWidth;

/// The frame height, in points, of that one shelf. A lower HEIGHT packs the
/// same, so a height drag stops here. 0 with no entries.
@property (nonatomic, readonly) double oneRowFrameHeight;

/// The frame height, in points, of the packing a HEIGHT keeps when every
/// packing fits: the one as wide as the widest cell. A higher HEIGHT packs the
/// same, so a height drag stops here. 0 with no entries.
@property (nonatomic, readonly) double tallestFrameHeight;

/// The smallest frame size, in points, that packs this list the same again, so
/// a resize drag starts from it and the frame does not jump when grabbed. Where
/// a part is drawn smaller, the icons shrank or shelves were dropped, the WIDTH
/// or HEIGHT packed with instead.
@property (nonatomic, readonly) Size2 resizeStartSize;

/// Points per LDU shared by every icon that was not capped. The shared scale
/// is what makes the parts look right next to each other.
@property (nonatomic, readonly) double scale;

@property (nonatomic, readonly) NSUInteger rowCount;

@property (nonatomic, readonly) NSArray<LDrawStepPartListPlacement *> *placements;

/// Entries dropped because they did not fit even at the minimum scale. The
/// caller shows a "+N more" note instead of clipping them silently.
@property (nonatomic, readonly) NSUInteger overflowCount;

+ (instancetype) layoutForEntries:(NSArray<LDrawStepPartListEntry *> *)entries
					   constraint:(LDrawStepPartListConstraint)constraint
					viewTransform:(Matrix4)viewTransform
						  metrics:(LDrawStepPartListMetrics)metrics
	NS_SWIFT_NAME(layout(forEntries:constraint:viewTransform:metrics:));


// MARK: - Defaults

/// Metrics to start from. A caller changes the fields it cares about instead
/// of filling in the whole struct.
+ (LDrawStepPartListMetrics) defaultMetrics;

/// AREA with no scope, which is LPub3D's default. A step that says nothing
/// gets its constraint from the policy class, not from here.
+ (LDrawStepPartListConstraint) defaultConstraint;

/// The constraint a directive expresses, or `defaultConstraint` for nil.
+ (LDrawStepPartListConstraint) constraintForDirective:(nullable LPubPliConstrain *)directive;

/// A rotation-only transform for the given latitude/longitude/roll in degrees,
/// suitable for `viewTransform:`.
+ (Matrix4) viewTransformForAngle:(Tuple3)degrees;

/// A rotation-only transform matching LPub3D's camera for these angles, in
/// degrees: from the front, turned `longitude` about the vertical, then
/// tilted `latitude` over the top. LPub3D's parts list uses 23, -45.
+ (Matrix4) viewTransformForLatitude:(double)latitude longitude:(double)longitude
	NS_SWIFT_NAME(viewTransform(latitude:longitude:));

/// The other way: the latitude and longitude of a view transform, in degrees.
/// NO when the camera is tilted to one side, which the two angles cannot say.
/// Seen from straight above or below, the longitude is read from the camera's
/// up.
+ (BOOL) getLatitude:(double *)latitude longitude:(double *)longitude ofViewTransform:(Matrix4)transform
	NS_SWIFT_NAME(getLatitude(_:longitude:ofViewTransform:));

/// The full rotation for an entry's icon: its own `listOrientation`, then the
/// list's view transform. The packer and the drawing code both call this, so
/// they measure and draw the same thing.
+ (Matrix4) transformForEntry:(LDrawStepPartListEntry *)entry
				viewTransform:(Matrix4)viewTransform
	NS_SWIFT_NAME(transform(for:viewTransform:));

/// The middle of what the packer measured for this entry, in view space. The
/// drawing code puts this point at the center of the cell.
+ (Point3) projectedCenterOfEntry:(LDrawStepPartListEntry *)entry
					viewTransform:(Matrix4)viewTransform
	NS_SWIFT_NAME(projectedCenter(of:viewTransform:));


// MARK: - Text

/// The multiplier under an icon. Every entry gets one, "1×" included.
+ (NSString *) quantityTextForQuantity:(NSUInteger)quantity;

/// The size badge drawn for text the host measured: one point taller than the
/// text, half its height wider at each end for the rounded ends, centered in
/// `slot` and no larger than it. The corners are half the height round.
+ (Box2) badgeRectForTextSize:(Size2)textSize inSlot:(Box2)slot
	NS_SWIFT_NAME(badgeRect(forTextSize:inSlot:));

@end

NS_ASSUME_NONNULL_END
