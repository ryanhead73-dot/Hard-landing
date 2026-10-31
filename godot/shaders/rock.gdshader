shader_type spatial;
// Basalt for every rock, column and crag: triplanar cellular texture in world space, darker
// down the sides, wet sheen low down, teal moss settling on the up-facing tops, faint glowing
// fissures at dusk. Shared by every rock so the world reads as one material.

uniform sampler2D basalt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D basalt_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 basalt_color : source_color = vec3(0.085, 0.09, 0.098);
uniform vec3 moss_color : source_color = vec3(0.035, 0.12, 0.1);
uniform vec3 glow_color : source_color = vec3(0.247, 0.82, 0.71);
uniform float glow = 0.0;
uniform float moss_amount = 0.6;
uniform float tile = 0.35;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec4 triplanar(sampler2D tex, vec3 p, vec3 w) {
	return texture(tex, p.zy) * w.x + texture(tex, p.xz) * w.y + texture(tex, p.xy) * w.z;
}

void fragment() {
	vec3 w = pow(abs(world_normal), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = world_pos * tile;
	float cells = triplanar(basalt_tex, p, w).r;
	float big = triplanar(detail_noise, world_pos * 0.05, w).r;
	float fine = triplanar(detail_noise, world_pos * 0.4, w).r;
	float up = smoothstep(0.55, 0.85, world_normal.y);
	float moss = smoothstep(0.45, 0.6, up * moss_amount + (fine - 0.5) * 0.6 + (big - 0.5) * 0.4);
	float low = 1.0 - smoothstep(0.0, 1.2, world_pos.y);
	vec3 rock = basalt_color * mix(0.45, 1.25, cells) * mix(0.8, 1.2, big);
	rock *= mix(1.0, 0.75, low);
	ALBEDO = mix(rock, moss_color * mix(0.7, 1.2, fine), moss);
	ROUGHNESS = mix(mix(0.72, 0.3, low), 0.95, moss);
	SPECULAR = 0.5;
	NORMAL_MAP = triplanar(basalt_normal, p, w).rgb;
	NORMAL_MAP_DEPTH = mix(1.6, 0.5, moss);
	float fissure = smoothstep(0.46, 0.4, cells) * smoothstep(0.55, 0.75, big);
	EMISSION = glow_color * (fissure * 0.04) * glow;
}
