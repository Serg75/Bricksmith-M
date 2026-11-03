//==============================================================================
//
//  File:       LDrawSelection+Query.m
//  Package:    LDrawEditing
//
//  Purpose:    Selection query helpers for LDrawSelection.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import <LDrawEditing/LDrawSelection.h>

#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawMovableDirective.h>
#import <LDrawCore/LDrawPart.h>

@implementation LDrawSelection (Query)

//========== moveSelectionBy: ==================================================
//
// Purpose:		Moves all selected (and moveable) directives in the direction 
//				indicated by movementVector.
//
//==============================================================================
+ (NSArray *)movableDirectivesInSelection:(NSArray *)selection
{
	NSMutableArray *movable = [NSMutableArray array];
	for (id currentObject in selection)
	{
		if ([currentObject conformsToProtocol:@protocol(LDrawMovableDirective)])
		{
			[movable addObject:currentObject];
		}
	}
	return movable;
}


//---------- partsInSelection: --------------------------------------[static]--
//
// Purpose:		Return the LDrawPart objects in selection, ignoring other
//				directive types.
//
//------------------------------------------------------------------------------
+ (NSArray *)partsInSelection:(NSArray *)selection
{
	NSMutableArray *parts = [NSMutableArray array];
	for (id currentObject in selection)
	{
		if ([currentObject isKindOfClass:[LDrawPart class]])
		{
			[parts addObject:currentObject];
		}
	}
	return parts;
}


//---------- firstPartInSelection: ----------------------------------[static]--
//
// Purpose:		Return the first LDrawPart in selection, or nil.
//
//------------------------------------------------------------------------------
+ (LDrawPart *)firstPartInSelection:(NSArray *)selection
{
	return [[self partsInSelection:selection] firstObject];
}


//---------- sharedReferenceNameInSelection: ------------------------[static]--
//
// Purpose:		Return the part name when every selected part is the same
//				reference; otherwise nil.
//
//------------------------------------------------------------------------------
+ (NSString *)sharedReferenceNameInSelection:(NSArray *)selection
{
	NSString *parentName = nil;
	for (id object in selection)
	{
		if ([object isKindOfClass:[LDrawPart class]] == NO)
		{
			continue;
		}

		NSString *thisName = [(LDrawPart *)object referenceName];
		if (parentName == nil || [thisName compare:parentName] == NSOrderedSame)
		{
			parentName = thisName;
		}
		else
		{
			return nil;
		}
	}
	return parentName;
}


//---------- modelShowingParts:inFile:foundParts: --------------------[static]--
//
// Purpose:		Return the model to show the parts in, and pass back the parts
//				that are in the file's models.
//
//------------------------------------------------------------------------------
+ (LDrawMPDModel *)modelShowingParts:(NSArray<LDrawPart *> *)parts
							  inFile:(LDrawFile *)file
						  foundParts:(NSArray<LDrawPart *> **)foundParts
{
	NSArray			*models		= [file submodels];
	NSMutableArray	*found		= [NSMutableArray array];
	NSHashTable		*holders	= [NSHashTable weakObjectsHashTable];	// models with a found part
	LDrawMPDModel	*shown		= nil;

	for (LDrawPart *part in parts)
	{
		LDrawModel *model = [part enclosingModel];

		if ([models containsObject:model] == NO)
			continue;
		[found addObject:part];
		[holders addObject:model];
	}
	if (foundParts != NULL)
		*foundParts = found;
	if ([found count] == 0)
		return nil;

	shown = [file activeModel];
	if ([holders containsObject:shown])
		return shown;
	for (LDrawMPDModel *model in models)
	{
		if ([holders containsObject:model])
			return model;
	}
	return nil;
}


@end
