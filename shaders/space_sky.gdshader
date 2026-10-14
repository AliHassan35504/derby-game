shader_type sky;
// Space: black with a dense star field, a faint milky way band, and the
// sun as a blinding disc with a halo and lens streaks in the direction of
// the main light.

uniform vec3 band_colour : source_color = vec3(0.25, 0.22, 0.3);
uniform float star_density = 0.006;

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
	vec3 col = vec3(0.0, 0.0, 0.004);
	// Stars at two sizes.
	for (int k = 0; k < 2; k++) {
		float scale = k == 0 ? 700.0 : 260.0;
		vec3 cell = floor(dir * scale);
		float h = hash3(cell + float(k) * 13.0);
		float density = k == 0 ? star_density : star_density * 0.25;
		float star = step(1.0 - density, h);
		vec3 tint = mix(vec3(1.0, 0.85, 0.7), vec3(0.75, 0.85, 1.0), hash3(cell + 7.0));
		col += tint * star * (h - (1.0 - density)) / density * (k == 0 ? 1.4 : 3.0);
	}
	// The milky way: a tilted band of faint glow and dust.
	vec3 band_axis = normalize(vec3(0.3, 0.5, 0.8));
	float b = abs(dot(dir, band_axis));
	vec2 bp = vec2(atan(dir.x, dir.z) * 3.0, dir.y * 6.0);
	float band = (1.0 - smoothstep(0.0, 0.28, b)) * (0.4 + 0.6 * fbm(bp * 2.0));
	col += band_colour * band * 0.35;
	if (LIGHT0_ENABLED) {
		float m = max(dot(dir, LIGHT0_DIRECTION), 0.0);
		float disc = smoothstep(0.9993, 0.9996, m);
		float halo = pow(m, 900.0) * 1.5 + pow(m, 60.0) * 0.18 + pow(m, 8.0) * 0.04;
		// Lens streaks: thin horizontal and vertical lines through the sun.
		vec3 side = normalize(cross(LIGHT0_DIRECTION, vec3(0.0, 1.0, 0.0)));
		vec3 upv = cross(side, LIGHT0_DIRECTION);
		float sx = dot(dir, side);
		float sy = dot(dir, upv);
		float streak = (exp(-abs(sy) * 400.0) + exp(-abs(sx) * 400.0) * 0.6) * pow(m, 30.0) * 0.5;
		col += vec3(1.0, 0.97, 0.9) * (disc * 40.0 + halo * 3.0 + streak * 2.0);
	}
	COLOR = col;
}
