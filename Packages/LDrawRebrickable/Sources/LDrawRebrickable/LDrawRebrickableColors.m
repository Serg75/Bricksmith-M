//==============================================================================
//
//  File:       LDrawRebrickableColors.m
//  Package:    LDrawRebrickable
//
//  Purpose:    Which LDraw colors Rebrickable's colors are.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawRebrickable/LDrawRebrickableColors.h>

#import <LDrawInventory/LDrawInventoryJSON.h>
#import <LDrawRebrickable/LDrawRebrickableClient.h>

static NSString * const TableResourceName	= @"rebrickable-colors";
static NSString * const FetchedFileName		= @"colors-api.json";
static NSString * const TableColorsKey		= @"colors";
static NSString * const TableSourceKey		= @"source";


@implementation LDrawRebrickableColors


// MARK: - THE SHIPPED TABLE -


//---------- resourceBundle ------------------------------------------[static]--
///
/// @abstract	The bundle the table is in: the package's resource bundle, or
/// 			the one Xcode nests beside the class for a local package.
///
//------------------------------------------------------------------------------
+ (NSBundle *) resourceBundle
{
#ifdef SWIFTPM_MODULE_BUNDLE
	return SWIFTPM_MODULE_BUNDLE;
#else
	NSBundle	*classBundle	= [NSBundle bundleForClass:[LDrawRebrickableColors class]];
	NSURL		*nestedURL		= [classBundle URLForResource:@"BricksmithM_LDrawRebrickable" withExtension:@"bundle"];
	NSBundle	*nested			= (nestedURL != nil) ? [NSBundle bundleWithURL:nestedURL] : nil;

	return nested ?: classBundle;
#endif
}


//---------- builtInTable --------------------------------------------[static]--
///
/// @abstract	The shipped table's file, read once.
///
//------------------------------------------------------------------------------
+ (NSDictionary *) builtInTable
{
	static NSDictionary		*table	= nil;
	static dispatch_once_t	 once	= 0;

	dispatch_once(&once, ^{
		NSURL *url = [[self resourceBundle] URLForResource:TableResourceName withExtension:@"json"];
		table = (url != nil) ? LDrawJSONReadFile(url) : nil;
	});
	return table;
}


//---------- builtInColorLinks ---------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSDictionary<NSNumber *, NSArray<NSNumber *> *> *) builtInColorLinks
{
	return [self colorLinksInTable:[self builtInTable]];
}


//---------- builtInTableSource --------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *) builtInTableSource
{
	return LDrawJSONString([self builtInTable][TableSourceKey]);
}


// MARK: - FROM THE API -


//---------- colorLinksFromAPIResults: -------------------------------[static]--
///
/// @abstract	Each color's LDraw ids, from `external_ids.LDraw.ext_ids`.
///
//------------------------------------------------------------------------------
+ (NSDictionary<NSNumber *, NSArray<NSNumber *> *> *) colorLinksFromAPIResults:(NSArray<NSDictionary *> *)results
{
	NSMutableDictionary *links = [NSMutableDictionary dictionary];

	for (NSDictionary *color in results)
	{
		NSInteger		 colorID	= LDrawJSONInteger(LDrawJSONDictionary(color)[@"id"], NSNotFound);
		NSDictionary	*external	= LDrawJSONDictionary(LDrawJSONDictionary(color)[@"external_ids"]);
		NSArray			*ids		= LDrawJSONArray(LDrawJSONDictionary(external[@"LDraw"])[@"ext_ids"]);
		NSMutableArray	*codes		= [NSMutableArray array];

		if (colorID == NSNotFound || colorID < 0)
			continue;

		for (id code in ids)
		{
			NSInteger number = LDrawJSONInteger(code, NSNotFound);
			if (number != NSNotFound)
				[codes addObject:@(number)];
		}
		if ([codes count] > 0)
			links[@(colorID)] = codes;
	}
	return links;

}//end colorLinksFromAPIResults:


//---------- fetchColorLinksWithClient:completion: -------------------[static]--
//------------------------------------------------------------------------------
+ (void) fetchColorLinksWithClient:(LDrawRebrickableClient *)client
						completion:(void (^)(NSDictionary<NSNumber *, NSArray<NSNumber *> *> *links,
											 NSError *error))completion
{
	[client fetchAllResultsAtPath:@"lego/colors/" parameters:nil completion:^(NSArray<NSDictionary *> *results,
																			  NSError *error) {
		completion((results != nil) ? [self colorLinksFromAPIResults:results] : nil, error);
	}];
}


// MARK: - KEPT IN THE FOLDER -


//---------- fetchedColorLinksInFolder: ------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSDictionary<NSNumber *, NSArray<NSNumber *> *> *) fetchedColorLinksInFolder:(NSURL *)folderURL
{
	NSDictionary *file = LDrawJSONReadFile([folderURL URLByAppendingPathComponent:FetchedFileName]);

	if (file == nil)
		return nil;
	return [self colorLinksInTable:file];
}


//---------- saveFetchedColorLinks:inFolder:error: -------------------[static]--
///
/// @abstract	Writes the links in the same form as the shipped table.
///
//------------------------------------------------------------------------------
+ (BOOL) saveFetchedColorLinks:(NSDictionary<NSNumber *, NSArray<NSNumber *> *> *)links
					  inFolder:(NSURL *)folderURL
						 error:(NSError **)error
{
	NSMutableDictionary *colors = [NSMutableDictionary dictionary];

	for (NSNumber *colorID in links)
		colors[[colorID stringValue]] = links[colorID];

	NSDictionary *file = @{
		@"version"		: @(LDrawInventoryFileVersion),
		TableSourceKey	: @"api",
		@"made"			: LDrawJSONStringFromDate([NSDate date]),
		TableColorsKey	: colors,
	};
	return LDrawJSONWriteFile(file, [folderURL URLByAppendingPathComponent:FetchedFileName], YES, error);

}//end saveFetchedColorLinks:inFolder:error:


//---------- colorLinksForFolder: ------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSDictionary<NSNumber *, NSArray<NSNumber *> *> *) colorLinksForFolder:(NSURL *)folderURL
{
	NSDictionary *fetched = [self fetchedColorLinksInFolder:folderURL];
	return ([fetched count] > 0) ? fetched : [self builtInColorLinks];
}


// MARK: - UTILITIES -


//---------- colorLinksInTable: --------------------------------------[static]--
///
/// @abstract	A table's links. Ids are written as strings, and a color may
/// 			have one code or a list.
///
//------------------------------------------------------------------------------
+ (NSDictionary<NSNumber *, NSArray<NSNumber *> *> *) colorLinksInTable:(NSDictionary *)table
{
	NSDictionary		*colors	= LDrawJSONDictionary(table[TableColorsKey]);
	NSMutableDictionary	*links	= [NSMutableDictionary dictionary];

	for (id key in colors)
	{
		NSInteger		 colorID	= LDrawJSONInteger(key, NSNotFound);
		id				 value		= colors[key];
		NSArray			*values		= [value isKindOfClass:[NSArray class]] ? value : @[value];
		NSMutableArray	*codes		= [NSMutableArray array];

		for (id code in values)
		{
			NSInteger number = LDrawJSONInteger(code, NSNotFound);
			if (number != NSNotFound)
				[codes addObject:@(number)];
		}
		if (colorID != NSNotFound && [codes count] > 0)
			links[@(colorID)] = codes;
	}
	return links;

}//end colorLinksInTable:

@end
