//
//	shaders.metal
//	LDrawRenderMetal
//
//	Created by Sergey Slobodenyuk on 2023-06-19.
//

#include <metal_stdlib>

using namespace metal;

// Include header shared between C code and .metal files. Canonical copy lives
// in the package public headers so CPU and GPU cannot drift apart.
#import "../include/LDrawRenderMetal/MetalCommonDefinitions.h"

// Vertex shader

struct VertexInput {
	float4	position	[[attribute(VertexAttributePosition)]];
	float3	normal		[[attribute(VertexAttributeNormal)]];
	float4	color		[[attribute(VertexAttributeColor)]];
};

struct VertexOutput {
	float4	position [[position]];
	float4	color;
	float4	position_eye;
	float3	normal_eye;
	float	tex_mix;
	float2	tex_coord;
};

vertex VertexOutput vertexShader(VertexInput				in		    [[stage_in]],
								 device const InstanceInput	*inst	    [[buffer(BufferIndexPerInstanceData)]],
								 constant VertexUniform&	uni		    [[buffer(BufferIndexVertexUniforms)]],
								 constant TexturePlaneData&	texGen	    [[buffer(BufferIndexTexturePlane)]],
								 constant float&			ghost_alpha [[buffer(BufferIndexGhostAlpha)]],
								 uint						iid		    [[instance_id]])
{
	VertexOutput out;

	float4 pos_obj;
	pos_obj.x = dot(in.position, inst[iid].transform_x);
	pos_obj.y = dot(in.position, inst[iid].transform_y);
	pos_obj.z = dot(in.position, inst[iid].transform_z);
	pos_obj.w = dot(in.position, inst[iid].transform_w);

	float3 norm_obj;
	norm_obj.x = dot(in.normal, inst[iid].transform_x.xyz);
	norm_obj.y = dot(in.normal, inst[iid].transform_y.xyz);
	norm_obj.z = dot(in.normal, inst[iid].transform_z.xyz);

	out.normal_eye = normalize(uni.normal_matrix * norm_obj);
	float4 eye_pos = uni.model_view_matrix * pos_obj;

	out.position = uni.projection_matrix * eye_pos;
	out.position_eye = eye_pos;

	float4 col = in.color;
	if (in.color.a == 0.0) {
		col = mix(inst[iid].color_current, inst[iid].color_complement, in.color.r);
	};

	// The ghost scale goes on here rather than on color_current, so that it
	// reaches a color baked into the mesh as well as a meta one.
	col.a *= ghost_alpha;

	out.color.a = col.a;
	out.color.rgb = col.rgb;

	if (in.normal.x == 0.0 && in.normal.y == 0.0 && in.normal.z == 0.0) {
		out.color = col;
	};

	float2 tex_coord;
	tex_coord.x = dot(texGen.plane_s, in.position);
	tex_coord.y = dot(texGen.plane_t, in.position);
	out.tex_coord = float2(tex_coord.x, 1.0 - tex_coord.y);

	return out;
}


// Fragment shader

struct FragmentInput {
	float4	color;
	float2	tex_coord;
	float3	normal_eye;
};

struct FragmentOutput {
	float4	frag_color;
};

fragment FragmentOutput fragmentShader(FragmentInput in [[stage_in]],
									   constant FragmentUniform& uni [[buffer(BufferIndexFragmentUniforms)]],
									   texture2d<float> tex [[texture(0)]])
{
	FragmentOutput out;

	float3 normal = normalize(in.normal_eye);

	float4 final_color = in.color;
	float light_source_0_k = dot(normal, uni.light_source[0].position.xyz);
	float light_source_1_k = dot(normal, uni.light_source[1].position.xyz);
	final_color.rgb *=
		(uni.light_source[0].diffuse.rgb * max(0.0, light_source_0_k) +
		 uni.light_source[1].diffuse.rgb * max(0.0, light_source_1_k) +
		 uni.light_model.ambient.rgb);

	constexpr sampler linear_sampler(mip_filter::linear,
									 mag_filter::linear,
									 min_filter::linear,
									 s_address::clamp_to_edge,
									 t_address::clamp_to_edge);

	float4 tex_color = tex.sample(linear_sampler, in.tex_coord);

	float4 frag_color;
	frag_color.rgb = ((float3)mix(final_color.rgb, (float3)tex_color.rgb, (float)tex_color.a));
	frag_color.a = in.color.a;

	out.frag_color = frag_color;

	return out;
}


// MARK: - Outlines -


// One vertex as the display list stores it.
struct PackedVertex {
	packed_float3	position;
	packed_float3	normal;
	packed_float4	color;
};

struct LineVertexOutput {
	float4	position [[position]];
	float4	color;
};

// The six corners of a line's quad: x picks the end, y the side.
constant float2 wideLineCorners[6] = {
	float2(0, -1), float2(0, 1), float2(1, -1),
	float2(1, -1), float2(0, 1), float2(1, 1)
};

// Where a vertex of the part is, in clip space.
static float4 clipPosition(PackedVertex point, device const InstanceInput& inst, constant VertexUniform& uni)
{
	float4 p		= float4(float3(point.position), 1.0);
	float4 pos_obj	= float4(dot(p, inst.transform_x), dot(p, inst.transform_y),
							 dot(p, inst.transform_z), dot(p, inst.transform_w));

	return uni.projection_matrix * (uni.model_view_matrix * pos_obj);
}

// A conditional line shows when its control points fall on the same side of
// it on screen. Worked out without dividing by w, so it also holds for a
// control point behind the eye.
static bool controlPointsOnOneSide(float4 end0, float4 end1, float4 control0, float4 control1)
{
	float3 plane = cross(end0.xyw, end1.xyw);

	return dot(plane, control0.xyw) * dot(plane, control1.xyw) > 0.0;
}

// A color darker than this gets a lighter outline. Black, blue, red and dark
// gray do; light gray, yellow and white do not.
constant float OUTLINE_DARK_BRIGHTNESS	= 0.5;

// How much of the color a darker outline keeps, from a color of no brightness
// to white. A lighter color keeps more, so white gets a mid gray outline and
// light gray a darker one.
constant float OUTLINE_KEEP_DARK		= 0.4;
constant float OUTLINE_KEEP_LIGHT		= 0.7;

// How far a lighter outline goes toward white, from a color of no brightness
// to one just under OUTLINE_DARK_BRIGHTNESS. Black needs it to show at all,
// while dark gray with much of it would look like light gray.
constant float OUTLINE_LIGHTEN_DARK		= 0.26;
constant float OUTLINE_LIGHTEN_LIGHT	= 0.15;

// The outline of a part of this color, as printed instructions draw it: a
// darker shade of it, or a lighter one for dark colors.
static float3 outlineColor(float3 color)
{
	float brightness = dot(color, float3(0.30, 0.59, 0.11));

	if (brightness < OUTLINE_DARK_BRIGHTNESS) {
		float lighten = mix(OUTLINE_LIGHTEN_DARK, OUTLINE_LIGHTEN_LIGHT, brightness / OUTLINE_DARK_BRIGHTNESS);

		return mix(color, float3(1.0), lighten);
	}

	return color * mix(OUTLINE_KEEP_DARK, OUTLINE_KEEP_LIGHT, brightness);
}

// Draws each line as a quad, so it can be wider than a pixel. A line takes six
// vertices, and reads its ends through the index buffer. The part's edge color
// becomes its outline color.
vertex LineVertexOutput wideLineVertexShader(
	device const PackedVertex	*verts		[[buffer(BufferIndexInstanceInvariantData)]],
	device const InstanceInput	*inst		[[buffer(BufferIndexPerInstanceData)]],
	constant VertexUniform&		uni			[[buffer(BufferIndexVertexUniforms)]],
	constant float&				ghost_alpha	[[buffer(BufferIndexGhostAlpha)]],
	device const uint			*indices	[[buffer(BufferIndexLineIndices)]],
	constant LineUniform&		line		[[buffer(BufferIndexLineUniforms)]],
	uint						vid			[[vertex_id]],
	uint						iid			[[instance_id]])
{
	LineVertexOutput out;

	device const InstanceInput&	part	= inst[iid];
	uint						first	= (vid / 6) * (line.conditional ? 4 : 2);
	float2						corner	= wideLineCorners[vid % 6];
	PackedVertex				end0	= verts[indices[first]];
	PackedVertex				end1	= verts[indices[first + 1]];
	float4						color	= float4(end0.color);

	// The same meta colors as a face: 0 is the part's own color, 1 its edge.
	if (color.a == 0.0) {
		float4 current = part.color_current;

		color = float4(mix(current.rgb, outlineColor(current.rgb), color.r), current.a);
	}

	color.a		*= ghost_alpha;
	out.color	 = color;

	float4	clip0	= clipPosition(end0, part, uni);
	float4	clip1	= clipPosition(end1, part, uni);
	bool	shows	= clip0.z >= 0.0 || clip1.z >= 0.0;

	if (shows && line.conditional) {
		shows = controlPointsOnOneSide(clip0, clip1,
									   clipPosition(verts[indices[first + 2]], part, uni),
									   clipPosition(verts[indices[first + 3]], part, uni));
	}

	// All six corners on one point draw nothing.
	if (shows == false) {
		out.position = float4(0.0, 0.0, 0.0, 1.0);
		return out;
	}

	// The line is cut at the near plane. Clipping drops what is in front of it
	// anyway, and an end behind the eye cannot be divided by its w.
	if (clip0.z < 0.0) {
		clip0 = mix(clip0, clip1, clip0.z / (clip0.z - clip1.z));
	}
	if (clip1.z < 0.0) {
		clip1 = mix(clip1, clip0, clip1.z / (clip1.z - clip0.z));
	}

	float2	halfViewport	= line.viewport_size * 0.5;
	float2	along			= (clip1.xy / clip1.w - clip0.xy / clip0.w) * halfViewport;

	along = (length(along) > 1e-6) ? normalize(along) : float2(1.0, 0.0);

	// Square ends, so the lines at a corner meet without a notch. The faces
	// beside the line are pushed back by a depth bias, so they do not cover
	// half of it.
	float2	across	= float2(-along.y, along.x);
	float2	offset	= (across * corner.y + along * (corner.x * 2.0 - 1.0)) * line.width * 0.5;
	float4	clip	= (corner.x == 0.0) ? clip0 : clip1;

	clip.xy		+= offset / halfViewport * clip.w;
	out.position = clip;

	return out;
}

// Outlines are not lit, so they look the same from every side.
fragment float4 wideLineFragmentShader(LineVertexOutput in [[stage_in]])
{
	return in.color;
}


// MARK: - Drag Handle -


struct DragHandleVertexOutput {
	float4	position [[position]];
	float3	normal;
};

vertex DragHandleVertexOutput vertexDragHandle(const device float3 *vertices [[buffer(0)]],
											   constant InstanceInput *inst [[buffer(BufferIndexPerInstanceData)]],
											   constant VertexUniform& uni [[buffer(BufferIndexVertexUniforms)]],
											   unsigned int vid [[vertex_id]],
											   uint iid [[instance_id]])
{
	DragHandleVertexOutput out;

	float4 position = float4(vertices[vid], 1.0);
	float4 pos_obj;
	pos_obj.x = dot(position, inst[iid].transform_x);
	pos_obj.y = dot(position, inst[iid].transform_y);
	pos_obj.z = dot(position, inst[iid].transform_z);
	pos_obj.w = dot(position, inst[iid].transform_w);

	float4 eye_pos = uni.model_view_matrix * pos_obj;
	out.position = uni.projection_matrix * eye_pos;
	out.normal = normalize((uni.model_view_matrix * float4(vertices[vid], 0.0)).xyz);
	return out;
}

fragment float4 fragmentDragHandle(const DragHandleVertexOutput in [[stage_in]],
								   constant float4 &color [[buffer(0)]]) {
	return color;
}


// MARK: - Marquee selection box -


struct VertexOut2D {
	float4 position [[position]];
};

vertex VertexOut2D vertex_shader_2D(const device float2 *in [[buffer(0)]],
									constant float2 &viewportSize [[buffer(1)]],
									unsigned int vid [[vertex_id]]) {
	VertexOut2D out;
	out.position = float4(in[vid] / (viewportSize * 0.5) - 1.0, 0.0, 1.0);
	return out;
}


fragment float4 fragment_shader_2D() {
	return float4(0.0, 1.0, 0.5, 0.5);
}
