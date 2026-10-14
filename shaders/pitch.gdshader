shader_type spatial;
// Stadium infield in world space: mown grass in stripes, white touchlines,
// a centre circle and dirt patches torn up by earlier rounds.

uniform vec3 grass_a : source_color = vec3(0.12, 0.3, 0.1);
uniform vec3 grass_b : source_color = vec3(0.16, 0.38, 0.13);
uniform vec3 dirt : source_color = vec3(0.3, 0.21, 0.13);
uniform vec2 half_size = vec2(105.0, 70.0);

varying vec3 world_pos;

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
			mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float stripe = step(0.5, fract(p.x / 12.0));
	vec3 col = mix(grass_a, grass_b, stripe) * (0.85 + 0.3 * noise(p * 0.8));
	float patches = smoothstep(0.62, 0.75, noise(p * 0.05) * 0.7 + noise(p * 0.3) * 0.3);
	col = mix(col, dirt * (0.8 + 0.4 * noise(p * 3.0)), patches);
	float w = 0.18;
	vec2 d = abs(p) - half_size;
	float outline = step(abs(max(d.x, d.y)), w) * step(max(d.x, d.y), w);
	float halfway = step(abs(p.x), w) * step(abs(p.y), half_size.y);
	float circle = step(abs(length(p) - 18.0), w);
	float lines = max(max(outline, halfway), circle) * (1.0 - patches * 0.7);
	col = mix(col, vec3(0.9), lines);
	// Outside the pitch: the dark running track round the field.
	float outside = step(0.0, max(d.x, d.y) - 2.0);
	col = mix(col, vec3(0.32, 0.12, 0.08) * (0.8 + 0.3 * noise(p * 2.0)), outside);
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
