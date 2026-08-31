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


@end
