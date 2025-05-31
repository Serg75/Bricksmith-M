//==============================================================================
//
// File:		LDrawConditionalLine.m
//
// Purpose:		Conditional-Line command.
//				Draws a line between the first two points, if the projections of 
//				the last two points onto the screen are on the same side of an 
//				imaginary line through the projections of the first two points 
//				onto the screen.
//
//				Line format:
//				5 colour x1 y1 z1 x2 y2 z2 x3 y3 z3 x4 y4 z4 
//
//				where
//
//				* colour is a colour code: 0-15, 16, 24, 32-47, 256-511
//				* x1, y1, z1 is the position of the first point
//				* x2, y2, z2 is the position of the second point
//				* x3, y3, z3 is the position of the third point
//				* x4, y4, z4 is the position of the fourth point 
//
//  Created by Allen Smith on 2/19/05.
//  Copyright (c) 2005. All rights reserved.
//==============================================================================
#import "LDrawConditionalLine.h"

#import "LDrawDragHandle.h"
#import "LDrawUtilities.h"

@implementation LDrawConditionalLine


#pragma mark -
#pragma mark INITIALIZATION
#pragma mark -

//========== initWithLines:inRange:parentGroup: ================================
//
// Purpose:		Returns the LDraw directive based on lineFromFile, a single line 
//				of LDraw code from a file.
//
//				directive should have the format:
//
//				5 colour x1 y1 z1 x2 y2 z2 x3 y3 z3 x4 y4 z4 
//
//==============================================================================
- (id) initWithLines:(NSArray *)lines
			 inRange:(NSRange)range
		 parentGroup:(dispatch_group_t)parentGroup
{
	NSString                *workingLine            = [lines objectAtIndex:range.location];
	NSString                *parsedField            = nil;
	Point3                  workingVertex           = ZeroPoint3;
	LDrawColor				*parsedColor			= nil;
	
	// Our superclass is LDrawLine, which has its own unique syntax, so we can't 
	// call -[super initWithLines:inRange:] 
	self = [self init];
	
	//A malformed part could easily cause a string indexing error, which would 
	// raise an exception. We don't want this to happen here.
	@try
	{
		//Read in the line code and advance past it.
		parsedField = [LDrawUtilities readNextField:  workingLine
										  remainder: &workingLine ];
		//Only attempt to create the part if this is a valid line.
		if([parsedField integerValue] == 5)
		{
			//Read in the color code.
			// (color)
			parsedField = [LDrawUtilities readNextField:  workingLine
											  remainder: &workingLine ];
			parsedColor = [LDrawUtilities parseColorFromField:parsedField];
			[self setLDrawColor:parsedColor];
			
			//Read Vertex 1.
			// (x1)
			parsedField = [LDrawUtilities readNextField:workingLine  remainder: &workingLine ];
			workingVertex.x = [parsedField floatValue];
			// (y1)
			parsedField = [LDrawUtilities readNextField:workingLine  remainder: &workingLine ];
			workingVertex.y = [parsedField floatValue];
			// (z1)
			parsedField = [LDrawUtilities readNextField:workingLine  remainder: &workingLine ];
			workingVertex.z = [parsedField floatValue];
			
			[self setVertex1:workingVertex];
				
			//Read Vertex 2.
			// (x2)
			parsedField = [LDrawUtilities readNextField:workingLine  remainder: &workingLine ];
			workingVertex.x = [parsedField floatValue];
			// (y2)
			parsedField = [LDrawUtilities readNextField:workingLine  remainder: &workingLine ];
			workingVertex.y = [parsedField floatValue];
			// (z2)
			parsedField = [LDrawUtilities readNextField:workingLine  remainder: &workingLine ];
			workingVertex.z = [parsedField floatValue];
			
			[self setVertex2:workingVertex];
			
			//Read Conditonal Vertex 1.
			// (x3)
			parsedField = [LDrawUtilities readNextField:workingLine  remainder: &workingLine ];
			workingVertex.x = [parsedField floatValue];
			// (y3)
			parsedField = [LDrawUtilities readNextField:workingLine  remainder: &workingLine ];
			workingVertex.y = [parsedField floatValue];
			// (z3)
			parsedField = [LDrawUtilities readNextField:workingLine  remainder: &workingLine ];
			workingVertex.z = [parsedField floatValue];
			
			[self setConditionalVertex1:workingVertex];
			
			//Read Conditonal Vertex 2.
			// (x4)
			parsedField = [LDrawUtilities readNextField:workingLine  remainder: &workingLine ];
			workingVertex.x = [parsedField floatValue];
			// (y4)
			parsedField = [LDrawUtilities readNextField:workingLine  remainder: &workingLine ];
			workingVertex.y = [parsedField floatValue];
			// (z4)
			parsedField = [LDrawUtilities readNextField:workingLine  remainder: &workingLine ];
			workingVertex.z = [parsedField floatValue];
			
			[self setConditionalVertex2:workingVertex];
		}
		else
			@throw [NSException exceptionWithName:@"BricksmithParseException" reason:@"Bad conditional line syntax" userInfo:nil];
	}	
	@catch(NSException *exception)
	{
		NSLog(@"the conditional line primitive %@ was fatally invalid", [lines objectAtIndex:range.location]);
		NSLog(@" raised exception %@", [exception name]);
		self = nil;
	}
	
	return self;
	
}//end initWithLines:inRange:


//========== initWithCoder: ====================================================
//
// Purpose:		Reads a representation of this object from the given coder,
//				which is assumed to always be a keyed decoder. This allows us to 
//				read and write LDraw objects as NSData.
//
//==============================================================================
- (id) initWithCoder:(NSCoder *)decoder
{
	const uint8_t *temporary = NULL; //pointer to a temporary buffer returned by the decoder.
	
	self		= [super initWithCoder:decoder];
	
	//Decoding structures is a bit messy.
	temporary	= [decoder decodeBytesForKey:@"conditionalVertex1" returnedLength:NULL];
	memcpy(&conditionalVertex1, temporary, sizeof(Point3));
	
	temporary	= [decoder decodeBytesForKey:@"conditionalVertex2" returnedLength:NULL];
	memcpy(&conditionalVertex2, temporary, sizeof(Point3));
	
	return self;
	
}//end initWithCoder:


//========== encodeWithCoder: ==================================================
//
// Purpose:		Writes a representation of this object to the given coder,
//				which is assumed to always be a keyed decoder. This allows us to 
//				read and write LDraw objects as NSData.
//
//==============================================================================
- (void) encodeWithCoder:(NSCoder *)encoder
{
	[super encodeWithCoder:encoder];
	
	[encoder encodeBytes:(void *)&conditionalVertex1 length:sizeof(Point3) forKey:@"conditionalVertex1"];
	[encoder encodeBytes:(void *)&conditionalVertex2 length:sizeof(Point3) forKey:@"conditionalVertex2"];
	
}//end encodeWithCoder:


//========== copyWithZone: =====================================================
//
// Purpose:		Returns a duplicate of this file.
//
//==============================================================================
- (id) copyWithZone:(NSZone *)zone
{
	LDrawConditionalLine *copied = (LDrawConditionalLine *)[super copyWithZone:zone];
	
	[copied setConditionalVertex1:[self conditionalVertex1]];
	[copied setConditionalVertex2:[self conditionalVertex2]];
	
	return copied;
	
}//end copyWithZone:


#pragma mark -
#pragma mark DIRECTIVES
#pragma mark -

//========== drawSelf: ===========================================================
//
// Purpose:		Draw this directive and its subdirectives by calling APIs on
//				the passed in renderer, then calling drawSelf on children.
//
// Notes:		Cond. lines use this message to get their drag handles drawn if
//				needed.  They do not draw their actual GL primitive because that
//				has already been "collected" by some parent capable of
//				accumulating a mesh.
//
//================================================================================
- (void) drawSelf:(id<LDrawCoreRenderer>)renderer
{
	[self revalCache:DisplayList];
	if(self->hidden == NO)
	{
		if(self->dragHandles)
		{
			for(LDrawDragHandle *handle in self->dragHandles)
			{
				[handle drawSelf:renderer];
			}
		}
	}
}//end drawSelf:


//========== collectSelf: ========================================================
//
// Purpose:		Collect self is called on each directive by its parents to
//				accumulate _mesh_ data into a display list for later drawing.
//				The collector protocol passed in is some object capable of
//				remembering the collectable data.
//
//				Real GL primitives participate by passing their color and
//				geometry data to the collector.
//
//================================================================================
- (void) collectSelf:(id<LDrawCollector>)renderer
{
	[self revalCache:DisplayList];
	if(self->hidden == NO)
	{
		#if !NO_LINE_DRWAING
		float v[12] = {
			vertex1.x, vertex1.y, vertex1.z,
			vertex2.x, vertex2.y, vertex2.z,
			conditionalVertex1.x, conditionalVertex1.y, conditionalVertex1.z,
			conditionalVertex2.x, conditionalVertex2.y, conditionalVertex2.z };
		float n[3] = { 0, -1, 0 };

		if([self->color colorCode] == LDrawCurrentColor)
			[renderer drawConditionalLine:v normal:n color:LDrawRenderCurrentColor];
		else if([self->color colorCode] == LDrawEdgeColor)
			[renderer drawConditionalLine:v normal:n color:LDrawRenderComplimentColor];
		else
		{
			float rgba[4];
			[self->color getColorRGBA:rgba];
			[renderer drawConditionalLine:v normal:n color:rgba];
		}
		#endif
	}
}//end collectSelf:


//========== write =============================================================
//
// Purpose:		Returns a line that can be written out to a file.
//				Line format:
//				5 colour x1 y1 z1 x2 y2 z2 x3 y3 z3 x4 y4 z4 
//
//==============================================================================
- (NSString *) write
{
	return [NSString stringWithFormat:
				@"5 %@ %@ %@ %@ %@ %@ %@ %@ %@ %@ %@ %@ %@",
				[LDrawUtilities outputStringForColor:self->color],
				
				[LDrawUtilities outputStringForFloat:vertex1.x],
				[LDrawUtilities outputStringForFloat:vertex1.y],
				[LDrawUtilities outputStringForFloat:vertex1.z],
				
				[LDrawUtilities outputStringForFloat:vertex2.x],
				[LDrawUtilities outputStringForFloat:vertex2.y],
				[LDrawUtilities outputStringForFloat:vertex2.z],
				
				[LDrawUtilities outputStringForFloat:conditionalVertex1.x],
				[LDrawUtilities outputStringForFloat:conditionalVertex1.y],
				[LDrawUtilities outputStringForFloat:conditionalVertex1.z],
		
				[LDrawUtilities outputStringForFloat:conditionalVertex2.x],
				[LDrawUtilities outputStringForFloat:conditionalVertex2.y],
				[LDrawUtilities outputStringForFloat:conditionalVertex2.z]		
			];
}//end write


#pragma mark -
#pragma mark DISPLAY
#pragma mark -

//========== browsingDescription ===============================================
//
// Purpose:		Returns a representation of the directive as a short string 
//				which can be presented to the user.
//
//==============================================================================
- (NSString *) browsingDescription
{
	return NSLocalizedString(@"ConditionalLine", nil);
	
}//end browsingDescription


//========== iconName ==========================================================
//
// Purpose:		Returns the name of image file used to display this kind of 
//				object, or nil if there is no icon.
//
//==============================================================================
- (NSString *) iconName
{
	return @"ConditionalLinePrimitive";
	
}//end iconName


//========== inspectorClassName ================================================
//
// Purpose:		Returns the name of the class used to inspect this one.
//
//==============================================================================
- (NSString *) inspectorClassName
{
	return @"InspectionConditionalLine";
	
}//end inspectorClassName


#pragma mark -
#pragma mark ACCESSORS
#pragma mark -

//========== conditionalVertex1 ================================================
//
// Purpose:		Returns the triangle's first vertex.
//
//==============================================================================
- (Point3) conditionalVertex1
{
	return conditionalVertex1;
	
}//end conditionalVertex1


//========== conditionalVertex2 ================================================
//
// Purpose:		
//
//==============================================================================
- (Point3) conditionalVertex2
{
	return conditionalVertex2;
	
}//end conditionalVertex2


//========== setconditionalVertex1: ============================================
//
// Purpose:		
//
//==============================================================================
-(void) setConditionalVertex1:(Point3)newVertex
{
	conditionalVertex1 = newVertex;
	
}//end setconditionalVertex1:


//========== setconditionalVertex2: ============================================
//
// Purpose:		
//
//==============================================================================
-(void) setConditionalVertex2:(Point3)newVertex
{
	conditionalVertex2 = newVertex;
	
}//end setconditionalVertex2:


#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//========== moveBy: ===========================================================
//
// Purpose:		Moves the receiver in the specified direction.
//
//==============================================================================
- (void) moveBy:(Vector3)moveVector
{
	//I don't know if this makes any sense.
	conditionalVertex1.x += moveVector.x;
	conditionalVertex1.y += moveVector.y;
	conditionalVertex1.z += moveVector.z;
	
	conditionalVertex2.x += moveVector.x;
	conditionalVertex2.y += moveVector.y;
	conditionalVertex2.z += moveVector.z;
	
}//end moveBy:


#pragma mark -
#pragma mark UTILITIES
#pragma mark -

//==== flattenIntoLines:conditionalLines:triangles:quadrilaterals:other:... ====
//
// Purpose:		Appends the directive into the appropriate container. 
//
//==============================================================================
- (void) flattenIntoLines:(NSMutableArray *)lines
		 conditionalLines:(NSMutableArray *)conditionalLines
				triangles:(NSMutableArray *)triangles
		   quadrilaterals:(NSMutableArray *)quadrilaterals
					other:(NSMutableArray *)everythingElse
			 currentColor:(LDrawColor *)parentColor
		 currentTransform:(Matrix4)transform
		  normalTransform:(Matrix3)normalTransform
				recursive:(BOOL)recursive
{
	// Do not call super to prevent adding this object as plain line

//	[super flattenIntoLines:lines
//		   conditionalLines:conditionalLines
//				  triangles:triangles
//			 quadrilaterals:quadrilaterals
//					  other:everythingElse
//			   currentColor:parentColor
//		   currentTransform:transform
//			normalTransform:normalTransform
//				  recursive:recursive];

	self->vertex1 = V3MulPointByProjMatrix(self->vertex1, transform);
	self->vertex2 = V3MulPointByProjMatrix(self->vertex2, transform);
	self->conditionalVertex1 = V3MulPointByProjMatrix(self->conditionalVertex1, transform);
	self->conditionalVertex2 = V3MulPointByProjMatrix(self->conditionalVertex2, transform);

	[conditionalLines addObject:self];

}//end flattenIntoLines:conditionalLines:triangles:quadrilaterals:other:...


//========== registerUndoActions ===============================================
//
// Purpose:		Registers the undo actions that are unique to this subclass, 
//				not to any superclass.
//
//==============================================================================
- (void) registerUndoActions:(NSUndoManager *)undoManager
{
	[super registerUndoActions:undoManager];
	
	[[undoManager prepareWithInvocationTarget:self] setConditionalVertex2:[self conditionalVertex2]];
	[[undoManager prepareWithInvocationTarget:self] setConditionalVertex1:[self conditionalVertex1]];
	
	[undoManager setActionName:NSLocalizedString(@"UndoAttributesConditionalLine", nil)];
	
}//end registerUndoActions:


@end
