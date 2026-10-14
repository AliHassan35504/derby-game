shader_type spatial;
// A rooftop helipad: dark painted concrete with a yellow touchdown circle,
// a big white H, a white edge line, and scuffed tyre marks. With helipad
// off it is a plain gravel roof with a hazard-striped edge. Object space on
// a pad's box: local XZ across the top, centred.

uniform float pad_size = 18.0;
uniform vec3 deck : source_color = vec3(0.16, 0.17, 0.18);
uniform vec3 circle_col : source_color = vec3(0.95, 0.75, 0.08);
uniform bool helipad = true;

varying vec3 local_pos;
varying vec3 local_normal;

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
			mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec2 p = local_pos.xz;
	float grit = noise(p * 9.0) * 0.5 + noise(p * 40.0) * 0.5;
	vec3 col = deck * (0.8 + 0.4 * grit);
	if (local_normal.y > 0.5 && !helipad) {
		vec2 a = abs(p);
		float half_s = pad_size * 0.5;
		col = mix(col, vec3(0.3, 0.29, 0.27) * (0.7 + 0.6 * noise(p * 23.0)), 0.6);
		float edge = step(half_s - 0.7, max(a.x, a.y));
		float stripe = step(0.5, fract((p.x + p.y) * 0.7));
		col = mix(col, mix(circle_col, vec3(0.03), stripe), edge);
	} else if (local_normal.y > 0.5) {
		float half_s = pad_size * 0.5;
		float r = length(p);
		float ring = step(abs(r - half_s * 0.62), 0.32);
		// The H: two uprights and a crossbar.
		vec2 a = abs(p);
		float h = (step(abs(a.x - 1.6), 0.45) * step(a.y, 2.8)) + step(a.x, 1.6) * step(a.y, 0.4);
		float edge = step(half_s - 0.45, max(a.x, a.y)) * step(max(a.x, a.y), half_s - 0.2);
		float wear = smoothstep(0.25, 0.7, noise(p * 2.5));
		col = mix(col, circle_col, ring * wear);
		col = mix(col, vec3(0.92), clamp(h + edge, 0.0, 1.0) * wear);
		// Rubber scuffs from cars spinning on the pad.
		float scuff = smoothstep(0.55, 0.8, noise(vec2(atan(p.y, p.x) * 3.0, r * 0.5))) * 0.5;
		col *= 1.0 - scuff * 0.6;
	} else {
		col *= 0.6;
	}
	ALBEDO = col;
	ROUGHNESS = 0.85;
}
