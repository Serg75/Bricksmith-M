//==============================================================================
//
// File:		StringUtilities.m
//
// Purpose:		General string utility methods. Logic lives in LDrawUtilities;
//				this host wrapper localizes the copy token.
//
// Modified:	12/21/2008 Allen Smith. Creation Date.
//
//==============================================================================
#import "StringUtilities.h"

#import <LDrawCore/LDrawUtilities.h>


@implementation StringUtilities

//---------- nextCopyNameForString: ----------------------------------[static]--
//
// Purpose:		Returns the next name (in sequence) for a copy of the given
//				name.
//
//------------------------------------------------------------------------------
+ (NSString *) nextCopyNameForString:(NSString *)originalString
{
	NSString *copyToken = NSLocalizedString([LDrawUtilities copySuffixLocalizationKey], nil);
	return [LDrawUtilities nextCopyNameForString:originalString copyToken:copyToken];
}//end nextCopyNameForString:


//---------- nextCopyPathForFilePath: --------------------------------[static]--
//
// Purpose:		Returns the next path or file name (in sequence) for a copy of 
//				the given name. Correctly handles file extensions.
//
//------------------------------------------------------------------------------
+ (NSString *) nextCopyPathForFilePath:(NSString *)basePath
{
	NSString *copyToken = NSLocalizedString([LDrawUtilities copySuffixLocalizationKey], nil);
	return [LDrawUtilities nextCopyPathForFilePath:basePath copyToken:copyToken];
}//end nextCopyPathForFilePath:


@end
