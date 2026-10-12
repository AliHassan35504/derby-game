shader_type spatial;
// Painted structural steel (crane frames, girders, hulls, lamp posts) with
// rust streaks running down from joints, salt grime low down and faint
// panel seams. The paint colour is multiplied by the vertex colour, so one
// material can paint parts of a structure differently.

uniform vec3 paint : source_color = vec3(0.8, 0.55, 0.1);
uniform vec3 rust : source_color = vec3(0.34, 0.17, 0.08);
uniform float rust_amount = 0.4;
uniform float metallic = 0.45;
uniform float roughness = 0.55;
// World height below which salt and grime build up.
uniform float grime_height = 4.0;
uniform float seam_spacing = 2.0;

varying vec3 world_pos;
varying vec3 world_normal;

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
		p *= 2.05;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 an = abs(world_normal);
	// Triplanar-ish: pick the plane facing the normal.
	vec2 p = an.y > 0.6 ? world_pos.xz : (an.x > an.z ? world_pos.zy : world_pos.xy);
	vec3 base = paint * COLOR.rgb;
	float mottle = fbm(p * 1.3);
	// Rust runs down vertical faces in streaks.
	float streaks = fbm(vec2(p.x * 2.5, world_pos.y * 0.15));
	float rust_mask = smoothstep(0.62, 0.9, streaks + mottle * 0.25) * rust_amount;
	rust_mask += smoothstep(0.72, 0.95, fbm(p * 4.0)) * rust_amount * 0.6;
	rust_mask = clamp(rust_mask, 0.0, 1.0);
	vec3 col = base * (0.82 + 0.3 * mottle);
	// Sun-faded paint on top faces.
	col = mix(col, col * 1.12 + 0.03, smoothstep(0.6, 1.0, world_normal.y) * 0.5);
	col = mix(col, rust * (0.7 + 0.6 * fbm(p * 6.0)), rust_mask);
	float grime = (1.0 - smoothstep(grime_height - 3.0, grime_height + 1.0, world_pos.y)) * 0.5;
	col = mix(col, vec3(0.32, 0.31, 0.28), grime * mottle);
	// Panel seams.
	vec2 seam = abs(fract(UV / seam_spacing) - 0.5);
	float seam_line = 1.0 - smoothstep(0.485, 0.495, max(seam.x, seam.y));
	col *= 1.0 - (1.0 - seam_line) * 0.25;
	ALBEDO = col;
	METALLIC = mix(metallic, 0.05, rust_mask);
	ROUGHNESS = clamp(mix(roughness, 0.92, rust_mask) + (mottle - 0.5) * 0.15, 0.05, 1.0);
}
