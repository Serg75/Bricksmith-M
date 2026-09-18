//==============================================================================
//
//  File:       LDrawStepPartListResizeTracker.h
//  Package:    LDrawFeatures
//
//  Created by Sergey Slobodenyuk on 2026-09-18.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/LPubPliConstrain.h>
#import <LDrawCore/MatrixMath.h>

#import <LDrawFeatures/LDrawStepPartListPolicy.h>

@class LDrawStepPartListPresentation;

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepPartListResizeTracker
///
/// @abstract   Follows one press on the frame: a pin click, or a drag on an
///             edge that resizes the frame.
///
/// @discussion The host passes points in the presentation's space and does
///             what the answers say. The document is not touched here.
///
//------------------------------------------------------------------------------
@interface LDrawStepPartListResizeTracker : NSObject

/// Whether a resize drag is in progress, and on which axis.
@property (nonatomic, readonly) BOOL isResizing;
@property (nonatomic, readonly) LPubPliAxis axis;

/// A press at this point. Returns the control under it. On an edge it starts a
/// resize, measured from the grab so the frame does not jump. On a pin, or
/// nowhere, no resize starts.
- (LDrawStepPartListControl) beginAtPoint:(Point2)point
							 presentation:(nullable LDrawStepPartListPresentation *)presentation
	NS_SWIFT_NAME(begin(at:presentation:));

/// The size, in inches, a drag to this point asks for: clamped to what can be
/// written and drawn, and snapped to the size the step inherits. 0 when no
/// resize is in progress.
- (double) inchesForDragToPoint:(Point2)point
				   presentation:(nullable LDrawStepPartListPresentation *)presentation
	NS_SWIFT_NAME(inchesForDrag(to:presentation:));

/// Ends the resize, if one is in progress.
- (void) end;

@end

NS_ASSUME_NONNULL_END
