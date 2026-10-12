//==============================================================================
//
//  File:       LDrawStepPartListPageAnchor.m
//  Package:    LDrawFeatures
//
//  Purpose:    Keeps the model points the page is pinned to.
//
//  Created by Sergey Slobodenyuk on 2026-09-17.
//
//==============================================================================

#import <LDrawFeatures/LDrawStepPartListPageAnchor.h>

#import <LDrawCore/LDrawModel.h>

#import <LDrawFeatures/LDrawStepPartListPolicy.h>


@implementation LDrawStepPartListPageAnchor
{
	/// The model the point was measured in, or nil to measure again.
	__weak LDrawModel	*measuredModel;
	Point3				anchor;

	/// Drawn scale over zoom scale, or 0 until the host notes one.
	double				drawnScaleRatio;

	/// Where the middle of the page is drawn, once the host has set it.
	BOOL				hasPageCenter;
	Point3				pageCenter;

	/// The box around the assembly, from the middle of the page in page
	/// inches, once the host has noted one.
	BOOL				hasAssemblyBox;
	Box2				assemblyBox;
}

//========== anchorForModel: ===================================================
///
/// @abstract	The stored point, measured first for a new model.
///
//==============================================================================
- (Point3) anchorForModel:(nullable LDrawModel *)model
{
	if (model == nil) {
		return ZeroPoint3;
	}

	// A page center and an assembly's box belong to the model they were kept
	// for.
	if (model != self->measuredModel) {
		self->anchor			= [LDrawStepPartListPolicy pageAnchorInModel:model];
		self->measuredModel		= model;
		self->hasPageCenter		= NO;
		self->hasAssemblyBox	= NO;
	}

	return self->anchor;

}//end anchorForModel:


//========== pageCenterForModel: ===============================================
///
/// @abstract	The model point the middle of the page is drawn at.
///
//==============================================================================
- (Point3) pageCenterForModel:(nullable LDrawModel *)model
{
	Point3 measured = [self anchorForModel:model];

	return self->hasPageCenter ? self->pageCenter : measured;

}//end pageCenterForModel:


//========== hasPageCenterForModel: ============================================
- (BOOL) hasPageCenterForModel:(nullable LDrawModel *)model
{
	return model != nil && model == self->measuredModel && self->hasPageCenter;

}//end hasPageCenterForModel:


//========== setPageCenter:forModel: ===========================================
- (void) setPageCenter:(Point3)center forModel:(nullable LDrawModel *)model
{
	if (model == nil) {
		return;
	}

	// First, so a new model's anchor is measured before its center is kept.
	[self anchorForModel:model];

	self->pageCenter	= center;
	self->hasPageCenter	= YES;

}//end setPageCenter:forModel:


//========== noteAssemblyRect:aroundPageCenter:pointsPerPageInch: ==============
///
/// @abstract	Keeps the box around the step's assembly as it sits on the page.
///
//==============================================================================
- (void) noteAssemblyRect:(Box2)rect
		 aroundPageCenter:(Point2)pageCenter
		pointsPerPageInch:(double)pointsPerPageInch
{
	if (pointsPerPageInch <= 0.0 || V2BoxWidth(rect) <= 0.0 || V2BoxHeight(rect) <= 0.0) {
		self->hasAssemblyBox = NO;
		return;
	}

	self->assemblyBox		= V2MakeBox((rect.origin.x - pageCenter.x) / pointsPerPageInch,
										(rect.origin.y - pageCenter.y) / pointsPerPageInch,
										rect.size.width / pointsPerPageInch,
										rect.size.height / pointsPerPageInch);
	self->hasAssemblyBox	= YES;

}//end noteAssemblyRect:aroundPageCenter:pointsPerPageInch:


//========== hasAssemblyRect ===================================================
- (BOOL) hasAssemblyRect
{
	return self->hasAssemblyBox;

}//end hasAssemblyRect


//========== assemblyRectAroundPageCenter:pointsPerPageInch: ===================
///
/// @abstract	The kept box in the view, for a page whose middle and scale are
/// 			these.
///
//==============================================================================
- (Box2) assemblyRectAroundPageCenter:(Point2)pageCenter pointsPerPageInch:(double)pointsPerPageInch
{
	if (self->hasAssemblyBox == NO) {
		return ZeroBox2;
	}

	Box2 box = self->assemblyBox;

	return V2MakeBox(pageCenter.x + box.origin.x * pointsPerPageInch,
					 pageCenter.y + box.origin.y * pointsPerPageInch,
					 box.size.width * pointsPerPageInch,
					 box.size.height * pointsPerPageInch);

}//end assemblyRectAroundPageCenter:pointsPerPageInch:


//========== forgetAssemblyRect ================================================
- (void) forgetAssemblyRect
{
	self->hasAssemblyBox = NO;

}//end forgetAssemblyRect


//========== invalidate ========================================================
///
/// @abstract	Measure again on the next call.
///
//==============================================================================
- (void) invalidate
{
	self->measuredModel		= nil;
	self->drawnScaleRatio	= 0.0;
	self->hasPageCenter		= NO;
	self->hasAssemblyBox	= NO;

}//end invalidate


//========== needsDrawnScale ===================================================
- (BOOL) needsDrawnScale
{
	return self->drawnScaleRatio <= 0.0;

}//end needsDrawnScale


//========== drawnScaleRatio ===================================================
- (double) drawnScaleRatio
{
	return self->drawnScaleRatio;

}//end drawnScaleRatio


//========== setDrawnScaleRatio: ===============================================
- (void) setDrawnScaleRatio:(double)ratio
{
	self->drawnScaleRatio = ratio;

}//end setDrawnScaleRatio:


//========== noteDrawnPointsPerLDU:atZoomScale: ================================
///
/// @abstract	Keeps the drawn scale as a ratio against the zoom.
///
/// @discussion	A measure that cannot be read keeps the zoom alone, so it is
/// 			not taken again on every redraw.
///
//==============================================================================
- (void) noteDrawnPointsPerLDU:(double)drawnPointsPerLDU atZoomScale:(double)zoomScale
{
	self->drawnScaleRatio = (drawnPointsPerLDU > 0.0 && zoomScale > 0.0)
						  ? (drawnPointsPerLDU / zoomScale)
						  : 1.0;

}//end noteDrawnPointsPerLDU:atZoomScale:


//========== assemblyScaleForZoomScale: ========================================
///
/// @abstract	Points per LDU the page is sized from at this zoom.
///
//==============================================================================
- (double) assemblyScaleForZoomScale:(double)zoomScale
{
	double ratio = (self->drawnScaleRatio > 0.0) ? self->drawnScaleRatio : 1.0;

	return zoomScale * ratio;

}//end assemblyScaleForZoomScale:

@end
