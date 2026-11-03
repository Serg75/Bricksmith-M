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

#import <LDrawInventory/LDrawInventoryItem.h>
#import <LDrawInventory/LDrawInventoryJSON.h>

static NSString * const IdentityPartLinksKey	= @"partLinks";
static NSString * const IdentityColorLinksKey	= @"colorLinks";
static NSString * const IdentityRelationsKey	= @"relations";
static NSString * const IdentityKnownPartsKey	= @"knownPartNumbers";
static NSString * const IdentityRubberPartsKey	= @"rubberPartNumbers";

static NSString * const RebrickableKeywordPrefix = @"rebrickable ";

/// A loop in moved parts or prints must not hang a lookup.
static const NSUInteger MaximumChainLength = 8;


//========== TrimmedLowercase ==================================================
//==============================================================================
static NSString *TrimmedLowercase(NSString *partName)
{
	NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	return [[partName stringByTrimmingCharactersInSet:whitespace] lowercaseString];
}


//========== NumberOrder =======================================================
///
/// @abstract	Part numbers in counting order, so "2555" comes before "12825".
///
//==============================================================================
static NSComparator const NumberOrder = ^NSComparisonResult(NSString *first, NSString *second)
{
	return [first compare:second options:NSNumericSearch];
};


@implementation LDrawPartIdentity
{
	NSDictionary<NSString *, NSString *>			*partLinks;			// normalized LDraw name → Rebrickable number
	NSDictionary<NSString *, NSString *>			*handLinks;			// the user's matches, also in partLinks
	NSSet<NSString *>								*libraryParts;		// normalized names in the catalog
	NSDictionary<NSString *, NSArray<NSString *> *>	*reverseLinks;		// Rebrickable number → LDraw names
	NSDictionary<NSString *, NSString *>			*movedParts;		// normalized LDraw name → normalized target
	NSDictionary<NSNumber *, NSArray<NSNumber *> *>	*colorLinks;		// Rebrickable color → LDraw codes
	NSDictionary<NSNumber *, NSArray<NSNumber *> *>	*reverseColors;		// LDraw code → Rebrickable colors
	NSDictionary<NSString *, NSString *>			*printParents;		// print or pattern → its plain part
	NSDictionary<NSString *, NSArray<NSString *> *>	*printChildren;		// part → its prints, in number order
	NSDictionary<NSString *, NSString *>			*moldRoots;			// part → the key of its mold group
	NSDictionary<NSString *, NSArray<NSString *> *>	*moldGroups;		// part → its mold group, in number order
	NSSet<NSString *>								*knownPartNumbers;	// nil when not known
	NSSet<NSString *>								*rubberPartNumbers;	// nil when not known
	NSSet<NSNumber *>								*rubberColorCodes;
}


// MARK: - INITIALIZATION -


//========== initWithPartLinks:... =============================================
///
/// @abstract	Designated initializer. Works out the reverse maps and the
/// 			pools once, so lookups are dictionary hits.
///
//==============================================================================
- (instancetype) initWithPartLinks:(NSDictionary<NSString *, NSString *> *)links
						 handLinks:(NSDictionary<NSString *, NSString *> *)hand
				  libraryPartNames:(NSSet<NSString *> *)library
						movedParts:(NSDictionary<NSString *, NSString *> *)moved
						colorLinks:(NSDictionary<NSNumber *, NSArray<NSNumber *> *> *)colors
						 relations:(NSArray<NSArray<NSString *> *> *)relations
				  knownPartNumbers:(NSSet<NSString *> *)known
				 rubberPartNumbers:(NSSet<NSString *> *)rubberParts
				  rubberColorCodes:(NSSet<NSNumber *> *)rubberColors
{
	self = [super init];
	if (self) {
		self->partLinks			= [links copy];
		self->handLinks			= [hand copy];
		self->libraryParts		= [library copy];
		self->movedParts		= [moved copy];
		self->colorLinks		= LDrawJSONColorLinks(colors);
		self->knownPartNumbers	= [known copy];
		self->rubberPartNumbers	= [rubberParts copy];
		self->rubberColorCodes	= [rubberColors copy] ?: [NSSet set];

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
//------------------------------------------------------------------------------
+ (instancetype) identityWithCatalogRecords:(NSArray<NSDictionary *> *)catalogRecords
							rebrickableData:(NSDictionary *)rebrickableData
								  overrides:(NSDictionary<NSString *, NSString *> *)overrides
{
	return [self identityWithCatalogRecords:catalogRecords
							rebrickableData:rebrickableData
								  overrides:overrides
						   rubberColorCodes:nil];
}


//---------- identityWithCatalogRecords:...rubberColorCodes: ---------[static]--
///
/// @abstract	Merges what is known about parts, weakest first, so a later
/// 			source wins over an earlier one.
///
//------------------------------------------------------------------------------
+ (instancetype) identityWithCatalogRecords:(NSArray<NSDictionary *> *)catalogRecords
							rebrickableData:(NSDictionary *)rebrickableData
								  overrides:(NSDictionary<NSString *, NSString *> *)overrides
						   rubberColorCodes:(NSSet<NSNumber *> *)rubberColorCodes
{
	NSDictionary		*data	= LDrawJSONDictionary(rebrickableData);
	NSSet				*known	= [self partNumbersForKey:IdentityKnownPartsKey inRebrickableData:data];
	NSMutableDictionary	*links	= [NSMutableDictionary dictionary];
	NSMutableDictionary	*hand	= [NSMutableDictionary dictionary];
	NSMutableSet		*parts	= [NSMutableSet set];
	NSDictionary		*moved	= @{};

	// Rebrickable's own links, then the library's keywords and renamed parts,
	// then the user's own matches.
	[self addLinks:LDrawJSONDictionary(data[IdentityPartLinksKey]) to:links];
	if (catalogRecords != nil)
	{
		[links addEntriesFromDictionary:[self keywordLinksFromCatalogRecords:catalogRecords]];
		for (NSDictionary *record in catalogRecords)
		{
			NSString *name = [self normalizedPartName:LDrawJSONString(record[PART_NUMBER_KEY])];
			if (name != nil)
				[parts addObject:name];
		}
		moved = [self movedPartsFromCatalogRecords:catalogRecords];
		[self addRenamedParts:moved knownPartNumbers:known to:links];
	}
	[self addLinks:overrides to:links];
	[self addLinks:overrides to:hand];

	return [[self alloc] initWithPartLinks:links
								 handLinks:hand
						  libraryPartNames:parts
								movedParts:moved
								colorLinks:[self colorLinksInRebrickableData:data]
								 relations:[self relationsInRebrickableData:data]
						  knownPartNumbers:known
						 rubberPartNumbers:[self rubberPartNumbersInRebrickableData:data]
						  rubberColorCodes:rubberColorCodes];

}//end identityWithCatalogRecords:...rubberColorCodes:


// MARK: - REBRICKABLE DATA -


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
							  rubberPartNumbers:(NSSet<NSString *> *)rubberPartNumbers
{
	NSMutableDictionary *data = [NSMutableDictionary dictionary];

	data[@"version"]				= @(LDrawInventoryFileVersion);
	data[IdentityPartLinksKey]		= partLinks ?: @{};
	data[IdentityColorLinksKey]		= LDrawJSONColorLinksObject(LDrawJSONColorLinks(colorLinks));
	data[IdentityRelationsKey]		= relations ?: @[];
	if (knownPartNumbers != nil)
		data[IdentityKnownPartsKey] = [[knownPartNumbers allObjects] sortedArrayUsingSelector:@selector(compare:)];
	if (rubberPartNumbers != nil)
		data[IdentityRubberPartsKey] = [[rubberPartNumbers allObjects] sortedArrayUsingSelector:@selector(compare:)];

	return data;

}//end rebrickableDataWithPartLinks:...


//---------- rebrickableDataByUpdating:... ---------------------------[static]--
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
						   rubberPartNumbers:(NSSet<NSString *> *)rubberPartNumbers
{
	NSDictionary		*values	= LDrawJSONDictionary(data);
	NSMutableDictionary	*links	= [NSMutableDictionary dictionary];
	NSSet				*known	= nil;
	NSSet				*rubber	= nil;

	[self addLinks:LDrawJSONDictionary(values[IdentityPartLinksKey]) to:links];
	[self addLinks:addedPartLinks to:links];

	known	= knownPartNumbers ?: [self partNumbersForKey:IdentityKnownPartsKey inRebrickableData:values];
	rubber	= rubberPartNumbers ?: [self rubberPartNumbersInRebrickableData:values];

	return [self rebrickableDataWithPartLinks:links
								   colorLinks:colorLinks ?: [self colorLinksInRebrickableData:values]
									relations:relations ?: [self relationsInRebrickableData:values]
							 knownPartNumbers:known
							rubberPartNumbers:rubber];

}//end rebrickableDataByUpdating:...


//---------- colorLinksInRebrickableData: ----------------------------[static]--
//------------------------------------------------------------------------------
+ (NSDictionary<NSNumber *, NSArray<NSNumber *> *> *) colorLinksInRebrickableData:(NSDictionary *)data
{
	return LDrawJSONColorLinks(LDrawJSONDictionary(data)[IdentityColorLinksKey]);
}


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


//---------- rubberPartNumbersInRebrickableData: ---------------------[static]--
//------------------------------------------------------------------------------
+ (NSSet<NSString *> *) rubberPartNumbersInRebrickableData:(NSDictionary *)data
{
	return [self partNumbersForKey:IdentityRubberPartsKey inRebrickableData:data];
}


//---------- partNumbersForKey:inRebrickableData: --------------------[static]--
///
/// @abstract	The part numbers listed under the key, or nil when the data
/// 			has no such list.
///
//------------------------------------------------------------------------------
+ (NSSet<NSString *> *) partNumbersForKey:(NSString *)key inRebrickableData:(NSDictionary *)data
{
	NSArray			*listed		= LDrawJSONArray(LDrawJSONDictionary(data)[key]);
	NSMutableSet	*numbers	= nil;

	if (listed != nil)
	{
		numbers = [NSMutableSet setWithCapacity:[listed count]];
		for (id partNumber in listed)
		{
			if (LDrawJSONString(partNumber) != nil)
				[numbers addObject:partNumber];
		}
	}
	return numbers;

}//end partNumbersForKey:inRebrickableData:


// MARK: - PART NAMES -


//---------- normalizedPartName: -------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *) normalizedPartName:(NSString *)partName
{
	NSString *name = TrimmedLowercase(partName);

	name = [name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
	if ([name hasSuffix:@".dat"])
		name = [name substringToIndex:[name length] - 4];

	return ([name length] > 0) ? name : nil;

}//end normalizedPartName:


//---------- libraryPartName: ----------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *) libraryPartName:(NSString *)partName
{
	NSString *name = TrimmedLowercase(partName);

	if ([name length] == 0)
		return nil;
	name = [name stringByReplacingOccurrencesOfString:@"/" withString:@"\\"];
	if ([[name pathExtension] length] == 0)
		name = [name stringByAppendingPathExtension:@"dat"];
	return name;

}//end libraryPartName:


// MARK: - CATALOG -


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
	NSMutableDictionary	*links	= [NSMutableDictionary dictionary];
	NSCharacterSet		*spaces	= [NSCharacterSet whitespaceCharacterSet];
	NSUInteger			 skip	= [RebrickableKeywordPrefix length];

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
				NSString *partNumber = [[text substringFromIndex:skip] stringByTrimmingCharactersInSet:spaces];
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
			NSString *rest		= [description substringFromIndex:[LDRAW_MOVED_DESCRIPTION_PREFIX length]];
			NSString *target	= [self normalizedPartName:rest];

			if (target != nil && [target isEqualToString:partName] == NO)
				moved[partName] = target;
		}
	}
	return moved;

}//end movedPartsFromCatalogRecords:


//---------- addRenamedParts:knownPartNumbers:to: --------------------[static]--
///
/// @abstract	A part the library renamed takes the old name's number while
/// 			Rebrickable has only that one. Links already made win.
///
//------------------------------------------------------------------------------
+ (void) addRenamedParts:(NSDictionary<NSString *, NSString *> *)moved
		knownPartNumbers:(NSSet<NSString *> *)known
					  to:(NSMutableDictionary<NSString *, NSString *> *)links
{
	NSArray	*oldNames	= [[moved allKeys] sortedArrayUsingSelector:@selector(compare:)];
	BOOL	 didLink	= YES;

	if (known == nil)
		return;

	// A chain of moves passes the number one step per pass.
	for (NSUInteger pass = 0; didLink && pass < MaximumChainLength; pass++)
	{
		didLink = NO;
		for (NSString *oldName in oldNames)
		{
			NSString *newName	= moved[oldName];
			NSString *number	= links[oldName] ?: oldName;

			if (links[newName] == nil && [known containsObject:newName] == NO && [known containsObject:number])
			{
				links[newName]	= number;
				didLink			= YES;
			}
		}
	}

}//end addRenamedParts:knownPartNumbers:to:


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

	// A hand match wins, even on a name the library moved.
	for (NSUInteger step = 0; name != nil && self->movedParts[name] != nil && step < MaximumChainLength; step++)
	{
		if (self->handLinks[name] != nil)
			break;
		name = self->movedParts[name];
	}

	if (name == nil)
		return nil;

	number = self->partLinks[name] ?: name;
	if (self->knownPartNumbers != nil && [self->knownPartNumbers containsObject:number] == NO)
		return nil;

	return number;

}//end rebrickablePartNumberForPartName:


//========== partNameForRebrickablePartNumber: =================================
//==============================================================================
- (NSString *) partNameForRebrickablePartNumber:(NSString *)partNumber
{
	NSString *same = [partNumber lowercaseString];
	NSString *file = [same stringByAppendingString:@".dat"];

	// The library's part of the same number wins over parts that link to it,
	// such as a stickered version, unless it moved or links elsewhere.
	if (	[self->libraryParts containsObject:same]
		&&	self->movedParts[same] == nil
		&&	[self samePartLinksElsewhere:partNumber] == NO )
		return file;

	return [self->reverseLinks[partNumber] firstObject] ?: file;

}//end partNameForRebrickablePartNumber:


//========== partNamesForRebrickablePartNumber: ================================
//==============================================================================
- (NSArray<NSString *> *) partNamesForRebrickablePartNumber:(NSString *)partNumber
{
	NSArray		*linked	= self->reverseLinks[partNumber] ?: @[];
	NSString	*file	= [[partNumber lowercaseString] stringByAppendingString:@".dat"];
	NSString	*first	= [self partNameForRebrickablePartNumber:partNumber];

	if ([self samePartLinksElsewhere:partNumber] == NO && [linked containsObject:file] == NO)
		linked = [linked arrayByAddingObject:file];

	// The one -partNameForRebrickablePartNumber: gives comes first.
	if ([linked containsObject:first] && [linked[0] isEqualToString:first] == NO)
	{
		NSMutableArray *ordered = [linked mutableCopy];

		[ordered removeObject:first];
		[ordered insertObject:first atIndex:0];
		linked = ordered;
	}
	return linked;

}//end partNamesForRebrickablePartNumber:


//========== rebrickableColorIDsForColorCode: ==================================
//==============================================================================
- (NSArray<NSNumber *> *) rebrickableColorIDsForColorCode:(LDrawColorT)colorCode
{
	return self->reverseColors[@(colorCode)] ?: @[];
}


//========== rebrickableColorIDForColorCode: ===================================
//==============================================================================
- (NSInteger) rebrickableColorIDForColorCode:(LDrawColorT)colorCode
{
	NSNumber *colorID = [self->reverseColors[@(colorCode)] firstObject];
	return (colorID != nil) ? [colorID integerValue] : LDrawRebrickableColorNone;
}


//========== colorCodeForRebrickableColorID: ===================================
//==============================================================================
- (LDrawColorT) colorCodeForRebrickableColorID:(NSInteger)colorID
{
	NSNumber *code = [self->colorLinks[@(colorID)] firstObject];
	return (code != nil) ? (LDrawColorT)[code intValue] : LDrawColorBogus;
}


//========== colorCodesForRebrickableColorID:ofPartNumber: =====================
///
/// @abstract	The linked LDraw colors, less the rubber ones after the first
/// 			when the part is known not to be rubber.
///
//==============================================================================
- (NSArray<NSNumber *> *) colorCodesForRebrickableColorID:(NSInteger)colorID
											 ofPartNumber:(NSString *)partNumber
{
	NSArray<NSNumber *>	*linked		= self->colorLinks[@(colorID)] ?: @[];
	NSMutableArray		*codes		= nil;
	BOOL				 isRubber	= (	self->rubberPartNumbers == nil
									||	(partNumber != nil && [self->rubberPartNumbers containsObject:partNumber]) );

	if (isRubber || [linked count] < 2 || [self->rubberColorCodes count] == 0)
		return linked;

	codes = [NSMutableArray arrayWithObject:linked[0]];
	for (NSUInteger index = 1; index < [linked count]; index++)
	{
		if ([self->rubberColorCodes containsObject:linked[index]] == NO)
			[codes addObject:linked[index]];
	}
	return codes;

}//end colorCodesForRebrickableColorID:ofPartNumber:


//========== colorCode:suitsPartNamed: =========================================
///
/// @abstract	Looks the part up only for a rubber color, since every other
/// 			color suits any part.
///
//==============================================================================
- (BOOL) colorCode:(LDrawColorT)colorCode suitsPartNamed:(NSString *)partName
{
	NSNumber *code			= @(colorCode);
	NSString *partNumber	= nil;

	if (self->rubberPartNumbers == nil || [self->rubberColorCodes containsObject:code] == NO)
		return YES;

	partNumber = [self rebrickablePartNumberForPartName:partName];
	for (NSNumber *colorID in self->reverseColors[code])
	{
		if ([[self colorCodesForRebrickableColorID:[colorID integerValue] ofPartNumber:partNumber] containsObject:code])
			return YES;
	}
	return NO;

}//end colorCode:suitsPartNamed:


//========== poolKeyForRebrickablePartNumber:... ===============================
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


//========== moldVariantsOfRebrickablePartNumber: ==============================
//==============================================================================
- (NSArray<NSString *> *) moldVariantsOfRebrickablePartNumber:(NSString *)partNumber
{
	NSMutableArray *variants = [self->moldGroups[partNumber] mutableCopy] ?: [NSMutableArray array];

	[variants removeObject:partNumber];
	return variants;
}


//========== plainPartNumberOfRebrickablePartNumber: ===========================
//==============================================================================
- (NSString *) plainPartNumberOfRebrickablePartNumber:(NSString *)partNumber
{
	NSString *plain = self->printParents[partNumber];

	for (NSUInteger step = 0; plain != nil && self->printParents[plain] != nil && step < MaximumChainLength; step++)
		plain = self->printParents[plain];

	return plain;
}


//========== printPartNumbersOfRebrickablePartNumber: ==========================
//==============================================================================
- (NSArray<NSString *> *) printPartNumbersOfRebrickablePartNumber:(NSString *)partNumber
{
	return self->printChildren[partNumber] ?: @[];
}


// MARK: - UTILITIES -


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


//========== samePartLinksElsewhere: ===========================================
///
/// @abstract	Whether the LDraw part named like the Rebrickable number links
/// 			to another Rebrickable number.
///
//==============================================================================
- (BOOL) samePartLinksElsewhere:(NSString *)partNumber
{
	NSString *link = self->partLinks[[partNumber lowercaseString]];
	return link != nil && [link isEqualToString:partNumber] == NO;
}


//========== buildReverseLinks =================================================
///
/// @abstract	Rebrickable number → the LDraw names linked to it, the chosen
/// 			one first: the one with the same number, else the first in sort
/// 			order, so the choice does not change from run to run.
///
//==============================================================================
- (void) buildReverseLinks
{
	NSMutableDictionary *reverse = [NSMutableDictionary dictionary];

	for (NSString *name in [[self->partLinks allKeys] sortedArrayUsingSelector:@selector(compare:)])
	{
		NSString		*number	= self->partLinks[name];
		NSString		*file	= [name stringByAppendingString:@".dat"];
		NSMutableArray	*linked	= reverse[number];

		if (linked == nil)
		{
			linked = [NSMutableArray array];
			reverse[number] = linked;
		}

		if ([name isEqualToString:[number lowercaseString]])
			[linked insertObject:file atIndex:0];
		else
			[linked addObject:file];
	}
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
/// @abstract	Prints and patterns point at their plain part, and each part
/// 			lists the prints made on it. Molds and alternates join one
/// 			group, keyed by the first part number in sort order.
///
//==============================================================================
- (void) buildPoolsFromRelations:(NSArray<NSArray<NSString *> *> *)relations
{
	NSMutableDictionary	*parents	= [NSMutableDictionary dictionary];
	NSMutableDictionary	*children	= [NSMutableDictionary dictionary];	// part → its prints, a mutable set
	NSMutableDictionary	*groupOf	= [NSMutableDictionary dictionary];	// part → its group, a mutable set
	NSMutableDictionary	*roots		= [NSMutableDictionary dictionary];
	NSMutableDictionary	*groups		= [NSMutableDictionary dictionary];
	NSHashTable			*sorted		= [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];

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
			NSMutableSet *group	= groupOf[child] ?: groupOf[parent] ?: [NSMutableSet set];
			NSMutableSet *other	= groupOf[parent];

			// Joining two groups moves every member of one into the other.
			if (other != nil && other != group)
			{
				[group unionSet:other];
				for (NSString *member in other)
					groupOf[member] = group;
			}
			[group addObject:child];
			[group addObject:parent];
			groupOf[child]	= group;
			groupOf[parent]	= group;
		}
	}

	// Each group is sorted once, and its members share the result.
	for (NSSet *group in [groupOf objectEnumerator])
	{
		NSArray		*members	= [group allObjects];
		NSString	*root		= nil;
		NSArray		*inOrder	= nil;

		if ([sorted containsObject:group])
			continue;
		[sorted addObject:group];

		root	= [members sortedArrayUsingSelector:@selector(compare:)][0];
		inOrder	= [members sortedArrayUsingComparator:NumberOrder];
		for (NSString *part in members)
		{
			roots[part]		= root;
			groups[part]	= inOrder;
		}
	}

	// A print of a print is listed with every part it is made on, down to the
	// plain part.
	for (NSString *print in parents)
	{
		NSString	*plain	= parents[print];
		NSUInteger	 steps	= 0;

		while (plain != nil && [plain isEqualToString:print] == NO && steps++ < MaximumChainLength)
		{
			NSMutableSet *prints = children[plain];

			if (prints == nil)
			{
				prints = [NSMutableSet set];
				children[plain] = prints;
			}
			[prints addObject:print];
			plain = parents[plain];
		}
	}
	for (NSString *plain in [children allKeys])
		children[plain] = [[children[plain] allObjects] sortedArrayUsingComparator:NumberOrder];

	self->printParents	= parents;
	self->printChildren	= children;
	self->moldRoots		= roots;
	self->moldGroups	= groups;

}//end buildPoolsFromRelations:

@end
