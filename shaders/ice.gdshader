shader_type spatial;
// Glassy blue road ice for mountain ledges and bridges, with snow drifted
// along both edges, polished wheel tracks, white crack lines and frost.
// Object space (local X across, Z along). With world_mode it covers a big
// flat plane instead, as a frozen lake with snow patches and pressure
// cracks.

uniform vec3 ice_deep : source_color = vec3(0.32, 0.46, 0.58);
uniform vec3 ice_light : source_color = vec3(0.68, 0.8, 0.88);
uniform vec3 snow : source_color = vec3(0.9, 0.93, 0.98);
uniform vec3 side_color : source_color = vec3(0.55, 0.62, 0.7);
uniform float road_width = 5.5;
uniform bool world_mode = false;
uniform float snow_patches = 0.3;

varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 world_pos;

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
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
		p = p * 2.03 + vec2(4.1, 1.3);
		a *= 0.5;
	}
	return v;
}
// Distance to the nearest cell edge of a jittered grid: crack lines.
float cracks(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 9.0;
	float d2 = 9.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash2(i + g), hash2(i + g + 17.0));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (local_normal.y > 0.5 || world_mode) {
		vec2 uv = world_mode ? world_pos.xz : local_pos.xz;
		float depth = fbm(world_pos.xz * 0.15);
		vec3 col = mix(ice_deep, ice_light, depth * 0.8 + 0.1);
		// White crack lines, big and small.
		float crack = 1.0 - smoothstep(0.0, 0.05, cracks(uv * (world_mode ? 0.05 : 0.35)));
		crack = max(crack, (1.0 - smoothstep(0.0, 0.04, cracks(uv * 1.3 + 5.0))) * 0.5);
		col = mix(col, vec3(0.92, 0.96, 1.0), crack * 0.6);
		// Frost and loose snow.
		float frost = smoothstep(0.55, 0.8, fbm(uv * 0.6 + 2.0));
		float drift = 0.0;
		float tracks = 0.0;
		if (!world_mode) {
			float half_w = road_width * 0.5;
			drift = smoothstep(half_w - 1.3, half_w - 0.35, abs(uv.x) + (noise(uv * vec2(0.7, 0.25)) - 0.5) * 0.9);
			tracks = 1.0 - smoothstep(0.2, 0.45, abs(abs(uv.x) - 0.8));
			frost *= 1.0 - tracks;
		} else {
			drift = smoothstep(0.55, 0.75, fbm(uv * 0.01)) * snow_patches + smoothstep(0.6, 0.85, fbm(uv * 0.08)) * snow_patches;
		}
		float snow_mask = clamp(max(drift, frost * 0.55), 0.0, 1.0);
		col = mix(col, snow * (0.85 + 0.15 * noise(uv * 3.0)), snow_mask);
		col *= 1.0 - tracks * 0.12;
		ALBEDO = col;
		ROUGHNESS = mix(mix(0.12, 0.03, tracks), 0.65, snow_mask) + crack * 0.2;
		SPECULAR = 0.7;
		METALLIC = 0.0;
		vec3 view_world = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;
		float glint = hash3(floor(world_pos * 24.0) + floor(view_world * 7.0) * 13.0);
		float dist_fade = 1.0 - smoothstep(20.0, 60.0, length(VERTEX));
		EMISSION = vec3(1.0) * step(0.995, glint) * snow_mask * dist_fade * 3.0;
		vec2 bump = vec2(noise(uv * 5.0) - 0.5, noise(uv * 5.0 + 3.0) - 0.5) * (0.12 + snow_mask * 0.3) + vec2(crack) * 0.15;
		NORMAL_MAP = normalize(vec3(0.5 + bump.x, 0.5 + bump.y, 1.0));
	} else {
		// Sides: packed snow and ice with streaks.
		float streak = fbm(vec2((world_pos.x + world_pos.z) * 1.5, world_pos.y * 0.4));
		ALBEDO = mix(side_color, snow, smoothstep(0.3, 0.7, streak));
		ROUGHNESS = 0.4;
	}
}
