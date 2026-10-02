//==============================================================================
//
//  File:       LDrawSubfileReader.m
//  Package:    LDrawConnectivity
//
//  Purpose:    Reads the subfile references and polygons of library files,
//              with a cache per file.
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
	NSMutableDictionary<NSString *, id>	*_cache;		// name -> references, or NSNull if missing
	NSMutableDictionary<NSString *, id>	*_triangles;	// name -> NSData, or NSNull if missing
	LDrawPaths							*_paths;
}

//========== initWithPaths: ====================================================
//==============================================================================
- (instancetype)initWithPaths:(nullable LDrawPaths *)paths
{
	self = [super init];
	if (self != nil)
	{
		_cache		= [NSMutableDictionary dictionary];
		_triangles	= [NSMutableDictionary dictionary];
		_paths		= (paths != nil) ? paths : [LDrawPaths sharedPaths];
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
		[_triangles removeAllObjects];
	}
}


//========== trianglesInFileNamed: =============================================
//==============================================================================
- (nullable NSData *)trianglesInFileNamed:(NSString *)name
{
	NSString	*key	= NormalizedName(name);
	id			cached	= nil;

	@synchronized (self)
	{
		cached = _triangles[key];
	}
	if (cached == nil)
	{
		NSString *path = [_paths pathForPartName:key];
		cached = (path != nil) ? [self readTrianglesAtPath:path] : nil;
		if (cached == nil)
		{
			cached = [NSNull null];
		}
		@synchronized (self)
		{
			_triangles[key] = cached;
		}
	}
	return (cached == [NSNull null]) ? nil : cached;
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


//---------- TextOfFile ------------------------------------------------[static]--
//------------------------------------------------------------------------------
static NSString *TextOfFile(NSString *path)
{
	NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];

	// Older library files are Latin-1.
	return text ?: [NSString stringWithContentsOfFile:path encoding:NSISOLatin1StringEncoding error:NULL];
}


//========== readTrianglesAtPath: ==============================================
//
// Purpose:		Parses every type 3 and type 4 line: "3 color x1 y1 z1 x2 y2 z2
//				x3 y3 z3", and a fourth corner for a quad.
//
//==============================================================================
- (nullable NSData *)readTrianglesAtPath:(NSString *)path
{
	NSString		*text		= TextOfFile(path);
	NSMutableData	*triangles	= [NSMutableData data];

	if (text == nil)
	{
		return nil;
	}
	[text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
		NSArray<NSString *>	*fields	= [[line componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
									   filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
		BOOL				quad	= [fields.firstObject isEqualToString:@"4"];
		float				v[12];

		if (fields.count < (quad ? 14u : 11u) || (quad == NO && [fields.firstObject isEqualToString:@"3"] == NO))
		{
			return;
		}
		for (NSUInteger index = 0; index < (quad ? 12u : 9u); index++)
		{
			v[index] = fields[2 + index].floatValue;
		}
		[triangles appendBytes:v length:9 * sizeof(float)];

		if (quad)
		{
			float other[9] = { v[0], v[1], v[2], v[6], v[7], v[8], v[9], v[10], v[11] };

			[triangles appendBytes:other length:sizeof(other)];
		}
	}];
	return triangles;
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
	NSString		*text		= TextOfFile(path);
	NSMutableArray	*references	= [NSMutableArray array];

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
