//==============================================================================
//
//  File:       LDrawLibraryUpdateErrorInternal.h
//  Package:    LDrawLibraryUpdate
//
//  Purpose:    Makes the package's errors. Not exported.
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//
//==============================================================================

#import <LDrawLibraryUpdate/LDrawLibraryUpdateError.h>

NS_ASSUME_NONNULL_BEGIN

/// An error of the package, with the reason as its description and the file
/// it is about, when given.
NSError *LDrawLibraryUpdateMakeError(LDrawLibraryUpdateError code, NSString * _Nullable reason, NSURL * _Nullable url);

NS_ASSUME_NONNULL_END
