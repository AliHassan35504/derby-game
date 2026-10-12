shader_type spatial;
// Rain-soaked asphalt for elevated highway decks, with lane markings and
// puddles that turn into mirrors for the street lights and neon. Object
// space: local X across the road, local Z along it. Pads use the junction
// mode: a yellow box-junction hatch instead of lane lines.

uniform vec3 asphalt : source_color = vec3(0.1, 0.1, 0.11);
uniform vec3 line_color : source_color = vec3(0.9, 0.9, 0.86);
uniform vec3 hatch_color : source_color = vec3(0.92, 0.7, 0.12);
uniform vec3 side_color : source_color = vec3(0.42, 0.42, 0.44);
uniform float road_width = 5.2;
uniform float wetness = 0.8;
uniform bool junction = false;
uniform float pad_size = 12.0;
uniform float paint_glow = 0.25;

varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 world_pos;

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
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (local_normal.y > 0.5) {
		vec2 uv = local_pos.xz;
		float grit = noise(uv * 19.0) * 0.5 + noise(uv * 57.0) * 0.5;
		float patches = noise(world_pos.xz * 0.3);
		vec3 col = asphalt * (0.75 + 0.5 * grit) * (0.85 + 0.3 * patches);
		// Tyre-worn wheel tracks are smoother and darker.
		float tracks = (1.0 - smoothstep(0.25, 0.6, abs(abs(uv.x) - 0.8))) * (junction ? 0.0 : 1.0);
		col *= 1.0 - tracks * 0.15;
		float paint = 0.0;
		vec3 paint_col = line_color;
		if (junction) {
			float half_p = pad_size * 0.5;
			float border = step(half_p - 0.9, max(abs(uv.x), abs(uv.y))) * step(max(abs(uv.x), abs(uv.y)), half_p - 0.6);
			float inside = step(max(abs(uv.x), abs(uv.y)), half_p - 0.9);
			float d1 = abs(fract((uv.x + uv.y) / 2.2) - 0.5);
			float d2 = abs(fract((uv.x - uv.y) / 2.2) - 0.5);
			float hatch = (1.0 - smoothstep(0.04, 0.06, min(d1, d2))) * inside;
			paint = max(border, hatch);
			paint_col = hatch_color;
		} else {
			float half_w = road_width * 0.5;
			float edge_line = step(half_w - 0.4, abs(uv.x)) * step(abs(uv.x), half_w - 0.22);
			float dash = step(0.55, fract(uv.y / 6.0));
			float centre = step(abs(uv.x), 0.07) * dash;
			// Cat's-eye studs between the dashes.
			float stud = (1.0 - step(0.07, length(vec2(uv.x, (fract(uv.y / 6.0 + 0.22) - 0.5) * 6.0)))) * 1.0;
			paint = max(edge_line, centre);
			col = mix(col, vec3(0.9, 0.55, 0.1), stud);
			EMISSION = vec3(1.0, 0.45, 0.05) * stud * 1.5;
		}
		float wear = smoothstep(0.25, 0.65, noise(uv * 2.7));
		paint *= wear;
		col = mix(col, paint_col, paint);
		// Retro-reflective paint picks up light even on a dark night.
		EMISSION += paint_col * paint * paint_glow;
		// Puddles collect in the low spots.
		float puddle = smoothstep(0.52, 0.66, fbm(world_pos.xz * 0.22 + 3.0)) * wetness;
		float damp = wetness * (0.6 + 0.4 * patches);
		col *= mix(1.0, 0.55, damp);
		col *= mix(1.0, 0.6, puddle);
		ALBEDO = col;
		ROUGHNESS = mix(mix(0.85, 0.42, damp), 0.02, puddle);
		ROUGHNESS = mix(ROUGHNESS, 0.5, paint * (1.0 - puddle));
		SPECULAR = mix(0.5, 0.9, puddle);
		vec2 bump = vec2(grit - 0.5, noise(uv * 31.0) - 0.5) * 0.35 * (1.0 - puddle);
		NORMAL_MAP = normalize(vec3(0.5 + bump.x, 0.5 + bump.y, 1.0));
	} else {
		float grain = noise(world_pos.xy * 13.0 + world_pos.zz * 11.0);
		float stain = fbm(vec2((world_pos.x + world_pos.z) * 0.8, world_pos.y * 2.0));
		ALBEDO = side_color * (0.8 + 0.25 * grain) * mix(1.0, 0.55, smoothstep(0.45, 0.8, stain));
		ROUGHNESS = 0.6;
	}
}
