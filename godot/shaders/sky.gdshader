shader_type sky;
// The Kettle's sky: a pale steam-hazed day that falls into an amber-and-violet dusk, layered
// drifting clouds, a soft sun with a wide glow, and haze thickening toward the horizon.

uniform vec3 top_color : source_color = vec3(0.49, 0.54, 0.56);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.75, 0.74);
uniform vec3 ground_color : source_color = vec3(0.1, 0.11, 0.12);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.95, 0.88);
uniform vec3 cloud_light : source_color = vec3(0.92, 0.92, 0.9);
uniform vec3 cloud_dark : source_color = vec3(0.45, 0.48, 0.5);
uniform float cloud_cover = 0.55;
uniform float sun_glow = 1.0;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += texture(cloud_noise, p).r * a;
		p = p * 2.03 + vec2(0.13, 0.27);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.55, h));
	col = mix(col, ground_color, smoothstep(0.0, -0.12, h));
	float sun_dot = max(dot(dir, LIGHT0_DIRECTION), 0.0);
	if (LIGHT0_ENABLED) {
		col += sun_tint * (pow(sun_dot, 8.0) * 0.25 + pow(sun_dot, 64.0) * 0.6) * sun_glow;
		col += sun_tint * smoothstep(0.9993, 0.9997, sun_dot) * 4.0 * sun_glow;
	}
	if (h > 0.0 && !AT_CUBEMAP_PASS) {
		vec2 uv = dir.xz / (h + 0.12) * 0.12 + TIME * vec2(0.0018, 0.0009);
		float c = fbm(uv);
		float cover = smoothstep(1.0 - cloud_cover, 1.05 - cloud_cover * 0.4, c);
		float shade = fbm(uv + vec2(0.02, 0.015));
		vec3 cc = mix(cloud_light, cloud_dark, smoothstep(0.35, 0.75, shade));
		cc += sun_tint * pow(sun_dot, 6.0) * 0.4 * sun_glow;
		col = mix(col, cc, cover * smoothstep(0.0, 0.12, h) * 0.9);
	} else if (h > 0.0) {
		col = mix(col, cloud_dark, cloud_cover * 0.25);
	}
	// Steam haze hugs the horizon.
	col = mix(col, horizon_color, smoothstep(0.12, 0.0, abs(h)) * 0.6);
	COLOR = col;
}
