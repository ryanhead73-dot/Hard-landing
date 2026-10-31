shader_type spatial;
// Kestrel's live consoles: rows of flickering readout glyphs, a bar graph and a slow scan
// line, in the ship's teal. Projected from the mesh's own local axes (the screens are thin
// boxes in any orientation), so it needs no UVs.

uniform vec3 tint : source_color = vec3(0.25, 0.82, 0.71);
uniform float energy = 1.4;

varying vec3 local_pos;
varying vec3 local_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 n = abs(local_normal);
	vec2 uv = n.x > 0.5 ? local_pos.zy : (n.z > 0.5 ? local_pos.xy : local_pos.xz);
	// Metres -> glyph cells: about 3 cm characters on 5 cm lines.
	vec2 cell = floor(uv * vec2(32.0, 20.0));
	float line_on = step(0.35, hash(vec2(cell.y, 7.0)));
	float line_len = hash(vec2(cell.y, 3.0));
	float glyph = step(0.3, hash(cell + floor(TIME * 1.5) * vec2(0.0, step(0.9, hash(cell.yy)))));
	vec2 f = fract(uv * vec2(32.0, 20.0));
	float in_glyph = step(0.15, f.x) * step(f.x, 0.85) * step(0.25, f.y) * step(f.y, 0.75);
	float text = line_on * glyph * in_glyph * step(fract(uv.x * 0.6 + 0.5), line_len);
	// A bar graph down one side, breathing.
	float bars = step(0.88, fract(uv.x * 0.9)) * step(fract(uv.y * 3.0), 0.4 + 0.4 * sin(TIME * 0.8 + floor(uv.y * 3.0) * 1.7));
	float scan = smoothstep(0.06, 0.0, abs(fract(uv.y * 0.5 - TIME * 0.12) - 0.5));
	float glow = 0.12 + 0.7 * max(text, bars) + 0.25 * scan;
	glow *= 0.92 + 0.08 * sin(TIME * 50.0 + uv.y * 400.0);
	ALBEDO = tint * 0.05;
	ROUGHNESS = 0.15;
	EMISSION = tint * glow * energy;
}
