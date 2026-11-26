shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// The terrain of the hub.
//
// The mesh carries the colors of the biome in its vertex colors: grass in the
// low ground, sand on the slopes, and rock on the peaks. The shader adds the
// fine variation of the surface and turns the steep slopes into bare rock, so
// the ground does not look like flat color patches.

uniform vec3 grass_color_a : source_color = vec3(0.18, 0.36, 0.14);
uniform vec3 grass_color_b : source_color = vec3(0.26, 0.44, 0.16);
uniform vec3 rock_color : source_color = vec3(0.32, 0.30, 0.28);
uniform float slope_threshold : hint_range(0.0, 1.0) = 0.72;
uniform float noise_scale = 0.15;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.45;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float coarse = noise(world_pos.xz * noise_scale);
	float fine = noise(world_pos.xz * noise_scale * 3.7);
	float n = coarse * 0.65 + fine * 0.35;

	// The steepness of the ground decides how much rock it shows.
	float slope = smoothstep(slope_threshold - 0.1, slope_threshold + 0.1, world_normal.y);

	vec3 grass = mix(grass_color_a, grass_color_b, n);
	vec3 rock = rock_color * (0.8 + 0.4 * n);

	// The color of the vertex carries the biome of the height, and the
	// procedural noise only adds the variation on top of it.
	vec3 biome = COLOR.rgb;
	vec3 base = mix(biome, mix(biome, grass, detail_strength), 0.5);
	vec3 final_albedo = mix(rock, base, slope);

	ALBEDO = final_albedo;
	ROUGHNESS = mix(0.92, 0.74, slope);
	SPECULAR = 0.22;
}
