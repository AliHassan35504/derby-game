shader_type spatial;
// Cast concrete in world space: fine aggregate, formwork joints on walls,
// darker water stains running down, and an optional wet sheen. With
// rough_rocks it breaks up into a craggy rubble look for breakwaters.
// The tint is multiplied by the vertex colour.

uniform vec3 tint : source_color = vec3(0.6, 0.59, 0.56);
uniform float wetness = 0.0;
uniform float rough_rocks = 0.0;
uniform float joint_spacing = 1.5;
uniform float stain_amount = 0.5;

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
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
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
	bool wall = an.y < 0.6;
	vec2 p = wall ? (an.x > an.z ? world_pos.zy : world_pos.xy) : world_pos.xz;
	float grain = noise(p * 23.0) * 0.5 + noise(p * 61.0) * 0.5;
	float blotch = fbm(p * 0.35);
	vec3 col = tint * COLOR.rgb * (0.82 + 0.22 * blotch) * (0.92 + 0.14 * grain);
	float stains = 0.0;
	if (wall) {
		// Formwork joints and stains running down from them.
		float to_joint = abs(fract(world_pos.y / joint_spacing + 0.5) - 0.5) * joint_spacing;
		float joint = 1.0 - smoothstep(0.01, 0.035, to_joint);
		col *= 1.0 - joint * 0.25;
		stains = smoothstep(0.5, 0.85, fbm(vec2(p.x * 1.8, world_pos.y * 0.12))) * stain_amount;
		col = mix(col, col * 0.55, stains);
	}
	float craggy = 0.0;
	if (rough_rocks > 0.0) {
		craggy = fbm(p * 1.4 + world_pos.y);
		col *= mix(1.0, 0.6 + 0.7 * craggy, rough_rocks);
	}
	float wet = clamp(wetness + (wall ? 0.0 : smoothstep(0.55, 0.75, blotch) * wetness), 0.0, 1.0);
	col *= 1.0 - wet * 0.35;
	ALBEDO = col;
	ROUGHNESS = mix(0.88 - grain * 0.1, 0.18, wet);
	SPECULAR = mix(0.35, 0.6, wet);
	NORMAL_MAP = normalize(vec3(0.5 + (grain - 0.5) * 0.25 + (craggy - 0.5) * rough_rocks * 0.8,
			0.5 + (noise(p * 9.0) - 0.5) * 0.25, 1.0));
}
