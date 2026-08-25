//==============================================================================
//
//	LDrawDocumentMTL.h
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
//	Info:		This category contains Metal-related code.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import "LDrawDocument.h"


@interface LDrawDocument (Metal)

/// Run block immediately; Metal has no shared GL context to lock.
- (void)lockContextAndExecute:(void (NS_NOESCAPE ^)(void))block;

@end
