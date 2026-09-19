//==============================================================================
//
//  File:       LDrawStepPartListResizeTracker.m
//  Package:    LDrawFeatures
//
//  Purpose:    Follows one press on the parts list frame.
//
//  Created by Sergey Slobodenyuk on 2026-09-18.
//
//==============================================================================

#import <LDrawFeatures/LDrawStepPartListResizeTracker.h>

#import <LDrawFeatures/LDrawStepPartListPresentation.h>


@implementation LDrawStepPartListResizeTracker
{
	/// Where the drag measures its size from, set when it starts.
	Point2	dragOrigin;
	/// The size the drag snaps to, read once when it starts.
	double	dragInheritedInches;
}

//========== beginAtPoint:presentation: ========================================
///
/// @abstract	A press at this point: starts a resize on an edge.
///
//==============================================================================
- (LDrawStepPartListControl) beginAtPoint:(Point2)point
							 presentation:(nullable LDrawStepPartListPresentation *)presentation
{
	LDrawStepPartListControl control = [LDrawStepPartListPolicy controlAtPoint:point
																	   inFrame:presentation.frameRect
																   widthPinned:presentation.widthPinned
																  heightPinned:presentation.heightPinned];

	self->_isResizing = (control == LDrawStepPartListControlWidthEdge
						 || control == LDrawStepPartListControlHeightEdge);

	if (self->_isResizing) {
		self->_axis = (control == LDrawStepPartListControlWidthEdge) ? LPubPliAxisWidth : LPubPliAxisHeight;

		self->dragOrigin			= [LDrawStepPartListPolicy dragOriginForAxis:self->_axis
																  grabbedAtPoint:point
																		  layout:presentation.layout];
		self->dragInheritedInches	= [presentation inheritedInchesForAxis:self->_axis];
	}

	return control;

}//end beginAtPoint:presentation:


//========== inchesForDragToPoint:presentation: ================================
///
/// @abstract	The size a drag to this point asks for.
///
/// @discussion	Read at the scale the frame was packed at, against the list on
/// 			show now.
///
//==============================================================================
- (double) inchesForDragToPoint:(Point2)point
				   presentation:(nullable LDrawStepPartListPresentation *)presentation
{
	if (self->_isResizing == NO || presentation.layout == nil) {
		return 0.0;
	}

	return [LDrawStepPartListPolicy inchesForDraggingAxis:self->_axis
												  toPoint:point
											   fromOrigin:self->dragOrigin
												   layout:presentation.layout
												 hostSize:presentation.hostSize
										pointsPerPageInch:presentation.pointsPerPageInch
										  inheritedInches:self->dragInheritedInches];

}//end inchesForDragToPoint:presentation:


//========== end ===============================================================
- (void) end
{
	self->_isResizing = NO;

}//end end

@end
