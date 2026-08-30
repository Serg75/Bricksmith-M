//==============================================================================
//
//  File:       LDrawEditorStrings.h
//  Package:    LDrawEditing
//
//  Purpose:    Localization keys and external-change policy for document
//              alerts. The host still localizes and presents.
//
//  Created by Sergey Slobodenyuk on 2023-02-10.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawEditorStrings
///
/// @abstract   Missing / moved pieces, open-file, unsaved-external-change, and
///             generic OK/Cancel keys, plus whether to prompt or silent-revert.
///
//------------------------------------------------------------------------------
@interface LDrawEditorStrings : NSObject

+ (NSString *)missingPiecesMessageKey;
+ (NSString *)missingPiecesInformativeKey;
+ (NSString *)movedPiecesMessageKey;
+ (NSString *)movedPiecesInformativeKey;
+ (NSString *)openingFileFormatKey;
+ (NSString *)unsavedDocumentMessageFormatKey;
+ (NSString *)unsavedDocumentInformativeKey;
+ (NSString *)unsavedDocumentRevertButtonKey;
+ (NSString *)unsavedDocumentKeepButtonKey;
+ (NSString *)okButtonNameKey;
+ (NSString *)cancelButtonNameKey;

/// File on disk newer than last known date: prompt if edited, else silent revert.
+ (BOOL)shouldPromptUnsavedExternalChangeWhenDocumentEdited:(BOOL)edited
										 fileNewerThanKnown:(BOOL)fileNewer;
+ (BOOL)shouldSilentRevertExternalChangeWhenDocumentEdited:(BOOL)edited
										fileNewerThanKnown:(BOOL)fileNewer;

@end

NS_ASSUME_NONNULL_END
