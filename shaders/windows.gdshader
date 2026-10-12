shader_type spatial;
// Office and apartment towers for a unit BoxMesh scaled per copy in a
// MultiMesh. Windows are laid out in world metres from the building's own
// corner, so every tower gets proper floors whatever its size. Per-copy
// custom data: r = seed, g = share of windows lit, b = style (glass curtain
// wall vs punched concrete), a = colour variation. Far away the window grid
// fades to its average so it doesn't shimmer.

uniform float night = 1.0;
uniform float floor_height = 3.6;
uniform vec3 warm_light : source_color = vec3(1.0, 0.72, 0.42);
uniform vec3 cool_light : source_color = vec3(0.72, 0.85, 1.0);
uniform vec3 glass : source_color = vec3(0.08, 0.11, 0.15);
uniform float shop_glow = 0.0;

varying vec3 rel;
varying vec3 size;
varying vec3 world_normal;
varying vec4 custom;

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	rel = (VERTEX + 0.5) * size;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	float seed = custom.r;
	float lit_share = custom.g;
	bool curtain = custom.b > 0.5;
	vec3 frame_col = mix(vec3(0.42, 0.41, 0.4), vec3(0.62, 0.58, 0.52), custom.a);
	if (curtain) {
		frame_col = mix(vec3(0.16, 0.17, 0.19), vec3(0.3, 0.32, 0.34), custom.a);
	}
	vec3 wn = abs(world_normal);
	if (wn.y > 0.5) {
		// Roof: gravel and plant.
		ALBEDO = frame_col * 0.45;
		ROUGHNESS = 0.95;
	} else {
		float u = wn.x > wn.z ? rel.z : rel.x;
		float face = wn.x > wn.z ? (world_normal.x > 0.0 ? 1.0 : 2.0) : (world_normal.z > 0.0 ? 3.0 : 4.0);
		float col_w = curtain ? 1.6 : 2.6;
		vec2 cell = vec2(u / col_w, rel.y / floor_height);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		float win_w = curtain ? 0.86 : 0.5;
		float win_h = curtain ? 0.72 : 0.46;
		// Anti-aliased window edges, and the grid fades to its average
		// when a window gets down to a few pixels.
		float px = max(fwidth(cell.x), fwidth(cell.y));
		vec2 aa = vec2(fwidth(cell.x), fwidth(cell.y)) * 1.5 + 0.001;
		float in_win = (1.0 - smoothstep(win_w - aa.x, win_w + aa.x, abs(f.x - 0.5) * 2.0))
				* (1.0 - smoothstep(win_h - aa.y, win_h + aa.y, abs(f.y - 0.55) * 2.0));
		float far_blend = smoothstep(0.06, 0.3, px);
		float coverage = win_w * win_h;
		in_win = mix(in_win, coverage, far_blend);
		float h = hash2(id + vec2(seed * 91.0 + face * 13.0, seed * 37.0));
		// Lights come on floor by floor in clusters, not purely at random.
		float cluster = hash2(floor(id / vec2(4.0, 3.0)) + seed * 17.0 + face);
		float lit = step(h, lit_share * (0.5 + cluster));
		lit = mix(lit, lit_share, far_blend);
		float tone = hash2(id * 1.7 + seed);
		vec3 light = mix(warm_light, cool_light, step(0.7, tone)) * (0.6 + 0.6 * hash2(id + 3.1));
		float ground = 1.0 - step(4.5, rel.y);
		vec3 window_col = glass * (0.8 + 0.4 * h);
		ALBEDO = mix(frame_col * (0.85 + 0.2 * hash2(vec2(id.y, seed))), window_col, in_win);
		METALLIC = in_win * 0.6;
		ROUGHNESS = mix(0.8, 0.08, in_win);
		vec3 emit = light * lit * in_win * night * 1.1;
		emit += ground * shop_glow * mix(warm_light, vec3(1.0, 0.4, 0.8), custom.a) * in_win * 2.0;
		EMISSION = emit;
	}
}
