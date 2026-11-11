//==============================================================================
//
//  File:       LDrawDisplayListStubs.m
//  Package:    LDrawTestSupport
//
//  Purpose:    No-op display-list functions that LDrawRenderCore leaves to a
//              backend, so tests can link it without one.
//
//  Info:       A real backend registers a shared part library when it loads,
//              which would change what other tests in the run see.
//
//  Created by Sergey Slobodenyuk on 2026-11-11.
//
//==============================================================================

#import <LDrawRenderCore/LDrawDisplayList.h>
#import <LDrawRenderCore/LDrawDisplayListBuilder.h>

int LDrawDLSupportedPrimitives(void)
{
	return 0;
}


void LDrawDLDestroy(struct LDrawDL *dl)
{
}


void LDrawDLDraw(LDrawRenderEncoder			renderEncoder,
				 struct LDrawDLSession *	session,
				 struct LDrawDL *			dl,
				 struct LDrawTextureSpec *	spec,
				 const float				cur_color[4],
				 const float				cmp_color[4],
				 const float				transform[16],
				 BOOL						is_wire_frame,
				 int						ghost_id,
				 float						ghost_alpha,
				 const float				mark[4])
{
}
