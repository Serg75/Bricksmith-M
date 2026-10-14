//==============================================================================
//
//  File:       LDrawStepLayoutCacheEntries.h
//  Package:    LDrawStepRendering
//
//  Purpose:    What the presenter keeps in a layout cache. Private to the
//              package.
//
//  Created by Sergey Slobodenyuk on 2026-10-14.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawCore/MatrixMath.h>
#import <LDrawStepRendering/LDrawStepLayoutCache.h>

NS_ASSUME_NONNULL_BEGIN

//------------------------------------------------------------------------------
///
/// @class      LDrawStepKeptCenter
///
/// @abstract   Where the page went for a step in one view.
///
//------------------------------------------------------------------------------
@interface LDrawStepKeptCenter : NSObject

/// The model point drawn at the middle of the page.
@property (nonatomic, readonly) Point3 pageCenter;

/// Whether the step had an assembly to measure.
@property (nonatomic, readonly) BOOL hasStepCenter;

/// The step's PLACEMENT lines then.
@property (nonatomic, readonly, copy) NSString *placementKey;

- (instancetype) initWithPageCenter:(Point3)pageCenter
					  hasStepCenter:(BOOL)hasStepCenter
					   placementKey:(NSString *)placementKey;

@end


@interface LDrawStepLayoutCache ()

/// The points around a step's assembly, as Point3 values. Kept by step.
- (nullable NSData *) outlineForKey:(NSString *)key;
- (void) setOutline:(NSData *)outline forKey:(NSString *)key;

/// Where the page went. Kept by step and view.
- (nullable LDrawStepKeptCenter *) centerForKey:(NSString *)key;
- (void) setCenter:(LDrawStepKeptCenter *)center forKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
