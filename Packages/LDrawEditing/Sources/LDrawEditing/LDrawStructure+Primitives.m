//==============================================================================
//
//  File:       LDrawStructure+Primitives.m
//  Package:    LDrawEditing
//
//  Purpose:    High-res primitive conversion rules for LDrawStructure.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import <LDrawEditing/LDrawStructure.h>

#import <LDrawCore/LDrawModel.h>


@implementation LDrawStructure (Primitives)

//---------- convertPrimitivesUndoActionKey --------------------------[static]--
//
// Purpose:		Localization key after converting to high-res primitives.
//
//------------------------------------------------------------------------------
+ (NSString *)convertPrimitivesUndoActionKey
{
	return @"UndoConvertPrimitives";
}


//---------- highResSourceDirectivesFromSelection:activeModel: -------[static]--
//
// Purpose:		Changes low-res directives into high-res quality for "48"
//				folder. If nothing is selected, all directives in the first
//				step are converted. The host still replaces (undo).
//
//------------------------------------------------------------------------------
+ (NSArray *)highResSourceDirectivesFromSelection:(NSArray *)selection
									  activeModel:(LDrawModel *)model
{
	if ([selection count] > 0) return selection;
	return [[[model steps] firstObject] subdirectives];
}

@end
