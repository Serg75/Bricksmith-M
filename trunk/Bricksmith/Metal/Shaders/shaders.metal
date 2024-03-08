//
//	shaders.metal
//	Bricksmith-Metal
//
//	Created by Sergey Slobodenyuk on 2023-06-19.
//

#include <metal_stdlib>
using namespace metal;


// Vertex shader

struct VertexInput {
	float4	position [[attribute(0)]];
	float3	normal [[attribute(1)]];
	float4	color [[attribute(2)]];
	float4	transform_x [[attribute(3)]];
	float4	transform_y [[attribute(4)]];
	float4	transform_z [[attribute(5)]];
	float4	transform_w [[attribute(6)]];
	float4	color_current [[attribute(7)]];
	float4	color_compliment [[attribute(8)]];
	float	texture_mix [[attribute(9)]];
};

struct VertexOutput {
	float4	front_color;
	float4	position [[position]];
	float2	tex_coord;
	float	tex_mix;
	float3	normal_eye;
	float4	position_eye;
};

struct VertexUniform {
	float4		object_plane_t[16];
	float4		object_plane_s[16];
	float3x3	normal_matrix;
	float4x4	projection_matrix;
	float4x4	model_view_matrix;
};

vertex VertexOutput VertexShader(VertexInput in [[stage_in]],
								 constant VertexUniform& uni [[buffer(0)]])
{
	VertexOutput out;

	float4 pos_obj = 0;
	pos_obj.x = dot(in.position, in.transform_x);
	pos_obj.y = dot(in.position, in.transform_y);
	pos_obj.z = dot(in.position, in.transform_z);
	pos_obj.w = dot(in.position, in.transform_w);

	float3 norm_obj = 0;
	norm_obj.x = dot(in.normal, in.transform_x.xyz);
	norm_obj.y = dot(in.normal, in.transform_y.xyz);
	norm_obj.z = dot(in.normal, in.transform_z.xyz);

	out.normal_eye = normalize(uni.normal_matrix * norm_obj);
	float4 eye_pos = uni.model_view_matrix * pos_obj;

	out.position = uni.projection_matrix * eye_pos;
	out.position_eye = eye_pos;

	float4 col = in.color;
	if (in.color.a == 0.0) {
		col = mix (in.color_current, in.color_compliment, in.color.r);
	};
	out.front_color.a = col.a;
	out.front_color.rgb = col.rgb;

	if (in.normal.x == 0.0 && in.normal.y == 0.0 && in.normal.z == 0.0) {
		out.front_color = col;
	};

	float2 tex_coord = 0;
	tex_coord.x = dot (uni.object_plane_s[0], in.position);
	tex_coord.y = dot (uni.object_plane_t[0], in.position);

	out.tex_coord = tex_coord;
	out.tex_mix = in.texture_mix;
	out.position.z = (out.position.z + out.position.w) / 2.0f;

	return out;
}


// Fragment shader

struct FragmentInput {
	float4	color;
	float2	tex_coord;
	float	tex_mix;
	float3	normal_eye;
};

struct FragmentOutput {
	float4	frag_color;
};

struct LightSourceParameters {
	float4	diffuse;
	float4	position;
};

struct LightModelParameters {
	float4	ambient;
};

struct FragmentUniform {
	LightSourceParameters	light_source[8];
	LightModelParameters	light_model;
};

fragment FragmentOutput FragmentShader(FragmentInput in [[stage_in]],
									   constant FragmentUniform& uni [[buffer(0)]],
									   texture2d<float> tex [[texture(0)]],
									   sampler smpl [[sampler(0)]])
{
	FragmentOutput out;

	float3 normal = normalize(in.normal_eye);

	float4 final_color = in.color;
	final_color.rgb *=
		(uni.light_source[0].diffuse.rgb * max(0.0, dot(normal, uni.light_source[0].position.xyz)) +
		 uni.light_source[1].diffuse.rgb * max(0.0, dot(normal, uni.light_source[1].position.xyz)) +
		 uni.light_model.ambient.rgb);

	float4 tex_color = tex.sample(smpl, float2((in.tex_coord).x, (1.0 - (in.tex_coord).y)));

	float4 tmp = 0;
	tmp.rgb = ((float3)mix(final_color.rgb, (float3)tex_color.rgb, (float)tex_color.a));
	tmp.a = in.color.a;

	out.frag_color = ((float4)mix(final_color, (float4)tmp, in.tex_mix));

	return out;
}
