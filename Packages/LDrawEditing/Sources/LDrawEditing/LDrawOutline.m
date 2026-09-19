//==============================================================================
//
//  File:       LDrawOutline.m
//  Package:    LDrawEditing
//
//  Purpose:    Outline data source, drop validation, and syntax coloring.
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <LDrawEditing/LDrawOutline.h>

#import <LDrawEditing/LDrawClipboard.h>

#import <LDrawCore/LDrawComment.h>
#import <LDrawCore/LDrawConditionalLine.h>
#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawLine.h>
#import <LDrawCore/LDrawLSynth.h>
#import <LDrawCore/LDrawLSynthDirective.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawQuadrilateral.h>
#import <LDrawCore/LPubRemoveGroup.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/LDrawTriangle.h>
#import <LDrawCore/LDrawColor.h>
#import <LDrawCore/LDrawKeys.h>

@interface LDrawOutline ()
+ (BOOL)canNestDirective:(LDrawDirective *)directive inParent:(id)parent;
+ (LDrawOutlineDropKind)outlineDropKindForDropOnItem:(BOOL)isDropOnItem
									hasDirectiveData:(BOOL)hasDirectiveData
									   isSameOutline:(BOOL)isSameOutline
								disallowDragToSource:(BOOL)disallowDragToSource
										   directive:(nullable id)directive
											  parent:(nullable id)parent;
@end

@implementation LDrawOutline

//---------- canNestDirective:inParent: ------------------------------[static]--
//
// Purpose:		Whether a dragged directive may land in the proposed parent.
//				Models must land in a file, steps in a model, other leaves in a
//				container. Prohibit dropping onto a container that it's not
//				happy to accept (acceptsDroppedDirective:).
//
//------------------------------------------------------------------------------
+ (BOOL)canNestDirective:(LDrawDirective *)directive inParent:(id)parent
{
	if ([directive isKindOfClass:[LDrawModel class]] == YES
	   && [parent isKindOfClass:[LDrawFile class]] == NO)
	{
		return NO;
	}
	if ([directive isKindOfClass:[LDrawStep class]] == YES
	   && [parent isKindOfClass:[LDrawModel class]] == NO)
	{
		return NO;
	}
	if ([directive isKindOfClass:[LDrawContainer class]] == NO
	   && [parent isKindOfClass:[LDrawContainer class]] == NO)
	{
		return NO;
	}
	if ([parent isKindOfClass:[LDrawContainer class]]
	   && [(LDrawContainer *)parent acceptsDroppedDirective:directive] == NO)
	{
		return NO;
	}
	return YES;
}


//---------- shouldDisallowDraggingItems: ----------------------------[static]--
//
// Purpose:		Disallow dragging if it is the only step in the model.
//
//------------------------------------------------------------------------------
+ (BOOL)shouldDisallowDraggingItems:(NSArray *)items
{
	if ([items count] != 1)
	{
		return NO;
	}

	id firstItem = [items objectAtIndex:0];
	if ([firstItem isKindOfClass:[LDrawStep class]] == NO)
	{
		return NO;
	}
	return [[[firstItem enclosingModel] steps] count] == 1;
}


//---------- outlineDropParent:file: ---------------------------------[static]--
//
// Purpose:		Fix our logic for handling drags to the root of the outline.
//				Identify the root object if needed: nil means the file.
//
//------------------------------------------------------------------------------
+ (nullable id)outlineDropParent:(nullable id)proposedParent file:(nullable LDrawFile *)file
{
	if (proposedParent == nil)
	{
		return file;
	}
	return proposedParent;
}


//---------- outlineDropKindForDropOnItem:… --------------------------[static]--
//
// Purpose:		Whether a drop is allowed, and whether it is a move or a copy.
//
//				We must make sure we have the proper pasteboard type available.
//				Drop-on is not a "drop-on" operation we accept. If the drag is
//				acceptable, same-outline is a move; otherwise copy.
//
//				Eliminate illegal positions: dragging the only step back into
//				the source, and nesting that canNestDirective:inParent: rejects.
//
//------------------------------------------------------------------------------
+ (LDrawOutlineDropKind)outlineDropKindForDropOnItem:(BOOL)isDropOnItem
									hasDirectiveData:(BOOL)hasDirectiveData
									   isSameOutline:(BOOL)isSameOutline
								disallowDragToSource:(BOOL)disallowDragToSource
										   directive:(nullable id)directive
											  parent:(nullable id)parent
{
	// We must make sure we have the proper pasteboard type available.
	if (isDropOnItem || hasDirectiveData == NO)
	{
		return LDrawOutlineDropNone;
	}

	// This drag is acceptable. Now figure out the operation.
	LDrawOutlineDropKind kind = isSameOutline ? LDrawOutlineDropMove : LDrawOutlineDropCopy;

	//---------- Eliminate Illegal Positions -------------------------------
	if (isSameOutline && disallowDragToSource)
	{
		return LDrawOutlineDropNone;
	}
	if ([self canNestDirective:directive inParent:parent] == NO)
	{
		return LDrawOutlineDropNone;
	}
	return kind;
}


//---------- outlineDropKindForValidateDropWithProposedParent:... ----[static]--
//
// Purpose:		Returns the representation of item given for the given table
//				column.
//
//------------------------------------------------------------------------------
+ (LDrawOutlineDropKind)outlineDropKindForValidateDropWithProposedParent:(id)proposedParent
																	file:(LDrawFile *)file
															  dropOnItem:(BOOL)dropOnItem
														 pasteboardTypes:(NSArray *)types
													disallowDragToSource:(BOOL)disallow
															 sameOutline:(BOOL)sameOutline
												archivedDirectiveObjects:(NSArray *)archivedDirectiveObjects
{
	id		 parent			= [self outlineDropParent:proposedParent file:file];
	BOOL	 hasDirective	= [types containsObject:LDrawDirectivePboardType];
	id		 currentObject	= nil;

	if (dropOnItem == NO && hasDirective && [archivedDirectiveObjects count] > 0)
	{
		currentObject = [LDrawClipboard unarchivedDirectiveFromData:[archivedDirectiveObjects objectAtIndex:0]];
	}

	return [self outlineDropKindForDropOnItem:dropOnItem
							 hasDirectiveData:hasDirective
								isSameOutline:sameOutline
						 disallowDragToSource:disallow
									directive:currentObject
									   parent:parent];
}


//---------- outlineDropUndoActionKeyForSameOutline: -----------------[static]--
//
// Purpose:		UndoReorder for same-outline moves. Cross-outline paste leaves
//				the host's default undo name. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)outlineDropUndoActionKeyForSameOutline:(BOOL)sameOutline
{
	if (sameOutline)
		return @"UndoReorder";
	return nil;
}


//---------- donatingParentsFromMovedDirectives: ---------------------[static]--
//
// Purpose:		Gather up (unique) parents that are donating child nodes to this
//				move. If the parents support tidying up they'll be given a
//				chance later. This is intended for e.g. containers such as
//				LDrawSynth that may need to take action if their subdirectives
//				change.
//
//				The file (outline root) is omitted; the outline represents that
//				parent as nil.
//
//------------------------------------------------------------------------------
+ (NSSet *)donatingParentsFromMovedDirectives:(NSArray *)directives
{
	NSMutableSet *parents = [NSMutableSet set];
	for (id item in directives)
	{
		id parent = [item enclosingDirective];
		if (parent != nil && [parent isKindOfClass:[LDrawFile class]] == NO)
		{
			[parents addObject:parent];
		}
	}
	return parents;
}


//---------- cleanupAfterOutlineDropDonors:destination: --------------[static]--
//
// Purpose:		Ask the source and target parents to cleanup if they can e.g.
//				used for updating container selection state.
//
//------------------------------------------------------------------------------
+ (void)cleanupAfterOutlineDropDonors:(NSSet *)donors destination:(nullable id)newParent
{
	for (id parent in donors)
	{
		if ([parent isKindOfClass:[LDrawContainer class]]
		   && [parent respondsToSelector:@selector(cleanupAfterDropIsDonor:)])
		{
			[parent performSelector:@selector(cleanupAfterDropIsDonor:)
						 withObject:@YES];
		}
	}
	if ([newParent respondsToSelector:@selector(cleanupAfterDropIsDonor:)])
	{
		[newParent performSelector:@selector(cleanupAfterDropIsDonor:)
						withObject:@NO];
	}
}


//---------- outlineChildCountOfItem:file: ---------------------------[static]--
//
// Purpose:		Returns the number of items which should be displayed under an
//				expanded item.
//
//------------------------------------------------------------------------------
+ (NSInteger)outlineChildCountOfItem:(nullable id)item file:(nullable LDrawFile *)file
{
	NSInteger numberOfChildren = 0;

	// root object; return the number of submodels
	if (item == nil)
		numberOfChildren = [[file submodels] count];

	// a step or model (or something); return the nth directives command
	else if ([item isKindOfClass:[LDrawContainer class]])
		numberOfChildren = [[item subdirectives] count];

	return numberOfChildren;
}


//---------- outlineItemIsExpandable: --------------------------------[static]--
//
// Purpose:		Returns the number of items which should be displayed under an
//				expanded item.
//
//------------------------------------------------------------------------------
+ (BOOL)outlineItemIsExpandable:(nullable id)item
{
	// You can expand models and steps.
	if ([item isKindOfClass:[LDrawContainer class]] )
		return YES;
	else
		return NO;
}


//---------- containerEnclosingOutlineItem: --------------------------[static]--
//
// Purpose:		The container that encloses (or is) the current selection, or
//				nil if there is no container in the selection chain.
//
// Notes:		If we are doing a copy-drag operation, the host still remembers
//				the original selection and passes that item. (We can't use the
//				current selection during copy drag because we clear it when the
//				drag begins.)
//
//------------------------------------------------------------------------------
+ (LDrawContainer *)containerEnclosingOutlineItem:(id)item
{
	if ([item isKindOfClass:[LDrawContainer class]]) return item;
	return [item enclosingDirective];
}


//---------- outlineChild:ofItem:file: -------------------------------[static]--
//
// Purpose:		Returns the child of item at the position index.
//
//------------------------------------------------------------------------------
+ (id)outlineChild:(NSInteger)index ofItem:(nullable id)item file:(nullable LDrawFile *)file
{
	NSArray *children = nil;

	// children of the root object; the nth of models.
	if (item == nil)
		children = [file submodels];

	// a container; return the nth subdirective.
	else if ([item isKindOfClass:[LDrawContainer class]])
		children = [item subdirectives];

	return [children objectAtIndex:index];
}


//---------- outlineSyntaxColorKeyForDirective: ----------------------[static]--
//
// Purpose:		Applies syntax coloring to the specified directive, which will
//				be displayed with the text representation. This is the
//				preference key for the object's syntax color; the host still
//				looks up NSColor.
//
//------------------------------------------------------------------------------
+ (NSString *)outlineSyntaxColorKeyForDirective:(id)item
{
	NSString *colorKey = nil; //preference key for object's syntax color.

	// Find the specified syntax color for the directive.
	if ([item isKindOfClass:[LDrawModel class]])
		colorKey = SYNTAX_COLOR_MODELS_KEY;

	else if ([item isKindOfClass:[LDrawStep class]])
		colorKey = SYNTAX_COLOR_STEPS_KEY;

	else if ([item isKindOfClass:[LDrawComment class]])
		colorKey = SYNTAX_COLOR_COMMENTS_KEY;

	else if ([item isKindOfClass:[LDrawPart class]])
		colorKey = SYNTAX_COLOR_PARTS_KEY;

	else if ([item isKindOfClass:[LDrawLSynth class]] ||
			 [item isKindOfClass:[LDrawLSynthDirective class]])
		colorKey = SYNTAX_COLOR_PARTS_KEY;

	else if ([item isKindOfClass:[LDrawLine				class]] ||
			[item isKindOfClass:[LDrawTriangle			class]] ||
			[item isKindOfClass:[LDrawQuadrilateral		class]] ||
			[item isKindOfClass:[LDrawConditionalLine	class]]    )
		colorKey = SYNTAX_COLOR_PRIMITIVES_KEY;

	else if ([item isKindOfClass:[LDrawColor class]])
		colorKey = SYNTAX_COLOR_COLORS_KEY;

	else if ([item isKindOfClass:[LPubRemoveGroup class]])
		colorKey = SYNTAX_COLOR_REMOVE_GROUP_KEY;

	else
		colorKey = SYNTAX_COLOR_UNKNOWN_KEY;

	return colorKey;
}


//---------- outlineSyntaxFallbackColorForKey: -----------------------[static]--
//
// Purpose:		Default syntax color when user-defaults unarchiving fails for
//				the given preference key. The host still instantiates NSColor.
//
// Notes:		Fallback to default color if unarchiving failed.
//				Can be removed in the future.
//
//------------------------------------------------------------------------------
+ (LDrawOutlineSyntaxFallbackColor)outlineSyntaxFallbackColorForKey:(NSString *)colorKey
{
	if ([colorKey isEqualToString:SYNTAX_COLOR_COMMENTS_KEY])
		return LDrawOutlineSyntaxFallbackSystemGreen;
	if ([colorKey isEqualToString:SYNTAX_COLOR_PARTS_KEY])
		return LDrawOutlineSyntaxFallbackSystemBlue;
	if ([colorKey isEqualToString:SYNTAX_COLOR_PRIMITIVES_KEY])
		return LDrawOutlineSyntaxFallbackSystemOrange;
	if ([colorKey isEqualToString:SYNTAX_COLOR_MODELS_KEY])
		return LDrawOutlineSyntaxFallbackSystemPurple;
	if ([colorKey isEqualToString:SYNTAX_COLOR_STEPS_KEY])
		return LDrawOutlineSyntaxFallbackSystemYellow;
	if ([colorKey isEqualToString:SYNTAX_COLOR_COLORS_KEY])
		return LDrawOutlineSyntaxFallbackSystemPink;
	if ([colorKey isEqualToString:SYNTAX_COLOR_REMOVE_GROUP_KEY])
		return LDrawOutlineSyntaxFallbackSystemRed;
	return LDrawOutlineSyntaxFallbackLabel;
}


//---------- outlineObliquenessForDirective: -------------------------[static]--
//
// Purpose:		Hidden directives are shown italicized in the outline.
//
//------------------------------------------------------------------------------
+ (double)outlineObliquenessForDirective:(id)item
{
	if ([item respondsToSelector:@selector(isHidden)])
		if ([(id)item isHidden])
			return 0.5;
	return 0.0;
}


//---------- outlineIconNameForItem: --------------------------------[static]--
//
// Purpose:		Return the outline-view icon name for a file-contents item.
//				The host still instantiates NSImage.
//
//------------------------------------------------------------------------------
+ (NSString *)outlineIconNameForItem:(id)item
{
	if ([item isKindOfClass:[LDrawDirective class]] == NO) return nil;
	NSString *imageName = [item iconName];
	if (imageName == nil || [imageName isEqualToString:@""]) return nil;
	return imageName;
}


//---------- outlineDescriptionForItem: -----------------------------[static]--
//
// Purpose:		Return the outline-view display string for a file-contents item.
//
//------------------------------------------------------------------------------
+ (NSString *)outlineDescriptionForItem:(id)item
{
	// Start off with a simple error message. Hopefully we won't see it.
	if ([item isKindOfClass:[LDrawDirective class]] == NO)
	{
		return @"<Something went wrong here.>";
	}

	// an LDraw directive; thank goodness! It knows how to describe itself.
	// The description will form the basis of the attributed text for the cell.
	return [item browsingDescription];
}


//---------- stepComponentFromOutlineItem: ---------------------------[static]--
//
// Purpose:		The drawable LDraw element that is currently selected (Part,
//				Quadrilateral, Triangle, etc.). Nil if the selection is not one
//				of these atomic LDraw commands.
//
// Notes:		If a model is selected, a step can't be. File, model, and step
//				are not step components; whatever else it is, it's what we are
//				looking for.
//
//------------------------------------------------------------------------------
+ (id)stepComponentFromOutlineItem:(id)item
{
	if (item == nil) return nil;
	if ([item isKindOfClass:[LDrawFile class]]) return nil;
	if ([item isKindOfClass:[LDrawModel class]]) return nil;
	if ([item isKindOfClass:[LDrawStep class]]) return nil;
	return item;
}


@end
