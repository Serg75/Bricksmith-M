//==============================================================================
//
//  File:       LDrawLibraryNewParts.m
//  Package:    LDrawLibraryUpdate
//
//  Purpose:    The parts an update added to an LDraw folder.
//
//  Created by Sergey Slobodenyuk on 2026-11-13.
//
//==============================================================================

#import <LDrawLibraryUpdate/LDrawLibraryNewParts.h>

// The keys of dictionaryRepresentation. Hosts save it, so they stay as they are.
static NSString * const FolderKey	= @"folder";
static NSString * const ReleaseKey	= @"release";
static NSString * const NamesKey	= @"names";


@implementation LDrawLibraryNewParts

// MARK: - INITIALIZATION -


//========== initWithPartNames:releaseIdentifier:folderPath: ===================
//==============================================================================
- (instancetype) initWithPartNames:(NSArray<NSString *> *)partNames
				 releaseIdentifier:(NSString *)releaseIdentifier
						folderPath:(NSString *)folderPath
{
	self = [super init];
	if (self) {
		self->_partNames			= [partNames copy];
		self->_releaseIdentifier	= [releaseIdentifier copy];
		self->_folderPath			= [folderPath copy];
	}
	return self;

}//end initWithPartNames:releaseIdentifier:folderPath:


//========== initWithDictionary: ===============================================
//==============================================================================
- (instancetype) initWithDictionary:(NSDictionary *)dictionary
{
	id folderPath	= dictionary[FolderKey];
	id release		= dictionary[ReleaseKey];
	id partNames	= dictionary[NamesKey];

	if (	[folderPath isKindOfClass:[NSString class]] == NO
		||	[release isKindOfClass:[NSString class]] == NO
		||	[partNames isKindOfClass:[NSArray class]] == NO )
	{
		return nil;
	}

	for (id name in partNames)
	{
		if ([name isKindOfClass:[NSString class]] == NO)
			return nil;
	}

	return [self initWithPartNames:partNames releaseIdentifier:release folderPath:folderPath];

}//end initWithDictionary:


// MARK: - ACCESSORS -


//========== dictionaryRepresentation ==========================================
//==============================================================================
- (NSDictionary<NSString *, id> *) dictionaryRepresentation
{
	return @{
		FolderKey	: self.folderPath,
		ReleaseKey	: self.releaseIdentifier,
		NamesKey	: self.partNames,
	};
}


//========== isOfFolderPath: ===================================================
//==============================================================================
- (BOOL) isOfFolderPath:(NSString *)folderPath
{
	NSString *standardPath = [folderPath stringByStandardizingPath];

	return	standardPath != nil
		&&	[[self.folderPath stringByStandardizingPath] isEqualToString:standardPath];
}

@end
