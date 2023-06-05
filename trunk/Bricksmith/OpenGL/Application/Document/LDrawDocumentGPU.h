//==============================================================================
//
//	LDrawDocumentGPU.h
//	Bricksmith
//
//	Purpose:	Document controller for an LDraw document.
//
//				Opens the document and manages its editor and viewer.
//
//				To use elsewhere, do something like:
//
//					#import "LDrawDocument.h"
//					NSDocumentController *documentController = [NSDocumentController sharedDocumentController];
//					LDrawDocument *currentDocument = [documentController currentDocument];
//
//	Info:		This category contains OpenGL-related code.
//
//	Created by Sergey Slobodenyuk on 2023-05-29.
//
//==============================================================================

#import "LDrawDocument.h"

NS_ASSUME_NONNULL_BEGIN

@interface LDrawDocument (OpenGL)

@end

NS_ASSUME_NONNULL_END
