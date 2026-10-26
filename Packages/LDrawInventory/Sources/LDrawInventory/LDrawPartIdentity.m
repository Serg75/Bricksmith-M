//==============================================================================
//
//  File:       LDrawPartIdentity.m
//  Package:    LDrawInventory
//
//  Purpose:    Which LEGO part an LDraw part is, which color an LDraw color is,
//              and which parts count as one.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawInventory/LDrawPartIdentity.h>

#import <LDrawCore/LDrawKeywords.h>
#import <LDrawCore/LDrawPartLibrary.h>

#import <LDrawInventory/LDrawInventoryJSON.h>

static NSString * const IdentityPartLinksKey	= @"partLinks";
static NSString * const IdentityColorLinksKey	= @"colorLinks";
static NSString * const IdentityRelationsKey	= @"relations";
static NSString * const IdentityKnownPartsKey	= @"knownPartNumbers";

static NSString * const RebrickableKeywordPrefix = @"rebrickable ";

/// A loop in moved parts or prints must not hang a lookup.
static const NSUInteger MaximumChainLength = 8;


//========== NormalizedColorLinks ==============================================
///
/// @abstract	Color links with every value a list of LDraw codes. A value
/// 			may come as one code or as a list; anything else is dropped.
///
//==============================================================================
static NSDictionary<NSNumber *, NSArray<NSNumber *> *> *NormalizedColorLinks(NSDictionary *links)
{
	NSMutableDictionary *normalized = [NSMutableDictionary dictionary];

	for (id colorID in links)
	{
		id				 value	= links[colorID];
		NSArray			*values	= [value isKindOfClass:[NSArray class]] ? value : @[value];
		NSMutableArray	*codes	= [NSMutableArray array];

		if ([colorID isKindOfClass:[NSNumber class]] == NO)
			continue;

		for (id code in values)
		{
			NSInteger number = LDrawJSONInteger(code, NSNotFound);
			if (number != NSNotFound && [codes containsObject:@(number)] == NO)
				[codes addObject:@(number)];
		}
		if ([codes count] > 0)
			normalized[colorID] = codes;
	}
	return normalized;

}//end NormalizedColorLinks


@interface LDrawPartIdentity ()

- (instancetype) initWithPartLinks:(NSDictionary<NSString *, NSString *> *)partLinks
						movedParts:(NSDictionary<NSString *, NSString *> *)movedParts
						colorLinks:(NSDictionary<NSNumber *, NSArray<NSNumber *> *> *)colorLinks
						 relations:(NSArray<NSArray<NSString *> *> *)relations
				  knownPartNumbers:(NSSet<NSString *> *)knownPartNumbers;

@end


@implementation LDrawPartIdentity
{
	NSDictionary<NSString *, NSString *>			*partLinks;			// normalized LDraw name → Rebrickable number
	NSDictionary<NSString *, NSString *>			*reverseLinks;		// Rebrickable number → LDraw name with ".dat"
	NSDictionary<NSString *, NSString *>			*movedParts;		// normalized LDraw name → normalized target
	NSDictionary<NSNumber *, NSArray<NSNumber *> *>	*colorLinks;		// Rebrickable color → LDraw codes
	NSDictionary<NSNumber *, NSArray<NSNumber *> *>	*reverseColors;		// LDraw code → Rebrickable colors
	NSDictionary<NSString *, NSString *>			*printParents;		// print or pattern → its plain part
	NSDictionary<NSString *, NSString *>			*moldRoots;			// part → the key of its mold group
	NSSet<NSString *>								*knownPartNumbers;	// nil when not known
}


// MARK: - INITIALIZATION -


//========== initWithPartLinks:... =============================================
///
/// @abstract	Designated initializer. Works out the reverse maps and the
/// 			pools once, so lookups are dictionary hits.
///
//==============================================================================
- (instancetype) initWithPartLinks:(NSDictionary<NSString *, NSString *> *)links
						movedParts:(NSDictionary<NSString *, NSString *> *)moved
						colorLinks:(NSDictionary<NSNumber *, NSArray<NSNumber *> *> *)colors
						 relations:(NSArray<NSArray<NSString *> *> *)relations
				  knownPartNumbers:(NSSet<NSString *> *)known
{
	self = [super init];
	if (self) {
		self->partLinks			= [links copy];
		self->movedParts		= [moved copy];
		self->colorLinks		= NormalizedColorLinks(colors);
		self->knownPartNumbers	= [known copy];

		[self buildReverseLinks];
		[self buildReverseColors];
		[self buildPoolsFromRelations:relations];
	}
	return self;

}//end initWithPartLinks:...


//---------- emptyIdentity -------------------------------------------[static]--
//------------------------------------------------------------------------------
+ (instancetype) emptyIdentity
{
	return [self identityWithCatalogRecords:nil rebrickableData:nil overrides:nil];
}


//---------- identityWithCatalogRecords:rebrickableData:overrides: ---[static]--
///
/// @abstract	Merges what is known about parts, weakest first, so a later
/// 			source wins over an earlier one.
///
//------------------------------------------------------------------------------
+ (instancetype) identityWithCatalogRecords:(NSArray<NSDictionary *> *)catalogRecords
							rebrickableData:(NSDictionary *)rebrickableData
								  overrides:(NSDictionary<NSString *, NSString *> *)overrides
{
	NSDictionary		*data	= LDrawJSONDictionary(rebrickableData);
	NSMutableDictionary	*links	= [NSMutableDictionary dictionary];
	NSDictionary		*moved	= @{};

	// Rebrickable's own links, then the library's keywords, then the user's
	// own matches.
	[self addLinks:LDrawJSONDictionary(data[IdentityPartLinksKey]) to:links];
	if (catalogRecords != nil)
	{
		[links addEntriesFromDictionary:[self keywordLinksFromCatalogRecords:catalogRecords]];
		moved = [self movedPartsFromCatalogRecords:catalogRecords];
	}
	[self addLinks:overrides to:links];

	return [[self alloc] initWithPartLinks:links
								movedParts:moved
								colorLinks:[self colorLinksInRebrickableData:data]
								 relations:[self relationsInRebrickableData:data]
						  knownPartNumbers:[self knownPartNumbersInRebrickableData:data]];

}//end identityWithCatalogRecords:rebrickableData:overrides:


//---------- rebrickableDataWithPartLinks:... ------------------------[static]--
///
/// @abstract	What Rebrickable tells about parts and colors, as the store
/// 			keeps it. JSON keys must be strings, so color ids are written
/// 			as strings.
///
//------------------------------------------------------------------------------
+ (NSDictionary *) rebrickableDataWithPartLinks:(NSDictionary<NSString *, NSString *> *)partLinks
									 colorLinks:(NSDictionary<NSNumber *, id> *)colorLinks
									  relations:(NSArray<NSArray<NSString *> *> *)relations
							   knownPartNumbers:(NSSet<NSString *> *)knownPartNumbers
{
	NSMutableDictionary *data	= [NSMutableDictionary dictionary];
	NSMutableDictionary *colors	= [NSMutableDictionary dictionary];

	NSDictionary *normalized = NormalizedColorLinks(colorLinks);
	for (NSNumber *colorID in normalized)
		colors[[colorID stringValue]] = normalized[colorID];

	data[@"version"]				= @(LDrawInventoryFileVersion);
	data[IdentityPartLinksKey]		= partLinks ?: @{};
	data[IdentityColorLinksKey]		= colors;
	data[IdentityRelationsKey]		= relations ?: @[];
	if (knownPartNumbers != nil)
		data[IdentityKnownPartsKey] = [[knownPartNumbers allObjects] sortedArrayUsingSelector:@selector(compare:)];

	return data;

}//end rebrickableDataWithPartLinks:...


//---------- rebrickableDataByUpdating:... --------------------------[static]--
///
/// @abstract	Rebrickable data with some parts replaced. Part links are
/// 			added; anything else given replaces what the data has.
///
//------------------------------------------------------------------------------
+ (NSDictionary *) rebrickableDataByUpdating:(NSDictionary *)data
								   partLinks:(NSDictionary<NSString *, NSString *> *)addedPartLinks
								  colorLinks:(NSDictionary<NSNumber *, id> *)colorLinks
								   relations:(NSArray<NSArray<NSString *> *> *)relations
							knownPartNumbers:(NSSet<NSString *> *)knownPartNumbers
{
	NSDictionary		*values	= LDrawJSONDictionary(data);
	NSMutableDictionary	*links	= [NSMutableDictionary dictionary];

	[self addLinks:LDrawJSONDictionary(values[IdentityPartLinksKey]) to:links];
	[self addLinks:addedPartLinks to:links];

	return [self rebrickableDataWithPartLinks:links
								   colorLinks:colorLinks ?: [self colorLinksInRebrickableData:values]
									relations:relations ?: [self relationsInRebrickableData:values]
							 knownPartNumbers:knownPartNumbers ?: [self knownPartNumbersInRebrickableData:values]];

}//end rebrickableDataByUpdating:...


//---------- colorLinksInRebrickableData: ----------------------------[static]--
///
/// @abstract	Rebrickable color → LDraw codes. The keys are written as
/// 			strings.
///
//------------------------------------------------------------------------------
+ (NSDictionary<NSNumber *, NSArray<NSNumber *> *> *) colorLinksInRebrickableData:(NSDictionary *)data
{
	NSDictionary		*colorData	= LDrawJSONDictionary(LDrawJSONDictionary(data)[IdentityColorLinksKey]);
	NSMutableDictionary	*colors		= [NSMutableDictionary dictionary];

	for (id key in colorData)
	{
		NSInteger colorID = LDrawJSONInteger(key, NSNotFound);
		if (colorID != NSNotFound)
			colors[@(colorID)] = colorData[key];
	}
	return NormalizedColorLinks(colors);

}//end colorLinksInRebrickableData:


//---------- relationsInRebrickableData: -----------------------------[static]--
///
/// @abstract	The rows of relation code, child and parent that read.
///
//------------------------------------------------------------------------------
+ (NSArray<NSArray<NSString *> *> *) relationsInRebrickableData:(NSDictionary *)data
{
	NSMutableArray *relations = [NSMutableArray array];

	for (id row in LDrawJSONArray(LDrawJSONDictionary(data)[IdentityRelationsKey]))
	{
		NSArray *fields = LDrawJSONArray(row);
		if (	[fields count] >= 3
			&&	LDrawJSONString(fields[0]) && LDrawJSONString(fields[1]) && LDrawJSONString(fields[2]) )
		{
			[relations addObject:@[fields[0], fields[1], fields[2]]];
		}
	}
	return relations;

}//end relationsInRebrickableData:


//---------- knownPartNumbersInRebrickableData: ----------------------[static]--
///
/// @abstract	Every part Rebrickable has, or nil when the data does not say.
///
//------------------------------------------------------------------------------
+ (NSSet<NSString *> *) knownPartNumbersInRebrickableData:(NSDictionary *)data
{
	NSArray			*knownData	= LDrawJSONArray(LDrawJSONDictionary(data)[IdentityKnownPartsKey]);
	NSMutableSet	*known		= nil;

	if (knownData != nil)
	{
		known = [NSMutableSet setWithCapacity:[knownData count]];
		for (id partNumber in knownData)
		{
			if (LDrawJSONString(partNumber) != nil)
				[known addObject:partNumber];
		}
	}
	return known;

}//end knownPartNumbersInRebrickableData:


//---------- addLinks:to: --------------------------------------------[static]--
///
/// @abstract	Adds links keyed by LDraw part names, normalizing the names.
///
//------------------------------------------------------------------------------
+ (void) addLinks:(NSDictionary *)source to:(NSMutableDictionary *)links
{
	for (id key in source)
	{
		NSString *partName		= [self normalizedPartName:LDrawJSONString(key)];
		NSString *partNumber	= LDrawJSONString(source[key]);

		if (partName != nil && partNumber != nil)
			links[partName] = partNumber;
	}
}


// MARK: - CATALOG -


//---------- normalizedPartName: -------------------------------------[static]--
///
/// @abstract	An LDraw part name as the map keys it.
///
//------------------------------------------------------------------------------
+ (NSString *) normalizedPartName:(NSString *)partName
{
	NSString *name = [[partName stringByTrimmingCharactersInSet:
					   [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];

	name = [name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
	if ([name hasSuffix:@".dat"])
		name = [name substringToIndex:[name length] - 4];

	return ([name length] > 0) ? name : nil;

}//end normalizedPartName:


//---------- keywordLinksFromCatalogRecords: -------------------------[static]--
///
/// @abstract	The "Rebrickable <number>" keywords of the library's parts.
///
/// @discussion	The LDraw Parts Tracker writes them when Rebrickable numbers a
/// 			part differently, which is most often a print.
///
//------------------------------------------------------------------------------
+ (NSDictionary<NSString *, NSString *> *) keywordLinksFromCatalogRecords:(NSArray<NSDictionary *> *)catalogRecords
{
	NSMutableDictionary *links = [NSMutableDictionary dictionary];

	for (NSDictionary *record in catalogRecords)
	{
		NSString *partName = [self normalizedPartName:LDrawJSONString(record[PART_NUMBER_KEY])];

		if (partName == nil)
			continue;

		for (id keyword in LDrawJSONArray(record[PART_KEYWORDS_KEY]))
		{
			NSString *text = LDrawJSONString(keyword);

			if ([[text lowercaseString] hasPrefix:RebrickableKeywordPrefix])
			{
				NSString *partNumber = [[text substringFromIndex:[RebrickableKeywordPrefix length]]
										stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
				if ([partNumber length] > 0)
					links[partName] = partNumber;
			}
		}
	}
	return links;

}//end keywordLinksFromCatalogRecords:


//---------- movedPartsFromCatalogRecords: ---------------------------[static]--
///
/// @abstract	Where the library's "~Moved to" parts went.
///
//------------------------------------------------------------------------------
+ (NSDictionary<NSString *, NSString *> *) movedPartsFromCatalogRecords:(NSArray<NSDictionary *> *)catalogRecords
{
	NSMutableDictionary *moved = [NSMutableDictionary dictionary];

	for (NSDictionary *record in catalogRecords)
	{
		NSString *partName		= [self normalizedPartName:LDrawJSONString(record[PART_NUMBER_KEY])];
		NSString *description	= LDrawJSONString(record[PART_NAME_KEY]);

		if (partName != nil && [description hasPrefix:LDRAW_MOVED_DESCRIPTION_PREFIX])
		{
			NSString *target = [self normalizedPartName:
								[description substringFromIndex:[LDRAW_MOVED_DESCRIPTION_PREFIX length]]];
			if (target != nil && [target isEqualToString:partName] == NO)
				moved[partName] = target;
		}
	}
	return moved;

}//end movedPartsFromCatalogRecords:


// MARK: - LOOKUPS -


//========== rebrickablePartNumberForPartName: =================================
///
/// @abstract	Rebrickable's number for an LDraw part, following moved parts.
///
//==============================================================================
- (NSString *) rebrickablePartNumberForPartName:(NSString *)partName
{
	NSString *name		= [LDrawPartIdentity normalizedPartName:partName];
	NSString *number	= nil;

	for (NSUInteger step = 0; name != nil && self->movedParts[name] != nil && step < MaximumChainLength; step++)
		name = self->movedParts[name];

	if (name == nil)
		return nil;

	number = self->partLinks[name] ?: name;
	if (self->knownPartNumbers != nil && [self->knownPartNumbers containsObject:number] == NO)
		return nil;

	return number;

}//end rebrickablePartNumberForPartName:


//========== partNameForRebrickablePartNumber: =================================
///
/// @abstract	The LDraw part for a Rebrickable number.
///
//==============================================================================
- (NSString *) partNameForRebrickablePartNumber:(NSString *)partNumber
{
	return self->reverseLinks[partNumber] ?: [[partNumber lowercaseString] stringByAppendingString:@".dat"];
}


//========== rebrickableColorIDsForColorCode: ==================================
//==============================================================================
- (NSArray<NSNumber *> *) rebrickableColorIDsForColorCode:(LDrawColorT)colorCode
{
	return self->reverseColors[@(colorCode)] ?: @[];
}


//========== colorCodeForRebrickableColorID: ===================================
//==============================================================================
- (LDrawColorT) colorCodeForRebrickableColorID:(NSInteger)colorID
{
	NSNumber *code = [self->colorLinks[@(colorID)] firstObject];
	return (code != nil) ? (LDrawColorT)[code intValue] : LDrawColorBogus;
}


//========== poolKeyForRebrickablePartNumber:... ===============================
///
/// @abstract	The part that stands for a whole pool.
///
//==============================================================================
- (NSString *) poolKeyForRebrickablePartNumber:(NSString *)partNumber
						   matchesMoldVariants:(BOOL)matchesMoldVariants
							   matchesAnyPrint:(BOOL)matchesAnyPrint
{
	NSString *key = partNumber;

	if (matchesAnyPrint)
	{
		for (NSUInteger step = 0; self->printParents[key] != nil && step < MaximumChainLength; step++)
			key = self->printParents[key];
	}
	if (matchesMoldVariants)
		key = self->moldRoots[key] ?: key;

	return key;

}//end poolKeyForRebrickablePartNumber:...


// MARK: - UTILITIES -


//========== buildReverseLinks =================================================
///
/// @abstract	Rebrickable number → LDraw name. When several LDraw parts link
/// 			to one number, the one with the same number wins, then the
/// 			first in sort order, so the choice does not change from run to
/// 			run.
///
//==============================================================================
- (void) buildReverseLinks
{
	NSMutableDictionary	*reverse	= [NSMutableDictionary dictionary];
	NSArray				*names		= [[self->partLinks allKeys] sortedArrayUsingSelector:@selector(compare:)];

	for (NSString *name in names)
	{
		NSString *number	= self->partLinks[name];
		NSString *current	= reverse[number];

		if (current == nil || [name isEqualToString:[number lowercaseString]])
			reverse[number] = name;
	}

	for (NSString *number in [reverse allKeys])
		reverse[number] = [reverse[number] stringByAppendingString:@".dat"];

	self->reverseLinks = reverse;

}//end buildReverseLinks


//========== buildReverseColors ================================================
//==============================================================================
- (void) buildReverseColors
{
	NSMutableDictionary *reverse = [NSMutableDictionary dictionary];

	for (NSNumber *colorID in self->colorLinks)
	{
		for (NSNumber *code in self->colorLinks[colorID])
		{
			NSMutableArray *colorIDs = reverse[code];

			if (colorIDs == nil)
			{
				colorIDs = [NSMutableArray array];
				reverse[code] = colorIDs;
			}
			if ([colorIDs containsObject:colorID] == NO)
				[colorIDs addObject:colorID];
		}
	}
	for (NSNumber *code in reverse)
		[reverse[code] sortUsingSelector:@selector(compare:)];

	self->reverseColors = reverse;

}//end buildReverseColors


//========== buildPoolsFromRelations: ==========================================
///
/// @abstract	Prints and patterns point at their plain part. Molds and
/// 			alternates join one group, keyed by the first part number in
/// 			sort order.
///
//==============================================================================
- (void) buildPoolsFromRelations:(NSArray<NSArray<NSString *> *> *)relations
{
	NSMutableDictionary	*parents	= [NSMutableDictionary dictionary];
	NSMutableDictionary	*groupOf	= [NSMutableDictionary dictionary];	// part → its group, a mutable set
	NSMutableDictionary	*roots		= [NSMutableDictionary dictionary];

	for (NSArray<NSString *> *relation in relations)
	{
		NSString *kind		= [relation[0] uppercaseString];
		NSString *child		= relation[1];
		NSString *parent	= relation[2];

		if ([kind isEqualToString:@"P"] || [kind isEqualToString:@"T"])
		{
			parents[child] = parent;
		}
		else if ([kind isEqualToString:@"M"] || [kind isEqualToString:@"A"])
		{
			NSMutableSet *childGroup	= groupOf[child];
			NSMutableSet *parentGroup	= groupOf[parent];

			if (childGroup == nil && parentGroup == nil)
			{
				NSMutableSet *group = [NSMutableSet setWithObjects:child, parent, nil];
				groupOf[child]	= group;
				groupOf[parent]	= group;
			}
			else if (childGroup == nil || parentGroup == nil)
			{
				NSMutableSet *group = childGroup ?: parentGroup;
				[group addObject:child];
				[group addObject:parent];
				groupOf[child]	= group;
				groupOf[parent]	= group;
			}
			else if (childGroup != parentGroup)
			{
				[childGroup unionSet:parentGroup];
				for (NSString *member in parentGroup)
					groupOf[member] = childGroup;
			}
		}
	}

	for (NSString *part in groupOf)
	{
		NSSet *group = groupOf[part];
		roots[part] = [[group allObjects] sortedArrayUsingSelector:@selector(compare:)][0];
	}

	self->printParents	= parents;
	self->moldRoots		= roots;

}//end buildPoolsFromRelations:

@end
