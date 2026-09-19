//==============================================================================
//
//  File:       LDrawStructure+Navigation.m
//  Package:    LDrawEditing
//
//  Purpose:    MPD submodel and peer-file navigation rules for LDrawStructure.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import <LDrawEditing/LDrawStructure.h>

#import <LDrawCore/LDrawModel.h>
#import <LDrawCore/LDrawMPDModel.h>


@implementation LDrawStructure (Navigation)

//---------- mpdSubmodelToActivateFromSelection: ---------------------[static]--
//
// Purpose:		If a single part is selected and the part is an MPD sub-model,
//				this is the current edited submodel to switch to.
//
//------------------------------------------------------------------------------
+ (LDrawMPDModel *)mpdSubmodelToActivateFromSelection:(NSArray *)selection
{
	if ([selection count] != 1)
	{
		return nil;
	}

	id currentObject = [selection objectAtIndex:0];
	if ([currentObject respondsToSelector:@selector(referencedMPDSubmodel)] == NO)
	{
		return nil;
	}

	LDrawModel *model = [currentObject referencedMPDSubmodel];
	if ([model isKindOfClass:[LDrawMPDModel class]])
	{
		return (LDrawMPDModel *)model;
	}
	return nil;
}


//---------- peerFileFromSelection:path: -----------------------------[static]--
//
// Purpose:		If a single part is selected and it's a peer file on disk, this
//				is the .ldr path to open in a new document. The host still opens
//				it.
//
//------------------------------------------------------------------------------
+ (BOOL)peerFileFromSelection:(NSArray *)selection
						 path:(NSString * _Nullable * _Nullable)outPath
{
	if (outPath != NULL)
	{
		*outPath = nil;
	}
	if ([selection count] != 1)
	{
		return NO;
	}

	id currentObject = [selection objectAtIndex:0];
	if ([currentObject respondsToSelector:@selector(referencedPeerFile)] == NO)
	{
		return NO;
	}

	LDrawModel *model = [currentObject referencedPeerFile];
	if (model == nil)
	{
		return NO;
	}
	if (outPath != NULL)
	{
		*outPath = [[model enclosingFile] path];
	}
	return YES;
}

@end
