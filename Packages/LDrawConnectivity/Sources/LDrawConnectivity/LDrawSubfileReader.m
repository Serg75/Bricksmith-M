//==============================================================================
//
//  File:       LDrawSubfileReader.m
//  Package:    LDrawConnectivity
//
//  Purpose:    Reads the subfile references of library files, with a cache
//              per file.
//
//  Created by Sergey Slobodenyuk on 2026-09-19.
//
//==============================================================================

#import "LDrawSubfileReader.h"

#import <LDrawCore/LDrawPaths.h>


//---------- NormalizedName --------------------------------------------[static]--
//
// Purpose:		The name in lowercase with / separators, to match the library's
//				file names.
//
//------------------------------------------------------------------------------
static NSString *NormalizedName(NSString *name)
{
	return [name.lowercaseString stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
}


@interface LDrawSubfileReference ()
- (instancetype)initWithName:(NSString *)name transform:(Matrix4)transform;
@end


@implementation LDrawSubfileReference

- (instancetype)initWithName:(NSString *)name transform:(Matrix4)transform
{
	self = [super init];
	if (self != nil)
	{
		_name		= [name copy];
		_transform	= transform;
	}
	return self;
}

@end


@implementation LDrawSubfileReader
{
	NSMutableDictionary<NSString *, id>	*_cache;	// name -> references, or NSNull if missing
	LDrawPaths							*_paths;
}

//========== initWithPaths: ====================================================
//==============================================================================
- (instancetype)initWithPaths:(nullable LDrawPaths *)paths
{
	self = [super init];
	if (self != nil)
	{
		_cache = [NSMutableDictionary dictionary];
		_paths = (paths != nil) ? paths : [LDrawPaths sharedPaths];
	}
	return self;
}


//========== init ==============================================================
//==============================================================================
- (instancetype)init
{
	return [self initWithPaths:nil];
}


//---------- normalizedName: -------------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *)normalizedName:(NSString *)name
{
	return NormalizedName(name);
}


//========== referencesInFileNamed: ============================================
//==============================================================================
- (nullable NSArray<LDrawSubfileReference *> *)referencesInFileNamed:(NSString *)name
{
	NSString	*key	= NormalizedName(name);
	id			cached	= nil;

	@synchronized (self)
	{
		cached = _cache[key];
	}
	if (cached == nil)
	{
		NSString *path = [_paths pathForPartName:key];
		cached = (path != nil) ? [self readReferencesAtPath:path] : nil;
		if (cached == nil)
		{
			cached = [NSNull null];
		}
		@synchronized (self)
		{
			_cache[key] = cached;
		}
	}
	return (cached == [NSNull null]) ? nil : cached;
}


//========== removeAllReferences ===============================================
//==============================================================================
- (void)removeAllReferences
{
	@synchronized (self)
	{
		[_cache removeAllObjects];
	}
}


//========== relativePathForFileNamed: =========================================
//==============================================================================
- (nullable NSString *)relativePathForFileNamed:(NSString *)name
{
	// Standardize both paths, because a root may end with a slash.
	NSString	*path	= [[_paths pathForPartName:NormalizedName(name)] stringByStandardizingPath];
	NSArray		*roots	= @[_paths.preferredLDrawPath ?: @"",
							_paths.internalLDrawPath ?: @""];

	for (NSString *root in roots)
	{
		NSString *base		= [root stringByStandardizingPath];
		NSString *prefix	= [base stringByAppendingString:@"/"];

		if (path != nil && base.length > 0 && [path hasPrefix:prefix])
		{
			return [path substringFromIndex:prefix.length];
		}
	}
	return nil;
}


//========== readReferencesAtPath: =============================================
//
// Purpose:		Parses every type 1 line: "1 color x y z a b c d e f g h i name".
//
// Notes:		The matrix is transposed for row vectors, with the offset as
//				the last row.
//
//==============================================================================
- (nullable NSArray<LDrawSubfileReference *> *)readReferencesAtPath:(NSString *)path
{
	NSString		*text		= [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
	NSMutableArray	*references	= [NSMutableArray array];

	if (text == nil)
	{
		// Older library files are Latin-1.
		text = [NSString stringWithContentsOfFile:path encoding:NSISOLatin1StringEncoding error:NULL];
	}
	if (text == nil)
	{
		return nil;
	}

	[text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
		NSArray<NSString *>	*fields	= [[line componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
									   filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
		double				v[12];
		Matrix4				m		= IdentityMatrix4;

		if (fields.count < 15 || [fields[0] isEqualToString:@"1"] == NO)
		{
			return;
		}
		for (NSUInteger index = 0; index < 12; index++)
		{
			v[index] = fields[2 + index].doubleValue;
		}

		m.element[0][0] = v[3];	m.element[0][1] = v[6];	m.element[0][2] = v[9];
		m.element[1][0] = v[4];	m.element[1][1] = v[7];	m.element[1][2] = v[10];
		m.element[2][0] = v[5];	m.element[2][1] = v[8];	m.element[2][2] = v[11];
		m.element[3][0] = v[0];	m.element[3][1] = v[1];	m.element[3][2] = v[2];

		NSString *name = [[fields subarrayWithRange:NSMakeRange(14, fields.count - 14)] componentsJoinedByString:@" "];
		[references addObject:[[LDrawSubfileReference alloc] initWithName:NormalizedName(name) transform:m]];
	}];

	return references;
}

@end
