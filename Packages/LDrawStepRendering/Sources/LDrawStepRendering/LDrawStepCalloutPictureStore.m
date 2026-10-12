//==============================================================================
//
//  File:       LDrawStepCalloutPictureStore.m
//  Package:    LDrawStepRendering
//
//  Purpose:    Keeps the pictures the callouts' boxes show.
//
//  Created by Sergey Slobodenyuk on 2026-10-12.
//
//==============================================================================

#import <LDrawStepRendering/LDrawStepCalloutPictureStore.h>

#import <LDrawFeatures/LDrawStepCalloutBox.h>


/// The most pictures kept at once. Past this, the ones no box on show uses are
/// dropped.
static const NSUInteger MAXIMUM_KEPT_PICTURES = 48;

/// How long the zoom has to stay as it is before the pictures are drawn again
/// at the new size.
static const NSTimeInterval PICTURE_SETTLE_DELAY = 0.15;

static const double DEFAULT_SCALE = 2.0;


@implementation LDrawStepCalloutPictureStore
{
	/// Each picture by what it shows and how big it is. The values are
	/// CGImage objects.
	NSMutableDictionary<NSString *, id>	*pictures;
	/// The picture on show of each thing the boxes show, whatever its size.
	NSMutableDictionary<NSString *, id>	*shownPictures;
	/// The boxes pictures were last made for.
	NSArray<LDrawStepCalloutBox *>		*boxes;
	/// Pictures left on show at another size were not drawn again when the
	/// zoom settled, so the next pass draws them without waiting.
	BOOL								 owesPictures;
}


//========== init ==============================================================
- (instancetype) init
{
	self = [super init];
	if (self) {
		self->_scale		= DEFAULT_SCALE;
		self->pictures		= [NSMutableDictionary dictionary];
		self->shownPictures	= [NSMutableDictionary dictionary];
		self->boxes			= @[];
	}
	return self;

}//end init


//========== makePicturesForBoxes:waitingForZoom: ==============================
- (void) makePicturesForBoxes:(NSArray<LDrawStepCalloutBox *> *)newBoxes waitingForZoom:(BOOL)waits
{
	NSMutableSet<NSString *>			*inUse		= [NSMutableSet set];
	NSMutableDictionary<NSString *, id>	*shown		= [NSMutableDictionary dictionary];
	BOOL								 isWaiting	= NO;

	self->boxes = [newBoxes copy];

	// This pass decides again whether anything is left to draw later.
	[self cancelUpdate];

	if (self->owesPictures) {
		waits = NO;
		self->owesPictures = NO;
	}

	for (LDrawStepCalloutBox *box in self->boxes) {
		for (LDrawStepCalloutPicture *picture in box.pictures) {
			NSString	*key	= [self keyForPicture:picture];
			id			 image	= self->pictures[key];
			id			 kept	= self->shownPictures[picture.subjectKey];

			[inUse addObject:key];

			if (image == nil && kept != nil && waits) {
				image		= kept;
				isWaiting	= YES;
			}
			else if (image == nil) {
				image = [self makeImageForPicture:picture];

				if (image != nil) {
					self->pictures[key] = image;
				}
			}

			if (image != nil) {
				shown[picture.subjectKey] = image;
			}
		}
	}

	self->shownPictures = shown;

	if (isWaiting) {
		[self performSelector:@selector(updateAfterZoom) withObject:nil afterDelay:PICTURE_SETTLE_DELAY];
	}

	if (self->pictures.count > MAXIMUM_KEPT_PICTURES) {
		for (NSString *key in [self->pictures allKeys]) {
			if ([inUse containsObject:key] == NO) {
				[self->pictures removeObjectForKey:key];
			}
		}
	}

}//end makePicturesForBoxes:waitingForZoom:


//========== imageForPicture: ==================================================
- (nullable CGImageRef) imageForPicture:(LDrawStepCalloutPicture *)picture
{
	id image = self->pictures[[self keyForPicture:picture]] ?: self->shownPictures[picture.subjectKey];

	return (__bridge CGImageRef)image;

}//end imageForPicture:


//========== discardPictures ===================================================
///
/// @abstract	Forgets every picture.
///
/// @discussion	A redraw still waiting for the zoom is called off. It would draw
///				for the boxes last shown, which are from before the change
///				that asks for this.
///
//==============================================================================
- (void) discardPictures
{
	[self cancelUpdate];

	[self->pictures removeAllObjects];
	[self->shownPictures removeAllObjects];

}//end discardPictures


// MARK: - PRIVATE -


//========== makeImageForPicture: ===============================================
- (nullable id) makeImageForPicture:(LDrawStepCalloutPicture *)picture
{
	CGImageRef image = [self.source newImageOfModel:picture.model
											 center:picture.center
									 zoomPercentage:picture.zoomPercentage
											   size:picture.rect.size
											  scale:self.scale];

	return CFBridgingRelease(image);

}//end makeImageForPicture:


//========== keyForPicture: ====================================================
///
/// @abstract	Names a picture as it is kept: what it shows, and how big.
///
//==============================================================================
- (NSString *) keyForPicture:(LDrawStepCalloutPicture *)picture
{
	return [NSString stringWithFormat:@"%.2f|%.1fx%.1f|%@",
			self.scale, picture.rect.size.width, picture.rect.size.height, picture.contentKey];

}//end keyForPicture:


//========== cancelUpdate ======================================================
- (void) cancelUpdate
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateAfterZoom) object:nil];

}//end cancelUpdate


//========== updateAfterZoom ===================================================
///
/// @abstract	The zoom has settled: draws the pictures that were left on show
///				at another size.
///
//==============================================================================
- (void) updateAfterZoom
{
	id<LDrawStepCalloutPictureStoreDelegate> delegate = self.delegate;

	if ([delegate respondsToSelector:@selector(calloutPictureStoreShouldUpdatePictures:)]
		&& [delegate calloutPictureStoreShouldUpdatePictures:self] == NO) {
		self->owesPictures = YES;
		return;
	}

	[self makePicturesForBoxes:self->boxes waitingForZoom:NO];
	[delegate calloutPictureStoreDidUpdatePictures:self];

}//end updateAfterZoom

@end
