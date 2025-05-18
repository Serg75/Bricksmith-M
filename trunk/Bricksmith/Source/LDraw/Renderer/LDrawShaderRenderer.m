//
//  LDrawShaderRenderer.m
//  Bricksmith
//
//  Created by bsupnik on 11/5/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import "LDrawShaderRendererGPU.h"

#import "LDrawDisplayList.h"
#import "LDrawBDPAllocator.h"
#import "MatrixMathEx.h"
#import "ColorLibrary.h"

//========== set_color4fv ========================================================
//
// Purpose:	Copies an RGBA color, but handles the special ptrs 0L and -1L by 
//			converting them into the 'magic' colors 0,0,0,0 and 1,1,1,0 that 
//			the shader wants.
//
// Notes:	The shader, when it sees alpha = 0, mixes between the attribute-set
//			current and compliment by blending with the red channel: red = 0 is
//			current, red = 1 is compliment.
//
//================================================================================
static void set_color4fv(float * c, float storage[4])
{
	if(c == LDrawRenderCurrentColor)
	{
		storage[0] = 0;
		storage[1] = 0;
		storage[2] = 0;
		storage[3] = 0;
	}
	else if(c == LDrawRenderComplimentColor)
	{
		storage[0] = 1;
		storage[1] = 1;
		storage[2] = 1;
		storage[3] = 0;
	}
	else 
	{
		memcpy(storage,c,sizeof(float)*4);
	}
}//end set_color4fv



//================================================================================
@implementation LDrawShaderRenderer
//================================================================================


//========== pushMatrix: =========================================================
//
// Purpose: accumulate a transform temporarily.  The transform will be 'grabbed'
//			later if a DL is made.
//
// Notes:	our current texture is mapped in _object_ coordinates.  So if we are
//			going to transform our coordinate system AND we have textures active
//			we produce a new texture whose planar projection matches our new
//			coordinates.
//
//			IF we used eye-space texturing this would not be necessary.  But
//			eye space texturing was actually more complex than this case in the
//			shader.
//
//================================================================================
- (void) pushMatrix:(float *)matrix
{
	assert(transform_stack_top < TRANSFORM_STACK_DEPTH);
	memcpy(transform_stack + 16 * transform_stack_top, transform_now, sizeof(transform_now));
	multMatrices(transform_now, transform_stack + 16 * transform_stack_top, matrix);
	++transform_stack_top;

	[self pushTexture:&tex_now];
	if(tex_now.tex_obj)
	{
		// If we have a current texture, transform the tetxure by "matrix".
		// TODO: doc _why_ this works mathematically.
		float	s[4], t[4];
		applyMatrixTranspose(s,matrix,tex_now.plane_s);
		applyMatrixTranspose(t,matrix,tex_now.plane_t);
		memcpy(tex_now.plane_s,s,sizeof(s));
		memcpy(tex_now.plane_t,t,sizeof(t));
	}
	multMatrices(cull_now,mvp,transform_now);
}//end pushMatrix:



//========== checkCull:to: =======================================================
//
// Purpose: cull out bounding boxes that are off-screen.  We transform to clip
//			coordinates and see if the AABB (in screen space) of the original
//			bounding cube (in MV coordinates) is now entirely out of clip bounds.
//
// Notes:	we also look at the screen-space size of the box to decide if we can
//			cull it because it's tiny or replace it with a box.
//
// TODO:	change hard-coded values to be compensated for aspect ratio, etc.
//
//================================================================================
- (int) checkCull:(float *)minXYZ to:(float *)maxXYZ
{
	if (minXYZ[0] > maxXYZ[0] ||
		minXYZ[1] > maxXYZ[1] ||
		minXYZ[2] > maxXYZ[2])		return cull_skip;
		
	float aabb_model[6] = { minXYZ[0], minXYZ[1], minXYZ[2], maxXYZ[0], maxXYZ[1], maxXYZ[2] };
	float aabb_ndc[6];
	
	aabbToClipbox(aabb_model, cull_now, aabb_ndc);
	
	if(aabb_ndc[3] < -1.0f ||
	   aabb_ndc[4] < -1.0f ||
	   aabb_ndc[0] > 1.0f ||
	   aabb_ndc[1] > 1.0f)
	{
		return cull_skip;
	}
	
	int x_pix = (aabb_ndc[3] - aabb_ndc[0]) * 512.0;
	int y_pix = (aabb_ndc[4] - aabb_ndc[1]) * 384.0;
	int dim = MAX(x_pix,y_pix);
	
	if(dim < 1)
		return cull_skip;
	if(dim < 10)
		return cull_box;
	
	return cull_draw;
}//end pushMatrix:to:


//========== drawBoxFrom:to: =====================================================
//
// Purpose: draw an axis-aligned cube of a given size.
//
// Notes:	this routine retains a single unit-cube display list that can be
//			drawn multiple times; the DL system will end up instancing it for us.
//			Because BrickSmith ensures GL resources are never lost, we can just
//			keep the cube statically.
//
//================================================================================
- (void) drawBoxFrom:(float *)minXyz to:(float *)maxXyz
{
	static struct LDrawDL * unit_cube = NULL;
	if(!unit_cube)
	{
		struct LDrawDLBuilder * builder = LDrawDLBuilderCreate();

		#define LBR 0,0,0
		#define RBR 1,0,0
		#define LTR 0,1,0
		#define RTR 1,1,0
		#define LBF 0,0,1
		#define RBF 1,0,1
		#define LTF 0,1,1
		#define RTF 1,1,1

		float top[12] = { LTF,RTF,RTR,LTR };
		float bot[12] = { LBF,LBR,RBR,RBF };
		float lft[12] = { LBR,LBF,LTF,LTR };
		float rgt[12] = { RBF,RBR,RTR,RTF };
		float frt[12] = { LBF,RBF,RTF,LTF };
		float bak[12] = { RBR,LBR,LTR,RTR };
		
		float c[4] = { 0 };
		float n[3] = { 0, 1, 0 };
		
		LDrawDLBuilderAddQuad(builder,top,n,c);
		LDrawDLBuilderAddQuad(builder,bot,n,c);
		LDrawDLBuilderAddQuad(builder,lft,n,c);
		LDrawDLBuilderAddQuad(builder,rgt,n,c);
		LDrawDLBuilderAddQuad(builder,frt,n,c);
		LDrawDLBuilderAddQuad(builder,bak,n,c);

		unit_cube = [self builderFinish:builder];
		
	}
	
	float dim[3] = {
		maxXyz[0] - minXyz[0],
		maxXyz[1] - minXyz[1],
		maxXyz[2] - minXyz[2] };

	float rescale[16] = {
		dim[0], 	0,			0,			0,
		0,			dim[1],		0,			0,
		0,			0,			dim[2],		0,
		minXyz[0],	minXyz[1],	minXyz[2],	1 };

	[self pushMatrix:rescale];
	[self drawDL:unit_cube];
	[self popMatrix];	
				
}//end drawBoxFrom:to:



//========== popMatrix: ==========================================================
//
// Purpose: reset one level of the matrix stack.
//
//================================================================================
- (void) popMatrix
{
	// We always push a texture frame with every matrix frame for now, so that
	// we can re-transform the tex projection.  We simply have 2x the slots
	// in our stacks.
	[self popTexture];
	
	assert(transform_stack_top > 0);
	--transform_stack_top;
	memcpy(transform_now, transform_stack + 16 * transform_stack_top, sizeof(transform_now));
	multMatrices(cull_now,mvp,transform_now);
}//end popMatrix:


//========== pushColor: ==========================================================
//
// Purpose: push a color change onto the stack.  This sets the RGBA for the 
//			current and compliment color for DLs that use the current color.
//
//================================================================================
- (void) pushColor:(float *)color
{
	assert(color_stack_top < COLOR_STACK_DEPTH);
	float * top = color_stack + color_stack_top * 4;
	top[0] = color_now[0];
	top[1] = color_now[1];
	top[2] = color_now[2];
	top[3] = color_now[3];
	++color_stack_top;
	if(color != LDrawRenderCurrentColor)
	{
		if(color == LDrawRenderComplimentColor)
			color = compl_now;
		color_now[0] = color[0];
		color_now[1] = color[1];
		color_now[2] = color[2];
		color_now[3] = color[3];
		complimentColor(color_now, compl_now);
	}
}//end pushColor:


//========== popColor: ===========================================================
//
// Purpose: pop the stack of current colors that has previously been pushed.
//
//================================================================================
- (void) popColor
{
	assert(color_stack_top > 0);
	--color_stack_top;
	float * top = color_stack + color_stack_top * 4;
	color_now[0] = top[0];
	color_now[1] = top[1];
	color_now[2] = top[2];
	color_now[3] = top[3];
	complimentColor(color_now, compl_now);
}//end popColor:


//========== pushTexture: ========================================================
//
// Purpose: change the current texture to a new one, specified by a spec with
//			textures and projection.
//
//================================================================================
- (void) pushTexture:(struct LDrawTextureSpec *) spec;
{
	assert(texture_stack_top < TEXTURE_STACK_DEPTH);
	tex_stack[texture_stack_top] = tex_now;
	++texture_stack_top;
	tex_now = *spec;

	if(dl_stack_top)
		LDrawDLBuilderSetTex(dl_now,&tex_now);
		
}//end pushTexture:


//========== popTexture: =========================================================
//
// Purpose: pop a texture off the stack that was previously pushed.  When the
//			last texture is popped, we go back to being untextured.
//
//================================================================================
- (void) popTexture
{
	assert(texture_stack_top > 0);
	--texture_stack_top;
	tex_now = tex_stack[texture_stack_top];

	if(dl_stack_top)
		LDrawDLBuilderSetTex(dl_now,&tex_now);
		
}//end popTexture:


//========== drawQuad:normal:color: ==============================================
//
// Purpose: Adds one quad to the current display list.
//
// Notes:	This should only be called after a dlBegin has been called; client 
//			code only gets a protocol interface to this API by calling beginDL
//			first.
//
//================================================================================
- (void) drawQuad:(float *) vertices normal:(float *)normal color:(float *)color;
{
	assert(dl_stack_top);
	float c[4];

	set_color4fv(color,c);
	
	LDrawDLBuilderAddQuad(dl_now,vertices,normal,c);

}//end drawQuad:normal:color:


//========== drawTri:normal:color: ===============================================
//
// Purpose: Adds one triangle to the current display list.
//
//================================================================================
- (void) drawTri:(float *) vertices normal:(float *)normal color:(float *)color;
{
	assert(dl_stack_top);

	float c[4];

	set_color4fv(color,c);
	
	LDrawDLBuilderAddTri(dl_now,vertices,normal,c);

}//end drawTri:normal:color:


//========== drawLine:normal:color: ==============================================
//
// Purpose: Adds one line to the current display list.
//
//================================================================================
- (void) drawLine:(float *) vertices normal:(float *)normal color:(float *)color;
{
	assert(dl_stack_top);

	float c[4];

	set_color4fv(color,c);
	
	LDrawDLBuilderAddLine(dl_now,vertices,normal,c);
}//end drawLine:normal:color:


//========== drawConditionalLine:normal:color: ===================================
//
// Purpose: Adds one conditional line to the current display list.
//
//================================================================================
- (void) drawConditionalLine:(float *) vertices normal:(float *)normal color:(float *)color;
{
	assert(dl_stack_top);

	float c[4];

	set_color4fv(color,c);
	
	LDrawDLBuilderAddCondLine(dl_now,vertices,normal,c);

}//end drawConditionalLine:normal:color:


//========== drawDragHandle:withSize: ============================================
//
// Purpose:	This draws one drag handle using the current transform.
//
// Notes:	We don't draw anything - we just grab a list link and stash the
//			drag handle in "global model space" - that is, the space that the 
//			root of all drawing happens, without the local part transform.
//			We do that so that when we pop out all local transforms and draw 
//			later we will be in the right place, but we'll have no local scaling 
//			that could deform our handle.
//
//================================================================================
- (void) drawDragHandle:(float *)xyz withSize:(float)size
{
	struct LDrawDragHandleInstance * dh = (struct LDrawDragHandleInstance *) LDrawBDPAllocate(pool,sizeof(struct LDrawDragHandleInstance));
	
	dh->next = drag_handles;	
	drag_handles = dh;
	dh->size = 7.0;
	
	float handle_local[4] = { xyz[0], xyz[1], xyz[2], 1.0f };
	float handle_world[4];
	
	applyMatrix(handle_world,transform_now, handle_local);
	
	dh->xyz[0] = handle_world[0];
	dh->xyz[1] = handle_world[1];
	dh->xyz[2] = handle_world[2];
	dh->size = size;

}//end drawDragHandle:withSize:


//========== beginDL: ============================================================
//
// Purpose:	This begins accumulating a display list.
//
//================================================================================
- (id<LDrawCollector>) beginDL
{
	assert(dl_stack_top < DL_STACK_DEPTH);
	
	dl_stack[dl_stack_top] = dl_now;
	++dl_stack_top;
	dl_now = LDrawDLBuilderCreate();
	
	return self;

}//end beginDL:


//========== endDL:cleanupFunc: ==================================================
//
// Purpose: close off a DL, returning the display list if there is one.
//
//================================================================================
- (void) endDL:(LDrawDLHandle *) outHandle cleanupFunc:(LDrawDLCleanup_f *)func
{
	assert(dl_stack_top > 0);
	struct LDrawDL * dl = dl_now ? [self builderFinish:dl_now] : NULL;
	--dl_stack_top;
	dl_now = dl_stack[dl_stack_top];
	
	*outHandle = (LDrawDLHandle)dl;
	*func =  (LDrawDLCleanup_f) LDrawDLDestroy;

}//end endDL:cleanupFunc:


//========== drawDL: =============================================================
//
// Purpose:	draw a DL using the current state.  We pass this to our DL session 
//			that sorts out how to actually do tihs.
//
//================================================================================
- (void) drawDL:(LDrawDLHandle)dl
{
	LDrawDLDraw(
		_renderEncoder,
		session,
		(struct LDrawDL *) dl,
		&tex_now,
		color_now,
		compl_now,
		transform_now,
		wire_frame_count > 0);

}//end drawDL:

@end
