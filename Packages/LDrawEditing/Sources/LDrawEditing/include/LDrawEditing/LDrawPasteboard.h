//==============================================================================
//
//  File:       LDrawPasteboard.h
//  Package:    LDrawEditing
//
//  Purpose:    Pasteboard type names for copy, paste, and drag-and-drop of
//              LDraw directives. The host still owns NSPasteboard / UIPasteboard.
//
//  Created by Sergey Slobodenyuk on 2026-08-30.
//
//==============================================================================

#import <Foundation/Foundation.h>

/// Used for dragging within the File Contents outline. Contains an array of
/// LDrawDirectives stored as NSData objects. There should be no duplication of
/// objects.
#define LDrawDirectivePboardType				@"LDrawDirectivePboardType"

/// Used for dragging parts around in or between viewports. Contains an array of
/// LDrawDirectives stored as NSData objects. There should be no duplication of
/// objects.
#define LDrawDraggingPboardType					@"LDrawDraggingPboardType"

/// Contains a Vector3 as NSData indicating the offset between the click location
/// which originated the drag and the position of the first dragged directive.
#define LDrawDraggingInitialOffsetPboardType	@"LDrawDraggingInitialOffsetPboardType"

/// Contains a BOOL indicating the dragging directive has never been part of a
/// model before.
#define LDrawDraggingIsUninitializedPboardType	@"LDrawDraggingIsUninitializedPboardType"

/// Contains an array of indexes for the original objects being drug.
/// Since the objects are converted to data when placed on the
/// LDrawDirectivePboardType (effectively copying them), these source indexes
/// must be used to delete the original objects after the copies have been
/// deposited in their new destination.
#define LDrawDragSourceRowsPboardType			@"LDrawDragSourceRowsPboardType"

#define LDrawDisallowDragToSourcePboardType		@"LDrawDisallowDragToSourcePboardType"
