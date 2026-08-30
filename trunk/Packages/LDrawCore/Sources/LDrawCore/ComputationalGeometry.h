//==============================================================================
//
//  File:       ComputationalGeometry.h
//  Package:    LDrawCore
//
//  Purpose:    General purpose computational geometry functionality
//
//  Created by rmacharg on 14/12/2012.
//
//==============================================================================

#import <Foundation/Foundation.h>
#import <LDrawCore/LDrawPart.h>

//------------------------------------------------------------------------------
///
/// @class      ComputationalGeometry
///
/// @abstract   General purpose computational geometry functionality
///
//------------------------------------------------------------------------------
@interface ComputationalGeometry : NSObject

+(NSArray *)tangentBetweenCircle:(NSMutableDictionary *)c1 andCircle:(NSMutableDictionary *)c2;

+(void)doJarvisMarch:(NSMutableArray *)preparedData;
+(int)nextHullPointWithPoints:(NSArray *)points andPointIndex:(int)pIndex;
+(int)turnWithPoints:(NSArray *)points P:(int)pIndex Q:(int)qIndex R:(int)rIndex;
+(int)distanceBetweenPoints:(NSArray *)points P:(int)pIndex Q:(int)qIndex;
+(int)leftmost:(NSArray *)points;

@end
