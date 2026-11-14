//==============================================================================
//
//  File:       LDrawLibraryUpdateError.h
//  Package:    LDrawLibraryUpdate
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//
//==============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Errors of the LDrawLibraryUpdate package. The description says what went
/// wrong, and NSURLErrorKey names the file or address, when there is one.
extern NSString * const LDrawLibraryUpdateErrorDomain;

typedef NS_ERROR_ENUM(LDrawLibraryUpdateErrorDomain, LDrawLibraryUpdateError)
{
	/// The server answered with something unexpected.
	LDrawLibraryUpdateErrorBadResponse	= 1,

	/// A download is not the file the release list describes.
	LDrawLibraryUpdateErrorBadDownload	= 2,

	/// An archive could not be read.
	LDrawLibraryUpdateErrorBadArchive	= 3,

	/// The LDraw folder cannot be written.
	LDrawLibraryUpdateErrorNotWritable	= 4,

	/// The work was canceled.
	LDrawLibraryUpdateErrorCanceled		= 5,

	/// Another update of the folder is under way.
	LDrawLibraryUpdateErrorBusy			= 6
};

NS_ASSUME_NONNULL_END
