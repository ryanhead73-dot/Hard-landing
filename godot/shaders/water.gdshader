shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;
// Steaming hot-spring pools: near-black teal water, a bright sky fresnel at grazing angles,
// slow ripples, and a glowing teal ring where the moss meets the water.

uniform sampler2D ripple_noise : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.03, 0.08, 0.08);
uniform vec3 shallow_color : source_color = vec3(0.08, 0.22, 0.2);
uniform vec3 glow_color : source_color = vec3(0.247, 0.82, 0.71);
uniform float glow = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * 0.08;
	vec3 n1 = texture(ripple_noise, uv + TIME * vec2(0.012, 0.007)).rgb;
	vec3 n2 = texture(ripple_noise, uv * 1.7 - TIME * vec2(0.009, 0.013)).rgb;
	NORMAL_MAP = normalize(n1 + n2 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.35;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	// UV.x of the pool disc mesh is the distance from the centre (0) to the rim (1).
	float edge = smoothstep(0.75, 1.0, UV.x);
	ALBEDO = mix(deep_color, shallow_color, edge);
	// Dark and only glossy at grazing angles: with the surface now facing up, a mirror finish
	// turned the pools into pale slabs of overcast sky.
	METALLIC = 0.0;
	ROUGHNESS = mix(0.22, 0.08, fres);
	SPECULAR = mix(0.18, 0.5, fres);
	ALPHA = mix(0.82, 0.95, fres);
	EMISSION = glow_color * edge * (0.08 + 0.5 * glow) + shallow_color * 0.05;
}
