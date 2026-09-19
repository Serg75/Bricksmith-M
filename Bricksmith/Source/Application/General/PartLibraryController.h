//==============================================================================
//
// File:		PartLibraryController.h
//
// Purpose:		UI layerings on top of LDrawPartLibrary.
//
// Modified:	01/28/2009 Allen Smith. Creation Date.
//
//==============================================================================
#import <Cocoa/Cocoa.h>

#ifdef METAL
#import <LDrawRenderMetal/LDrawPartLibraryMTL.h>
#else
#import <LDrawRenderOpenGL/LDrawPartLibraryGL.h>
#endif


////////////////////////////////////////////////////////////////////////////////
//
// class PartLibraryController
//
////////////////////////////////////////////////////////////////////////////////
@interface PartLibraryController : NSObject <LDrawPartLibraryDelegate>

// Actions
- (void) loadPartCatalog:(void (^)(BOOL success))completionHandler;
- (void) reloadPartCatalog:(void (^)(BOOL success))completionHandler;
- (BOOL) validateLDrawFolderWithMessage:(NSString *) folderPath;

@end
