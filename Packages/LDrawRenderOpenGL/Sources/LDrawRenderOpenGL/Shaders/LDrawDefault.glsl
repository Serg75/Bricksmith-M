#line 1

varying vec2	tex_coord;
varying float	tex_mix;

varying vec3	normal_eye;
varying vec4	position_eye;

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
		position_eye = eye_pos;

		vec4	col = color;
		if (col.a == 0.0)
		{
			col = mix(color_current,color_complement, col.r);
		}

		//	A vertex in the edge color is on an edge line. A marked part's
		//	edges take the mark's color.
		if (color.a == 0.0 && color.r == 1.0 && mark.w > 0.0)
			col.rgb = mark.rgb;

		//	The ghost scale goes on here rather than on color_current, so that it
		//	reaches a color baked into the mesh as well as a meta one.
		col.a *= ghost_alpha;

		gl_FrontColor.a = col.a;
		gl_FrontColor.rgb = col.rgb;
		mark_v = mark;
				 
		if(normal == vec3(0))
			gl_FrontColor = col;
			
//		gl_FrontColor.rgb = norm_obj;

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
	

//		float hdot = max(0.0,dot(gl_LightSource[0].position.xyz,normalize(
//				reflect(position_eye.xyz,normal)		
//				)));
//		final_color.rgb += pow(hdot,128.0);
	
	
	
	
	
		vec4 tex_color = texture2D(u_tex, tex_coord);
		gl_FragColor = markedColor(
			mix(
			final_color,
			vec4(mix(final_color.rgb,tex_color.rgb,tex_color.a),gl_Color.a),
			tex_mix));
	}

#endif
