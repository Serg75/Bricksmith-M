//==============================================================================
//
//  File:       LDrawHighResPrimitives.h
//  Package:    LDrawCore
//
//  Purpose:    Subdivide rotating LDraw primitives into higher-resolution
//              triangles, lines, and conditional lines for the "48" folder.
//
//  Created by Sergey Slobodenyuk on 2022-08-31.
//
//==============================================================================

#import <Foundation/Foundation.h>
#import <LDrawCore/LDrawConditionalLine.h>
#import <LDrawCore/LDrawDirective.h>
#import <LDrawCore/LDrawLine.h>
#import <LDrawCore/MatrixMath.h>


typedef NS_ENUM(int, LDrawAxis) {
	LDrawAxisX       = 0,
	LDrawAxisY,
	LDrawAxisZ,
	LDrawAxisUnknown = -1
};


typedef struct
{
	LDrawAxis axis;
	Matrix4 rotationMatrix;
} RotationParameters;


NS_ASSUME_NONNULL_BEGIN

@class LDrawHighResPrimitives;


//------------------------------------------------------------------------------
///
/// @class      LDrawHighResReplacement
///
/// @abstract   One original directive plus the high-resolution primitives that
///             replace it.
///
//------------------------------------------------------------------------------
@interface LDrawHighResReplacement : NSObject

@property (nonatomic, readonly, strong) LDrawDirective *original;
@property (nonatomic, readonly, strong) LDrawHighResPrimitives *highRes;

/// Record one original directive and the high-resolution primitives that replace it.
- (instancetype)initWithOriginal:(LDrawDirective *)original highRes:(LDrawHighResPrimitives *)highRes;

@end


//------------------------------------------------------------------------------
///
/// @class      LDrawHighResPrimitives
///
/// @abstract   Higher-resolution triangle, line, and conditional-line
///             substitutes for a primitive that rotates around an axis.
///
//------------------------------------------------------------------------------
@interface LDrawHighResPrimitives : NSObject

@property (nonatomic, readonly) NSArray *primitives;
@property (nonatomic, readonly) RotationParameters rotation;

/// YES if at least two vertices among primitives rotate around the given axis.
+ (BOOL)hasRotationByAxis:(LDrawAxis)axis forPrimitives:(NSArray *)directives;

/// High-resolution replacements for primitive around axis; nil if unsupported.
+ (LDrawHighResPrimitives *)highResPrimitivesFor:(LDrawDirective *)directive axis:(LDrawAxis)axis;

/// YES if primitive (quad or triangle) contains an edge that matches line.
+ (BOOL)isPrimitive:(LDrawDirective *)directive includesLine:(LDrawLine *)line;

/// YES if line is similar to any line in lines.
+ (BOOL)isLine:(LDrawLine *)line withinLines:(NSArray *)lines;

/// Replace the line's endpoints with their images under rotationMatrix.
+ (void)rotateLine:(LDrawLine *)line byMatrix:(Matrix4)rotationMatrix;

/// Store the generated high-resolution primitives and the rotation used.
- (LDrawHighResPrimitives *)initWithPrimitives:(NSArray *)directives rotation:(RotationParameters)rotation;

/// Per-axis conversion plan. Directives that become high-res are returned as
/// replacements. Lines that do not convert are appended to unknownLines (the
/// host should keep that array across axes). Does not mutate the tree.
+ (NSArray<LDrawHighResReplacement *> *)replacementsForDirectives:(NSArray *)directives
															 axis:(LDrawAxis)axis
													 unknownLines:(NSMutableArray *)unknownLines;

@end

NS_ASSUME_NONNULL_END
