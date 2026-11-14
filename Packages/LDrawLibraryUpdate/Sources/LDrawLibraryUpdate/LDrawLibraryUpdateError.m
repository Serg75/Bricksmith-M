//==============================================================================
//
//  File:       LDrawLibraryUpdateError.m
//  Package:    LDrawLibraryUpdate
//
//  Purpose:    The package's errors.
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//
//==============================================================================

#import "LDrawLibraryUpdateErrorInternal.h"

NSString * const LDrawLibraryUpdateErrorDomain = @"LDrawLibraryUpdateErrorDomain";


//========== LDrawLibraryUpdateMakeError =======================================
//==============================================================================
NSError *LDrawLibraryUpdateMakeError(LDrawLibraryUpdateError code, NSString *reason, NSURL *url)
{
	NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];

	userInfo[NSLocalizedDescriptionKey]	= reason;
	userInfo[NSURLErrorKey]				= url;
	return [NSError errorWithDomain:LDrawLibraryUpdateErrorDomain code:code userInfo:userInfo];
}
