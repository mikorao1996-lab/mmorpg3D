shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// The water of the lake.
//
// The surface is a flat plane, and the shore of the lake is the line where the
// ground rises through it. The depth of the ground under every point of the
// surface is baked into the mesh when the lake is built, so the colour can go
// from the shallow blue to the deep one, and the white foam follows the shore.

uniform vec3 shallow_color : source_color = vec3(0.14, 0.52, 0.62);
uniform vec3 deep_color : source_color = vec3(0.04, 0.18, 0.32);
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 1.0);
uniform float foam_distance = 0.35;
uniform float wave_speed = 0.8;
uniform float wave_height = 0.04;
uniform float depth_range = 1.1;
uniform float max_depth = 6.0;

varying vec3 world_pos;
varying float water_depth;

void vertex() {
	// The red channel of the vertex color holds the depth of the ground,
	// scaled by the range of the depth.
	water_depth = COLOR.r * max_depth;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(TIME * wave_speed + world_pos.x * 1.4 + world_pos.z * 1.1);
	VERTEX.y += wave * wave_height;
}

void fragment() {
	float depth = max(water_depth, 0.0);

	// The shallow water is lighter than the deep one.
	float depth_factor = clamp(depth / depth_range, 0.0, 1.0);
	vec3 water_col = mix(shallow_color, deep_color, depth_factor);

	// The sky at a sharp angle of the view.
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	water_col = mix(water_col, vec3(0.65, 0.82, 0.95), fresnel * 0.45);

	// The foam of the shore pulses with the waves.
	float foam_wave = sin(depth * 12.0 - TIME * 2.5) * 0.08;
	float foam_mask = 1.0 - smoothstep(0.02, foam_distance + foam_wave, depth);

	ALBEDO = mix(water_col, foam_color, foam_mask * 0.8);
	// The water fades out at the shore, so the line of the shore is soft.
	ALPHA = clamp(
		smoothstep(0.0, 0.25, depth) * (0.5 + depth_factor * 0.45) + foam_mask * 0.35,
		0.0,
		0.95
	);
	ROUGHNESS = 0.12;
	SPECULAR = 0.8;
}
