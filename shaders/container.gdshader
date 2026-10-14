shader_type spatial;
// Corrugated steel shipping container. The mesh is one container in object
// space: X across (2.44 m), Y up (2.59 m), Z along (12.19 m). Each copy gets
// its paint from the MultiMesh instance colour. Long sides have vertical
// ribs, the ends have doors with locking bars, and everything is weathered
// with rust and salt.

uniform vec3 rust : source_color = vec3(0.33, 0.16, 0.07);
uniform float rust_amount = 0.5;

varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 world_pos;
varying float seed;

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
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	seed = hash2(MODEL_MATRIX[3].xz * 0.37 + MODEL_MATRIX[3].y);
}

void fragment() {
	vec3 n = abs(local_normal);
	vec3 paint = COLOR.rgb * (0.85 + 0.3 * seed);
	float rib = 0.0;
	float frame = 0.0;
	vec2 p;
	if (n.x > 0.5) {
		// Long side: trapezoid ribs every 0.28 m.
		p = local_pos.zy;
		rib = sin(local_pos.z / 0.28 * 6.2832);
		frame = step(1.18, abs(local_pos.y)) + step(5.95, abs(local_pos.z));
	} else if (n.z > 0.5) {
		// Doors: two leaves, four locking bars, hinges at the edges.
		p = local_pos.xy;
		rib = sin(local_pos.y / 0.3 * 6.2832) * 0.4;
		float bars = 1.0 - smoothstep(0.02, 0.04, abs(fract((local_pos.x + 1.22) / 0.61) - 0.5) * 0.61 - 0.0);
		frame = step(1.1, abs(local_pos.x)) + step(1.18, abs(local_pos.y));
		paint *= 1.0 - (1.0 - smoothstep(0.0, 0.015, abs(local_pos.x))) * 0.6;
		paint = mix(paint, vec3(0.2), bars * step(abs(local_pos.y), 1.1) * 0.7);
	} else {
		// Roof: shallow dents across.
		p = local_pos.xz;
		rib = sin(local_pos.z / 0.9 * 6.2832) * 0.3;
		frame = step(1.12, abs(local_pos.x)) + step(5.95, abs(local_pos.z));
	}
	frame = clamp(frame, 0.0, 1.0);
	// Ribs smaller than a pixel fade out instead of shimmering.
	float rib_scale = n.x > 0.5 ? local_pos.z / 0.28 : local_pos.y / 0.3;
	float rib_fade = 1.0 - smoothstep(0.25, 0.6, fwidth(rib_scale));
	rib *= rib_fade;
	vec2 wp = p + vec2(seed * 31.0, seed * 17.0);
	float grime = fbm(wp * 0.9);
	float streak = fbm(vec2(wp.x * 3.0, local_pos.y * 0.35 + seed * 5.0));
	float rust_mask = smoothstep(0.62, 0.9, streak + grime * 0.2) * rust_amount * (0.5 + seed);
	rust_mask = clamp(rust_mask + frame * 0.35 * rust_amount, 0.0, 1.0);
	vec3 col = paint * (0.78 + 0.35 * grime) * (1.0 - frame * 0.25);
	col *= 0.92 + rib * 0.08;
	col = mix(col, rust * (0.7 + 0.6 * fbm(wp * 5.0)), rust_mask);
	// Salt and dust settle on the roof.
	col = mix(col, vec3(0.55, 0.52, 0.47), smoothstep(0.5, 1.0, local_normal.y) * grime * 0.45);
	ALBEDO = col;
	METALLIC = mix(0.3, 0.05, rust_mask);
	ROUGHNESS = mix(0.55, 0.9, rust_mask) + grime * 0.08;
	// Ribs as a bump across the face. On the sides and doors the ribs vary
	// along the face's V direction, which is the normal map's Y.
	float slope = cos(rib_scale * 6.2832) * (n.y > 0.5 ? 0.0 : 1.0) * rib_fade;
	NORMAL_MAP = normalize(vec3(0.5, 0.5 + slope * 0.35 * (n.z > 0.5 ? 0.4 : 1.0), 1.0));
}
