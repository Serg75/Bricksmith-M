//==============================================================================
//
//  File:       LDrawStructure+Split.m
//  Package:    LDrawEditing
//
//  Purpose:    Step and model split rules for LDrawStructure.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import <LDrawEditing/LDrawStructure.h>

#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/MatrixMath.h>


@interface LDrawStructure (SplitPrivate)
+ (nullable LDrawModel *)referencedModelForSplitPart:(LDrawPart *)part;
+ (NSArray<LDrawPart *> *)partsExpandedFromAnchor:(LDrawPart *)anchor
										  inModel:(LDrawModel *)model;
@end


@implementation LDrawStructure (Split)

//---------- splitStepDirectivesFromSelection:… ----------------------[static]--
//
// Purpose:		Takes the current selection and moves each selected directive
//				into a new step. The newly created step is inserted directly
//				BEFORE the last parent step of the selection. (Users can use
//				this to rapidly 'break down' a monolithic pile of bricks into
//				sane steps.)
//
// Notes:		The function will only move selection directives that are
//				children of steps from a single model.
//
//------------------------------------------------------------------------------
+ (NSArray *)splitStepDirectivesFromSelection:(NSArray *)selection
							  containingModel:(LDrawContainer * _Nullable * _Nullable)outModel
								   sourceStep:(LDrawStep * _Nullable * _Nullable)outSourceStep
								  insertIndex:(NSInteger * _Nullable)outInsertIndex
{
	NSMutableArray  *movedDirectives = [NSMutableArray arrayWithCapacity:[selection count]];
	LDrawContainer  *containingModel = nil;
	NSInteger        highestIndex    = 0;

	for (id child in selection)
	{
		LDrawDirective *parent = [child enclosingDirective];
		if (parent == nil)
		{
			continue;
		}

		LDrawContainer *model = [parent enclosingDirective];
		if (model == nil)
		{
			continue;
		}

		if (containingModel == nil)
		{
			containingModel = model;
		}
		if (containingModel == model)
		{
			highestIndex = MAX(highestIndex, [containingModel indexOfDirective:parent]);
			[movedDirectives addObject:child];
		}
	}

	if ([movedDirectives count] == 0)
	{
		return movedDirectives;
	}

	if (outModel != NULL)
	{
		*outModel = containingModel;
	}
	if (outInsertIndex != NULL)
	{
		*outInsertIndex = highestIndex;
	}
	if (outSourceStep != NULL)
	{
		*outSourceStep = (LDrawStep *)containingModel.subdirectives[highestIndex];
	}
	return movedDirectives;
}


//---------- transferRotationFromStep:toStep: ------------------------[static]--
//
// Purpose:		Copy rotation from the source step onto the destination, then
//				clear the source type. Do undo stuff before changing rotation
//				in the host.
//
//------------------------------------------------------------------------------
+ (void)transferRotationFromStep:(LDrawStep *)source toStep:(LDrawStep *)destination
{
	[destination setStepRotationType:[source stepRotationType]];
	[destination setRotationAngle:[source rotationAngle]];
	[source setStepRotationType:LDrawStepRotationNone];
}


//---------- referencedModelForSplitPart: ----------------------------[static]--
//
// Purpose:		Copy each part from a MPD sub-model into its location in the
//				parent model. This basically turns a reference to a sub-model
//				into a big pile of bricks that can be directly edited.
//
// Notes:		Only parts are copied; any step information and primitives in
//				the sub-module are ignored. This is the referenced MPD or peer
//				file, or nil if it cannot be split.
//
//------------------------------------------------------------------------------
+ (LDrawModel *)referencedModelForSplitPart:(LDrawPart *)part
{
	LDrawModel *model = [part referencedMPDSubmodel];
	if (model == nil)
	{
		model = [part referencedPeerFile];
	}
	return model;
}


//---------- partsExpandedFromAnchor:inModel: ------------------------[static]--
//
// Purpose:		New parts at the anchor's world transform. Does not mutate the
//				tree. The host still inserts (undo).
//
//------------------------------------------------------------------------------
+ (NSArray<LDrawPart *> *)partsExpandedFromAnchor:(LDrawPart *)anchor
										  inModel:(LDrawModel *)model
{
	Matrix4         xfrm  = [anchor transformationMatrix];
	NSMutableArray *added = [NSMutableArray array];

	[model applyToAllParts:^(LDrawPart *part) {
		Matrix4 local  = [part transformationMatrix];
		Matrix4 global = Matrix4Multiply(local, xfrm);

		LDrawPart *newPart = [[LDrawPart alloc] init];
		[newPart setLDrawColor:[part LDrawColor]];
		[newPart setDisplayName:[part displayName]];
		[newPart setTransformationMatrix:&global];
		[added addObject:newPart];
	}];
	return added;
}


//---------- splitExpansionsInSelection: -----------------------------[static]--
//
// Purpose:		Copy each part from a MPD sub-model into its location in the
//				parent model. This basically turns a reference to a sub-model
//				into a big pile of bricks that can be directly edited.
//
// Notes:		Only parts are copied; any step information and primitives in
//				the sub-module are ignored. The host still deletes the anchor
//				and inserts the copies (undo).
//
//------------------------------------------------------------------------------
+ (NSArray<LDrawSplitExpansion *> *)splitExpansionsInSelection:(NSArray *)selection
{
	NSMutableArray *expansions = [NSMutableArray array];
	for (id thing in selection)
	{
		if ([thing isKindOfClass:[LDrawPart class]] == NO) continue;

		LDrawPart  *anchor = (LDrawPart *)thing;
		LDrawModel *model  = [self referencedModelForSplitPart:anchor];
		if (model == nil) continue;

		LDrawSplitExpansion *expansion = [LDrawSplitExpansion new];
		expansion.anchor = anchor;
		expansion.model = model;
		expansion.expandedParts = [self partsExpandedFromAnchor:anchor inModel:model];
		[expansions addObject:expansion];
	}
	return expansions;
}


//---------- selectionCanSplitStep: ----------------------------------[static]--
//
// Purpose:		splitStep splits the selected directives out of their current
//				steps and puts them into a newly created step. The function will
//				only move selection directives that are children of steps from a
//				single model.
//
//------------------------------------------------------------------------------
+ (BOOL)selectionCanSplitStep:(NSArray *)selection
{
	if ([selection count] == 0)
	{
		return NO;
	}

	LDrawModel *commonModel = nil;
	for (id currentDirective in selection)
	{
		LDrawModel     *model  = [currentDirective enclosingModel];
		LDrawContainer *parent = [currentDirective enclosingDirective];
		if (commonModel == nil)
		{
			commonModel = model;
		}

		if (	parent == nil || model == nil
		   ||	model != commonModel
		   ||	[parent isKindOfClass:[LDrawStep class]] == NO)
		{
			return NO;
		}
	}
	return YES;
}


//---------- selectionCanSplitModel: ---------------------------------[static]--
//
// Purpose:		Copy each part from a MPD sub-model into its location in the
//				parent model. This basically turns a reference to a sub-model
//				into a big pile of bricks that can be directly edited.
//
// Notes:		Only parts are copied; any step information and primitives in
//				the sub-module are ignored. Menu enable: every selected object
//				must be an LDrawPart.
//
//------------------------------------------------------------------------------
+ (BOOL)selectionCanSplitModel:(NSArray *)selection
{
	if ([selection count] == 0)
	{
		return NO;
	}
	for (id object in selection)
	{
		if ([object class] != [LDrawPart class])
		{
			return NO;
		}
	}
	return YES;
}


//---------- splitStepUndoActionKey ----------------------------------[static]--
//
// Purpose:		Localization key after splitting a step. The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)splitStepUndoActionKey
{
	return @"UndoSplitStep";
}


//---------- splitModelUndoActionKey ---------------------------------[static]--
//
// Purpose:		Localization key after expanding a split-able model. The host
//				still localizes. (Key casing matches the existing strings file.)
//
//------------------------------------------------------------------------------
+ (NSString *)splitModelUndoActionKey
{
	return @"undoSplitModel";
}

@end
