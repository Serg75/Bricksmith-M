//==============================================================================
//
//	LDrawShaderRendererGPU.m
//	Bricksmith
//
//	Purpose:	an implementation of the LDrawCoreRenderer API using GL shaders.
//
//				The renderer maintains a stack view of OpenGL state; as
//				directives push their info to the renderer, containing LDraw
//				parts push and pop state to affect the child parts that are
//				drawn via the depth-first traversal.
//
//	Info:		This category contains OpenGL-related code.
//
//	Created by Sergey Slobodenyuk on 2023-05-10.
//
//==============================================================================

#import "LDrawShaderRendererGPU.h"

#import "ColorLibrary.h"
#import "LDrawBDPAllocator.h"
#import "LDrawShaderLoader.h"
#import "LDrawDisplayList.h"
#import "MatrixMathEx.h"

// This list of attribute names matches the text of the GLSL attribute declarations -
// and its order must match the attr_position...array in the .h.
static const char * attribs[] = {
	"position",
	"normal",
	"color",
	"transform_x",
	"transform_y",
	"transform_z",
	"transform_w",
	"color_current",
	"color_compliment",
	"texture_mix", NULL };


@implementation LDrawShaderRenderer (OpenGL)

//========== init: ===============================================================
//
// Purpose: initialize our renderer, and grab all basic OpenGL state we need.
//
//================================================================================
- (id) initWithScale:(float)initial_scale
		   modelView:(GLfloat *)mv_matrix
		  projection:(GLfloat *)proj_matrix
{
	pool = LDrawBDPCreate();
	// Build our shader if it doesn't exist yet.  For now, just stash the GL
	// object statically.
	static GLuint prog = 0;
	if(!prog)
	{
		prog = LDrawLoadShaderFromResource(@"test.glsl", attribs);
		GLint u_tex = glGetUniformLocation(prog,"u_tex");
		glUseProgram(prog);
		
		// This matches up texture unit 0 with the sampler in the shader.
		glUniform1i(u_tex, 0);
	}
	else
		glUseProgram(prog);
	
	self = [super init];
	
	self->scale = initial_scale;
	
	[[[ColorLibrary sharedColorLibrary] colorForCode:LDrawCurrentColor] getColorRGBA:color_now];
	glVertexAttrib1f(attr_texture_mix,0.0f);
	complimentColor(color_now, compl_now);
	
	// Set up the basic transform to be identity - our transform is on top of the MVP matrix.
	memset(transform_now,0,sizeof(transform_now));
	transform_now[0] = transform_now[5] = transform_now[10] = transform_now[15] = 1.0f;
	
	// "Rip" the MVP matrix from OpenGL.  (TODO: does LDraw just have this info?)
	// We use this for culling.
	multMatrices(mvp,proj_matrix,mv_matrix);
	memcpy(cull_now,mvp,sizeof(mvp));
	
	// Create a DL session to match our lifetime.
	session = LDrawDLSessionCreate(mv_matrix);
	
	// Set up GL state for attribute drawing, not the fixed function drawing we used to do.
	glEnableVertexAttribArray(attr_position);
	glEnableVertexAttribArray(attr_normal);
	glEnableVertexAttribArray(attr_color);
	glDisableClientState(GL_COLOR_ARRAY);
	glDisableClientState(GL_NORMAL_ARRAY);
	glDisableClientState(GL_VERTEX_ARRAY);
	
	drag_handles = NULL;
	
	return self;
}//end init:


// Suppress warning "Category is implementing a method which will also be implemented by its primary class."
// These two methods have declaration only without implementation in the primary class.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

//========== pushWireFrame: ======================================================
//
// Purpose: push a change to wire frame mode.  This is nested - when the last
//			"wire frame" is popped, we are no longer wire frame.
//
//================================================================================
- (void) pushWireFrame
{
	if(wire_frame_count++ == 0)
		glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
		
}//end pushWireFrame:


//========== popWireFrame: =======================================================
//
// Purpose: undo a previous wire frame command - the push and pops must be
//			balanced.
//
//================================================================================
- (void) popWireFrame
{
	if(--wire_frame_count == 0)
		glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);

}//end popWireFrame:

#pragma clang diagnostic pop


//========== drawDragHandle:withSize: ============================================
//
// Purpose:	Draw a drag handle - for realzies this time
//
// Notes:	This routine builds a one-off sphere VBO as needed.  BrickSmith
//			guarantees that we never lose our shared group of GL contexts, so we
//			don't have to worry about the last context containing the VBO going
//			away.
//
//			The vertex format for the sphere handle is just pure vertices - since
//			the draw routine sets up its own VAO with its own internal format,
//			there's no need to depend on or conform to vertex formats for the rest
//			of the drawing system.
//
//================================================================================
- (void) drawDragHandleImm:(GLfloat *)xyz withSize:(GLfloat)size
{
	static GLuint   vaoTag          = 0;
	static GLuint   vboTag          = 0;
	static GLuint   vboVertexCount  = 0;

	if(vaoTag == 0)
	{
		// Bail if we've already done it.

		int latitudeSections = 8;
		int longitudeSections = 8;
		
		float           latitudeRadians     = (M_PI / latitudeSections); // lat. wraps halfway around sphere
		float           longitudeRadians    = (2*M_PI / longitudeSections); // long. wraps all the way
		int             vertexCount         = 0;
		GLfloat			*vertexes           = NULL;
		int             latitudeCount       = 0;
		int             longitudeCount      = 0;
		float           latitude            = 0;
		float           longitude           = 0;
		
		//---------- Generate Sphere -----------------------------------------------
		
		// Each latitude strip begins with two vertexes at the prime meridian, then
		// has two more vertexes per segment thereafter.
		vertexCount = (2 + longitudeSections*2) * latitudeSections;

		glGenBuffers(1, &vboTag);
		glBindBuffer(GL_ARRAY_BUFFER, vboTag);
		glBufferData(GL_ARRAY_BUFFER, vertexCount * 3 * sizeof(GLfloat), NULL, GL_STATIC_DRAW);
		vertexes = (GLfloat *) glMapBuffer(GL_ARRAY_BUFFER, GL_WRITE_ONLY);
		
		// Calculate vertexes for each strip of latitude.
		for(latitudeCount = 0; latitudeCount < latitudeSections; latitudeCount += 1 )
		{
			latitude = (latitudeCount * latitudeRadians);
			
			// Include the prime meridian twice; once to start the strip and once to
			// complete the last triangle of the -1 meridian.
			for(longitudeCount = 0; longitudeCount <= longitudeSections; longitudeCount += 1 )
			{
				longitude = longitudeCount * longitudeRadians;
			
				// Ben says: when we are "pushing" vertices into a GL_WRITE_ONLY mapped buffer, we should really
				// never read back from the vertices that we read to - the memory we are writing to often has funky
				// properties like being uncached which make it expensive to do anything other than what we said we'd
				// do (and we said: we are only going to write to them).
				//
				// Mind you it's moot in this case since we only need to write vertices.
			
				// Top vertex
				*vertexes++ =cos(longitude)*sin(latitude);
				*vertexes++ =sin(longitude)*sin(latitude);
				*vertexes++ =cos(latitude);
			
				// Bottom vertex
				*vertexes++ = cos(longitude)*sin(latitude + latitudeRadians);
				*vertexes++ = sin(longitude)*sin(latitude + latitudeRadians);
				*vertexes++ = cos(latitude + latitudeRadians);
			}
		}

		glUnmapBuffer(GL_ARRAY_BUFFER);
		glBindBuffer(GL_ARRAY_BUFFER, 0);

		//---------- Optimize ------------------------------------------------------
		
		vboVertexCount = vertexCount;
		
		// Encapsulate in a VAO
		glGenVertexArraysAPPLE(1, &vaoTag);
		glBindVertexArrayAPPLE(vaoTag);
		glBindBuffer(GL_ARRAY_BUFFER, vboTag);
		glEnableVertexAttribArray(attr_position);
		glEnableVertexAttribArray(attr_normal);
		// Normal and vertex use the same data - in a unit sphere the normals are the vertices!
		glVertexAttribPointer(attr_position, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(GLfloat), NULL);
		glVertexAttribPointer(attr_normal, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(GLfloat), NULL);
		// The sphere color is constant - no need to get it from per-vertex data.
		glBindVertexArrayAPPLE(0);
		glBindBuffer(GL_ARRAY_BUFFER, 0);
		
	}
	
	glDisable(GL_TEXTURE_2D);
	
	int i;
	for(i = 0; i < 4; ++i)
		glVertexAttrib4f(attr_transform_x+i,transform_now[i],transform_now[4+i],transform_now[8+i],transform_now[12+i]);

	glVertexAttrib4f(attr_color,0.50,0.53,1.00,1.00);		// Nice lavendar color for the whole sphere.
	
	glBindVertexArrayAPPLE(vaoTag);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, vboVertexCount);
	glBindVertexArrayAPPLE(0); // Failing to unbind can cause bizarre crashes if other VAOs are in display lists

	glEnable(GL_TEXTURE_2D);

}//end drawDragHandleImm:

- (struct LDrawDL *)builderFinish:(struct LDrawDLBuilder *)ctx
{
	return LDrawDLBuilderFinish(ctx);
}

//========== dealloc: ============================================================
//
// Purpose: Clean up our state.  Note that this "triggers" the draw from our
//			display list session that has stored up some of our draw calls.
//
//================================================================================
- (void) dealloc
{
	struct LDrawDragHandleInstance * dh;
	LDrawDLSessionDrawAndDestroy(session);
	session = nil;
	
	// Go through and draw the drag handles...
	
	for(dh = drag_handles; dh != NULL; dh = dh->next)
	{
		GLfloat s = dh->size / self->scale;
		GLfloat m[16] = { s, 0, 0, 0, 0, s, 0, 0, 0, 0, s, 0, dh->xyz[0], dh->xyz[1],dh->xyz[2], 1.0 };
		
		[self pushMatrix:m];
		[self drawDragHandleImm:dh->xyz withSize:dh->size];
		[self popMatrix];
	}
	
	// Put back OGL state to what LDraw usually has.
	glUseProgram(0);
	
	int a;
	for(a = 0; a < attr_count; ++a)
		glDisableVertexAttribArray(a);
	glEnableClientState(GL_COLOR_ARRAY);
	glEnableClientState(GL_NORMAL_ARRAY);
	glEnableClientState(GL_VERTEX_ARRAY);
	
	LDrawBDPDestroy(pool);
	
}//end dealloc:


@end
