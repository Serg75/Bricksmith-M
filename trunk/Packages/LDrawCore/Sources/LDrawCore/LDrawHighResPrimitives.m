//==============================================================================
//
//  File:       LDrawHighResPrimitives.m
//  Package:    LDrawCore
//
//  Purpose:    Subdivide rotating LDraw primitives into higher-resolution
//              triangles, lines, and conditional lines for the "48" folder.
//
//  Created by Sergey Slobodenyuk on 2022-08-31.
//
//==============================================================================

#import <LDrawCore/LDrawHighResPrimitives.h>

#import <LDrawCore/LDrawQuadrilateral.h>
#import <LDrawCore/LDrawTriangle.h>
#import <LDrawCore/MatrixMath.h>


@interface LDrawHighResPrimitives ()

@property (nonatomic, readwrite) NSArray *primitives;
@property (nonatomic, readwrite) RotationParameters rotation;

+ (NSArray<LDrawHighResReplacement *> *)extraReplacementsForUnknownLines:(NSArray *)unknownLines
													   usingReplacements:(NSArray<LDrawHighResReplacement *> *)replacements;

@end


@implementation LDrawHighResReplacement

//========== initWithOriginal:highRes: ========================================
//
// Purpose:		Record one original directive and the high-resolution primitives
//				that replace it.
//
//==============================================================================
- (instancetype)initWithOriginal:(LDrawDirective *)original highRes:(LDrawHighResPrimitives *)highRes
{
	self = [super init];
	if (self)
	{
		_original = original;
		_highRes  = highRes;
	}
	return self;
}

@end


@implementation LDrawHighResPrimitives

//---------- hasRotationByAxis:forPrimitives: -----------------------[static]--
//
// Purpose:		Return YES if at least two vertices among primitives rotate
//				around the given axis, so a high-res conversion is possible.
//
//------------------------------------------------------------------------------
+ (BOOL)hasRotationByAxis:(LDrawAxis)axis forPrimitives:(NSArray *)primitives
{
	int rotatedPointCount = 0;
	for (LDrawDirective *primitive in primitives) {
		rotatedPointCount += [self rotatedVertexCountByAxis:axis forPrimitive:primitive];
		if (rotatedPointCount >= 2) {
			return YES;
		}
	}
	return NO;
}


//---------- rotatedVertexCountByAxis:forPrimitive: -----------------[static]--
//
// Purpose:		Count how many edges of primitive lie on a rotation around axis.
//				Dispatches to the quad / triangle / line helpers.
//
//------------------------------------------------------------------------------
+ (int)rotatedVertexCountByAxis:(LDrawAxis)axis forPrimitive:(LDrawDirective *)primitive
{
	if ([primitive isKindOfClass:LDrawQuadrilateral.class]) {
		return [self rotatedVertexCountByAxis:axis forQuadrilateral:(LDrawQuadrilateral *)primitive];
	} else if ([primitive isKindOfClass:LDrawTriangle.class]) {
		return [self rotatedVertexCountByAxis:axis forTriangle:(LDrawTriangle *)primitive];
	} else if ([primitive isKindOfClass:LDrawLine.class]) {
		return [self rotatedVertexCountByAxis:axis forLine:(LDrawConditionalLine *)primitive];
	}
	return 0;
}


//---------- rotatedVertexCountByAxis:forQuadrilateral: -------------[static]--
//
// Purpose:		Count opposite-edge pairs of the quad that rotate around axis.
//				Returns the larger of the two pair counts.
//
//------------------------------------------------------------------------------
+ (int)rotatedVertexCountByAxis:(LDrawAxis)axis forQuadrilateral:(LDrawQuadrilateral *)quad
{
	int count1 = 0;
	if ([self isVertex:quad.vertex1 andVertex:quad.vertex2 rotatedByAxis:axis]) {
		count1++;
	}
	if ([self isVertex:quad.vertex3 andVertex:quad.vertex4 rotatedByAxis:axis]) {
		count1++;
	}
	
	int count2 = 0;
	if ([self isVertex:quad.vertex1 andVertex:quad.vertex4 rotatedByAxis:axis]) {
		count2++;
	}
	if ([self isVertex:quad.vertex2 andVertex:quad.vertex3 rotatedByAxis:axis]) {
		count2++;
	}
	
	return MAX(count1, count2);
}


//---------- rotatedVertexCountByAxis:forTriangle: ------------------[static]--
//
// Purpose:		Return 1 if any edge of the triangle rotates around axis,
//				otherwise 0.
//
//------------------------------------------------------------------------------
+ (int)rotatedVertexCountByAxis:(LDrawAxis)axis forTriangle:(LDrawTriangle *)triangle
{
	if ([self isVertex:triangle.vertex1 andVertex:triangle.vertex2 rotatedByAxis:axis]) {
		return 1;
	}
	if ([self isVertex:triangle.vertex2 andVertex:triangle.vertex3 rotatedByAxis:axis]) {
		return 1;
	}
	if ([self isVertex:triangle.vertex1 andVertex:triangle.vertex3 rotatedByAxis:axis]) {
		return 1;
	}
	return 0;
}


//---------- rotatedVertexCountByAxis:forLine: ----------------------[static]--
//
// Purpose:		Return 1 if the line's endpoints rotate around axis, otherwise 0.
//
//------------------------------------------------------------------------------
+ (int)rotatedVertexCountByAxis:(LDrawAxis)axis forLine:(LDrawLine *)line
{
	if ([self isVertex:line.vertex1 andVertex:line.vertex2 rotatedByAxis:axis]) {
		return 1;
	}
	return 0;
}


//---------- isVertex:andVertex:rotatedByAxis: ----------------------[static]--
//
// Purpose:		Return YES if the two vertices share a circular arc around axis
//				(same radius, different angle).
//
//------------------------------------------------------------------------------
+ (BOOL)isVertex:(Point3)vertex1 andVertex:(Point3)vertex2 rotatedByAxis:(LDrawAxis)axis
{
	if (component(vertex1, axis) != component(vertex2, axis)) {
		return NO;
	}
	
	float v11, v12, v21, v22;
	switch (axis) {
		case LDrawAxisX:
			v11 = component(vertex1, LDrawAxisY);
			v12 = component(vertex1, LDrawAxisZ);
			v21 = component(vertex2, LDrawAxisY);
			v22 = component(vertex2, LDrawAxisZ);
			break;
		case LDrawAxisY:
			v11 = component(vertex1, LDrawAxisX);
			v12 = component(vertex1, LDrawAxisZ);
			v21 = component(vertex2, LDrawAxisX);
			v22 = component(vertex2, LDrawAxisZ);
			break;
		case LDrawAxisZ:
			v11 = component(vertex1, LDrawAxisX);
			v12 = component(vertex1, LDrawAxisY);
			v21 = component(vertex2, LDrawAxisX);
			v22 = component(vertex2, LDrawAxisY);
			break;
		default:
			return NO;
	}
	float R1 = sqrtf(v11 * v11 + v12 * v12);
	float R2 = sqrtf(v21 * v21 + v22 * v22);
	float Ra = (R1 + R2) / 2.0f;
	return Ra > 0.0f ? ABS(R1 - Ra) / Ra < 0.0001f : NO;
}


//---------- rotationForVertex:toVertex:byAxis: ---------------------[static]--
//
// Purpose:		Build the rotation matrix that carries vertex1 onto vertex2
//				around axis. axis is LDrawAxisUnknown when the pair is not a rotation.
//
//------------------------------------------------------------------------------
+ (RotationParameters)rotationForVertex:(Point3)vertex1 toVertex:(Point3)vertex2 byAxis:(LDrawAxis)axis
{
	RotationParameters result;
	result.axis = LDrawAxisUnknown;
	
	if (![self isVertex:vertex1 andVertex:vertex2 rotatedByAxis:axis]) {
		return result;
	}
	
	float x[3] = { 1, 0, 0 };
	float y[3] = { 0, 1, 0 };
	float z[3] = { 0, 0, 1 };
	
	Point3 *verticesPair[2];
	
	verticesPair[0] = &vertex1;
	verticesPair[1] = &vertex2;
	
	Matrix4 rotationMatrix;
	
	// adjust initial value temporary for specific cases
	for (int step = 16; step <= 48; step += 8) {
		for (int i = 0; i < 3; i++) {
			float m[16];
			buildRotationMatrix(m, 360.0f / step, x[i], y[i], z[i]);
			rotationMatrix = Matrix4CreateFromFloats(m);
			Point3 rotatedPoint = V3MulPointByProjMatrix(*verticesPair[0], rotationMatrix);
			
			if (V3PointsWithinGivenTolerance(rotatedPoint, *verticesPair[1], 0.001f)) {
				buildRotationMatrix(m, 360.0f / step / 3, x[i], y[i], z[i]);
				result.rotationMatrix = Matrix4CreateFromFloats(m);;
				result.axis = i;
				return result;
			}
			
			buildRotationMatrix(m, -360.0f / step, x[i], y[i], z[i]);
			rotationMatrix = Matrix4CreateFromFloats(m);
			rotatedPoint = V3MulPointByProjMatrix(*verticesPair[0], rotationMatrix);
			
			if (V3PointsWithinGivenTolerance(rotatedPoint, *verticesPair[1], 0.001f)) {
				buildRotationMatrix(m, -360.0f / step / 3, x[i], y[i], z[i]);
				result.rotationMatrix = Matrix4CreateFromFloats(m);;
				result.axis = i;
				return result;
			}
		}
	}
	
	return result;
}


//---------- isPrimitive:includesLine: ------------------------------[static]--
//
// Purpose:		Return YES if primitive (quad or triangle) contains an edge that
//				matches line.
//
//------------------------------------------------------------------------------
+ (BOOL)isPrimitive:(LDrawDirective *)primitive includesLine:(LDrawLine *)line
{
	if ([primitive isKindOfClass:LDrawQuadrilateral.class]) {
		return [self isQuad:(LDrawQuadrilateral *)primitive includesLine:line];
	} else if ([primitive isKindOfClass:LDrawTriangle.class]) {
		return [self isTriangle:(LDrawTriangle *)primitive includesLine:line];
	} else {
		return NO;
	}
}


//---------- isQuad:includesLine: -----------------------------------[static]--
//
// Purpose:		Return YES if any edge of the quad matches line.
//
//------------------------------------------------------------------------------
+ (BOOL)isQuad:(LDrawQuadrilateral *)quad includesLine:(LDrawLine *)line
{
	float tolerance = 0.001f;
	Point3 vertex = line.vertex1;
	if (!V3PointsWithinGivenTolerance(vertex, quad.vertex1, tolerance) &&
		!V3PointsWithinGivenTolerance(vertex, quad.vertex2, tolerance) &&
		!V3PointsWithinGivenTolerance(vertex, quad.vertex3, tolerance) &&
		!V3PointsWithinGivenTolerance(vertex, quad.vertex4, tolerance))
	{
		return NO;
	}
	vertex = line.vertex2;
	if (!V3PointsWithinGivenTolerance(vertex, quad.vertex1, tolerance) &&
		!V3PointsWithinGivenTolerance(vertex, quad.vertex2, tolerance) &&
		!V3PointsWithinGivenTolerance(vertex, quad.vertex3, tolerance) &&
		!V3PointsWithinGivenTolerance(vertex, quad.vertex4, tolerance))
	{
		return NO;
	}
	return YES;
}


//---------- isTriangle:includesLine: -------------------------------[static]--
//
// Purpose:		Return YES if any edge of the triangle matches line.
//
//------------------------------------------------------------------------------
+ (BOOL)isTriangle:(LDrawTriangle *)triangle includesLine:(LDrawLine *)line
{
	float tolerance = 0.001f;
	Point3 vertex = line.vertex1;
	if (!V3PointsWithinGivenTolerance(vertex, triangle.vertex1, tolerance) &&
		!V3PointsWithinGivenTolerance(vertex, triangle.vertex2, tolerance) &&
		!V3PointsWithinGivenTolerance(vertex, triangle.vertex3, tolerance))
	{
		return NO;
	}
	vertex = line.vertex2;
	if (!V3PointsWithinGivenTolerance(vertex, triangle.vertex1, tolerance) &&
		!V3PointsWithinGivenTolerance(vertex, triangle.vertex2, tolerance) &&
		!V3PointsWithinGivenTolerance(vertex, triangle.vertex3, tolerance))
	{
		return NO;
	}
	return YES;
}


//---------- isLine:withinLines: ------------------------------------[static]--
//
// Purpose:		Return YES if line is similar to any line in lines.
//
//------------------------------------------------------------------------------
+ (BOOL)isLine:(LDrawLine *)line withinLines:(NSArray *)lines
{
	for (LDrawLine *lineInArray in lines) {
		if ([self isLine:line similarToLine:lineInArray]) {
			return YES;
		}
	}
	return NO;
}


//---------- isLine:similarToLine: ----------------------------------[static]--
//
// Purpose:		Return YES if the two lines share the same endpoints, in either
//				order.
//
//------------------------------------------------------------------------------
+ (BOOL)isLine:(LDrawLine *)line1 similarToLine:(LDrawLine *)line2
{
	float tolerance = 0.001f;
	if (V3PointsWithinGivenTolerance(line1.vertex1, line2.vertex1, tolerance) &&
		V3PointsWithinGivenTolerance(line1.vertex2, line2.vertex2, tolerance)) {
		return YES;
	}
	if (V3PointsWithinGivenTolerance(line1.vertex1, line2.vertex2, tolerance) &&
		V3PointsWithinGivenTolerance(line1.vertex2, line2.vertex1, tolerance)) {
		return YES;
	}
	return NO;
}


//---------- highResPrimitivesFor:axis: -----------------------------[static]--
//
// Purpose:		Build high-resolution replacements for primitive around axis.
//				Dispatches by concrete type; returns nil for unsupported types.
//
//------------------------------------------------------------------------------
+ (LDrawHighResPrimitives *)highResPrimitivesFor:(LDrawDirective *)primitive axis:(LDrawAxis)axis
{
	if ([primitive isKindOfClass:LDrawQuadrilateral.class]) {
		return [self highResPrimitivesForQuad:(LDrawQuadrilateral *)primitive axis:axis];
	} else if ([primitive isKindOfClass:LDrawTriangle.class]) {
		return [self highResPrimitivesForTriangle:(LDrawTriangle *)primitive axis:axis];
	} else if ([primitive isKindOfClass:LDrawConditionalLine.class]) {
		return [self highResPrimitivesForConditionLine:(LDrawConditionalLine *)primitive axis:axis];
	} else if ([primitive isKindOfClass:LDrawLine.class]) {
		return [self highResPrimitivesForLine:(LDrawLine *)primitive axis:axis];
	} else {
		return nil;
	}
}


//---------- highResPrimitivesForQuad:axis: -------------------------[static]--
//
// Purpose:		Subdivide a quad that rotates around axis into a triangle strip
//				of higher-resolution primitives.
//
//------------------------------------------------------------------------------
+ (LDrawHighResPrimitives *)highResPrimitivesForQuad:(LDrawQuadrilateral *)quad axis:(LDrawAxis)axis
{
	NSMutableArray *newPrimitives = [NSMutableArray array];
	
	Point3 vertex1 = quad.vertex1;
	Point3 vertex2 = quad.vertex2;
	Point3 vertex3 = quad.vertex3;
	Point3 vertex4 = quad.vertex4;
	Point3 *pair1[2], *pair2[2];
	Point3 strip1[4], strip2[4];
	
	BOOL isAllVertices = NO;
	
	RotationParameters rotation12 = [self rotationForVertex:vertex1 toVertex:vertex2 byAxis:axis];
	RotationParameters rotation23 = [self rotationForVertex:vertex2 toVertex:vertex3 byAxis:axis];
	RotationParameters rotation34 = [self rotationForVertex:vertex3 toVertex:vertex4 byAxis:axis];
	RotationParameters rotation41 = [self rotationForVertex:vertex4 toVertex:vertex1 byAxis:axis];
	
	RotationParameters *rotation;
	
	BOOL is12 = rotation12.axis != LDrawAxisUnknown;
	BOOL is23 = rotation23.axis != LDrawAxisUnknown;
	BOOL is34 = rotation34.axis != LDrawAxisUnknown;
	BOOL is41 = rotation41.axis != LDrawAxisUnknown;
	
	if (is12 && is34) {
		isAllVertices = YES;
		pair1[0] = &vertex1;
		pair1[1] = &vertex2;
		pair2[0] = &vertex4;
		pair2[1] = &vertex3;
		rotation = &rotation12;
	} else if (is41 && is23) {
		isAllVertices = YES;
		pair1[0] = &vertex1;
		pair1[1] = &vertex4;
		pair2[0] = &vertex2;
		pair2[1] = &vertex3;
		rotation = &rotation41;
	} else if (is12) {
		pair1[0] = &vertex1;
		pair1[1] = &vertex2;
		pair2[0] = &vertex3;
		rotation = &rotation12;
	} else if (is23) {
		pair1[0] = &vertex2;
		pair1[1] = &vertex3;
		pair2[0] = &vertex4;
		rotation = &rotation23;
	} else if (is34) {
		pair1[0] = &vertex3;
		pair1[1] = &vertex4;
		pair2[0] = &vertex1;
		rotation = &rotation34;
	} else if (is41) {
		pair1[0] = &vertex4;
		pair1[1] = &vertex1;
		pair2[0] = &vertex2;
		rotation = &rotation41;
	} else {
		return nil;
	}
	
	strip1[0] = *pair1[0];
	strip1[3] = *pair1[1];
	[self fillHiResPoints:strip1 byMatrix:rotation->rotationMatrix];
	*pair1[1] = strip1[1];
	
	if (isAllVertices)
	{
		strip2[0] = *pair2[0];
		strip2[3] = *pair2[1];
		[self fillHiResPoints:strip2 byMatrix:rotation->rotationMatrix];
		*pair2[1] = strip2[1];
	}
	
	LDrawQuadrilateral *newQuad = [quad copy];
	newQuad.vertex1 = vertex1;
	newQuad.vertex2 = vertex2;
	newQuad.vertex3 = vertex3;
	newQuad.vertex4 = vertex4;
	
	[newPrimitives addObject:newQuad];
	
	if (isAllVertices)
	{
		*pair1[0] = strip1[1];
		*pair1[1] = strip1[2];
		*pair2[0] = strip2[1];
		*pair2[1] = strip2[2];
		
		newQuad = [newQuad copy];
		newQuad.vertex1 = vertex1;
		newQuad.vertex2 = vertex2;
		newQuad.vertex3 = vertex3;
		newQuad.vertex4 = vertex4;
		
		[newPrimitives addObject:newQuad];
		
		*pair1[0] = strip1[2];
		*pair1[1] = strip1[3];
		*pair2[0] = strip2[2];
		*pair2[1] = strip2[3];
		
		newQuad = [newQuad copy];
		newQuad.vertex1 = vertex1;
		newQuad.vertex2 = vertex2;
		newQuad.vertex3 = vertex3;
		newQuad.vertex4 = vertex4;
		
		[newPrimitives addObject:newQuad];
	}
	else
	{
		LDrawTriangle *triangle = [LDrawTriangle new];
		triangle.LDrawColor = quad.LDrawColor;
		triangle.vertex1 = strip1[1];
		triangle.vertex2 = strip1[2];
		triangle.vertex3 = *pair2[0];
		
		[newPrimitives addObject:triangle];
		
		triangle = [triangle copy];
		triangle.vertex1 = strip1[2];
		triangle.vertex2 = strip1[3];

		[newPrimitives addObject:triangle];
	}
	
	return [[LDrawHighResPrimitives alloc] initWithPrimitives:newPrimitives rotation:*rotation];
}


//---------- highResPrimitivesForTriangle:axis: ---------------------[static]--
//
// Purpose:		Subdivide a triangle that rotates around axis into higher-
//				resolution primitives.
//
//------------------------------------------------------------------------------
+ (LDrawHighResPrimitives *)highResPrimitivesForTriangle:(LDrawTriangle *)triangle axis:(LDrawAxis)axis
{
	NSMutableArray *newPrimitives = [NSMutableArray array];
	
	Point3 vertex1 = triangle.vertex1;
	Point3 vertex2 = triangle.vertex2;
	Point3 vertex3 = triangle.vertex3;
	Point3 *pair[2], *oppositeVertex;
	Point3 strip[4];
	
	RotationParameters rotation12 = [self rotationForVertex:vertex1 toVertex:vertex2 byAxis:axis];
	RotationParameters rotation13 = [self rotationForVertex:vertex1 toVertex:vertex3 byAxis:axis];
	RotationParameters rotation23 = [self rotationForVertex:vertex2 toVertex:vertex3 byAxis:axis];
	
	RotationParameters *rotation;
	
	BOOL is12 = rotation12.axis != LDrawAxisUnknown;
	BOOL is13 = rotation13.axis != LDrawAxisUnknown;
	BOOL is23 = rotation23.axis != LDrawAxisUnknown;
	
	if (is12) {
		pair[0] = &vertex1;
		pair[1] = &vertex2;
		oppositeVertex = &vertex3;
		rotation = &rotation12;
	} else if (is13) {
		pair[0] = &vertex1;
		pair[1] = &vertex3;
		oppositeVertex = &vertex2;
		rotation = &rotation13;
	} else if (is23) {
		pair[0] = &vertex2;
		pair[1] = &vertex3;
		oppositeVertex = &vertex1;
		rotation = &rotation23;
	} else {
		return nil;
	}
	
	strip[0] = *pair[0];
	strip[3] = *pair[1];
	[self fillHiResPoints:strip byMatrix:rotation->rotationMatrix];
	*pair[1] = strip[1];
	
	LDrawTriangle *newTriangle = [triangle copy];
	newTriangle.vertex1 = vertex1;
	newTriangle.vertex2 = vertex2;
	newTriangle.vertex3 = vertex3;
	
	[newPrimitives addObject:newTriangle];
	
	newTriangle = [newTriangle copy];
	newTriangle.vertex1 = strip[1];
	newTriangle.vertex2 = strip[2];
	newTriangle.vertex3 = *oppositeVertex;
	
	[newPrimitives addObject:newTriangle];
	
	newTriangle = [newTriangle copy];
	newTriangle.vertex1 = strip[3];
	
	[newPrimitives addObject:newTriangle];
	
	return [[LDrawHighResPrimitives alloc] initWithPrimitives:newPrimitives rotation:*rotation];
}


//---------- highResPrimitivesForConditionLine:axis: ----------------[static]--
//
// Purpose:		Subdivide a conditional line that rotates around axis into
//				higher-resolution conditional lines.
//
//------------------------------------------------------------------------------
+ (LDrawHighResPrimitives *)highResPrimitivesForConditionLine:(LDrawConditionalLine *)line axis:(LDrawAxis)axis
{
	NSMutableArray *newPrimitives = [NSMutableArray array];
	
	Point3 vertex1 = line.vertex1;
	Point3 vertex2 = line.vertex2;
	Point3 *pair[2];
	Point3 strip1[4], strip2[4], strip3[4];
	
	RotationParameters rotation = [self rotationForVertex:vertex1 toVertex:vertex2 byAxis:axis];
	
	if (rotation.axis != LDrawAxisUnknown) {
		pair[0] = &vertex1;
		pair[1] = &vertex2;
	} else {
		return nil;
	}
	
	strip1[0] = *pair[0];
	strip1[3] = *pair[1];
	[self fillHiResPoints:strip1 byMatrix:rotation.rotationMatrix];
	
	strip2[0] = line.conditionalVertex1;
	[self fillHiResPoints:strip2 byMatrix:rotation.rotationMatrix];
	
	strip3[0] = line.conditionalVertex2;
	[self fillHiResPoints:strip3 byMatrix:rotation.rotationMatrix];
	
	*pair[1] = strip1[1];
	
	LDrawConditionalLine *newline = [line copy];
	newline.vertex1 = vertex1;
	newline.vertex2 = vertex2;
	
	[newPrimitives addObject:newline];
	
	*pair[0] = strip1[1];
	*pair[1] = strip1[2];
	
	newline = [newline copy];
	newline.vertex1 = vertex1;
	newline.vertex2 = vertex2;
	newline.conditionalVertex1 = strip2[1];
	newline.conditionalVertex2 = strip3[1];
	
	[newPrimitives addObject:newline];
	
	*pair[0] = strip1[2];
	*pair[1] = strip1[3];
	
	newline = [newline copy];
	newline.vertex1 = vertex1;
	newline.vertex2 = vertex2;
	newline.conditionalVertex1 = strip2[2];
	newline.conditionalVertex2 = strip3[2];
	
	[newPrimitives addObject:newline];
	
	return [[LDrawHighResPrimitives alloc] initWithPrimitives:newPrimitives rotation:rotation];
}


//---------- highResPrimitivesForLine:axis: -------------------------[static]--
//
// Purpose:		Subdivide a line that rotates around axis into higher-resolution
//				line segments.
//
//------------------------------------------------------------------------------
+ (LDrawHighResPrimitives *)highResPrimitivesForLine:(LDrawLine *)line axis:(LDrawAxis)axis
{
	NSMutableArray *newPrimitives = [NSMutableArray array];
	
	Point3 vertex1 = line.vertex1;
	Point3 vertex2 = line.vertex2;
	Point3 *pair[2];
	Point3 strip[4];
	
	RotationParameters rotation = [self rotationForVertex:vertex1 toVertex:vertex2 byAxis:axis];
	
	if (rotation.axis != LDrawAxisUnknown) {
		pair[0] = &vertex1;
		pair[1] = &vertex2;
	} else {
		return nil;
	}
	
	strip[0] = *pair[0];
	strip[3] = *pair[1];
	[self fillHiResPoints:strip byMatrix:rotation.rotationMatrix];
	
	*pair[1] = strip[1];
	
	LDrawConditionalLine *newline = [line copy];
	newline.vertex1 = vertex1;
	newline.vertex2 = vertex2;
	
	[newPrimitives addObject:newline];
	
	*pair[0] = strip[1];
	*pair[1] = strip[2];
	
	newline = [newline copy];
	newline.vertex1 = vertex1;
	newline.vertex2 = vertex2;
	
	[newPrimitives addObject:newline];
	
	*pair[0] = strip[2];
	*pair[1] = strip[3];
	
	newline = [newline copy];
	newline.vertex1 = vertex1;
	newline.vertex2 = vertex2;
	
	[newPrimitives addObject:newline];
	
	return [[LDrawHighResPrimitives alloc] initWithPrimitives:newPrimitives rotation:rotation];
}


//---------- fillHiResPoints:byMatrix: ------------------------------[static]--
//
// Purpose:		Walk points through successive applications of rotationMatrix to
//				fill in intermediate vertices along the arc.
//
//------------------------------------------------------------------------------
+ (void)fillHiResPoints:(Point3 *)points byMatrix:(Matrix4)rotationMatrix
{
	points[1] = V3MulPointByProjMatrix(points[0], rotationMatrix);
	points[2] = V3MulPointByProjMatrix(points[1], rotationMatrix);
}


//---------- rotateLine:byMatrix: -----------------------------------[static]--
//
// Purpose:		Replace the line's endpoints with their images under
//				rotationMatrix.
//
//------------------------------------------------------------------------------
+ (void)rotateLine:(LDrawLine *)line byMatrix:(Matrix4)rotationMatrix
{
	line.vertex1 = V3MulPointByProjMatrix(line.vertex1, rotationMatrix);
	line.vertex2 = V3MulPointByProjMatrix(line.vertex2, rotationMatrix);
	if ([line isKindOfClass:[LDrawConditionalLine class]])
	{
		LDrawConditionalLine *condLine = (LDrawConditionalLine *)line;
		condLine.conditionalVertex1 = V3MulPointByProjMatrix(condLine.conditionalVertex1, rotationMatrix);
		condLine.conditionalVertex2 = V3MulPointByProjMatrix(condLine.conditionalVertex2, rotationMatrix);
	}
}


//========== initWithPrimitives:rotation: =====================================
//
// Purpose:		Store the generated high-resolution primitives and the rotation
//				that produced them.
//
//==============================================================================
- (LDrawHighResPrimitives *)initWithPrimitives:(NSArray *)primitives rotation:(RotationParameters)rotation
{
	self = [super init];
	
	self.primitives = primitives;
	self.rotation = rotation;
	
	return self;
}


//---------- replacementsForDirectives:axis:unknownLines: -----------[static]--
//
// Purpose:		Per-axis conversion plan. Directives that become high-res are
//				returned as replacements. Lines that do not convert are appended
//				to unknownLines (the host should keep that array across axes).
//				Does not mutate the tree.
//
//------------------------------------------------------------------------------
+ (NSArray<LDrawHighResReplacement *> *)replacementsForDirectives:(NSArray *)directives
															 axis:(LDrawAxis)axis
													 unknownLines:(NSMutableArray *)unknownLines
{
	if ([self hasRotationByAxis:axis forPrimitives:directives] == NO)
	{
		return @[];
	}

	NSMutableArray<LDrawHighResReplacement *> *replacements = [NSMutableArray array];

	for (LDrawDirective *directive in directives)
	{
		LDrawHighResPrimitives *newDirectives = [self highResPrimitivesFor:directive axis:axis];
		if (newDirectives.primitives.count > 0)
		{
			[replacements addObject:[[LDrawHighResReplacement alloc] initWithOriginal:directive highRes:newDirectives]];
		}
		else if ([directive isKindOfClass:[LDrawLine class]])
		{
			[unknownLines addObject:directive];
		}
	}

	if (unknownLines.count > 0 && replacements.count > 0)
	{
		NSArray *extras = [self extraReplacementsForUnknownLines:unknownLines usingReplacements:replacements];
		[replacements addObjectsFromArray:extras];
	}

	return replacements;
}


//---------- extraReplacementsForUnknownLines:usingReplacements: ----[static]--
//
// Purpose:		Convert leftover lines that belong to an already-converted
//				primitive, using that primitive's rotation.
//
//------------------------------------------------------------------------------
+ (NSArray<LDrawHighResReplacement *> *)extraReplacementsForUnknownLines:(NSArray *)unknownLines
													   usingReplacements:(NSArray<LDrawHighResReplacement *> *)replacements
{
	NSMutableArray *extraReplacements = [NSMutableArray array];
	NSMutableArray *allNewLines       = [NSMutableArray array];

	for (LDrawLine *line in unknownLines)
	{
		for (LDrawHighResReplacement *replacement in replacements)
		{
			NSMutableArray     *newLines          = [NSMutableArray arrayWithArray:@[[line copy]]];
			LDrawDirective     *originalDirective = replacement.original;
			RotationParameters  rotation          = replacement.highRes.rotation;
			Matrix4             forwardMatrix     = rotation.rotationMatrix;
			Matrix4             oppositeMatrix    = Matrix4Transpose(forwardMatrix);

			if ([self isPrimitive:originalDirective includesLine:line] == NO)
			{
				continue;
			}

			LDrawLine *newLine  = line;
			LDrawLine *newLine2 = line;
			for (int i = 0; i < 2; i++)
			{
				newLine  = [newLine copy];
				newLine2 = [newLine2 copy];

				[self rotateLine:newLine byMatrix:forwardMatrix];
				if ([self isLine:newLine withinLines:allNewLines] == NO)
				{
					[newLines addObject:newLine];
				}

				[self rotateLine:newLine2 byMatrix:oppositeMatrix];
				if ([self isLine:newLine2 withinLines:allNewLines] == NO)
				{
					[newLines addObject:newLine2];
				}
			}

			for (NSInteger i = (NSInteger)newLines.count - 1; i > 0; i--)
			{
				LDrawLine *candidate     = newLines[(NSUInteger)i];
				NSArray   *newDirectives = replacement.highRes.primitives;
				BOOL       isInside      = NO;
				for (LDrawDirective *directive in newDirectives)
				{
					if ([self isPrimitive:directive includesLine:candidate])
					{
						isInside = YES;
						break;
					}
				}
				if (isInside == NO)
				{
					[newLines removeObjectAtIndex:(NSUInteger)i];
				}
			}

			if (newLines.count > 1)
			{
				[allNewLines addObjectsFromArray:newLines];
				LDrawHighResPrimitives *newPrimitives =
					[[LDrawHighResPrimitives alloc] initWithPrimitives:newLines rotation:rotation];
				[extraReplacements addObject:[[LDrawHighResReplacement alloc] initWithOriginal:line
																					   highRes:newPrimitives]];
				break;
			}
		}
	}

	return extraReplacements;
}

@end
