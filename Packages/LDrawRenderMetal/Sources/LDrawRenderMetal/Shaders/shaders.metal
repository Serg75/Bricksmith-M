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

// A vertex of a part's face or thin line, placed and colored.
static VertexOutput partVertex(VertexInput					in,
							   device const InstanceInput	*inst,
							   constant VertexUniform&		uni,
							   constant TexturePlaneData&	texGen,
							   float						ghost_alpha,
							   uint							iid)
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

vertex VertexOutput vertexShader(VertexInput				in		    [[stage_in]],
								 device const InstanceInput	*inst	    [[buffer(BufferIndexPerInstanceData)]],
								 constant VertexUniform&	uni		    [[buffer(BufferIndexVertexUniforms)]],
								 constant TexturePlaneData&	texGen	    [[buffer(BufferIndexTexturePlane)]],
								 constant float&			ghost_alpha [[buffer(BufferIndexGhostAlpha)]],
								 uint						iid		    [[instance_id]])
{
	return partVertex(in, inst, uni, texGen, ghost_alpha, iid);
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

// The color of a face or line lit by the two lights, under its texture.
static float4 shadedColor(float4 color, float3 normal_eye, float2 tex_coord,
						  constant FragmentUniform& uni, texture2d<float> tex)
{
	float3 normal = normalize(normal_eye);

	float4 final_color = color;
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

	float4 tex_color = tex.sample(linear_sampler, tex_coord);

	float4 frag_color;
	frag_color.rgb = ((float3)mix(final_color.rgb, (float3)tex_color.rgb, (float)tex_color.a));
	frag_color.a = color.a;

	return frag_color;
}

fragment FragmentOutput fragmentShader(FragmentInput in [[stage_in]],
									   constant FragmentUniform& uni [[buffer(BufferIndexFragmentUniforms)]],
									   texture2d<float> tex [[texture(0)]])
{
	FragmentOutput out;

	out.frag_color = shadedColor(in.color, in.normal_eye, in.tex_coord, uni, tex);

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

// A corner of a line's quad, so the line can be wider than a pixel. A line
// takes six vertices, and reads its ends through the index buffer. The part's
// edge color becomes its outline color. depthAcrossWidth is how much the depth
// changes along the line over one line width.
static LineVertexOutput wideLineVertex(device const PackedVertex	*verts,
									   device const InstanceInput	*inst,
									   constant VertexUniform&		uni,
									   float						ghost_alpha,
									   device const uint			*indices,
									   constant LineUniform&		line,
									   uint							vid,
									   uint							iid,
									   thread float&				depthAcrossWidth)
{
	LineVertexOutput out;

	depthAcrossWidth = 0.0;

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
	float	depthChange		= abs(clip1.z / clip1.w - clip0.z / clip0.w);

	depthAcrossWidth = depthChange / max(length(along), 1e-6) * line.width;

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
	float depthAcrossWidth;

	return wideLineVertex(verts, inst, uni, ghost_alpha, indices, line, vid, iid, depthAcrossWidth);
}

// Outlines are not lit, so they look the same from every side.
fragment float4 wideLineFragmentShader(LineVertexOutput in [[stage_in]])
{
	return in.color;
}


// MARK: - Transparency -


// One transparent fragment in its pixel's list.
struct TransparentFragment {
	uint		color;			// RGBA, 8 bits each
	atomic_uint	depth_mask;		// depth in the top 24 bits, line bits and samples below
	uint		next;			// the pixel's next fragment, or TransparentListEnd
};

static_assert(sizeof(TransparentFragment) == TransparentFragmentSize, "the renderer sizes the buffer by this");

// Where transparent fragments go.
struct TransparentLists {
	device atomic_uint				*heads;
	device TransparentFragment		*fragments;
	device atomic_uint				*counters;
	constant TransparencyUniform	*uniform;
};

constant float TRANSPARENT_DEPTH_STEPS	= 16777215.0;

// Fragments that follow each other this close in depth, in steps, are taken
// as one surface, such as the faces where two parts touch. They are ordered by
// color, so the surface does not speckle.
constant uint TRANSPARENT_DEPTH_TIE		= 16;

// The byte below the depth holds the samples a fragment covers in its low 4
// bits. A line marks itself in the top bit, so the blend can tell lines that
// lie on each other from faces that do, and keeps in the 3 bits below it how
// far apart in depth another line on it may be.
constant uint TRANSPARENT_SAMPLE_BITS	= 0x0Fu;
constant uint TRANSPARENT_LINE_BITS		= 0xF0u;
constant uint TRANSPARENT_LINE_BIT		= 0x80u;
constant uint TRANSPARENT_LEEWAY_SHIFT	= 4;
constant uint TRANSPARENT_LEEWAY_MAX	= 7;

// The line bits for a line that another line may be this many depth steps
// from and still lie on it. The leeway is kept as a tie times a power of 4, at
// least as much as asked.
static uint lineBits(float leewaySteps)
{
	float	ties	= clamp(leewaySteps / TRANSPARENT_DEPTH_TIE, 1.0, 65536.0);
	uint	power	= min(uint(ceil(log2(ties) * 0.5)), TRANSPARENT_LEEWAY_MAX);

	return TRANSPARENT_LINE_BIT | (power << TRANSPARENT_LEEWAY_SHIFT);
}

// The depth steps another line may be from a line with these bits.
static uint lineLeeway(uint bits)
{
	return TRANSPARENT_DEPTH_TIE << (2 * ((bits >> TRANSPARENT_LEEWAY_SHIFT) & TRANSPARENT_LEEWAY_MAX));
}

// Adds a transparent color at one sample to its pixel's list, with the line
// bits of a line in lineFlags or 0 for a face. The shader runs once for each sample of a
// face that nothing opaque hides, and those runs get the same color and
// depth, so they share one fragment and each adds its sample to it.
static void addTransparentFragment(TransparentLists lists, float4 color, uint lineFlags, float depth, float2 position,
								   uint sample)
{
	uint2	pixel		= uint2(position);
	uint	headIndex	= pixel.y * lists.uniform->width + pixel.x;
	uint	packed		= pack_float_to_unorm4x8(saturate(color));
	uint	steps		= uint(saturate(depth) * TRANSPARENT_DEPTH_STEPS);
	uint	depthBits	= steps << 8;
	uint	sampleBit	= 1u << sample;
	uint	head		= atomic_load_explicit(&lists.heads[headIndex], memory_order_relaxed);
	uint	mine		= TransparentListEnd;

	// Another sample of the same face may have just put its fragment first.
	// Their depths can round one step apart. A fragment that already has this
	// sample is another face, even one of the same color touching this one.
	for (int attempt = 0; attempt < 16; ++attempt)
	{
		if (head != TransparentListEnd)
		{
			device TransparentFragment	&first		= lists.fragments[head];
			uint						firstDepth	= atomic_load_explicit(&first.depth_mask, memory_order_relaxed);
			uint						firstSteps	= firstDepth >> 8;

			if (	first.color == packed
				&&	(firstDepth & TRANSPARENT_LINE_BITS) == lineFlags
				&&	(firstDepth & sampleBit) == 0
				&&	max(firstSteps, steps) - min(firstSteps, steps) <= 1)
			{
				atomic_fetch_or_explicit(&first.depth_mask, sampleBit, memory_order_relaxed);
				return;
			}
		}

		if (mine == TransparentListEnd)
		{
			// Neighboring tiles of 8 pixels use different counters.
			uint2	tile	= pixel / 8;
			uint	counter	= (tile.x * 7 + tile.y * 13) % TransparentCounterCount;
			uint	taken	= atomic_fetch_add_explicit(&lists.counters[counter * TransparentCounterStride], 1,
														memory_order_relaxed);

			// Out of room. The renderer reads the counters and makes more for
			// the next frame.
			if (taken >= lists.uniform->slice)
				return;

			mine = counter * lists.uniform->slice + taken;
			lists.fragments[mine].color = packed;
			atomic_store_explicit(&lists.fragments[mine].depth_mask, depthBits | lineFlags | sampleBit,
								  memory_order_relaxed);
		}

		lists.fragments[mine].next = head;

		if (atomic_compare_exchange_weak_explicit(&lists.heads[headIndex], &head, mine,
												  memory_order_relaxed, memory_order_relaxed))
			return;
	}

	// Out of tries, which a compare and exchange may run into for no reason.
	// An exchange cannot fail, so the fragment still goes in at the head.
	lists.fragments[mine].next = atomic_exchange_explicit(&lists.heads[headIndex], mine, memory_order_relaxed);
}

// A face or thin line of a transparent part, with what the lists need too.
struct TransparentVertexOutput {
	float4	position [[position]];
	float4	color;
	float2	tex_coord;
	float3	normal_eye;
	float2	clip_zw [[center_perspective]];		// for the depth at the pixel's center
};

vertex TransparentVertexOutput transparentVertexShader(
	VertexInput					in			[[stage_in]],
	device const InstanceInput	*inst		[[buffer(BufferIndexPerInstanceData)]],
	constant VertexUniform&		uni			[[buffer(BufferIndexVertexUniforms)]],
	constant TexturePlaneData&	texGen		[[buffer(BufferIndexTexturePlane)]],
	constant float&				ghost_alpha	[[buffer(BufferIndexGhostAlpha)]],
	uint						iid			[[instance_id]])
{
	VertexOutput			part	= partVertex(in, inst, uni, texGen, ghost_alpha, iid);
	TransparentVertexOutput	out;

	out.position	= part.position;
	out.color		= part.color;
	out.tex_coord	= part.tex_coord;
	out.normal_eye	= part.normal_eye;
	out.clip_zw		= part.position.zw;

	return out;
}

// A wide line of a transparent part, with its depth for the lists.
struct TransparentLineVertexOutput {
	float4	position [[position]];
	float4	color;
	float2	clip_zw [[center_perspective]];		// for the depth at the pixel's center
	uint	line_flags [[flat]];
};

// How many line widths along a line another line at a corner may reach, where
// the ends of their quads overlap. More than one for corners sharper than
// square.
constant float TRANSPARENT_CORNER_WIDTHS = 2.0;

vertex TransparentLineVertexOutput transparentWideLineVertexShader(
	device const PackedVertex	*verts		[[buffer(BufferIndexInstanceInvariantData)]],
	device const InstanceInput	*inst		[[buffer(BufferIndexPerInstanceData)]],
	constant VertexUniform&		uni			[[buffer(BufferIndexVertexUniforms)]],
	constant float&				ghost_alpha	[[buffer(BufferIndexGhostAlpha)]],
	device const uint			*indices	[[buffer(BufferIndexLineIndices)]],
	constant LineUniform&		line		[[buffer(BufferIndexLineUniforms)]],
	uint						vid			[[vertex_id]],
	uint						iid			[[instance_id]])
{
	float						depthAcrossWidth;
	LineVertexOutput			corner	= wideLineVertex(verts, inst, uni, ghost_alpha, indices, line, vid, iid,
														 depthAcrossWidth);
	TransparentLineVertexOutput	out;
	float						leeway	= depthAcrossWidth * TRANSPARENT_CORNER_WIDTHS * TRANSPARENT_DEPTH_STEPS;

	out.position	= corner.position;
	out.color		= corner.color;
	out.clip_zw		= corner.position.zw;
	out.line_flags	= lineBits(leeway);

	return out;
}

// How far a face sorts behind the lines on its edges. More than a tie.
constant float TRANSPARENT_FACE_DEPTH_OFFSET = 2.0 * TRANSPARENT_DEPTH_TIE / TRANSPARENT_DEPTH_STEPS;

// The depth at the pixel's center, from the clip position the rasterizer
// interpolates there. z and w are both perspective-correct, so z / w is what
// [[position]].z is at the center. The runs for the samples of one face then
// get the same depth, wherever the GPU puts their position. Derivatives would
// not do: where an opaque edge culls part of a pixel's quad, they are not
// defined.
static float depthAtPixelCenter(float2 clipZW)
{
	return clipZW.x / clipZW.y;
}

// Puts a transparent face or thin line into the lists instead of blending it.
// It runs per sample, and only where nothing opaque is in front.
[[early_fragment_tests]]
fragment void transparentFragmentShader(
	TransparentVertexOutput			in			[[stage_in]],
	uint							sample		[[sample_id]],
	constant FragmentUniform&		uni			[[buffer(BufferIndexFragmentUniforms)]],
	device atomic_uint				*heads		[[buffer(BufferIndexTransparentHeads), raster_order_group(0)]],
	device TransparentFragment		*fragments	[[buffer(BufferIndexTransparentFragments), raster_order_group(0)]],
	device atomic_uint				*counters	[[buffer(BufferIndexTransparentCounters)]],
	constant TransparencyUniform&	uniform		[[buffer(BufferIndexTransparencyUniforms)]],
	constant uint&					thinLines	[[buffer(BufferIndexTransparentThinLines)]],
	texture2d<float>				tex			[[texture(0)]])
{
	TransparentLists	lists	= { heads, fragments, counters, &uniform };
	float4				color	= shadedColor(in.color, in.normal_eye, in.tex_coord, uni, tex);
	bool				isLine	= thinLines != 0;
	float				behind	= isLine ? 0.0 : TRANSPARENT_FACE_DEPTH_OFFSET;
	uint				flags	= isLine ? lineBits(0.0) : 0u;		// a thin line gets the least leeway

	addTransparentFragment(lists, color, flags, depthAtPixelCenter(in.clip_zw) + behind, in.position.xy, sample);
}

// Puts a transparent wide line into the lists instead of blending it.
[[early_fragment_tests]]
fragment void transparentWideLineFragmentShader(
	TransparentLineVertexOutput		in			[[stage_in]],
	uint							sample		[[sample_id]],
	device atomic_uint				*heads		[[buffer(BufferIndexTransparentHeads), raster_order_group(0)]],
	device TransparentFragment		*fragments	[[buffer(BufferIndexTransparentFragments), raster_order_group(0)]],
	device atomic_uint				*counters	[[buffer(BufferIndexTransparentCounters)]],
	constant TransparencyUniform&	uniform		[[buffer(BufferIndexTransparencyUniforms)]])
{
	TransparentLists lists = { heads, fragments, counters, &uniform };

	addTransparentFragment(lists, in.color, in.line_flags, depthAtPixelCenter(in.clip_zw), in.position.xy, sample);
}

// Empties the lists of the pixels in one tile, in the render pass before the
// transparent parts are drawn. A tile's later fragments come after it. In a
// tile dispatch the grid position is the pixel in the render target.
kernel void clearTransparentLists(
	ushort2							position	[[thread_position_in_grid]],
	device uint						*heads		[[buffer(BufferIndexTransparentHeads)]],
	constant TransparencyUniform&	uniform		[[buffer(BufferIndexTransparencyUniforms)]])
{
	if (position.x < uniform.width && position.y < uniform.height)
		heads[position.y * uniform.width + position.x] = TransparentListEnd;
}

struct ResolveVertexOutput {
	float4	position [[position]];
};

// A triangle over the whole surface.
vertex ResolveVertexOutput transparencyResolveVertexShader(uint vid [[vertex_id]])
{
	ResolveVertexOutput	out;
	float2				corner	= float2((vid << 1) & 2, vid & 2);

	out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);

	return out;
}

// The most fragments a sample blends in their own order. They stay in
// registers. The ones behind them are blended as one layer of their average
// color.
constant uint TRANSPARENT_SORTED_MAX	= 16;
// Marks a free place among the sorted fragments. A depth and line bits
// without the samples are never this.
constant uint TRANSPARENT_SORTED_FREE	= 0xFFFFFFFFu;
// A list is not followed further, so a broken one cannot hang the GPU.
constant uint TRANSPARENT_LIST_MAX		= 4096;
// The lines last blended that a line is checked against, to blend a line
// lying on one of them only once.
constant uint TRANSPARENT_RECENT_LINES	= 4;

// Whether fragment a goes before fragment b: nearer, or as near and of a
// smaller color. x is the depth, y the color.
static bool isBefore(uint2 a, uint2 b)
{
	return a.x < b.x || (a.x == b.x && a.y < b.y);
}

// Whether two sorted fragments are lines of one color that lie on each other:
// no further apart in depth than the leeway of either.
static bool isSameLine(uint2 a, uint2 b)
{
	uint aDepth = a.x >> 8;
	uint bDepth = b.x >> 8;

	return (	a.y == b.y
			&&	(a.x & b.x & TRANSPARENT_LINE_BIT) != 0
			&&	max(aDepth, bDepth) - min(aDepth, bDepth) <= max(lineLeeway(a.x), lineLeeway(b.x)));
}

// Blends the transparent fragments over one sample onto what is drawn there,
// as a premultiplied color: the nearest first, front to back, with the layer
// of the farthest behind them. It runs per sample, so a sample a fragment does
// not cover keeps what is drawn there. Lines that lie on each other count
// once.
fragment float4 transparencyResolveFragmentShader(
	ResolveVertexOutput				in			[[stage_in]],
	uint							sample		[[sample_id]],
	device atomic_uint				*heads		[[buffer(BufferIndexTransparentHeads), raster_order_group(0)]],
	device TransparentFragment		*fragments	[[buffer(BufferIndexTransparentFragments), raster_order_group(0)]],
	constant TransparencyUniform&	uniform		[[buffer(BufferIndexTransparencyUniforms)]])
{
	uint2	pixel		= uint2(in.position.xy);
	uint	index		= atomic_load_explicit(&heads[pixel.y * uniform.width + pixel.x], memory_order_relaxed);
	uint	sampleBit	= 1u << sample;

	if (index == TransparentListEnd)
		return float4(0.0);

	// The nearest fragments, nearest first, and free places after them. x is
	// the depth, y the color.
	uint2	sorted[TRANSPARENT_SORTED_MAX];

	// The layer behind them: the colors times their alphas with the alphas in
	// w, and how much light gets through it.
	float4	far			= float4(0.0);
	float	farLight	= 1.0;

	for (uint i = 0; i < TRANSPARENT_SORTED_MAX; ++i)
		sorted[i] = uint2(TRANSPARENT_SORTED_FREE, 0);

	for (uint visited = 0; index != TransparentListEnd && visited < TRANSPARENT_LIST_MAX; ++visited)
	{
		uint2 entry = uint2(atomic_load_explicit(&fragments[index].depth_mask, memory_order_relaxed),
							fragments[index].color);

		index = fragments[index].next;

		if ((entry.x & sampleBit) == 0)
			continue;

		entry.x &= ~TRANSPARENT_SAMPLE_BITS;

		// The fragment takes its place and the ones behind it move back one.
		// Every place is visited, so the array stays in registers.
		#pragma unroll
		for (uint i = 0; i < TRANSPARENT_SORTED_MAX; ++i)
		{
			bool	inFront	= sorted[i].x == TRANSPARENT_SORTED_FREE || isBefore(entry, sorted[i]);
			uint2	kept	= inFront ? entry : sorted[i];

			entry		= inFront ? sorted[i] : entry;
			sorted[i]	= kept;
		}

		// The one pushed off the end goes behind.
		if (entry.x != TRANSPARENT_SORTED_FREE)
		{
			float4 farColor = unpack_unorm4x8_to_float(entry.y);

			far			+= float4(farColor.rgb * farColor.a, farColor.a);
			farLight	*= 1.0 - farColor.a;
		}
	}

	// Fragments within a tie of the first one of their run are one surface, and
	// go by color. A run spans no more than a tie, so a chain of close surfaces
	// does not become one. Which run each is in is worked out from the depths
	// first, so the order does not depend on the order the fragments came in.
	uint run[TRANSPARENT_SORTED_MAX];
	uint runDepth = sorted[0].x >> 8;

	run[0] = 0;

	#pragma unroll
	for (uint i = 1; i < TRANSPARENT_SORTED_MAX; ++i)
	{
		uint	depth	= sorted[i].x >> 8;
		bool	tied	= (	sorted[i].x != TRANSPARENT_SORTED_FREE
						 &&	depth - runDepth <= TRANSPARENT_DEPTH_TIE);

		run[i]		= tied ? run[i - 1] : run[i - 1] + 1;
		runDepth	= tied ? runDepth : depth;
	}

	for (uint pass = 1; pass < TRANSPARENT_SORTED_MAX; ++pass)
	{
		bool swapped = false;

		#pragma unroll
		for (uint i = 1; i < TRANSPARENT_SORTED_MAX; ++i)
		{
			if (run[i] == run[i - 1] && sorted[i].y < sorted[i - 1].y)
			{
				uint2 later = sorted[i];

				sorted[i]		= sorted[i - 1];
				sorted[i - 1]	= later;
				swapped			= true;
			}
		}

		if (swapped == false)
			break;
	}

	float3	color	= float3(0.0);
	float	light	= 1.0;		// how much of what is behind gets through
	uint2	recentLines[TRANSPARENT_RECENT_LINES];

	for (uint k = 0; k < TRANSPARENT_RECENT_LINES; ++k)
		recentLines[k] = uint2(0);

	#pragma unroll
	for (uint i = 0; i < TRANSPARENT_SORTED_MAX; ++i)
	{
		if (sorted[i].x == TRANSPARENT_SORTED_FREE)
			break;

		// A line on a nearer line of the same color, such as where the ends
		// of two wide lines overlap at a corner, is blended once, as the depth
		// test does for opaque lines. It is checked against the lines last
		// blended, so faces between them do not matter. Faces never match.
		if ((sorted[i].x & TRANSPARENT_LINE_BIT) != 0)
		{
			bool repeated = false;

			#pragma unroll
			for (uint k = 0; k < TRANSPARENT_RECENT_LINES; ++k)
				repeated = repeated || isSameLine(sorted[i], recentLines[k]);

			if (repeated)
				continue;

			#pragma unroll
			for (uint k = TRANSPARENT_RECENT_LINES - 1; k > 0; --k)
				recentLines[k] = recentLines[k - 1];

			recentLines[0] = sorted[i];
		}

		float4 fragmentColor = unpack_unorm4x8_to_float(sorted[i].y);

		color += light * fragmentColor.a * fragmentColor.rgb;
		light *= 1.0 - fragmentColor.a;
	}

	if (far.w > 0.0)
	{
		color += light * (1.0 - farLight) * far.rgb / far.w;
		light *= farLight;
	}

	return float4(color, 1.0 - light);
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
