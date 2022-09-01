//
//  LDrawHighResPrimitives.h
//  Bricksmith
//
//  Created by Sergey Slobodenyuk on 2022-08-31.
//

#import <Foundation/Foundation.h>
#import "LDrawConditionalLine.h"
#import "LDrawDirective.h"
#import "LDrawLine.h"
#import "MatrixMath.h"


typedef NS_ENUM(int, Axis) {
	AxisX		= 0,
	AxisY,
	AxisZ,
	AxisUnknown	= -1
};


typedef struct
{
	Axis axis;
	Matrix4 rotationMatrix;
} RotationParameters;


NS_ASSUME_NONNULL_BEGIN

@interface LDrawHighResPrimitives : NSObject

@property (nonatomic, readonly) NSArray *primitives;
@property (nonatomic, readonly) RotationParameters rotation;

+ (BOOL) hasRotationByAxis:(Axis)axis forPrimitives:(NSArray *)directives;
+ (LDrawHighResPrimitives *) highResPrimitivesFor:(LDrawDirective *)directive axis:(Axis)axis;
+ (BOOL) isPrimitive:(LDrawDirective *)directive includesLine:(LDrawLine *)line;
+ (BOOL) isLine:(LDrawLine *)line withinLines:(NSArray *)lines;
+ (void) rotateLine:(LDrawLine *)line byMatrix:(Matrix4)rotationMatrix;

- (LDrawHighResPrimitives *)initWithPrimitives:(NSArray *)directives rotation:(RotationParameters)rotation;

@end

NS_ASSUME_NONNULL_END
