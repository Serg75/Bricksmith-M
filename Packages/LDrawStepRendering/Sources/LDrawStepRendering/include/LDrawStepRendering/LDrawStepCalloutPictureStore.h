//==============================================================================
//
//  File:       LDrawStepCalloutPictureStore.h
//  Package:    LDrawStepRendering
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>

@class LDrawModel;
@class LDrawStepCalloutBox;
@class LDrawStepCalloutPicture;
@class LDrawStepCalloutPictureStore;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @protocol   LDrawStepCalloutPictureSource
///
/// @abstract   Draws a model off screen. The host has the 3D renderer, so it
///             makes the pictures.
///
//------------------------------------------------------------------------------
@protocol LDrawStepCalloutPictureSource <NSObject>

/// A picture of a model seen straight on with no perspective, on a clear
/// background. `size` is in points and `scale` is pixels per point. The zoom
/// and the center mean what they do for a view. NULL when no picture can be
/// drawn off screen.
- (nullable CGImageRef) newImageOfModel:(LDrawModel *)model
								 center:(Point3)center
						 zoomPercentage:(double)zoomPercentage
								   size:(Size2)size
								  scale:(double)scale CF_RETURNS_RETAINED;

@end


//------------------------------------------------------------------------------
///
/// @protocol   LDrawStepCalloutPictureStoreDelegate
///
//------------------------------------------------------------------------------
@protocol LDrawStepCalloutPictureStoreDelegate <NSObject>

/// The zoom has settled, and the pictures left on show at another size were
/// drawn again. The host redraws.
- (void) calloutPictureStoreDidUpdatePictures:(LDrawStepCalloutPictureStore *)store;

@optional

/// NO while the host has nowhere to show pictures, such as a view in no
/// window. The store then draws them the next time pictures are made. YES when
/// not implemented.
- (BOOL) calloutPictureStoreShouldUpdatePictures:(LDrawStepCalloutPictureStore *)store;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawStepCalloutPictureStore
///
/// @abstract   Keeps a picture of what each callout's box shows, so a redraw
///             that changes nothing draws none again.
///
/// @discussion A picture is kept by what it shows and how big it is. A zoom
///             gives every picture another size at each step it takes, so
///             while the zoom runs the pictures on show are stretched, and
///             they are drawn at the new size once the zoom has settled.
///
///             A key does not see inside a submodel. The host discards the
///             pictures when a change may have reached one.
///
//------------------------------------------------------------------------------
@interface LDrawStepCalloutPictureStore : NSObject

@property (nonatomic, weak, nullable) id<LDrawStepCalloutPictureSource> source;
@property (nonatomic, weak, nullable) id<LDrawStepCalloutPictureStoreDelegate> delegate;

/// Pixels per point of the screen the pictures are shown on. 2 to begin with.
@property (nonatomic) double scale;

/// Makes each picture of each box, unless one that shows the same thing is
/// kept. With `waits`, a picture on show at another size stays on show, and
/// is drawn at the new size a moment later, unless pictures are made again
/// before then.
- (void) makePicturesForBoxes:(NSArray<LDrawStepCalloutBox *> *)boxes waitingForZoom:(BOOL)waits
	NS_SWIFT_NAME(makePictures(for:waitingForZoom:));

/// The picture to draw for one of those boxes' pictures, or NULL when none
/// could be made.
- (nullable CGImageRef) imageForPicture:(LDrawStepCalloutPicture *)picture
	CF_RETURNS_NOT_RETAINED NS_SWIFT_NAME(image(for:));

/// Forgets every picture, so each is drawn again when next made. Call it when
/// what the pictures show may have changed.
- (void) discardPictures;

@end

NS_ASSUME_NONNULL_END
