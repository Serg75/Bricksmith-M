//==============================================================================
//
//  File:       LDrawStructure+LSynth.m
//  Package:    LDrawEditing
//
//  Purpose:    LSynth insertion rules for LDrawStructure.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import <LDrawEditing/LDrawStructure.h>

#import <LDrawCore/LDrawContainer.h>
#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawLSynth.h>
#import <LDrawCore/MacLDraw.h>


@implementation LDrawStructure (LSynth)

//---------- lsynthInsertionParent:index:forLastSelected: ------------[static]--
//
// Purpose:		Insert a synthesizable directive constraint into the model.
//				We don't distinguish between hose or band constraints since
//				both types can be used for either synthesizable type.
//
//------------------------------------------------------------------------------
+ (BOOL)lsynthInsertionParent:(LDrawContainer * _Nullable * _Nullable)outParent
						index:(NSInteger * _Nullable)outIndex
			  forLastSelected:(id)lastSelected
{
	if (lastSelected == nil)
	{
		return NO;
	}

	if ([lastSelected isKindOfClass:[LDrawLSynth class]])
	{
		if (outParent != NULL)
		{
			*outParent = lastSelected;
		}
		if (outIndex != NULL)
		{
			*outIndex = [[lastSelected subdirectives] count];
		}
		return YES;
	}

	if ([lastSelected isKindOfClass:[LDrawDirective class]])
	{
		LDrawContainer *parent = [lastSelected enclosingDirective];
		if ([parent isKindOfClass:[LDrawLSynth class]])
		{
			if (outParent != NULL)
			{
				*outParent = parent;
			}
			if (outIndex != NULL)
			{
				*outIndex = [parent indexOfDirective:lastSelected] + 1;
			}
			return YES;
		}
	}
	return NO;
}


//---------- lsynthDirectionCommandForMenuTag: -----------------------[static]--
//
// Purpose:		Insert an LSynth direction directive, INSIDE or OUTSIDE, which
//				causes a constraint to switch the side the band passes it.
//				INSIDE / OUTSIDE / CROSS from MacLDraw.h menu tags; nil if the
//				tag is unrelated.
//
//------------------------------------------------------------------------------
+ (NSString *)lsynthDirectionCommandForMenuTag:(NSInteger)tag
{
	if (tag == lsynthInsertINSIDETag)
	{
		return @"INSIDE";
	}
	if (tag == lsynthInsertOUTSIDETag)
	{
		return @"OUTSIDE";
	}
	if (tag == lsynthInsertCROSSTag)
	{
		return @"CROSS";
	}
	return nil;
}


//---------- lsynthInsertUndoKeyForMenuTag: -------------------------[static]--
//
// Purpose:		Undo action name key for inserting an LSynth object from a menu
//				tag. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)lsynthInsertUndoKeyForMenuTag:(NSInteger)tag
{
	if (tag == lsynthInsertINSIDETag) return @"UndoAddLSynthInside";
	if (tag == lsynthInsertOUTSIDETag) return @"UndoAddLSynthOutside";
	return @"UndoAddLSynthCross";
}

@end
