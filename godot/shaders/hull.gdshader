shader_type spatial;
render_mode specular_schlick_ggx;
// Kestrel's skin and every painted or bare metal part on her: panels on a staggered grid in
// ship space (so the pattern rides with the hull when she levels or lifts off), recessed seams
// and rivet rows, per-panel tint drift (some plates were replaced over the years), paint
// chipped back to primer and metal along panel edges, rain-streaked grime under the seams,
// mud and soot thrown up from the crash furrow on the belly and the nose, and engine soot.
// `pattern`: 0 = hull plating, 1 = deck tread plate, 2 = machinery (no panels, just wear).

uniform vec3 base_color : source_color = vec3(0.86, 0.82, 0.71);
// What shows through chipped paint: primer for the cream, bare steel under that.
uniform vec3 primer_color : source_color = vec3(0.36, 0.33, 0.29);
uniform vec3 bare_color : source_color = vec3(0.42, 0.43, 0.44);
uniform vec3 grime_color : source_color = vec3(0.16, 0.14, 0.11);
uniform vec3 mud_color : source_color = vec3(0.06, 0.065, 0.06);
uniform int pattern = 0;
uniform vec2 panel_size = vec2(2.4, 1.15);
uniform float seam_width = 0.007;
uniform float paint_roughness = 0.55;
uniform float metallic_amount = 0.0;
uniform float chip = 0.5;
uniform float grime = 0.6;
// Mud and soot from the crash: thrown up the belly and over the nose.
uniform float mud = 1.0;
uniform float soot = 0.0;
uniform float tint_drift = 0.035;
uniform float bump = 1.0;
uniform float rain = 0.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// World -> ship space (set by Kestrel whenever she moves). Identity for static wrecks.
uniform mat4 ship_xform = mat4(1.0);

varying vec3 ship_pos;
varying vec3 ship_normal;

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	ship_pos = (ship_xform * wp).xyz;
	ship_normal = normalize((ship_xform * (MODEL_MATRIX * vec4(NORMAL, 0.0))).xyz);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float tri_noise(vec3 p, vec3 w, float scale) {
	return texture(noise_tex, p.zy * scale).r * w.x + texture(noise_tex, p.xz * scale).r * w.y + texture(noise_tex, p.xy * scale).r * w.z;
}

// Distance to the nearest panel seam on a staggered grid, the panel's id, and rivet coverage.
vec3 panel(vec2 uv, vec2 size) {
	vec2 g = uv / size;
	float row = floor(g.y);
	g.x += mod(row, 2.0) * 0.5;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	vec2 d = min(f, 1.0 - f) * size;
	float seam = min(d.x, d.y);
	// Rivets: a row 4 cm inside each horizontal and vertical seam, every 12 cm.
	vec2 rv = vec2(mod(uv.x + 0.06, 0.12) - 0.06, mod(uv.y + 0.06, 0.12) - 0.06);
	float rx = length(vec2(rv.x, d.y - 0.04));
	float ry = length(vec2(d.x - 0.04, rv.y));
	float rivet = 1.0 - smoothstep(0.008, 0.014, min(rx, ry));
	return vec3(seam, hash12(cell + vec2(row * 7.0, 3.0)), rivet);
}

void fragment() {
	vec3 n = normalize(ship_normal);
	vec3 w = pow(abs(n), vec3(6.0));
	w /= (w.x + w.y + w.z);
	vec3 p = ship_pos;
	// Pick the dominant projection for the panel grid (blending grids smears the seams).
	vec2 uv = p.xy;
	if (w.x > w.y && w.x > w.z) {
		uv = vec2(p.z, p.y);
	} else if (w.y > w.z) {
		uv = vec2(p.x, p.z);
	}
	float big = tri_noise(p, w, 0.07);
	float mid = tri_noise(p, w, 0.31);
	float fine = tri_noise(p, w, 1.7);
	vec3 pan = vec3(1.0, 0.5, 0.0);
	float height = 0.0;
	float aa = max(fwidth(uv.x) + fwidth(uv.y), 0.0005);
	float seam_mask = 0.0;
	if (pattern == 0) {
		pan = panel(uv, panel_size);
		seam_mask = 1.0 - smoothstep(seam_width - aa, seam_width + aa, pan.x);
		height = -seam_mask + pan.z * 0.6;
	} else if (pattern == 1) {
		pan = panel(uv, vec2(1.2, 1.2));
		seam_mask = 1.0 - smoothstep(seam_width - aa, seam_width + aa, pan.x);
		// Diamond tread: raised lozenges in alternating directions.
		vec2 t = uv * 9.0;
		vec2 tc = floor(t);
		vec2 tf = fract(t) - 0.5;
		float flip = mod(tc.x + tc.y, 2.0) * 2.0 - 1.0;
		vec2 r = vec2(tf.x + tf.y * flip, tf.y - tf.x * flip) * 0.7071;
		float lozenge = 1.0 - smoothstep(0.05, 0.09, length(vec2(r.x * 0.35, r.y)));
		height = lozenge * 0.5 - seam_mask;
	}
	// Seams fade out with distance so they don't shimmer.
	float near = 1.0 - smoothstep(0.02, 0.08, aa);
	height *= near;

	// Paint chips gather along the seams and on the exposed lower hull.
	float edge_wear = 1.0 - smoothstep(0.0, 0.09, pan.x);
	float zone = smoothstep(0.5, 0.7, mid * 0.6 + big * 0.6);
	float chips = smoothstep(0.83, 0.85, fine + edge_wear * 0.17 * float(pattern != 1) + zone * 0.05) * chip;
	float deep = smoothstep(0.88, 0.9, fine + edge_wear * 0.12 + zone * 0.04) * chip;
	// Grime: soft streaks running down from the seams, heavier toward the bottom of the hull.
	float streak = texture(noise_tex, vec2(uv.x * 1.3, p.y * 0.06)).r;
	float below_seam = 1.0 - smoothstep(0.0, 0.35, pan.x);
	float g = clamp(smoothstep(0.42, 0.75, streak) * 0.75 + below_seam * 0.2 + smoothstep(0.5, 0.8, big) * 0.3, 0.0, 1.0) * grime;
	g *= mix(0.45, 1.0, 1.0 - smoothstep(0.0, 3.6, p.y));
	float spatter = texture(noise_tex, uv * 0.8 + vec2(0.37, 0.11)).r;
	float belly = 1.0 - smoothstep(0.1, 0.9, p.y + (mid - 0.5) * 0.8 + (spatter - 0.5) * 0.5);
	float nose = (1.0 - smoothstep(-17.0, -12.5, p.x + (mid - 0.5) * 4.0)) * (1.0 - smoothstep(0.6, 2.2, p.y + (spatter - 0.5) * 0.8));
	float m = clamp(max(belly, nose), 0.0, 1.0);
	m = smoothstep(0.3, 0.55, m) * mud;
	// Soot: engine scorch, streaked aft.
	float s = smoothstep(0.35, 0.8, big + fine * 0.3) * soot;

	vec3 paint = base_color * (1.0 + (pan.y - 0.5) * 2.0 * tint_drift) * mix(0.94, 1.03, fine);
	vec3 col = mix(paint, primer_color, chips);
	col = mix(col, bare_color, deep);
	col = mix(col, col * 0.62, seam_mask * 0.45);
	col = mix(col, grime_color, g * 0.38);
	col = mix(col, vec3(0.03), s * 0.8);
	col = mix(col, mud_color, m * 0.9);
	float wet = rain * (0.6 + 0.4 * (1.0 - smoothstep(-0.5, 3.0, p.y)));
	ALBEDO = col * mix(1.0, 0.78, wet);
	float metal = max(metallic_amount, deep * 0.8);
	METALLIC = metal * (1.0 - m);
	ROUGHNESS = clamp(mix(mix(paint_roughness, 0.42, deep), 0.95, max(g * 0.4, m)) * mix(1.0, 0.35, wet), 0.08, 1.0);
	SPECULAR = 0.5;
	AO = 1.0 - seam_mask * 0.35 * near;
	AO_LIGHT_AFFECT = 0.3;

	// Bump from the height field (screen-space derivative method: Mikkelsen 2010).
	float h = height * bump * 0.004 + (chips - deep * 0.5) * -0.0015 * near;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(h);
	float dhy = dFdy(h);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);
}
