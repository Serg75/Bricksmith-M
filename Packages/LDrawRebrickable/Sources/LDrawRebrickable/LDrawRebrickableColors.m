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

static NSString * const TableResourceName	= @"rebrickable-colors";
static NSString * const TableColorsKey		= @"colors";
static NSString * const TableSourceKey		= @"source";


@implementation LDrawRebrickableColors


// MARK: - THE SHIPPED TABLE -


//---------- builtInColorLinks ---------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSDictionary<NSNumber *, NSArray<NSNumber *> *> *) builtInColorLinks
{
	return LDrawJSONColorLinks([self builtInTable][TableColorsKey]);
}


//---------- builtInTableSource --------------------------------------[static]--
//------------------------------------------------------------------------------
+ (NSString *) builtInTableSource
{
	return LDrawJSONString([self builtInTable][TableSourceKey]);
}


// MARK: - UTILITIES -


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

@end
