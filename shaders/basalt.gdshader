shader_type spatial;
// Basalt and obsidian for a volcano. World space: near-black rock in
// columnar hexagonal joints on top faces and vertical columns on the sides,
// with glowing orange cracks that get hotter towards the lava (below
// heat_height) and flare up with heat during an eruption. In deck mode it
// is a polished obsidian road deck (object space: X across, Z along) with
// glowing seams along both edges so the road reads against the lava.

uniform vec3 rock : source_color = vec3(0.12, 0.11, 0.11);
uniform vec3 rock_light : source_color = vec3(0.24, 0.22, 0.21);
uniform vec3 glow : source_color = vec3(1.0, 0.33, 0.04);
uniform float heat_height = 14.0;
uniform float heat = 0.0;
uniform bool deck = false;
// With deck: a square pad (seams on all four edges) of this size.
uniform bool pad = false;
uniform float pad_size = 13.0;
uniform float road_width = 5.0;
uniform float crack_amount = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;
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
// Distance to the edge of a hexagonal cell.
float hex_edge(vec2 p) {
	vec2 r = vec2(1.0, 1.732);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 q = abs(g);
	return 0.5 - max(dot(q, normalize(vec2(1.0, 1.732))), q.x);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 an = abs(world_normal);
	vec2 p = an.y > 0.6 ? world_pos.xz : (an.x > an.z ? world_pos.zy : world_pos.xy);
	float mottle = fbm(p * 0.7);
	vec3 col = mix(rock, rock_light, mottle * 0.8);
	float joint;
	if (an.y > 0.6) {
		joint = 1.0 - smoothstep(0.0, 0.04, hex_edge(p * 0.45));
	} else {
		// Vertical columns on the sides.
		float u = an.x > an.z ? world_pos.z : world_pos.x;
		joint = 1.0 - smoothstep(0.0, 0.05, abs(fract(u * 0.42 + noise(vec2(u, world_pos.y) * 0.2) * 0.3) - 0.5) * 2.0 - 0.9);
	}
	col *= 1.0 - joint * 0.5;
	float crack_noise = fbm(p * 0.35 + vec2(world_pos.y * 0.1));
	float crack = (1.0 - smoothstep(0.0, 0.035, abs(crack_noise - 0.5))) * crack_amount;
	float hot_zone = 1.0 - smoothstep(heat_height - 10.0, heat_height + 8.0, world_pos.y);
	float pulse = 0.8 + 0.2 * sin(TIME * 2.0 + crack_noise * 20.0);
	float g = crack * (0.15 + hot_zone * 0.85 + heat * 0.6) * pulse;
	g += hot_zone * hot_zone * 0.35 * (0.6 + 0.4 * mottle);
	vec3 emit = glow * g * (1.6 + heat * 1.5);
	float rough = 0.85 - mottle * 0.2;
	float metal = 0.0;
	if (deck) {
		vec2 uv = local_pos.xz;
		if (local_normal.y > 0.5) {
			float glass = fbm(uv * 1.5);
			col = mix(vec3(0.13, 0.115, 0.12), vec3(0.26, 0.22, 0.22), glass * 0.7);
			float plate = 1.0 - smoothstep(0.0, 0.03, hex_edge(uv * 0.6));
			col *= 1.0 - plate * 0.6;
			float half_w = pad ? pad_size * 0.5 : road_width * 0.5;
			float across = pad ? max(abs(uv.x), abs(uv.y)) : abs(uv.x);
			float seam = step(half_w - 0.28, across) * step(across, half_w - 0.12);
			emit = glow * (seam * (2.6 + heat * 2.0) + plate * 0.25 * (0.5 + heat));
			rough = 0.45 + glass * 0.25;
			metal = 0.1;
		}
	}
	ALBEDO = col;
	EMISSION = emit;
	ROUGHNESS = rough;
	METALLIC = metal;
}
