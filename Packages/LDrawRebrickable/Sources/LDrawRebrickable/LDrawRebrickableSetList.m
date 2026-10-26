//==============================================================================
//
//  File:       LDrawRebrickableSetList.m
//  Package:    LDrawRebrickable
//
//  Purpose:    Every set Rebrickable has, read from the downloads, for finding
//              a set by number or name.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawRebrickable/LDrawRebrickableSetList.h>

#import <LDrawInventory/LDrawInventoryJSON.h>
#import <LDrawInventory/LDrawSetInventory.h>
#import <LDrawRebrickable/LDrawRebrickableCSVReader.h>
#import <LDrawRebrickable/LDrawRebrickableDownloads.h>

/// The theme Rebrickable files its lists of loose parts under.
static NSString * const DatabaseSetsThemeName = @"Database Sets";

/// A loop in the themes' parents must not hang the reading.
static const NSUInteger MaximumThemeDepth = 16;


@interface LDrawRebrickableSet ()

@property (nonatomic, readwrite, copy) NSString *setNumber;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite) NSInteger year;
@property (nonatomic, readwrite, copy, nullable) NSString *themeName;
@property (nonatomic, readwrite) NSUInteger partCount;
@property (nonatomic, readwrite, copy, nullable) NSString *imageURL;
@property (nonatomic, readwrite) BOOL isDatabaseSet;

@end


@implementation LDrawRebrickableSet

//========== description =======================================================
//==============================================================================
- (NSString *) description
{
	return [NSString stringWithFormat:@"<%@ %@ \"%@\" %ld>", [self class], self.setNumber, self.name, (long)self.year];
}

@end


@interface LDrawRebrickableSetList ()

- (instancetype) initWithSets:(NSDictionary<NSString *, LDrawRebrickableSet *> *)sets;

@end


@implementation LDrawRebrickableSetList
{
	NSDictionary<NSString *, LDrawRebrickableSet *>	*setsByNumber;
	NSArray<LDrawRebrickableSet *>					*newestFirst;
}


// MARK: - INITIALIZATION -


//========== initWithSets: =====================================================
//==============================================================================
- (instancetype) initWithSets:(NSDictionary<NSString *, LDrawRebrickableSet *> *)sets
{
	self = [super init];
	if (self) {
		NSSortDescriptor *byYear	= [NSSortDescriptor sortDescriptorWithKey:@"year" ascending:NO];
		NSSortDescriptor *byNumber	= [NSSortDescriptor sortDescriptorWithKey:@"setNumber" ascending:YES
																	 selector:@selector(localizedStandardCompare:)];
		NSMutableSet *database = [NSMutableSet set];

		for (LDrawRebrickableSet *set in [sets allValues])
		{
			if (set.isDatabaseSet)
				[database addObject:set.setNumber];
		}

		self->setsByNumber			= [sets copy];
		self->newestFirst			= [[sets allValues] sortedArrayUsingDescriptors:@[byYear, byNumber]];
		self->_databaseSetNumbers	= database;
	}
	return self;

}//end initWithSets:


//---------- setListFromDownloads:error: -----------------------------[static]--
///
/// @abstract	Reads the themes, then the sets.
///
//------------------------------------------------------------------------------
+ (instancetype) setListFromDownloads:(LDrawRebrickableDownloads *)downloads error:(NSError **)error
{
	NSMutableDictionary	*themeNames		= [NSMutableDictionary dictionary];	// id → name
	NSMutableDictionary	*themeParents	= [NSMutableDictionary dictionary];	// id → parent id
	NSMutableDictionary	*sets			= [NSMutableDictionary dictionary];
	NSURL				*themesURL		= [downloads localURLForFileNamed:@"themes"];
	NSURL				*setsURL		= [downloads localURLForFileNamed:@"sets"];

	LDrawRebrickableCSVReader	*themes		= [[LDrawRebrickableCSVReader alloc] initWithURL:themesURL error:error];
	NSArray						*themeIndex	= [themes indexesOfColumns:@[@"id", @"name", @"parent_id"] error:error];
	NSUInteger					 themeLast	= [LDrawRebrickableCSVReader lastIndexOfColumns:themeIndex];

	if (themeIndex == nil)
		return nil;

	if ([themes enumerateRowsUsingBlock:^(NSArray<NSString *> *fields, BOOL *stop) {
			if ([fields count] <= themeLast)
				return;

			NSString *theme		= fields[[themeIndex[0] unsignedIntegerValue]];
			NSString *parent	= fields[[themeIndex[2] unsignedIntegerValue]];

			themeNames[theme] = fields[[themeIndex[1] unsignedIntegerValue]];
			if ([parent length] > 0)
				themeParents[theme] = parent;
		} error:error] == NO)
		return nil;

	LDrawRebrickableCSVReader	*reader		= [[LDrawRebrickableCSVReader alloc] initWithURL:setsURL error:error];
	NSArray						*setIndex	= [reader indexesOfColumns:@[@"set_num", @"name", @"year", @"theme_id",
																		 @"num_parts"]
																error:error];
	NSUInteger					 setLast	= [LDrawRebrickableCSVReader lastIndexOfColumns:setIndex];
	NSUInteger					 imageColumn	= [reader indexOfColumn:@"img_url"];

	if (setIndex == nil)
		return nil;

	if ([reader enumerateRowsUsingBlock:^(NSArray<NSString *> *fields, BOOL *stop) {
			if ([fields count] <= setLast)
				return;

			NSString			*theme	= fields[[setIndex[3] unsignedIntegerValue]];
			NSInteger			 parts	= LDrawJSONInteger(fields[[setIndex[4] unsignedIntegerValue]], 0);
			LDrawRebrickableSet	*set	= [[LDrawRebrickableSet alloc] init];

			set.setNumber		= [LDrawSetInventory normalizedSetNumber:fields[[setIndex[0] unsignedIntegerValue]]];
			set.name			= fields[[setIndex[1] unsignedIntegerValue]];
			set.year			= LDrawJSONInteger(fields[[setIndex[2] unsignedIntegerValue]], 0);
			set.themeName		= themeNames[theme];
			set.partCount		= (NSUInteger)MAX(parts, 0);
			set.isDatabaseSet	= [self theme:theme
								  isUnder:DatabaseSetsThemeName
									names:themeNames
								  parents:themeParents];
			if (imageColumn < [fields count] && [fields[imageColumn] length] > 0)
				set.imageURL = fields[imageColumn];

			if (set.setNumber != nil)
				sets[set.setNumber] = set;
		} error:error] == NO)
		return nil;

	return [[self alloc] initWithSets:sets];

}//end setListFromDownloads:error:


//---------- theme:isUnder:names:parents: ----------------------------[static]--
///
/// @abstract	Whether the theme, or a theme above it, has this name.
///
//------------------------------------------------------------------------------
+ (BOOL) theme:(NSString *)theme
	   isUnder:(NSString *)name
		 names:(NSDictionary<NSString *, NSString *> *)names
	   parents:(NSDictionary<NSString *, NSString *> *)parents
{
	NSString *current = theme;

	for (NSUInteger depth = 0; current != nil && depth < MaximumThemeDepth; depth++)
	{
		if ([names[current] caseInsensitiveCompare:name] == NSOrderedSame)
			return YES;
		current = parents[current];
	}
	return NO;

}//end theme:isUnder:names:parents:


// MARK: - LOOKUPS -


//========== count =============================================================
//==============================================================================
- (NSUInteger) count
{
	return [self->setsByNumber count];
}


//========== setForNumber: =====================================================
//==============================================================================
- (LDrawRebrickableSet *) setForNumber:(NSString *)setNumber
{
	NSString *number = [LDrawSetInventory normalizedSetNumber:setNumber];
	return (number != nil) ? self->setsByNumber[number] : nil;
}


//========== setsMatching:limit: ===============================================
///
/// @abstract	Sets by number first, then by name.
///
//==============================================================================
- (NSArray<LDrawRebrickableSet *> *) setsMatching:(NSString *)text limit:(NSUInteger)limit
{
	NSString		*query		= [[text stringByTrimmingCharactersInSet:
									[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
	NSArray			*words		= [query componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	NSMutableArray	*byNumber	= [NSMutableArray array];
	NSMutableArray	*byName		= [NSMutableArray array];
	NSStringCompareOptions options = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;

	if ([query length] == 0 || limit == 0)
		return @[];

	words = [words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];

	for (LDrawRebrickableSet *set in self->newestFirst)
	{
		if ([set.setNumber hasPrefix:query])
		{
			[byNumber addObject:set];
			continue;
		}

		BOOL hasEveryWord = YES;
		for (NSString *word in words)
			hasEveryWord = hasEveryWord && [set.name rangeOfString:word options:options].location != NSNotFound;
		if (hasEveryWord)
			[byName addObject:set];
	}

	[byNumber addObjectsFromArray:byName];
	return [byNumber subarrayWithRange:NSMakeRange(0, MIN(limit, [byNumber count]))];

}//end setsMatching:limit:

@end
