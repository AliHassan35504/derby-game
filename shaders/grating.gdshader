shader_type spatial;
// Galvanised steel bar grating for walkway decks, with painted kick strips
// along both edges. Object space: local X across the road, local Z along it.
// The holes between bars are cut out up close (you can see the sea through
// the deck) and blend to a solid average further away, so there is no
// shimmer.

render_mode cull_disabled;

uniform vec3 steel : source_color = vec3(0.46, 0.47, 0.47);
uniform vec3 rust : source_color = vec3(0.36, 0.2, 0.1);
uniform vec3 edge_paint : source_color = vec3(0.86, 0.62, 0.08);
uniform float road_width = 5.0;
uniform float bar_pitch = 0.09;
uniform float cross_pitch = 0.5;
uniform float rust_amount = 0.35;
uniform bool cut_holes = true;

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
		p *= 2.07;
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
	vec3 n = abs(local_normal);
	float rust_mask = smoothstep(0.55, 0.85, fbm(world_pos.xz * 0.6 + world_pos.y * 0.3)) * rust_amount;
	float grime = fbm(world_pos.xz * 2.3);
	vec3 metal = steel * (0.8 + 0.35 * grime);
	if (n.y > 0.5) {
		vec2 uv = local_pos.xz;
		float half_w = road_width * 0.5;
		float edge = step(half_w - 0.32, abs(uv.x));
		// Bearing bars run along the road, cross bars every cross_pitch.
		float bx = fract(uv.x / bar_pitch);
		float bz = fract(uv.y / cross_pitch);
		float bar = 1.0 - smoothstep(0.26, 0.36, abs(bx - 0.5) * 2.0);
		float cbar = 1.0 - smoothstep(0.05, 0.09, abs(bz - 0.5) * 2.0);
		float solid = max(max(bar, cbar), edge);
		// How many bars fall in one pixel: far away, show the average.
		float px = fwidth(uv.x / bar_pitch);
		float far_blend = smoothstep(0.25, 0.6, px);
		float hole = (1.0 - solid) * (1.0 - far_blend);
		if (cut_holes && hole > 0.5) {
			discard;
		}
		vec3 col = mix(metal, metal * 0.35, far_blend * 0.45);
		// Painted kick strip with worn yellow and black chevrons.
		float stripe = step(0.5, fract((uv.y + uv.x * sign(uv.x)) * 0.8));
		vec3 paint = mix(edge_paint, vec3(0.05), stripe) * (0.75 + 0.3 * grime);
		float wear = smoothstep(0.35, 0.75, fbm(uv * 4.0));
		col = mix(col, mix(paint, metal, wear * 0.6), edge);
		col = mix(col, rust * (0.7 + 0.5 * grime), rust_mask);
		ALBEDO = col;
		METALLIC = mix(0.75, 0.2, max(edge, rust_mask));
		ROUGHNESS = mix(0.42, 0.85, max(rust_mask, edge * 0.6)) + grime * 0.1;
		// Raised bars catch the light across their tops.
		float slope = (bx - 0.5) * bar * (1.0 - far_blend);
		NORMAL_MAP = normalize(vec3(0.5 + slope * 0.6, 0.5, 1.0));
	} else {
		// Side girders: painted steel with drip streaks.
		vec2 uv = n.x > 0.5 ? local_pos.zy : local_pos.xy;
		float streak = fbm(vec2(uv.x * 3.0, uv.y * 0.4 + world_pos.y * 0.1));
		vec3 col = mix(edge_paint * 0.55, rust, smoothstep(0.45, 0.8, streak) * 0.8);
		col *= 0.75 + 0.35 * grime;
		ALBEDO = col;
		METALLIC = 0.35;
		ROUGHNESS = 0.6 + streak * 0.3;
	}
}
