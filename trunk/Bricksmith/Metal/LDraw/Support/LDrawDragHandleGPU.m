//==============================================================================
//
//	LDrawDragHandleGPU.m
//	Bricksmith
//
//	Purpose:	In-scene widget to manipulate a vertex.
//
//	Info:		This category contains Metal-related code.
//
//	Created by Sergey Slobodenyuk on 2023-06-07.
//
//==============================================================================

#import "LDrawDragHandleGPU.h"

// Shared tag to draw the standard drag handle sphere
static GLuint   vaoTag          = 0;
static GLuint   vboTag          = 0;
static GLuint   vboVertexCount  = 0;


@implementation LDrawDragHandle (Metal)

#pragma mark -
#pragma mark DRAWING
#pragma mark -

//========== draw:viewScale:parentColor: =======================================
//
// Purpose:		Draw the drag handle.
//
//==============================================================================
- (void) draw:(NSUInteger)optionsMask viewScale:(float)scaleFactor parentColor:(LDrawColor *)parentColor
{
	float   handleScale = 0.0;
	float   drawRadius  = 0.0;
	
	handleScale = 1.0 / scaleFactor;
	drawRadius  = HandleDiameter/2 * handleScale;
	
	glDisable(GL_TEXTURE_2D);
	glPushMatrix();
	{
		glTranslatef(self->position.x, self->position.y, self->position.z);
		glScalef(drawRadius, drawRadius, drawRadius);
		
		glBindVertexArrayAPPLE(vaoTag);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, vboVertexCount);
		glBindVertexArrayAPPLE(0); // Failing to unbind can cause bizarre crashes if other VAOs are in display lists
	}
	glPopMatrix();
	glEnable(GL_TEXTURE_2D);
	
}//end draw:viewScale:parentColor:


#pragma mark -
#pragma mark ACTIONS
#pragma mark -

//---------- makeSphereWithLongitudinalCount:latitudinalCount: -------[static]--
//
// Purpose:		Populates the shared tag used to draw drag handle spheres.
//
//				The sphere has a radius of 1.
//
//------------------------------------------------------------------------------
+ (void) makeSphereWithLongitudinalCount:(int)longitudeSections
						latitudinalCount:(int)latitudeSections
{
	// Bail if we've already done it.
	if(vboTag != 0)
	{
		return;
	}

	float           latitudeRadians     = (M_PI / latitudeSections); // lat. wraps halfway around sphere
	float           longitudeRadians    = (2*M_PI / longitudeSections); // long. wraps all the way
	int             vertexCount         = 0;
	VBOVertexData   *vertexes           = NULL;
	int             latitudeCount       = 0;
	int             longitudeCount      = 0;
	float           latitude            = 0;
	float           longitude           = 0;
	int             counter             = 0;
	GLfloat         sphereColor[4];
	
	// A pleasant lavender color
	sphereColor[0] = 0.50;
	sphereColor[1] = 0.53;
	sphereColor[2] = 1.00;
	sphereColor[3] = 1.00;
	
	//---------- Generate Sphere -----------------------------------------------
	
	// Each latitude strip begins with two vertexes at the prime meridian, then
	// has two more vertexes per segment thereafter.
	vertexCount = (2 + longitudeSections*2) * latitudeSections;
	vertexes    = calloc(vertexCount, sizeof(VBOVertexData));
	
	// Calculate vertexes for each strip of latitude.
	for(latitudeCount = 0; latitudeCount < latitudeSections; latitudeCount += 1 )
	{
		latitude = (latitudeCount * latitudeRadians);
		
		// Include the prime meridian twice; once to start the strip and once to
		// complete the last triangle of the -1 meridian.
		for(longitudeCount = 0; longitudeCount <= longitudeSections; longitudeCount += 1 )
		{
			longitude = longitudeCount * longitudeRadians;
		
			VBOVertexData   *top    = vertexes + counter;
			VBOVertexData   *bottom = vertexes + counter + 1;
		
			// Top vertex
			top->position[0]    = cos(longitude)*sin(latitude);
			top->position[1]    = sin(longitude)*sin(latitude);
			top->position[2]    = cos(latitude);
			top->normal[0]      = top->position[0]; // it's a unit sphere; the normal is the same as the vertex.
			top->normal[1]      = top->position[1];
			top->normal[2]      = top->position[2];
			memcpy(top->color, sphereColor, sizeof(sphereColor));
			
			counter++;
			
			// Bottom vertex
			bottom->position[0] = cos(longitude)*sin(latitude + latitudeRadians);
			bottom->position[1] = sin(longitude)*sin(latitude + latitudeRadians);
			bottom->position[2] = cos(latitude + latitudeRadians);
			bottom->normal[0]   = bottom->position[0];
			bottom->normal[1]   = bottom->position[1];
			bottom->normal[2]   = bottom->position[2];
			memcpy(bottom->color, sphereColor, sizeof(sphereColor));
			
			counter++;
		}
	}

	//---------- Optimize ------------------------------------------------------
	
//	vboVertexCount = counter;
//	
//	glGenBuffers(1, &vboTag);
//	glBindBuffer(GL_ARRAY_BUFFER, vboTag);
//	
//	glBufferData(GL_ARRAY_BUFFER, vboVertexCount * sizeof(VBOVertexData), vertexes, GL_STATIC_DRAW);
//	free(vertexes);
//	glBindBuffer(GL_ARRAY_BUFFER, 0);
//	
//	// Encapsulate in a VAO
//	glGenVertexArraysAPPLE(1, &vaoTag);
//	glBindVertexArrayAPPLE(vaoTag);
//	glEnableClientState(GL_VERTEX_ARRAY);
//	glEnableClientState(GL_NORMAL_ARRAY);
//	glEnableClientState(GL_COLOR_ARRAY);
//	glBindBuffer(GL_ARRAY_BUFFER, vboTag);
//	glVertexPointer(3, GL_FLOAT, sizeof(VBOVertexData), NULL);
//	glNormalPointer(GL_FLOAT,    sizeof(VBOVertexData), (GLvoid*)(sizeof(float)*3));
//	glColorPointer(4, GL_FLOAT,  sizeof(VBOVertexData), (GLvoid*)(sizeof(float)*3 + sizeof(float)*3) );
//	glBindVertexArrayAPPLE(0);
//	glBindBuffer(GL_ARRAY_BUFFER, 0);
}


@end
