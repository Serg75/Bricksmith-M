//==============================================================================
//
//  File:       LDrawStepOverlayRenderer.h
//  Package:    LDrawStepRendering
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>
#import <LDrawFeatures/LDrawStepPartListPolicy.h>

@class LDrawStepCalloutPictureStore;
@class LDrawStepCalloutText;
@class LDrawStepPartListLayout;
@class LDrawStepPartListPresentation;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @enum       LDrawStepTurnedViewButton
///
/// @abstract   A button of the strip shown while the view is turned away from
///             the step's angle.
///
//------------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, LDrawStepTurnedViewButton) {
	/// Writes the view's angle as the step's.
	LDrawStepTurnedViewButtonUseAngle	= 0,
	/// Turns the view back to the step's angle.
	LDrawStepTurnedViewButtonStepAngle	= 1
};


//------------------------------------------------------------------------------
///
/// @class      LDrawStepOverlayRenderer
///
/// @abstract   Draws what a step shows over the model: LPub3D's page and its
///             number, the parts list's frame and labels, the callouts, and the
///             button that leads back from a called-out submodel.
///
/// @discussion Plain CoreGraphics and CoreText, so any host with a context can
///             use it. In the context the view's top left corner is the origin
///             and y runs down, as in the presentation's rectangles.
///
///             The host draws the parts list's icons itself, between the frame
///             and the labels, so the drawing comes in layers.
///
//------------------------------------------------------------------------------
@interface LDrawStepOverlayRenderer : NSObject

/// What to draw. Nil draws nothing but the button.
@property (nonatomic, strong, nullable) LDrawStepPartListPresentation *presentation;

/// Each callout's arrows: one block of LDrawStepCalloutArrow values per box, in
/// the order of the presentation's boxes.
@property (nonatomic, copy, nullable) NSArray<NSData *> *calloutArrows;

/// Where the callouts' pictures come from. With none, a box names its submodel
/// instead.
@property (nonatomic, strong, nullable) LDrawStepCalloutPictureStore *pictureStore;

/// The fill of the list's frame, of a callout's box off the page, and of the
/// button. Nil fills none of them.
@property (nonatomic, nullable) CGColorRef listBackgroundColor;

/// The fill of a pin on the list's frame. Nil draws no pins.
@property (nonatomic, nullable) CGColorRef pinColor;

/// The color of the dashed frame around the arranged step, with its handles,
/// and of the line around the page. Nil draws neither.
@property (nonatomic, nullable) CGColorRef arrangeFrameColor;

/// The part of the view the viewport's scroll bars leave uncovered. The line
/// around the page stays inside it. An empty box is the whole view.
@property (nonatomic) Box2 unobscuredRect;

/// Guides on the page: Box2 lines with no width or no height, such as the
/// page's middle lines and margins that the arranged step or a dragged list
/// meets. Drawn in `guideColor`, and not at all with none.
@property (nonatomic, copy, nullable) NSData *guides;
@property (nonatomic, nullable) CGColorRef guideColor;

/// Where the previous step's assembly sat on its page: an outline of Point2
/// values in the view, filled in `ghostColor` on the paper. Not drawn with
/// fewer than 3 points or no color.
@property (nonatomic, copy, nullable) NSData *ghostOutline;
@property (nonatomic, nullable) CGColorRef ghostColor;

/// A picture of the previous step's assembly, drawn faintly in `ghostRect` in
/// place of the outline's fill. NULL draws the outline.
@property (nonatomic, nullable) CGImageRef ghostImage;
@property (nonatomic) Box2 ghostRect;

/// The frame of the item the arrow keys move, the parts list or a callout's
/// box, in the view. Outlined in `selectionColor`. An empty box draws nothing.
@property (nonatomic) Box2 selectionRect;
@property (nonatomic, nullable) CGColorRef selectionColor;

/// Formats the host has localized. Each takes one unsigned long: how many parts
/// a list cut short leaves out, and how many steps build a callout's submodels.
@property (nonatomic, copy) NSString *overflowFormat;
@property (nonatomic, copy) NSString *stepCountFormat;

/// What the button that leads back says. Nil or empty shows no button.
@property (nonatomic, copy, nullable) NSString *returnTitle;

/// The strip at the top of the view that says the view is turned away from
/// the angle LPub3D prints the step at: what it says, and the titles of its
/// two buttons. No strip while the text is nil or empty.
@property (nonatomic, copy, nullable) NSString *turnedViewText;
@property (nonatomic, copy, nullable) NSString *useAngleTitle;
@property (nonatomic, copy, nullable) NSString *stepAngleTitle;

/// The bottom layer: the dimming around the page, the previous step's
/// outline, the page's number, and the list's frame with its pins.
- (void) drawPageAndFrameInContext:(CGContextRef)context viewSize:(Size2)viewSize
	NS_SWIFT_NAME(drawPageAndFrame(in:viewSize:));

/// The top layer: each callout's arrows and box, the selected item's outline,
/// the guides, the frame of a step being arranged and the view's edge, the
/// button that leads back, and the strip of a turned view.
- (void) drawCalloutsInContext:(CGContextRef)context viewSize:(Size2)viewSize
	NS_SWIFT_NAME(drawCallouts(in:viewSize:));

/// Where the button is in a view of this size: its bottom left corner, as far
/// in as the list is from the top. An empty box when there is no title.
- (Box2) returnButtonRectForViewSize:(Size2)viewSize NS_SWIFT_NAME(returnButtonRect(forViewSize:));

/// Where that strip is in a view of this size: across the middle of its top.
/// An empty box when there is no strip.
- (Box2) turnedViewStripRectForViewSize:(Size2)viewSize NS_SWIFT_NAME(turnedViewStripRect(forViewSize:));

/// Where one of the strip's buttons is, or an empty box when there is no strip.
- (Box2) rectOfTurnedViewButton:(LDrawStepTurnedViewButton)button forViewSize:(Size2)viewSize
	NS_SWIFT_NAME(rect(ofTurnedViewButton:forViewSize:));

/// The middle layer, for one packed list: the counts, the size badges, a box
/// for each part that is missing, and the notice of a list cut short. The
/// list's top left corner is the context's origin, and `contentWidth` is how
/// wide the list is drawn.
+ (void) drawLabelsOfLayout:(LDrawStepPartListLayout *)layout
					 chrome:(LDrawStepPartListChrome)chrome
			   contentWidth:(double)contentWidth
			 overflowFormat:(NSString *)overflowFormat
				  inContext:(CGContextRef)context
	NS_SWIFT_NAME(drawLabels(of:chrome:contentWidth:overflowFormat:in:));

/// The same, with the counts in the font `countText` names and the size
/// badges in the font `annotationText` names. Their colors are the chrome's.
/// The counts' size is the chrome's label size, and a nil `countText` writes
/// them in the system's bold font. The badges' size is the chrome's annotation
/// size, and a nil `annotationText` writes them as big as the counts in the
/// system's font.
+ (void) drawLabelsOfLayout:(LDrawStepPartListLayout *)layout
					 chrome:(LDrawStepPartListChrome)chrome
				  countText:(nullable LDrawStepCalloutText *)countText
			 annotationText:(nullable LDrawStepCalloutText *)annotationText
			   contentWidth:(double)contentWidth
			 overflowFormat:(NSString *)overflowFormat
				  inContext:(CGContextRef)context
	NS_SWIFT_NAME(drawLabels(of:chrome:countText:annotationText:contentWidth:overflowFormat:in:));

@end

NS_ASSUME_NONNULL_END
