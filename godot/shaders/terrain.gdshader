shader_type spatial;
// The basin floor: wet black basalt with cellular cracks, slate in the low wet ground, teal moss
// in the creases and round the pools, glowing veins that come up at dusk. Vertex colour carries
// the masks baked by CrashSite: r = wetness, g = moss, b = cliff (steep rock).

uniform sampler2D basalt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D basalt_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 basalt_color : source_color = vec3(0.08, 0.085, 0.092);
uniform vec3 slate_color : source_color = vec3(0.17, 0.2, 0.21);
uniform vec3 moss_color : source_color = vec3(0.035, 0.12, 0.1);
uniform vec3 glow_color : source_color = vec3(0.247, 0.82, 0.71);
uniform float glow = 0.0;
uniform float tile = 0.25;

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
	float big = texture(detail_noise, world_pos.xz * 0.012).r;
	float fine = texture(detail_noise, world_pos.xz * 0.11).r;
	float wet = clamp(COLOR.r + (big - 0.5) * 0.35, 0.0, 1.0);
	float moss = smoothstep(0.45, 0.7, COLOR.g * 0.85 + (fine - 0.5) * 0.9 + (big - 0.5) * 0.5) * (1.0 - COLOR.b);
	float cliff = COLOR.b;

	// Ash-grey drifts and darker glassy flows at the large scale, cells and cracks up close.
	float ash = smoothstep(0.55, 0.8, big);
	float flow = smoothstep(0.42, 0.2, big);
	vec3 rock = basalt_color * mix(0.4, 1.25, cells) * mix(0.85, 1.15, fine);
	rock = mix(rock, vec3(0.2, 0.2, 0.2) * mix(0.6, 1.1, cells), ash * 0.55);
	rock *= mix(1.0, 0.6, flow);
	wet = max(wet, flow * 0.6);
	rock = mix(rock, slate_color * mix(0.7, 1.1, cells), wet * 0.6);
	rock = mix(rock, basalt_color * 0.8 * cells, cliff);
	vec3 col = mix(rock, moss_color * mix(0.6, 1.2, fine), moss);
	// Cracks between the cells catch a faint teal from below, stronger at dusk.
	float crack = smoothstep(0.5, 0.44, cells) * (1.0 - cliff) * smoothstep(0.4, 0.7, big);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.82, 0.18, wet), 0.9, moss);
	SPECULAR = mix(0.5, 0.7, wet);
	NORMAL_MAP = triplanar(basalt_normal, p, w).rgb;
	NORMAL_MAP_DEPTH = mix(2.2, 0.4, moss);
	EMISSION = glow_color * (crack * 0.04) * glow;
}
