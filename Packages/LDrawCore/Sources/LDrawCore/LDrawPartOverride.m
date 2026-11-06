//==============================================================================
//
//  File:       LDrawPartOverride.m
//  Package:    LDrawCore
//
//  Purpose:    A part in the overrides folder, and whether the library has a
//              newer version of it.
//
//  Created by Sergey Slobodenyuk on 2026-11-04.
//
//==============================================================================

#import <LDrawCore/LDrawPartOverride.h>

#import <LDrawCore/LDrawPaths.h>
#import <LDrawCore/LDrawUtilities.h>
#import <LDrawCore/NSString+LDraw.h>

// How much of a file is read for its header. A header fits in it.
static const NSUInteger HeaderReadLength = 4096;

static NSString * const OriginalUpdate = @"ORIGINAL";


//========== HeaderText ========================================================
///
/// @abstract	The start of a file, or nil when it cannot be read.
///
//==============================================================================
static NSString *HeaderText(NSString *path)
{
	NSFileHandle	*file	= [NSFileHandle fileHandleForReadingAtPath:path];
	NSData			*start	= [file readDataUpToLength:HeaderReadLength error:NULL];

	[file closeAndReturnError:NULL];
	return (start != nil) ? [LDrawUtilities stringFromFileData:start] : nil;

}//end HeaderText


//========== UpdateOrder ======================================================
///
/// @abstract	A release as text that sorts by age. ORIGINAL is older than
/// 			every update.
///
//==============================================================================
static NSString *UpdateOrder(NSString *update)
{
	return [update isEqualToString:OriginalUpdate] ? @"0000-00" : update;
}


@interface LDrawPartOverride ()

- (instancetype) initWithPartName:(NSString *)partName
							 path:(NSString *)path
							paths:(LDrawPaths *)paths;

@end


@implementation LDrawPartOverride

#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//========== initWithPartName:path:paths: ======================================
//==============================================================================
- (instancetype) initWithPartName:(NSString *)partName
							 path:(NSString *)path
							paths:(LDrawPaths *)paths
{
	self = [super init];
	if (self) {
		self->_partName			= [partName lowercaseString];
		self->_libraryPath		= [[self class] libraryPathForPartName:self->_partName paths:paths];
		self->_update			= [[self class] updateOfFileAtPath:path];
		self->_libraryUpdate	= [[self class] updateOfFileAtPath:self->_libraryPath];
	}
	return self;
}


//---------- libraryPathForPartName:paths: ---------------------------[static]--
///
/// @abstract	The library file an override was made from. A high or low
/// 			version the library does not have, such as "48\s\54087s00.dat",
/// 			was made from the part itself.
///
//------------------------------------------------------------------------------
+ (NSString *) libraryPathForPartName:(NSString *)partName paths:(LDrawPaths *)paths
{
	NSString *path		= [paths libraryPathForPartName:partName];
	NSString *original	= [LDrawPaths partNameWithoutResolution:partName];

	if (path == nil && original != nil)
		path = [paths libraryPathForPartName:original];
	return path;

}//end libraryPathForPartName:paths:


#pragma mark -
#pragma mark READING
#pragma mark -

//---------- filesWithPaths: -----------------------------------------[static]--
///
/// @abstract	Each part file in the overrides folder of `paths`, by the name a
/// 			part line gives it: its path below "parts" or "p", with
/// 			backslashes, in lowercase.
///
//------------------------------------------------------------------------------
+ (NSDictionary<NSString *, NSString *> *) filesWithPaths:(LDrawPaths *)paths
{
	NSFileManager									*fileManager	= [[NSFileManager alloc] init];
	NSMutableDictionary<NSString *, NSString *>		*files			= [NSMutableDictionary dictionary];

	if ([paths overridesPath] == nil)
		return files;

	for (NSString *folder in @[[paths partsPathForDomain:LDrawUserOverrides],
							   [paths primitivesPathForDomain:LDrawUserOverrides]])
	{
		NSDirectoryEnumerator	*walk		= [fileManager enumeratorAtPath:folder];
		NSString				*relative	= nil;

		while ((relative = [walk nextObject]) != nil)
		{
			NSString *extension = [[relative pathExtension] lowercaseString];

			// Hidden files, such as the "._4592.dat" files some disks keep
			// next to each file, are not parts.
			if ([[relative lastPathComponent] hasPrefix:@"."])
			{
				[walk skipDescendants];
				continue;
			}
			if ([extension isEqualToString:@"dat"] == NO && [extension isEqualToString:@"ldr"] == NO)
				continue;

			NSString *partName = [[relative stringByReplacingOccurrencesOfString:@"/" withString:@"\\"]
								  lowercaseString];

			// "p" comes second, so it wins a name both have, as in the search.
			files[partName] = [folder stringByAppendingPathComponent:relative];
		}
	}

	return files;

}//end filesWithPaths:


//---------- overridesWithPaths: -------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSArray<LDrawPartOverride *> *) overridesWithPaths:(LDrawPaths *)paths
{
	NSDictionary<NSString *, NSString *>	*files		= [self filesWithPaths:paths];
	NSMutableArray<LDrawPartOverride *>		*overrides	= [NSMutableArray arrayWithCapacity:[files count]];

	for (NSString *partName in files)
	{
		@autoreleasepool {
			[overrides addObject:[[self alloc] initWithPartName:partName path:files[partName] paths:paths]];
		}
	}

	[overrides sortUsingComparator:^NSComparisonResult(LDrawPartOverride *a, LDrawPartOverride *b) {
		return [a.partName compare:b.partName options:NSNumericSearch];
	}];
	return overrides;

}//end overridesWithPaths:


//---------- readOverridesWithPaths:completionHandler: ---------------[static]--
///
/// @abstract	Lists the overrides on a background queue, from a copy of the
/// 			paths, and calls the handler on the main queue.
///
//------------------------------------------------------------------------------
+ (void) readOverridesWithPaths:(LDrawPaths *)paths
			  completionHandler:(void (^)(NSArray<LDrawPartOverride *> *overrides))completionHandler
{
	LDrawPaths *copy = [paths copy];

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		NSArray *overrides = [self overridesWithPaths:copy];

		dispatch_async(dispatch_get_main_queue(), ^{
			completionHandler(overrides);
		});
	});

}//end readOverridesWithPaths:completionHandler:


//---------- updateOfFileAtPath: ------------------------------------[static]--
///
/// @abstract	The release in the header of the file, or nil.
///
//------------------------------------------------------------------------------
+ (NSString *) updateOfFileAtPath:(NSString *)path
{
	NSString *text = (path != nil) ? HeaderText(path) : nil;

	return (text != nil) ? [self updateInText:text] : nil;

}//end updateOfFileAtPath:


//---------- updateInText: ------------------------------------------[static]--
///
/// @abstract	Reads "UPDATE 2022-01" or "ORIGINAL" from the "!LDRAW_ORG"
/// 			line. Only the header is read: it ends at the first line that
/// 			is not a comment.
///
//------------------------------------------------------------------------------
+ (NSString *) updateInText:(NSString *)text
{
	static NSRegularExpression	*orgLine	= nil;
	static dispatch_once_t		 onceToken;
	NSCharacterSet				*spaces		= [NSString ldraw_lineSpaceCharacterSet];
	__block NSString			*update		= nil;

	dispatch_once(&onceToken, ^{
		orgLine	= [NSRegularExpression regularExpressionWithPattern:
				   @"^0\\s+!?LDRAW_ORG\\b.*?\\b(?:UPDATE\\s+(\\d{4}-\\d{2})|(ORIGINAL))\\b"
															options:NSRegularExpressionCaseInsensitive
															  error:NULL];
	});

	[text enumerateLinesUsingBlock:^(NSString *rawLine, BOOL *stop) {
		NSString				*line	= [rawLine stringByTrimmingCharactersInSet:spaces];
		NSTextCheckingResult	*match	= nil;

		if ([line length] > 0 && [line hasPrefix:@"0"] == NO)
		{
			*stop = YES;
			return;
		}

		match = [orgLine firstMatchInString:line options:0 range:NSMakeRange(0, [line length])];
		if (match != nil)
		{
			NSRange stamp = [match rangeAtIndex:1];

			update	= (stamp.location != NSNotFound) ? [line substringWithRange:stamp] : OriginalUpdate;
			*stop	= YES;
		}
	}];

	return update;

}//end updateInText:


#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

//========== libraryIsNewer ====================================================
//==============================================================================
- (BOOL) libraryIsNewer
{
	if (self.update == nil || self.libraryUpdate == nil)
		return NO;

	return [UpdateOrder(self.libraryUpdate) compare:UpdateOrder(self.update)
											options:NSNumericSearch] == NSOrderedDescending;
}


//========== description =======================================================
//==============================================================================
- (NSString *) description
{
	return [NSString stringWithFormat:@"%@ %@ (library %@)", self.partName,
			self.update ?: @"-", self.libraryUpdate ?: @"-"];
}

@end
