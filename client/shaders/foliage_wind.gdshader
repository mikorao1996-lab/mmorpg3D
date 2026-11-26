shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// The wind of the grass.
//
// The vertices move only in the upper part of the blade, so the roots stay on
// the ground and the tips sway in waves. The tint of the instance follows the
// biome of the ground, so the grass of the slope and the grass of the lowland
// do not look like the same field.

uniform vec3 base_color : source_color = vec3(0.14, 0.30, 0.11);
uniform vec3 tip_color : source_color = vec3(0.36, 0.56, 0.20);
uniform float wind_speed = 1.8;
uniform float wind_strength = 0.18;
uniform float wind_scale = 0.35;

varying float height_factor;
varying vec3 instance_tint;

void vertex() {
	// The instance color of a MultiMesh arrives in COLOR.
	instance_tint = max(COLOR.rgb, vec3(0.05));
	// The UV of the blade points down, so the top of the blade has UV.y = 0.
	height_factor = 1.0 - UV.y;

	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(TIME * wind_speed + world_pos.x * wind_scale + world_pos.z * wind_scale * 0.7);
	float gust = cos(TIME * wind_speed * 0.45 + world_pos.z * wind_scale * 1.5) * 0.5;
	float sway = (wave + gust) * wind_strength * pow(height_factor, 1.6);
	VERTEX.x += sway;
	VERTEX.z += sway * 0.4;
}

void fragment() {
	ALBEDO = mix(base_color, tip_color, height_factor) * instance_tint;
	ROUGHNESS = 0.78;
	SPECULAR = 0.15;
	// The grass lets a little of the sun through.
	BACKLIGHT = tip_color * 0.35;
}
