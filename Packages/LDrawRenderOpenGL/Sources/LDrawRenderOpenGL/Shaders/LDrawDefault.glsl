#line 1

varying vec2	tex_coord;
varying float	tex_mix;

varying vec3	normal_eye;

//	Toward the eye, for reflections.
varying vec3	view_eye;

//	Where a point is in the grid of cubes the flakes of a metal paint sit in.
varying vec3	flake_position;

//	The finish of a face, one of the Material values the shader loader defines.
//	The same for every vertex of a face.
varying float	material_v;

//	A part's mark: RGB and a style, the same for every vertex of the part.
varying vec4	mark_v;

#if VSHADER

	attribute	vec4	position;
	attribute	vec3	normal;
	attribute	vec4	color;

	attribute	vec4	transform_x;
	attribute	vec4	transform_y;
	attribute	vec4	transform_z;
	attribute	vec4	transform_w;
	attribute	vec4	color_current;
	attribute	vec4	color_complement;
	attribute	float	texture_mix;

	//	Scales the alpha of whatever color this vertex ends up with, so a
	//	ghosted part goes translucent whether that color came from the meta
	//	colors or was baked into the mesh.  1 for everything but a ghost.
	attribute	float	ghost_alpha;

	//	Marks a part that breaks the parts limit: RGB and an
	//	LDrawRenderMarkStyle. Zero for no mark.
	attribute	vec4	mark;

	//	How far the direction to the eye leans, as a tangent, at the ends of
	//	the longer side of a view with no perspective.
	const float FLAT_VIEW_SPREAD = 0.15;

	//	The flake grid is fixed to the part. It is turned, so that a part's
	//	flat faces do not lie in its planes, where a face would flicker
	//	between two cubes.
	const mat3 FLAKE_GRID = mat3(vec3(2.0, 3.0, 6.0) / 7.0,
								 vec3(3.0, -6.0, 2.0) / 7.0,
								 vec3(6.0, 2.0, -3.0) / 7.0);

	void main (void)
	{
		vec4	pos_obj = vec4(
								dot(position, transform_x),
								dot(position, transform_y),
								dot(position, transform_z),
								dot(position, transform_w));

		vec3	norm_obj = vec3(
								dot(normal, transform_x.xyz),
								dot(normal, transform_y.xyz),
								dot(normal, transform_z.xyz));
	
				normal_eye = normalize(gl_NormalMatrix * norm_obj);
		vec4	eye_pos = gl_ModelViewMatrix * pos_obj;
		gl_Position = gl_ProjectionMatrix * eye_pos;

		//	In the part's own coordinates, which stay small enough for
		//	cubeNoise.
		flake_position = FLAKE_GRID * position.xyz;

		//	Toward the eye, for reflections. With no perspective the eye is
		//	taken to be near the middle of the view, so a flat mirror is not one
		//	flat color.
		vec2	halfView	= 1.0 / vec2(gl_ProjectionMatrix[0][0], gl_ProjectionMatrix[1][1]);
		vec2	lean		= gl_Position.xy * halfView / max(abs(halfView.x), abs(halfView.y));

		if (gl_ProjectionMatrix[3][3] == 0.0)
			view_eye = -eye_pos.xyz;
		else
			view_eye = vec3(-FLAT_VIEW_SPREAD * lean, 1.0);

		vec4	col = color;
		if (col.a == 0.0)
		{
			col = mix(color_current,color_complement, col.r);
		}

		//	The alpha carries the material too, as 2 * material + alpha.
		material_v = floor(col.a * 0.5);
		col.a -= 2.0 * material_v;

		//	Green = 1 in a meta color marks a line in the part's color, or the
		//	edge color. Neither has a finish.
		if (color.a == 0.0 && color.g == 1.0)
			material_v = MaterialPlain;

		//	A face with no normal has nothing to reflect.
		if (normal == vec3(0))
			material_v = MaterialPlain;

		//	A vertex in the edge color is on an edge line. A marked part's
		//	edges take the mark's color.
		if (color.a == 0.0 && color.r == 1.0 && mark.w > 0.0)
			col.rgb = mark.rgb;

		//	The ghost scale goes on here rather than on color_current, so that it
		//	reaches a color baked into the mesh as well as a meta one.
		col.a *= ghost_alpha;

		gl_FrontColor = col;
		mark_v = mark;

			vec4	eye_plane_s = gl_ObjectPlaneS[0];
			vec4	eye_plane_t = gl_ObjectPlaneT[0];
				 
		tex_coord = vec2(
					dot(eye_plane_s, position),
					dot(eye_plane_t, position));
					
		tex_mix = texture_mix;
	}

#endif

#if FSHADER

	uniform sampler2D	u_tex;

	//	How wide a flake is drawn, in pixels.
	const float FLAKE_PIXELS = 1.5;

	//	A value from 0 to 1 for a cube of the flake grid.
	float cubeNoise(vec3 cube)
	{
		vec3 mixed = fract(cube * 0.1031);

		mixed += dot(mixed, mixed.zyx + 31.32);
		return fract((mixed.x + mixed.y) * mixed.z);
	}

	//	A value from 0 to 1 that differs from flake to flake, with flakes about
	//	FLAKE_PIXELS wide. across and down are how the place changes over one
	//	pixel.
	float flakeNoise(vec3 position, vec3 across, vec3 down)
	{
		//	Cube sizes are powers of 2. Two sizes blend, so a zoom fades
		//	flakes in and out and none appears at once.
		float	pixelSize	= sqrt(length(across) * length(down));
		float	level		= log2(max(pixelSize, 1e-6) * FLAKE_PIXELS);
		float	perUnit		= exp2(-floor(level));		// cubes along one unit of the grid
		float	blend		= fract(level);
		float	noise		= 0.0;

		//	The mean of four places in the pixel, so a flake slides from
		//	pixel to pixel when the model moves, and does not jump.
		for (int i = 0; i < 4; i++)
		{
			float	alongAcross	= (i == 1 || i == 3) ? 0.25 : -0.25;
			float	alongDown	= (i >= 2) ? 0.25 : -0.25;
			vec3	place		= position + alongAcross * across + alongDown * down;
			vec3	smallCube	= floor(place * perUnit);
			vec3	largeCube	= floor(smallCube * 0.5);

			noise += 0.25 * mix(cubeNoise(smallCube), cubeNoise(largeCube), blend);
		}

		//	A blend of two values is nearer the middle, so it is spread out
		//	again.
		float	spread	= inversesqrt(blend * blend + (1.0 - blend) * (1.0 - blend));

		return clamp(0.5 + (noise - 0.5) * spread, 0.0, 1.0);
	}

	//	The studio that metallic parts reflect is bright above. Its floor is
	//	dark far away and lighter below.
	const float	STUDIO_FLOOR_FAR	= 0.20;
	const float	STUDIO_FLOOR		= 0.60;
	const float	STUDIO_WALL			= 0.75;
	const float	STUDIO_CEILING		= 0.25;		// added to the wall, straight up

	//	A round lamp up and to the left. Its size is 1 less the cosine of its
	//	angle.
	const vec3	STUDIO_KEY_DIRECTION	= vec3(-0.503, 0.704, 0.503);
	const float	STUDIO_KEY_SIZE			= 0.2;
	const float	STUDIO_KEY_LIGHT		= 0.8;

	//	A narrow band of light to the right. It draws a bright line down a
	//	chrome cylinder.
	const float	STUDIO_STRIP_X			= 0.85;
	const float	STUDIO_STRIP_HALF_WIDTH	= 0.07;
	const float	STUDIO_STRIP_LIGHT		= 1.2;

	//	A wide lamp behind the eye, so a face toward the eye is lit as plain
	//	parts are.
	const float	STUDIO_FILL_LIGHT		= 0.5;
	const float	STUDIO_FILL_SHARPNESS	= 3.0;

	//	How soft a mirror's reflection is, and how much softer the roughest
	//	surface's is. The blur grows with the square of the roughness.
	const float	MIRROR_BLUR	= 0.015;
	const float	ROUGH_BLUR	= 1.4142;

	//	How much of a lamp shows this far inside its edge. A blurred lamp is
	//	wider and dimmer.
	float lampLight(float inside, float size, float blur)
	{
		return smoothstep(-blur, blur, inside) * size / (size + blur);
	}

	//	The light the studio sends from a direction, as soft as the blur.
	float studioLight(vec3 direction, float blur)
	{
		float	above		= smoothstep(-blur, blur, direction.y);
		float	floorLight	= mix(STUDIO_FLOOR, STUDIO_FLOOR_FAR, exp(4.0 * min(0.0, direction.y)));
		float	light		= mix(floorLight, STUDIO_WALL, above) + STUDIO_CEILING * max(0.0, direction.y);

		float	inKey		= dot(direction, STUDIO_KEY_DIRECTION) - (1.0 - STUDIO_KEY_SIZE);
		float	inStrip		= STUDIO_STRIP_HALF_WIDTH - abs(direction.x - STUDIO_STRIP_X);

		light += STUDIO_KEY_LIGHT * lampLight(inKey, STUDIO_KEY_SIZE, blur);
		light += STUDIO_STRIP_LIGHT * lampLight(inStrip, STUDIO_STRIP_HALF_WIDTH, blur);
		light += STUDIO_FILL_LIGHT * exp(STUDIO_FILL_SHARPNESS * (direction.z - 1.0));

		return light;
	}

	//	How much of a finish is metal, how rough it is, and how much the flakes
	//	in it make the reflection differ from place to place.
	vec3 metalRoughnessAndFlakes(float material)
	{
		//	Rounded, since the value comes through a varying.
		float finish = floor(material + 0.5);

		if (finish == MaterialChrome)			return vec3(1.0, 0.05, 0.0);
		if (finish == MaterialMetal)			return vec3(0.9, 0.30, 0.17);
		if (finish == MaterialPearlescent)		return vec3(0.8, 0.28, 0.0);
		if (finish == MaterialSatinMetallic)	return vec3(0.6, 0.55, 0.10);
		if (finish == MaterialMatteMetallic)	return vec3(0.6, 0.65, 0.17);

		return vec3(0.0, 1.0, 0.0);
	}

	//	A lit face of a metallic finish: less of the plain lit color, and the
	//	studio reflected in the finish's own color.
	vec3 metallicColor(vec3 color, vec3 lit, vec3 normal, vec3 finish, float flake)
	{
		float	metal	= finish.x;
		float	rough	= finish.y;
		float	flakes	= 1.0 + finish.z * (2.0 * flake - 1.0);
		vec3	view	= normalize(view_eye);

		//	Both sides of a face reflect.
		if (dot(normal, view) < 0.0)
			normal = -normal;

		float	facing		= clamp(dot(normal, view), 0.0, 1.0);
		vec3	mirrored	= reflect(-view, normal);
		float	blur		= MIRROR_BLUR + ROUGH_BLUR * rough * rough;

		//	Metal reflects in its own color, and anything reflects more at a
		//	glancing angle.
		vec3	straight	= mix(vec3(0.04), color, metal);
		vec3	glancing	= max(vec3(1.0 - rough), straight);
		vec3	reflectance	= mix(straight, glancing, pow(1.0 - facing, 5.0));

		return lit * (1.0 - metal) + reflectance * studioLight(mirrored, blur) * flakes;
	}

	//	How marked faces look. The stripes are in pixels, so they look the
	//	same at any zoom.
	const float MARK_STRIPE_PERIOD		= 14.0;
	const float MARK_STRIPE_WIDTH		= 5.0;
	const float MARK_STRIPE_STRENGTH	= 0.8;
	const float MARK_TINT_STRENGTH		= 0.55;

	//	A marked face at this pixel: in a stripe, or tinted, in the mark's
	//	color. Styles 1 and 2 are stripes leaning opposite ways, 3 a tint, and
	//	4, an outline, leaves faces alone.
	vec4 markedColor(vec4 color)
	{
		float style = floor(mark_v.w + 0.5);

		if (style == 1.0 || style == 2.0)
		{
			float along = (style == 1.0) ? gl_FragCoord.x + gl_FragCoord.y : gl_FragCoord.x - gl_FragCoord.y;
			float phase = along - MARK_STRIPE_PERIOD * floor(along / MARK_STRIPE_PERIOD);

			if (phase < MARK_STRIPE_WIDTH)
				color.rgb = mix(color.rgb, mark_v.rgb, MARK_STRIPE_STRENGTH);
		}
		else if (style == 3.0)
			color.rgb = mix(color.rgb, mark_v.rgb, MARK_TINT_STRENGTH);

		return color;
	}

	void main()
	{
		vec3 normal = normalize(normal_eye);
		vec4 final_color = gl_Color;
		final_color.rgb *= 			
				(gl_LightSource[0].diffuse.rgb * max(0.0,dot(normal, gl_LightSource[0].position.xyz)) +
				 gl_LightSource[1].diffuse.rgb * max(0.0,dot(normal, gl_LightSource[1].position.xyz)) +
				 gl_LightModel.ambient.rgb);

		//	How the place in the flake grid changes over one pixel. Taken
		//	here, for every fragment, because that is not known inside a
		//	branch.
		vec3 flake_across	= dFdx(flake_position);
		vec3 flake_down		= dFdy(flake_position);

		if (material_v > MaterialPlain + 0.5)
		{
			vec3	finish	= metalRoughnessAndFlakes(material_v);
			float	flake	= 0.5;

			//	A finish with no flakes skips the noise, which is the costly
			//	part.
			if (finish.z > 0.0)
				flake = flakeNoise(flake_position, flake_across, flake_down);

			final_color.rgb = metallicColor(gl_Color.rgb, final_color.rgb, normal, finish, flake);
		}

		vec4 tex_color = texture2D(u_tex, tex_coord);
		gl_FragColor = markedColor(
			mix(
			final_color,
			vec4(mix(final_color.rgb,tex_color.rgb,tex_color.a),gl_Color.a),
			tex_mix));
	}

#endif
