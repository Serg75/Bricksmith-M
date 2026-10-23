//==============================================================================
//
//  File:       LDrawStepAssemblyScaleTracker.h
//  Package:    LDrawStepEditing
//
//  Created by Sergey Slobodenyuk on 2026-10-21.
//
//==============================================================================

#import <Foundation/Foundation.h>
#import <LDrawCore/MatrixMath.h>

#import <LDrawFeatures/LDrawStepPartListPresentation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepAssemblyScaleTracker
///
/// @abstract   Follows a drag of a handle on the frame around the step being
///             arranged, and says what scale it asks for.
///
/// @discussion The step grows from the point its placement holds it by, its
///             middle unless the file says otherwise. The scale is the start
///             scale times how far the pointer has gone from that point,
///             along the line to the handle, against how far the handle was.
///             So the handle follows the pointer as the step grows.
///
///             The host gives the scale to the presenter, which snaps it as a
///             zoom snaps. Nothing is written until the host ends arranging.
///
//------------------------------------------------------------------------------
@interface LDrawStepAssemblyScaleTracker : NSObject

/// A drag of a handle is in progress.
@property (nonatomic, readonly) BOOL isScaling;

/// The handle being dragged, or none.
@property (nonatomic, readonly) LDrawStepArrangeHandle handle;

/// The scale when the drag started, which Escape goes back to.
@property (nonatomic, readonly) double startScale;

/// Starts a drag when the point is on one of the frame's handles. NO anywhere
/// else, and for a scale of 0 or less.
- (BOOL) beginAtPoint:(Point2)point
		 presentation:(nullable LDrawStepPartListPresentation *)presentation
				scale:(double)scale
	NS_SWIFT_NAME(begin(at:presentation:scale:));

/// The scale the pointer here asks for, before it snaps. Never below 0.05.
- (double) scaleForDragToPoint:(Point2)point NS_SWIFT_NAME(scaleForDrag(to:));

/// Ends the drag.
- (void) end;

@end

NS_ASSUME_NONNULL_END
