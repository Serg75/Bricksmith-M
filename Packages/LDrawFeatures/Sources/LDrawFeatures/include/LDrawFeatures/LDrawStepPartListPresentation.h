//==============================================================================
//
//  File:       LDrawStepPartListPresentation.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-09-18.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LPubColor.h>
#import <LDrawCore/LPubPlacement.h>
#import <LDrawCore/LPubPliConstrain.h>
#import <LDrawCore/MatrixMath.h>

#import <LDrawFeatures/LDrawStepPartListPolicy.h>

@class LDrawModel;
@class LDrawStepCalloutArrangement;
@class LDrawStepCalloutBox;
@class LDrawStepCalloutText;
@class LDrawStepPageNumbers;
@class LDrawStepPartListEntry;
@class LDrawStepPartListLayout;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @enum       LDrawStepArrangeHandle
///
/// @abstract   A corner handle of the frame drawn around the step while it is
///             arranged. Dragging one scales the assembly.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LDrawStepArrangeHandle) {
	LDrawStepArrangeHandleNone			= 0,
	LDrawStepArrangeHandleTopLeft		= 1,
	LDrawStepArrangeHandleTopRight		= 2,
	LDrawStepArrangeHandleBottomRight	= 3,
	LDrawStepArrangeHandleBottomLeft	= 4
};


//------------------------------------------------------------------------------
///
/// @struct     LDrawStepPartListHostState
///
/// @abstract   What the host measures for one redraw: the things only a view
///             can answer.
///
//------------------------------------------------------------------------------
typedef struct LDrawStepPartListHostState {
	/// The view the list is drawn over, in points.
	Size2		viewSize;
	/// Points per LDU the model is drawn at beside the page anchor. Only read
	/// on LPub3D's page; 0 draws no page.
	double		assemblyScale;
	/// Where the model point the page is kept centered on lands in the view,
	/// in its points, y down.
	Point2		pageCenterInView;
	/// The box around the step's assembly as the view draws it, or an empty
	/// box when it was not measured. Only read on the page, to place callouts
	/// and to center the page.
	Box2		assemblyRect;
	/// A resize drag in progress, its axis and the size it asks for.
	BOOL		hasPreview;
	LPubPliAxis	previewAxis;
	double		previewInches;
	/// A callout drag in progress: which box of the step, and where its corner
	/// is held, in the view.
	BOOL		hasCalloutPreview;
	NSUInteger	calloutPreviewBox;
	Point2		calloutPreviewPoint;
	/// A drag of the parts list in progress: where its frame's top left
	/// corner is held, in the view.
	BOOL		hasListPreview;
	Point2		listPreviewOrigin;
} LDrawStepPartListHostState;


//------------------------------------------------------------------------------
///
/// @class      LDrawStepPartListPresentation
///
/// @abstract   Everything the host draws for the visible step: the page, the
///             packed list, its icon model, the chrome, the pins and the
///             callouts.
///
/// @discussion Worked out in one place because the order matters: the metrics
///             are scaled to the page before the height budget is taken from
///             it, and the document's CONSTRAIN is read only on the page.
///
//------------------------------------------------------------------------------
@interface LDrawStepPartListPresentation : NSObject

- (instancetype) init NS_UNAVAILABLE;

/// Collects, packs and places the list for the model's visible step.
+ (instancetype) presentationForModel:(nullable LDrawModel *)model
								 host:(LDrawStepPartListHostState)host
	NS_SWIFT_NAME(init(model:host:));

/// The same, with the page numbers a host keeps for the file. Nil, or a count
/// for another file, counts the pages again.
+ (instancetype) presentationForModel:(nullable LDrawModel *)model
								 host:(LDrawStepPartListHostState)host
						  pageNumbers:(nullable LDrawStepPageNumbers *)pageNumbers
	NS_SWIFT_NAME(init(model:host:pageNumbers:));

/// Whether the list is drawn on LPub3D's page. Only then does the document's
/// CONSTRAIN count, and only then can the frame be resized.
@property (nonatomic, readonly) BOOL isOnPage;

/// The page in the view, or `ZeroBox2` when there is none.
@property (nonatomic, readonly) Box2 pageRect;

/// Where the middle of the page belongs for this step, in the view. LPub3D
/// takes one box around the assembly and the callouts placed against it that
/// have not been dragged, and puts that box where the `ASSEM PLACEMENT` line
/// says: in the middle of the page when there is no such line. The page itself
/// is drawn where the host keeps it, so the host moves it here when the step
/// is to be centered. NO off the page, and with no assembly measured.
@property (nonatomic, readonly) BOOL hasStepCenter;
@property (nonatomic, readonly) Point2 stepCenterInView;

/// That box around the assembly and what is centered with it, in the view. An
/// empty box when there is no step center.
@property (nonatomic, readonly) Box2 stepRect;

/// The point of that box that stays put on the page as the assembly grows: its
/// middle, or the corner or side its `ASSEM PLACEMENT` places it by.
@property (nonatomic, readonly) Point2 stepAnchorInView;

/// Where the dashed line runs while the step is arranged: that box, a few
/// points larger all round. `ZeroBox2` when there is no step center.
@property (nonatomic, readonly) Box2 arrangeFrameRect;

/// The square drawn for a handle on a corner of `arrangeFrameRect`. Only the
/// corners that move as the step grows have one: `ZeroBox2` for the others.
- (Box2) rectOfArrangeHandle:(LDrawStepArrangeHandle)handle NS_SWIFT_NAME(rect(ofArrangeHandle:));

/// The handle under a point of the view, taken a little wider than drawn.
- (LDrawStepArrangeHandle) arrangeHandleAtPoint:(Point2)point NS_SWIFT_NAME(arrangeHandle(at:));

/// How far in from the page's edges the step is kept, in page inches: the
/// file's `PAGE MARGINS`, else LPub3D's 0.05.
- (Size2) pageMargins;

/// Where the list's frame goes, at its size, at one of the page's nine places
/// with no offset: its top left corner in the view, kept as far in from the
/// page's edges as LPub3D keeps it. Zero off the page, or with no list.
- (Point2) listOriginAtPagePosition:(LPubPlacementPosition)position
	NS_SWIFT_NAME(listOrigin(atPagePosition:));

/// The text of the PLACEMENT lines that say where the step's assembly and
/// callouts go on the page, with the way each callout's steps run, which of
/// them follow a divider, and the size of each box that is centered with the
/// assembly. A host compares it, to know when the step has to be centered
/// again. Empty off the page.
@property (nonatomic, readonly) NSString *placementKey;

/// Points one page inch covers, or 0 off the page.
@property (nonatomic, readonly) double pointsPerPageInch;

/// How wide the parts are outlined on the page, in points. 0 off the page, or
/// when bold outlines are off.
@property (nonatomic, readonly) double outlineWidth;

/// What the frame is packed against and sits in: the page, else the view.
@property (nonatomic, readonly) Size2 hostSize;

/// The frame in the view, and the icon area inside its padding. Both are
/// `ZeroBox2` when there is nothing to draw.
@property (nonatomic, readonly) Box2 frameRect;
@property (nonatomic, readonly) Box2 contentRect;

/// The values the frame is drawn with, scaled to the page when there is one.
/// On the page its outline, its fill, its counts' size and color, and its
/// badges' size and text color when the file gives them, are the file's.
@property (nonatomic, readonly) LDrawStepPartListChrome chrome;

/// The same values without the file's PLI lines, for what is drawn in the
/// callouts' boxes. Their parts are packed with the list's own sizes.
@property (nonatomic, readonly) LDrawStepPartListChrome calloutChrome;

/// The page's color from the file, which the host clears the view to behind
/// the model. NO off the page, and for a file that gives no color.
@property (nonatomic, readonly) BOOL hasPageColor;
@property (nonatomic, readonly) LPubColorComponents pageColor;

/// The font the counts are written in on the page, from the file. Nil off the
/// page. Their size and color are the chrome's.
@property (nonatomic, readonly, nullable) LDrawStepCalloutText *countText;

/// The font the size badges are written in on the page, from the file. Nil off
/// the page, and for a file that gives none. Their size and color are the
/// chrome's.
@property (nonatomic, readonly, nullable) LDrawStepCalloutText *annotationText;

/// The page's number as the file prints it, such as "16", or "10/15" for a
/// step on two pages. Nil off the page, when the file or the host hides it,
/// and for a step on no page.
@property (nonatomic, readonly, nullable) NSString *pageNumber;

/// Where the number is drawn in the view, and its font and color.
@property (nonatomic, readonly) Box2 pageNumberRect;
@property (nonatomic, readonly, nullable) LDrawStepCalloutText *pageNumberText;

/// The packed list, or nil when there is nothing to draw.
@property (nonatomic, readonly, nullable) LDrawStepPartListLayout *layout;

/// The row of the list whose cell is under a point of the view, or nil.
- (nullable LDrawStepPartListEntry *) entryAtPoint:(Point2)point NS_SWIFT_NAME(entry(at:));

/// The parts placed as the layout says, for the icon view to draw, and the
/// camera that view needs to show them where the layout put them. The model
/// is built the first time it is asked for.
@property (nonatomic, readonly, nullable) LDrawModel *iconModel;
@property (nonatomic, readonly) double iconZoomPercentage;
@property (nonatomic, readonly) Point3 iconCenter;

/// What the icons show, as bytes. A host already showing icons of the same
/// key can keep them and never ask for the model. Nil with no list.
@property (nonatomic, readonly, copy, nullable) NSData *iconKey;

/// One box per callout of the step, stacked under the frame. Empty when the
/// step has none.
@property (nonatomic, readonly) NSArray<LDrawStepCalloutBox *> *calloutBoxes;

/// The callout's box under a point of the view, or nil. Where two overlap it
/// is the one drawn last, which is the one on top.
- (nullable LDrawStepCalloutBox *) calloutBoxAtPoint:(Point2)point NS_SWIFT_NAME(calloutBox(at:));

/// Moves the callouts' boxes with what they call out, for a camera that has
/// been turned since the step was laid out. A box goes as far as the middle of
/// what it places has moved in the view, where there is room. It stays on the
/// page, and clear of the parts list and of the other boxes, by the larger of
/// the two things' margins. It also keeps off the arrows where it can. A box
/// the file puts off the page stays where it is: one that reaches more than a
/// tenth of an inch over an edge.
///
/// `places` has, for each box, where the camera draws what it places now, as
/// Box2 values: a box with no size at the middle of its placements, then the
/// box around each placement one of its arrows goes to. A placement that
/// cannot be measured is a box with no size at its middle. `laidOutPlaces`
/// has the same as it was drawn when the step was laid out.
///
/// With no arrangement each box keeps to the side of the others and of the
/// arrows that the file's layout puts it on. With one, the boxes may go to
/// another side of their submodels and change places where that is better,
/// and they move there over a short time.
///
/// Does nothing off the page.
- (void) moveCalloutBoxesFrom:(NSArray<NSData *> *)laidOutPlaces
						   to:(NSArray<NSData *> *)places
				  arrangement:(nullable LDrawStepCalloutArrangement *)arrangement
	NS_SWIFT_NAME(moveCalloutBoxes(from:to:arrangement:));

/// Puts the callouts' boxes by itself, for when their PLACEMENT lines are not
/// read. Each box goes beside the step's assembly, past the side nearest what
/// it calls out and level with that, where there is room. It stays on the
/// page, clear of the parts list and of the other boxes, and off the arrows.
///
/// `assemblyRect` is the box around the step's assembly as the camera draws it
/// now. `places` is as for moving the boxes. With an arrangement the boxes
/// keep their sides from one layout to the next, change them only for a gain
/// that is worth a move, and move over a short time when they do.
///
/// Does nothing off the page.
- (void) placeCalloutBoxesAroundAssembly:(Box2)assemblyRect
								  places:(NSArray<NSData *> *)places
							 arrangement:(nullable LDrawStepCalloutArrangement *)arrangement
	NS_SWIFT_NAME(placeCalloutBoxes(aroundAssembly:places:arrangement:));

/// Puts the callouts' boxes where the file puts them, for a camera at the
/// angle the step was laid out at. A box that had gone to another side moves
/// back over a short time. Does nothing off the page.
- (void) restCalloutBoxesWithArrangement:(LDrawStepCalloutArrangement *)arrangement
	NS_SWIFT_NAME(restCalloutBoxes(arrangement:));

/// Whether the frame grows to the left as it gets wider, and upward as it
/// gets taller: the file places it by its right or bottom edge. Its resize
/// edges and pins are then on the left and top. NO off the page.
@property (nonatomic, readonly) BOOL growsLeftward;
@property (nonatomic, readonly) BOOL growsUpward;

/// The control under a point of the view: an edge to drag, or a pin to click.
- (LDrawStepPartListControl) controlAtPoint:(Point2)point NS_SWIFT_NAME(control(at:));

/// Where an axis's pin is drawn, on the edge that moves.
- (Box2) pinRectForAxis:(LPubPliAxis)axis NS_SWIFT_NAME(pinRect(forAxis:));

/// Where the pin of the step's own placement is drawn, on the corner that
/// stays put as the frame grows.
@property (nonatomic, readonly) Box2 placementPinRect;

/// The most room the frame may take on each axis, in points: the page less
/// the larger of its margins and the list's, or the policy's share of the view
/// off the page. Packing and a resize drag both stop here.
@property (nonatomic, readonly) Size2 allowedFrameSize;

/// A point of the view as the resize arithmetic reads it. Across an edge that
/// stays put it is mirrored, so a drag away from the frame makes it bigger.
- (Point2) resizePointForPoint:(Point2)point NS_SWIFT_NAME(resizePoint(for:));

/// Whether each axis shows a pin: set by the step's own line, or by where a
/// drag would leave it.
@property (nonatomic, readonly) BOOL widthPinned;
@property (nonatomic, readonly) BOOL heightPinned;

/// Whether the corner shows a pin: the step places the list with its own
/// line. NO while the list is dragged.
@property (nonatomic, readonly) BOOL placementPinned;

/// The size the step has on this axis without its own line, which a drag
/// snaps to. 0 for none, and always 0 off the page.
- (double) inheritedInchesForAxis:(LPubPliAxis)axis NS_SWIFT_NAME(inheritedInches(forAxis:));

@end

NS_ASSUME_NONNULL_END
