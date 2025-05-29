//
//	shaders.metal
//	Bricksmith-Metal
//
//	Created by Sergey Slobodenyuk on 2023-06-19.
//

#include <metal_stdlib>

using namespace metal;

// Include header shared between C code and .metal files.
#import "MetalCommonDefinitions.h"

// Vertex shader

struct VertexInput {
	float4	position	[[attribute(VertexAttributePosition)]];
	float3	normal		[[attribute(VertexAttributeNormal)]];
	float4	color		[[attribute(VertexAttributeColor)]];
};

struct InstanceInput {
	float4	transform_x;
	float4	transform_y;
	float4	transform_z;
	float4	transform_w;
	float4	color_current;
	float4	color_compliment;
};

struct VertexOutput {
	float4	position [[position]];
	float4	color;
	float4	position_eye;
	float3	normal_eye;
	float	tex_mix;
	float2	tex_coord;
};

struct VertexUniform {
	float4x4	model_view_matrix;
	float4x4	projection_matrix;
	float3x3	normal_matrix;
};

struct TexturePlaneData {
	float4		plane_s;
	float4		plane_t;
};

vertex VertexOutput vertexShader(VertexInput				in		[[stage_in]],
								 device const InstanceInput	*inst	[[buffer(BufferIndexPerInstanceData)]],
								 constant VertexUniform&	uni		[[buffer(BufferIndexVertexUniforms)]],
								 constant TexturePlaneData&	texGen	[[buffer(BufferIndexTexturePlane)]],
								 ushort						iid		[[instance_id]])
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
		col = mix(inst[iid].color_current, inst[iid].color_compliment, in.color.r);
	};
	out.color.a = col.a;
	out.color.rgb = col.rgb;

	if (in.normal.x == 0.0 && in.normal.y == 0.0 && in.normal.z == 0.0) {
		out.color = col;
	};

	float2 tex_coord;
	tex_coord.x = dot(texGen.plane_s, in.position);
	tex_coord.y = dot(texGen.plane_t, in.position);

	out.tex_coord = tex_coord;

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

struct LightingUniforms {
	float3	light_position_0;
	float3	light_position_1;
	float3	ambient_color;
	float3	diffuse_color;
	float3	specular_color;
	float	shininess;
};

struct LightSourceParameters {
	float4	diffuse;
	float4	position;
};

struct LightModelParameters {
	float4	ambient;
};

struct FragmentUniform {
	LightSourceParameters	light_source[2];
	LightModelParameters	light_model;
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
									 min_filter::linear);

	float4 tex_color = tex.sample(linear_sampler, float2(in.tex_coord.x, (1.0 - in.tex_coord.y)));

	float4 frag_color;
	frag_color.rgb = ((float3)mix(final_color.rgb, (float3)tex_color.rgb, (float)tex_color.a));
	frag_color.a = in.color.a;

	out.frag_color = frag_color;

	return out;
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
											   ushort iid [[instance_id]])
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
