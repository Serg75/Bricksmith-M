//==============================================================================
//
//  File:       LDrawStepLayoutCache.m
//  Package:    LDrawStepRendering
//
//  Purpose:    Keeps what centering a step on the page measured, for every
//              presenter that shares it.
//
//  Created by Sergey Slobodenyuk on 2026-10-14.
//
//==============================================================================

#import "LDrawStepLayoutCacheEntries.h"


/// How many bytes of outlines are kept. Past that some are let go.
static const NSUInteger OUTLINE_BYTE_LIMIT = 16 * 1024 * 1024;


@implementation LDrawStepKeptCenter

//========== initWithPageCenter:hasStepCenter:placementKey: ====================
- (instancetype) initWithPageCenter:(Point3)pageCenter
					  hasStepCenter:(BOOL)hasStepCenter
					   placementKey:(NSString *)placementKey
{
	self = [super init];
	if (self) {
		self->_pageCenter		= pageCenter;
		self->_hasStepCenter	= hasStepCenter;
		self->_placementKey		= [placementKey copy];
	}
	return self;

}//end initWithPageCenter:hasStepCenter:placementKey:

@end


@implementation LDrawStepLayoutCache
{
	NSCache<NSString *, NSData *>				*outlines;
	NSCache<NSString *, LDrawStepKeptCenter *>	*centers;
}


//========== init ==============================================================
- (instancetype) init
{
	self = [super init];
	if (self) {
		self->outlines	= [[NSCache alloc] init];
		self->centers	= [[NSCache alloc] init];

		self->outlines.totalCostLimit = OUTLINE_BYTE_LIMIT;
	}
	return self;

}//end init


//========== removeAll =========================================================
- (void) removeAll
{
	[self->outlines removeAllObjects];
	[self->centers removeAllObjects];

}//end removeAll


//========== outlineForKey: ====================================================
- (nullable NSData *) outlineForKey:(NSString *)key
{
	return [self->outlines objectForKey:key];

}//end outlineForKey:


//========== setOutline:forKey: ================================================
- (void) setOutline:(NSData *)outline forKey:(NSString *)key
{
	[self->outlines setObject:outline forKey:key cost:outline.length];

}//end setOutline:forKey:


//========== centerForKey: =====================================================
- (nullable LDrawStepKeptCenter *) centerForKey:(NSString *)key
{
	return [self->centers objectForKey:key];

}//end centerForKey:


//========== setCenter:forKey: =================================================
- (void) setCenter:(LDrawStepKeptCenter *)center forKey:(NSString *)key
{
	[self->centers setObject:center forKey:key];

}//end setCenter:forKey:

@end
