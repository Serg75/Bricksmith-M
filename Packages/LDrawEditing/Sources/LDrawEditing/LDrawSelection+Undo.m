//==============================================================================
//
//  File:       LDrawSelection+Undo.m
//  Package:    LDrawEditing
//
//  Purpose:    Undo action localization keys for LDrawSelection.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#import <LDrawEditing/LDrawSelection.h>

@implementation LDrawSelection (Undo)

//---------- hideShowUndoActionKeyForHidden: -------------------------[static]--
//
// Purpose:		Undo-aware call to change the visibility attribute of an
//				element. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)hideShowUndoActionKeyForHidden:(BOOL)hideFlag
{
	if (hideFlag == YES)
		return @"UndoHidePart";
	return @"UndoShowPart";
}


//---------- moveUndoActionKey ---------------------------------------[static]--
+ (NSString *)moveUndoActionKey
{
	return @"UndoMove";
}


//---------- rotateUndoActionKey ------------------------------------[static]--
//
// Purpose:		Undo action name key for rotating the selection. The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)rotateUndoActionKey
{
	return @"UndoRotate";
}


//---------- colorUndoActionKey -------------------------------------[static]--
//
// Purpose:		Undo action name key for coloring the selection. The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)colorUndoActionKey
{
	return @"UndoColor";
}


//---------- snapToGridUndoActionKey --------------------------------[static]--
//
// Purpose:		Undo action name key for snapping the selection to the grid.
//				The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)snapToGridUndoActionKey
{
	return @"UndoSnapToGrid";
}


//---------- setGroupUndoActionKey ----------------------------------[static]--
//
// Purpose:		Undo action name key for assigning an MLCAD group. The host
//				still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)setGroupUndoActionKey
{
	return @"UndoSetGroup";
}


@end
