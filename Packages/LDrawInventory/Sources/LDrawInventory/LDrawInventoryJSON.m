//==============================================================================
//
//  File:       LDrawInventoryJSON.m
//  Package:    LDrawInventory
//
//  Purpose:    Reading values out of parsed JSON without trusting their types,
//              and reading and writing the store's files.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <LDrawInventory/LDrawInventoryJSON.h>

#import <math.h>

const NSInteger LDrawInventoryFileVersion = 1;


//========== LDrawJSONString ===================================================
//==============================================================================
NSString *LDrawJSONString(id value)
{
	if ([value isKindOfClass:[NSString class]] && [value length] > 0)
		return value;
	return nil;
}


//========== LDrawJSONInteger ==================================================
///
/// @abstract	A whole number, from a number or a string of digits. A boolean
/// 			is not a number here.
///
//==============================================================================
NSInteger LDrawJSONInteger(id value, NSInteger fallback)
{
	if ([value isKindOfClass:[NSNumber class]])
	{
		if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())
			return fallback;

		double number = [value doubleValue];
		if (number != floor(number) || fabs(number) > (double)NSIntegerMax / 2)
			return fallback;
		return [value integerValue];
	}
	if ([value isKindOfClass:[NSString class]])
	{
		NSScanner	*scanner	= [NSScanner scannerWithString:value];
		NSInteger	 number		= 0;
		if ([scanner scanInteger:&number] && [scanner isAtEnd])
			return number;
	}
	return fallback;

}//end LDrawJSONInteger


//========== LDrawJSONBool =====================================================
//==============================================================================
BOOL LDrawJSONBool(id value, BOOL fallback)
{
	if ([value isKindOfClass:[NSNumber class]])
		return [value boolValue];
	return fallback;
}


//========== LDrawJSONArray ====================================================
//==============================================================================
NSArray *LDrawJSONArray(id value)
{
	return [value isKindOfClass:[NSArray class]] ? value : nil;
}


//========== LDrawJSONDictionary ===============================================
//==============================================================================
NSDictionary *LDrawJSONDictionary(id value)
{
	return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}


//========== LDrawJSONDateFormatter ============================================
///
/// @abstract	One formatter for the whole process. Formatting is thread safe.
///
//==============================================================================
static NSISO8601DateFormatter *LDrawJSONDateFormatter(void)
{
	static NSISO8601DateFormatter	*formatter	= nil;
	static dispatch_once_t			 once		= 0;

	dispatch_once(&once, ^{
		formatter = [[NSISO8601DateFormatter alloc] init];
	});
	return formatter;
}


//========== LDrawJSONDate =====================================================
//==============================================================================
NSDate *LDrawJSONDate(id value)
{
	NSString *string = LDrawJSONString(value);
	return string ? [LDrawJSONDateFormatter() dateFromString:string] : nil;
}


//========== LDrawJSONStringFromDate ===========================================
//==============================================================================
NSString *LDrawJSONStringFromDate(NSDate *date)
{
	return [LDrawJSONDateFormatter() stringFromDate:date];
}


//========== LDrawJSONColorLinks ===============================================
//==============================================================================
NSDictionary<NSNumber *, NSArray<NSNumber *> *> *LDrawJSONColorLinks(id value)
{
	NSDictionary		*links	= LDrawJSONDictionary(value);
	NSMutableDictionary	*result	= [NSMutableDictionary dictionary];

	for (id key in links)
	{
		NSInteger		 colorID	= LDrawJSONInteger(key, NSNotFound);
		NSArray			*values		= LDrawJSONArray(links[key]) ?: @[links[key]];
		NSMutableArray	*codes		= [NSMutableArray array];

		for (id code in values)
		{
			NSInteger number = LDrawJSONInteger(code, NSNotFound);
			if (number != NSNotFound && [codes containsObject:@(number)] == NO)
				[codes addObject:@(number)];
		}
		if (colorID != NSNotFound && [codes count] > 0)
			result[@(colorID)] = codes;
	}
	return result;

}//end LDrawJSONColorLinks


//========== LDrawJSONColorLinksObject =========================================
//==============================================================================
NSDictionary<NSString *, NSArray<NSNumber *> *> *LDrawJSONColorLinksObject(
	NSDictionary<NSNumber *, NSArray<NSNumber *> *> *links)
{
	NSMutableDictionary *object = [NSMutableDictionary dictionary];

	for (NSNumber *colorID in links)
		object[[colorID stringValue]] = links[colorID];
	return object;
}


//========== LDrawJSONReadFile =================================================
///
/// @abstract	The top-level dictionary of a JSON file, or nil.
///
//==============================================================================
NSDictionary *LDrawJSONReadFile(NSURL *url)
{
	NSData	*data	= [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:NULL];
	id		 object	= nil;

	if (data == nil)
		return nil;

	object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
	return LDrawJSONDictionary(object);

}//end LDrawJSONReadFile


//========== LDrawJSONWriteFile ================================================
///
/// @abstract	Writes a dictionary as JSON, atomically, making the folder
/// 			first. A pretty file has its keys sorted, so it changes only
/// 			where its data does. Large caches skip the sort.
///
//==============================================================================
BOOL LDrawJSONWriteFile(NSDictionary *dictionary, NSURL *url, BOOL pretty, NSError **error)
{
	NSJSONWritingOptions	 options	= pretty ? (NSJSONWritingSortedKeys | NSJSONWritingPrettyPrinted) : 0;
	NSData					*data		= nil;
	NSURL					*folder		= [url URLByDeletingLastPathComponent];

	if ([[NSFileManager defaultManager] createDirectoryAtURL:folder
								 withIntermediateDirectories:YES
												  attributes:nil
													   error:error] == NO)
		return NO;

	data = [NSJSONSerialization dataWithJSONObject:dictionary options:options error:error];
	if (data == nil)
		return NO;

	return [data writeToURL:url options:NSDataWritingAtomic error:error];

}//end LDrawJSONWriteFile
