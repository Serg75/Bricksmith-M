//==============================================================================
//
//  File:       LDrawPaste.m
//  Package:    LDrawEditing
//
//  Purpose:    Paste and duplicate placement for models, steps, and directives.
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <LDrawEditing/LDrawPaste.h>

#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawPart.h>
#import <LDrawCore/LDrawStep.h>
#import <LDrawCore/MatrixMath.h>

@interface LDrawPaste ()
+ (LDrawDirective *)similarDirective:(LDrawDirective *)directive amongObjects:(id)objects;
+ (nullable LDrawContainer *)pasteStepParentFromParent:(nullable id)parent;
+ (BOOL)selectionIsModelForDuplicate:(NSArray *)selection;
+ (BOOL)nextToSimilarPlacementForDirective:(LDrawDirective *)directive
							   inSelection:(NSArray *)selection
									parent:(LDrawContainer * _Nullable * _Nullable)outParent
									 index:(NSInteger * _Nullable)outIndex;
@end

@implementation LDrawPaste

//---------- similarDirective:amongObjects: --------------------------[static]--
///
/// @abstract	Returns the part that is similar to the given one, or NSNotFound
///				if there is no such directive or given directive is not a part.
///
/// @param 		directive	- given directive which copy we are looking for.
/// @param 		objects		- we are searching withing this set of objects.
///
//------------------------------------------------------------------------------
+ (LDrawDirective *)similarDirective:(LDrawDirective *)directive
						amongObjects:(id)objects
{
	if ([directive isKindOfClass:[LDrawPart class]]) {
		LDrawPart *part = (LDrawPart *)directive;
		for (id object in objects) {
			if ([object isKindOfClass:[LDrawPart class]]) {
				LDrawPart *p = (LDrawPart *)object;
				Matrix4 m1 = part.transformationMatrix;
				Matrix4 m2 = p.transformationMatrix;
				if (	[part.displayName isEqualToString:p.displayName]
					&& 	part.LDrawColor == p.LDrawColor
					&& 	Matrix4EqualMatrices(&m1, &m2))
				{
					return object;
				}
			}
		}
	}
	return nil;
	
} // end similarDirective:amongObjects:


//---------- partitionPastedObjects:models:steps:directives: ---------[static]--
//
// Purpose:		Paste the directives on the given pasteboard into the document.
//				Reset default icons, then bucket unarchived objects into models
//				/ steps / other directives. Paste inserts the first non-empty
//				bucket. The host still inserts (undo).
//
//------------------------------------------------------------------------------
+ (void)partitionPastedObjects:(NSArray *)objects
						models:(NSMutableArray *)models
						 steps:(NSMutableArray *)steps
					directives:(NSMutableArray *)directives
{
	for (id currentObject in objects)
	{
		if ([currentObject isKindOfClass:[LDrawDirective class]])
		{
			NSString *iconName = [[currentObject class] defaultIconName];
			if (iconName != nil)
			{
				[currentObject setIconName:iconName];
			}
		}

		if ([currentObject isKindOfClass:[LDrawModel class]])
		{
			[models addObject:currentObject];
		}
		else if ([currentObject isKindOfClass:[LDrawStep class]])
		{
			[steps addObject:currentObject];
		}
		else
		{
			[directives addObject:currentObject];
		}
	}
}


//---------- pasteStepParentFromParent: -----------------------------[static]--
//
// Purpose:		Return the step-level container to paste into, walking up from
//				parent if needed.
//
//------------------------------------------------------------------------------
+ (LDrawContainer *)pasteStepParentFromParent:(id)parent
{
	if ([parent isKindOfClass:[LDrawStep class]]) return parent;
	return nil;
}


//---------- pasteModelParentFromParent: ----------------------------[static]--
//
// Purpose:		Return the MPD model to paste a new model next to, walking up
//				from parent if needed.
//
//------------------------------------------------------------------------------
+ (LDrawMPDModel *)pasteModelParentFromParent:(id)parent
{
	if ([parent isKindOfClass:[LDrawMPDModel class]]) return parent;
	return nil;
}


//---------- selectionIsModelForDuplicate: ---------------------------[static]--
//
// Purpose:		Makes a copy of the selected object. Duplicate of the current
//				selection should insert as a new MPD model when the first
//				selected object is a model.
//
//------------------------------------------------------------------------------
+ (BOOL)selectionIsModelForDuplicate:(NSArray *)selection
{
	return [[selection firstObject] isKindOfClass:[LDrawMPDModel class]];
}


//---------- insertIndexAfterModel:inFile: ---------------------------[static]--
//
// Purpose:		Returns index of the next model that follows another one, which
//				encloses the current selection, or NSNotFound if there is no
//				selection.
//
//------------------------------------------------------------------------------
+ (NSInteger)insertIndexAfterModel:(LDrawModel *)model inFile:(LDrawFile *)file
{
	if (model == nil || file == nil)
	{
		return NSNotFound;
	}

	NSInteger indexOfObject = [file indexOfDirective:model];
	if (indexOfObject != NSNotFound)
	{
		indexOfObject++;
	}
	return indexOfObject;
}


//---------- nextToSimilarPlacementForDirective:inSelection:parent:index:
//																     [static]--
//
// Purpose:		Paste the directives on the given pasteboard into the document.
//				For part duplication: if true, paste duplicated parts next to
//				originals. YES if a matching selected part was found.
//
//------------------------------------------------------------------------------
+ (BOOL)nextToSimilarPlacementForDirective:(LDrawDirective *)directive
							   inSelection:(NSArray *)selection
									parent:(LDrawContainer * _Nullable * _Nullable)outParent
									 index:(NSInteger * _Nullable)outIndex
{
	LDrawDirective *similar = [self similarDirective:directive amongObjects:selection];
	if (similar == nil)
	{
		return NO;
	}

	LDrawContainer *parent = (LDrawContainer *)[similar enclosingDirective];
	if (parent == nil)
	{
		return NO;
	}

	if (outParent != NULL)
	{
		*outParent = parent;
	}
	if (outIndex != NULL)
	{
		*outIndex = [parent indexOfDirective:similar] + 1;
	}
	return YES;
}


//---------- resolveStepPasteParent:index:forDirective:... -------------[static]--
//
// Purpose:		Paste the directives on the given pasteboard into the document.
//				For part duplication: if true, paste duplicated parts next to
//				originals.
//
//------------------------------------------------------------------------------
+ (void)resolveStepPasteParent:(LDrawContainer * __autoreleasing *)outParent
						 index:(NSInteger *)outIndex
				  forDirective:(LDrawDirective *)directive
						parent:(id)parent
				 insertAtIndex:(NSInteger)insertAtIndex
				 nextToSimilar:(BOOL)nextToSimilar
				   inSelection:(NSArray *)selection
			fallbackParentStep:(LDrawContainer *)fallbackParentStep
{
	LDrawContainer *parentStep = nil;
	NSInteger       realIndex  = insertAtIndex;

	if (nextToSimilar)
	{
		if ([self nextToSimilarPlacementForDirective:directive
										 inSelection:selection
											  parent:&parentStep
											   index:&realIndex] == NO)
		{
			parentStep = fallbackParentStep;
			realIndex  = NSNotFound;
		}
	}
	else
	{
		parentStep = [self pasteStepParentFromParent:parent];
	}

	if (outParent != NULL)
		*outParent = parentStep;
	if (outIndex != NULL)
		*outIndex = realIndex;
}


//---------- modelPasteStartIndexForInsertAtIndex:defaultIndex: ------[static]--
//
// Purpose:		Model paste uses the explicit drop index, or the next model slot.
//
//------------------------------------------------------------------------------
+ (NSInteger)modelPasteStartIndexForInsertAtIndex:(NSInteger)insertAtIndex
									 defaultIndex:(NSInteger)defaultIndex
{
	if (insertAtIndex != NSNotFound)
		return insertAtIndex;
	return defaultIndex;
}


//---------- nextSequentialModelInsertIndexAfter: --------------------[static]--
//
// Purpose:		Each pasted model after the first goes at the next index.
//
//------------------------------------------------------------------------------
+ (NSInteger)nextSequentialModelInsertIndexAfter:(NSInteger)index
{
	if (index != NSNotFound)
		return index + 1;
	return NSNotFound;
}


//---------- duplicatePasteIndexForSelection:defaultNextModelIndex: --[static]--
//
// Purpose:		Makes a copy of the selected object. Duplicate of the current
//				selection should insert as a new MPD model when the first
//				selected object is a model.
//
//------------------------------------------------------------------------------
+ (NSInteger)duplicatePasteIndexForSelection:(NSArray *)selection
					   defaultNextModelIndex:(NSInteger)defaultNextModelIndex
{
	if ([self selectionIsModelForDuplicate:selection])
		return defaultNextModelIndex;
	return NSNotFound;
}


//---------- duplicateUndoActionKey ----------------------------------[static]--
//
// Purpose:		Makes a copy of the selected object. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)duplicateUndoActionKey
{
	return @"UndoDuplicate";
}


@end
