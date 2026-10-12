shader_type spatial;
// Weathered wooden planks laid across a road. Works in object space, so the
// mesh should be sized with its mesh size (not node scale): local X runs
// across the road, local Z along it, and planks are laid every plank_width.

uniform vec3 wood_light : source_color = vec3(0.78, 0.68, 0.52);
uniform vec3 wood_dark : source_color = vec3(0.46, 0.36, 0.25);
uniform float plank_width = 0.32;
uniform float gap = 0.018;
uniform float weathering = 0.35;

varying vec3 local_pos;
varying vec3 local_normal;

float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }
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
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	// Pick the two axes of the face being drawn.
	vec3 n = abs(local_normal);
	vec2 uv;
	if (n.y > 0.5) {
		uv = local_pos.xz;
	} else if (n.x > 0.5) {
		uv = local_pos.zy;
	} else {
		uv = local_pos.xy;
	}

	float along = uv.y;
	float plank = floor(along / plank_width);
	float within = fract(along / plank_width);
	float seed = hash(plank);

	// Grain runs across the road (along each plank).
	vec2 grain_uv = vec2(uv.x * 0.6 + seed * 13.0, within * 6.0 + seed * 7.0);
	float grain = fbm(vec2(grain_uv.x * 1.5, grain_uv.y * 9.0));
	float rings = sin((grain_uv.y + fbm(grain_uv * 2.0) * 2.5) * 6.0) * 0.5 + 0.5;

	vec3 base = mix(wood_dark, wood_light, 0.35 + 0.5 * seed);
	vec3 col = mix(base * 0.82, base, grain * 0.6 + rings * 0.4);

	// Weathering: grey, sun-bleached patches and darker wet streaks.
	float weather = fbm(uv * 0.35 + seed);
	col = mix(col, vec3(0.62, 0.62, 0.6) * (0.85 + 0.3 * grain), weather * weathering);
	col *= 0.9 + 0.2 * fbm(uv * 3.1);

	// Dark gaps between planks, plus nail heads near each end.
	float edge = smoothstep(0.0, gap / plank_width, within) * smoothstep(0.0, gap / plank_width, 1.0 - within);
	col *= mix(0.25, 1.0, edge);
	float nail_x = abs(fract(uv.x / 1.6) - 0.5);
	float nail = (1.0 - smoothstep(0.012, 0.02, length(vec2(nail_x * 1.6, (within - 0.5) * plank_width))));
	col = mix(col, vec3(0.2, 0.2, 0.22), nail * 0.8);

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.75, grain);
	SPECULAR = 0.3;

	// Fake bump: grooves at plank edges and fine grain.
	float bump_edge = 1.0 - edge;
	NORMAL_MAP = normalize(vec3(0.5 + (grain - 0.5) * 0.25, 0.5 + (bump_edge * (within < 0.5 ? -0.5 : 0.5)), 1.0));
	NORMAL_MAP_DEPTH = 1.2;
}
