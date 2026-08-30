//==============================================================================
//
//  File:       LDrawEditorStrings.m
//  Package:    LDrawEditing
//
//  Purpose:    Localization keys and external-change policy for document alerts.
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <LDrawEditing/LDrawEditorStrings.h>

@implementation LDrawEditorStrings

//---------- missingPiecesMessageKey ---------------------------------[static]--
//
// Purpose:		Missing / moved pieces and external-change alert keys. The host
//				still localizes and presents.
//
//------------------------------------------------------------------------------
+ (NSString *)missingPiecesMessageKey
{
	return @"MissingPiecesMessage";
}


//---------- missingPiecesInformativeKey ----------------------------[static]--
//
// Purpose:		Localization key for the missing-pieces alert informative text.
//				The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)missingPiecesInformativeKey
{
	return @"MissingPiecesInformative";
}


//---------- movedPiecesMessageKey ----------------------------------[static]--
//
// Purpose:		Localization key for the alert when parts were moved by another
//				app. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)movedPiecesMessageKey
{
	return @"MovedPiecesMessage";
}


//---------- movedPiecesInformativeKey ------------------------------[static]--
//
// Purpose:		Localization key for the informative text of that moved-parts
//				alert. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)movedPiecesInformativeKey
{
	return @"MovedPiecesInformative";
}


//---------- openingFileFormatKey -----------------------------------[static]--
//
// Purpose:		Localization key format for the opening-file progress message.
//				The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)openingFileFormatKey
{
	return @"OpeningFileX";
}


//---------- unsavedDocumentMessageFormatKey ------------------------[static]--
//
// Purpose:		Localization key format for the unsaved-document alert message.
//				The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)unsavedDocumentMessageFormatKey
{
	return @"UnsavedDocumentMessage";
}


//---------- unsavedDocumentInformativeKey --------------------------[static]--
//
// Purpose:		Localization key for the unsaved-document alert informative
//				text. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)unsavedDocumentInformativeKey
{
	return @"UnsavedDocumentInformative";
}


//---------- unsavedDocumentRevertButtonKey -------------------------[static]--
//
// Purpose:		Localization key for the Revert button on the unsaved-document
//				alert. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)unsavedDocumentRevertButtonKey
{
	return @"UnsavedDocumentRevertButton";
}


//---------- unsavedDocumentKeepButtonKey ---------------------------[static]--
//
// Purpose:		Localization key for the Keep button on the unsaved-document
//				alert. The host still localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)unsavedDocumentKeepButtonKey
{
	return @"UnsavedDocumentKeepButton";
}


//---------- okButtonNameKey ----------------------------------------[static]--
//
// Purpose:		Localization key for a generic OK button. The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)okButtonNameKey
{
	return @"OKButtonName";
}


//---------- cancelButtonNameKey ------------------------------------[static]--
//
// Purpose:		Localization key for a generic Cancel button. The host still
//				localizes.
//
//------------------------------------------------------------------------------
+ (NSString *)cancelButtonNameKey
{
	return @"CancelButtonName";
}


//---------- shouldPromptUnsavedExternalChangeWhenDocumentEdited:… ---[static]--
//
// Purpose:		File on disk newer than last known date: prompt if edited.
//
//------------------------------------------------------------------------------
+ (BOOL)shouldPromptUnsavedExternalChangeWhenDocumentEdited:(BOOL)edited
										 fileNewerThanKnown:(BOOL)fileNewer
{
	return fileNewer && edited;
}


//---------- shouldSilentRevertExternalChangeWhenDocumentEdited:… ----[static]--
//
// Purpose:		File on disk newer than last known date: silent revert if not
//				edited.
//
//------------------------------------------------------------------------------
+ (BOOL)shouldSilentRevertExternalChangeWhenDocumentEdited:(BOOL)edited
										fileNewerThanKnown:(BOOL)fileNewer
{
	return fileNewer && edited == NO;
}


@end
