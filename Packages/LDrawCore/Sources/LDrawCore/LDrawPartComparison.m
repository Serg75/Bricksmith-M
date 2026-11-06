//==============================================================================
//
//  File:       LDrawPartComparison.m
//  Package:    LDrawCore
//
//  Purpose:    A part as the overrides folder has it and as the library has
//              it, each as a file that can be drawn next to the other.
//
//  Created by Sergey Slobodenyuk on 2026-11-04.
//
//==============================================================================

#import <LDrawCore/LDrawPartComparison.h>

#import <LDrawCore/LDrawFile.h>
#import <LDrawCore/LDrawMPDModel.h>
#import <LDrawCore/LDrawPaths.h>
#import <LDrawCore/LDrawUtilities.h>
#import <LDrawCore/NSString+LDraw.h>

// Joins a part's name to the name of a model inside its own file, so the
// models of two files cannot have the same name.
static NSString * const InnerModelSeparator = @"#";


//========== Fields ============================================================
///
/// @abstract	The words of a line. A byte order mark counts as a space.
///
//==============================================================================
static NSArray<NSString *> *Fields(NSString *line)
{
	NSCharacterSet				*spaces	= [NSString ldraw_lineSpaceCharacterSet];
	NSMutableArray<NSString *>	*fields	= [NSMutableArray array];

	for (NSString *field in [line componentsSeparatedByCharactersInSet:spaces])
	{
		if ([field length] > 0)
			[fields addObject:field];
	}
	return fields;

}//end Fields


//========== UsedName ==========================================================
///
/// @abstract	The part a type 1 line uses, lowercase, or nil for any other
/// 			line.
///
//==============================================================================
static NSString *UsedName(NSArray<NSString *> *fields)
{
	NSArray<NSString *> *nameFields = nil;

	if ([fields count] < 15 || [fields[0] isEqualToString:@"1"] == NO)
		return nil;

	nameFields = [fields subarrayWithRange:NSMakeRange(14, [fields count] - 14)];
	return [[nameFields componentsJoinedByString:@" "] lowercaseString];

}//end UsedName


//------------------------------------------------------------------------------
///
/// @class		LDrawComparedFile
///
/// @abstract	One part file, cut into the models it holds.
///
//------------------------------------------------------------------------------
@interface LDrawComparedFile : NSObject

/// The lines of each model, without their FILE lines. The first is the part.
@property (nonatomic, readonly) NSArray<NSArray<NSString *> *> *models;

/// The lowercase names of the models after the first.
@property (nonatomic, readonly) NSArray<NSString *> *innerNames;

/// The parts its lines use, not counting its own models.
@property (nonatomic, readonly) NSSet<NSString *> *usedNames;

+ (nullable instancetype) fileAtPath:(nullable NSString *)path;

@end


@implementation LDrawComparedFile

//---------- fileAtPath: ---------------------------------------------[static]--
///
/// @abstract	Reads the file. A FILE line before any other line names the
/// 			part's own model; later ones start the models inside it.
///
//------------------------------------------------------------------------------
+ (instancetype) fileAtPath:(NSString *)path
{
	NSString					*text		= (path != nil) ? [LDrawUtilities stringFromFile:path] : nil;
	NSMutableArray				*models		= [NSMutableArray arrayWithObject:[NSMutableArray array]];
	NSMutableArray<NSString *>	*innerNames	= [NSMutableArray array];
	NSMutableSet<NSString *>	*usedNames	= [NSMutableSet set];
	BOOL						 skipping	= NO;
	LDrawComparedFile			*file		= nil;

	if (text == nil)
		return nil;

	for (NSString *line in [text separateByLine])
	{
		NSString	*modelName	= nil;
		NSArray		*fields		= Fields(line);
		NSString	*used		= UsedName(fields);

		if ([LDrawMPDModel lineIsMPDModelStart:line modelName:&modelName])
		{
			if ([innerNames count] > 0 || [[models firstObject] count] > 0)
			{
				[models addObject:[NSMutableArray array]];
				[innerNames addObject:[modelName lowercaseString]];
			}
			skipping = NO;
			continue;
		}
		if ([LDrawMPDModel lineIsMPDModelEnd:line])
		{
			skipping = YES;
			continue;
		}
		if (skipping || ([fields count] == 0 && [[models lastObject] count] == 0))
			continue;

		[[models lastObject] addObject:line];
		if (used != nil)
			[usedNames addObject:used];
	}

	[usedNames minusSet:[NSSet setWithArray:innerNames]];

	file = [[self alloc] init];
	file->_models		= models;
	file->_innerNames	= innerNames;
	file->_usedNames	= usedNames;
	return file;

}//end fileAtPath:

@end


@implementation LDrawPartComparison
{
	LDrawPaths											*paths;
	NSMutableDictionary<NSString *, NSNumber *>			*overridden;
	NSMutableDictionary<NSString *, id>					*overrideFiles;		// name → file, or NSNull
	NSMutableDictionary<NSString *, id>					*libraryFiles;
	NSMutableDictionary<NSString *, NSNumber *>			*overrideLeads;		// name → leads to an override
	NSMutableDictionary<NSString *, NSNumber *>			*libraryLeads;
}


#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//========== initWithPartName:paths: ===========================================
///
/// @abstract	Reads both sides from the part down, as far as each file goes.
///
//==============================================================================
- (instancetype) initWithPartName:(NSString *)partName paths:(LDrawPaths *)pathsIn
{
	self = [super init];
	if (self)
	{
		NSSet<NSString *> *changed = nil;

		self->_partName		= [partName lowercaseString];
		self->paths			= pathsIn;
		self->overridden	= [NSMutableDictionary dictionary];
		self->overrideFiles	= [NSMutableDictionary dictionary];
		self->libraryFiles	= [NSMutableDictionary dictionary];
		self->overrideLeads	= [NSMutableDictionary dictionary];
		self->libraryLeads	= [NSMutableDictionary dictionary];

		[self leadsToOverride:self->_partName usingOverrides:YES];
		[self leadsToOverride:self->_partName usingOverrides:NO];

		// Every part either side reached was checked.
		changed = [self->overridden keysOfEntriesPassingTest:^BOOL(NSString *name, NSNumber *isOverridden, BOOL *stop) {
			return [isOverridden boolValue];
		}];

		self->_changedPartNames	= [[changed allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
		self->_overridePath		= [pathsIn pathForPartName:self->_partName usingOverrides:YES];
		self->_libraryPath		= [pathsIn pathForPartName:self->_partName usingOverrides:NO];
	}
	return self;
}


#pragma mark -
#pragma mark READING
#pragma mark -

//========== isOverridden: =====================================================
///
/// @abstract	Whether the overrides folder has its own file for the part.
///
//==============================================================================
- (BOOL) isOverridden:(NSString *)name
{
	NSNumber *known = self->overridden[name];

	if (known == nil)
	{
		NSString *withOverrides	= [self->paths pathForPartName:name usingOverrides:YES];
		NSString *withLibrary	= [self->paths pathForPartName:name usingOverrides:NO];

		known = @(withOverrides != nil && [withOverrides isEqualToString:withLibrary] == NO);
		self->overridden[name] = known;
	}
	return [known boolValue];

}//end isOverridden:


//========== fileNamed:usingOverrides: =========================================
//==============================================================================
- (LDrawComparedFile *) fileNamed:(NSString *)name usingOverrides:(BOOL)useOverrides
{
	NSMutableDictionary	*files	= useOverrides ? self->overrideFiles : self->libraryFiles;
	id					 file	= files[name];

	if (file == nil)
	{
		file = [LDrawComparedFile fileAtPath:[self->paths pathForPartName:name usingOverrides:useOverrides]]
			   ?: [NSNull null];
		files[name] = file;
	}
	return (file == [NSNull null]) ? nil : file;

}//end fileNamed:usingOverrides:


//========== leadsToOverride:usingOverrides: ===================================
///
/// @abstract	Whether the part is overridden, or uses one that is, however
/// 			deep, on this side. Every part it reaches is recorded.
///
//==============================================================================
- (BOOL) leadsToOverride:(NSString *)name usingOverrides:(BOOL)useOverrides
{
	NSMutableDictionary	*leads	= useOverrides ? self->overrideLeads : self->libraryLeads;
	NSNumber			*known	= leads[name];
	BOOL				 result	= NO;

	if (known != nil)
		return [known boolValue];

	// Set first, so a file that uses itself ends.
	leads[name]	= @NO;
	result		= [self isOverridden:name];

	for (NSString *used in [[self fileNamed:name usingOverrides:useOverrides] usedNames])
	{
		if ([self leadsToOverride:used usingOverrides:useOverrides])
			result = YES;
	}

	leads[name] = @(result);
	return result;

}//end leadsToOverride:usingOverrides:


#pragma mark -
#pragma mark BUILDING
#pragma mark -

//========== linesUsingOverrides: ==============================================
///
/// @abstract	The part first, then each part on the way to an override. A part
/// 			this side does not have is an empty model, so the library
/// 			cannot fill it in from the other side.
///
//==============================================================================
- (NSArray<NSString *> *) linesUsingOverrides:(BOOL)useOverrides
{
	NSDictionary<NSString *, NSNumber *>	*leads	= useOverrides ? self->overrideLeads : self->libraryLeads;
	NSMutableArray<NSString *>				*names	= [NSMutableArray arrayWithObject:self.partName];
	NSMutableArray<NSString *>				*lines	= [NSMutableArray array];

	for (NSString *name in [[leads allKeys] sortedArrayUsingSelector:@selector(compare:)])
	{
		if ([leads[name] boolValue] && [name isEqualToString:self.partName] == NO)
			[names addObject:name];
	}

	for (NSString *name in names)
	{
		LDrawComparedFile	*file	= [self fileNamed:name usingOverrides:useOverrides];
		NSString			*prefix	= [name stringByAppendingString:InnerModelSeparator];
		NSUInteger			 index	= 0;

		[lines addObject:[@"0 FILE " stringByAppendingString:name]];
		if (file == nil)
		{
			[lines addObject:@"0 ~Missing"];
			continue;
		}

		for (index = 0; index < [file.models count]; index++)
		{
			if (index > 0)
				[lines addObject:[NSString stringWithFormat:@"0 FILE %@%@", prefix, file.innerNames[index - 1]]];

			for (NSString *line in file.models[index])
			{
				NSArray<NSString *>	*fields	= Fields(line);
				NSString			*used	= UsedName(fields);

				if (used != nil && [file.innerNames containsObject:used])
				{
					NSString *start = [[fields subarrayWithRange:NSMakeRange(0, 14)] componentsJoinedByString:@" "];

					[lines addObject:[NSString stringWithFormat:@"%@ %@%@", start, prefix, used]];
				}
				else
					[lines addObject:line];
			}
		}
	}

	return lines;

}//end linesUsingOverrides:


//========== fileUsingOverrides: ===============================================
//==============================================================================
- (LDrawFile *) fileUsingOverrides:(BOOL)useOverrides
{
	NSString *text = [[self linesUsingOverrides:useOverrides] componentsJoinedByString:@"\r\n"];

	return [LDrawFile parseFromFileContents:text] ?: [LDrawFile file];

}//end fileUsingOverrides:

@end
