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
@class LDrawStepPartListLayout;
@class LDrawStepPartListPresentation;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepOverlayRenderer
///
/// @abstract   Draws what a step shows over the model: LPub3D's page, the parts
///             list's frame and labels, the callouts, and the button that leads
///             back from a called-out submodel.
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

/// Formats the host has localized. Each takes one unsigned long: how many parts
/// a list cut short leaves out, and how many steps build a callout's submodels.
@property (nonatomic, copy) NSString *overflowFormat;
@property (nonatomic, copy) NSString *stepCountFormat;

/// What the button that leads back says. Nil or empty shows no button.
@property (nonatomic, copy, nullable) NSString *returnTitle;

/// The bottom layer: the page, the dimming around it, and the list's frame
/// with its pins.
- (void) drawPageAndFrameInContext:(CGContextRef)context viewSize:(Size2)viewSize
	NS_SWIFT_NAME(drawPageAndFrame(in:viewSize:));

/// The top layer: each callout's arrows and box, and the button that leads
/// back.
- (void) drawCalloutsInContext:(CGContextRef)context viewSize:(Size2)viewSize
	NS_SWIFT_NAME(drawCallouts(in:viewSize:));

/// Where the button is in a view of this size: its bottom left corner, as far
/// in as the list is from the top. An empty box when there is no title.
- (Box2) returnButtonRectForViewSize:(Size2)viewSize NS_SWIFT_NAME(returnButtonRect(forViewSize:));

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

@end

NS_ASSUME_NONNULL_END
