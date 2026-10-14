shader_type sky;
// Night sky over a big city: deep blue overhead fading to a sodium and
// neon glow on the horizon, stars that the glow washes out low down, a moon
// in the direction of the main light, and dim clouds lit from below.

uniform vec3 zenith : source_color = vec3(0.01, 0.015, 0.04);
uniform vec3 horizon : source_color = vec3(0.16, 0.08, 0.2);
uniform vec3 city_glow : source_color = vec3(0.55, 0.25, 0.2);
uniform vec3 cloud_tint : source_color = vec3(0.2, 0.12, 0.2);
uniform float star_density = 0.0025;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
			mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = clamp(dir.y, -1.0, 1.0);
	vec3 col = mix(horizon, zenith, smoothstep(0.0, 0.55, up));
	col += city_glow * pow(1.0 - clamp(up, 0.0, 1.0), 6.0) * 0.8;
	if (up > 0.0) {
		// Stars: a hash over a fine grid on the sky dome.
		vec3 cell = floor(dir * 500.0);
		float h = hash3(cell);
		float star = step(1.0 - star_density, h) * smoothstep(0.08, 0.5, up);
		float twinkle = 0.6 + 0.4 * sin(TIME * (2.0 + h * 5.0) + h * 40.0);
		col += vec3(0.9, 0.92, 1.0) * star * twinkle * (h - (1.0 - star_density)) / star_density * 2.0;
		// Low clouds lit from below by the city.
		vec2 cp = dir.xz / (up + 0.12) * 1.4 + vec2(TIME * 0.004, 0.0);
		float c = smoothstep(0.45, 0.8, fbm(cp));
		col = mix(col, cloud_tint * (0.6 + 0.8 * (1.0 - up)), c * 0.8 * smoothstep(0.0, 0.15, up));
	} else {
		col = mix(horizon * 0.6, vec3(0.02), smoothstep(0.0, -0.3, up));
	}
	// The moon, opposite the light's travel direction.
	if (LIGHT0_ENABLED) {
		float m = dot(dir, LIGHT0_DIRECTION);
		float disc = smoothstep(0.9994, 0.9996, m);
		float halo = pow(max(m, 0.0), 300.0) * 0.4 + pow(max(m, 0.0), 30.0) * 0.06;
		float craters = 0.85 + 0.15 * noise(dir.xy * 900.0);
		col += vec3(0.95, 0.95, 1.0) * disc * 3.0 * craters + vec3(0.5, 0.55, 0.7) * halo;
	}
	COLOR = col;
}
