shader_type spatial;
// Layered desert sandstone in world space. Colour comes in horizontal
// strata (warped a little so they wander), with dark desert-varnish streaks
// running down the cliffs, ledges catching the light where layers step, and
// pale wind-blown sand on anything flat. Vertex colour tints it (terrain
// uses it for river banks and scrub).

uniform vec3 deep_red : source_color = vec3(0.5, 0.19, 0.1);
uniform vec3 orange : source_color = vec3(0.68, 0.33, 0.16);
uniform vec3 cream : source_color = vec3(0.74, 0.55, 0.38);
uniform vec3 maroon : source_color = vec3(0.36, 0.15, 0.1);
uniform vec3 sand : source_color = vec3(0.6, 0.39, 0.24);
uniform vec3 varnish : source_color = vec3(0.18, 0.11, 0.08);
// Thickness of the big rock units, and of the fine beds inside them.
uniform float unit_height = 11.0;
uniform float band_height = 1.4;
uniform float sand_cover = 1.0;
uniform float bump = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

float hash1(float n) { return fract(sin(n * 127.1) * 43758.5453); }
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
		p = p * 2.03 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return v;
}

vec3 palette(float h) {
	return h < 0.36 ? deep_red : (h < 0.7 ? orange : (h < 0.85 ? maroon : cream));
}

vec3 strata(float y) {
	float u = y / unit_height;
	float id = floor(u);
	float f = fract(u);
	vec3 col = mix(palette(hash1(id)), palette(hash1(id + 1.0)), smoothstep(0.88, 1.0, f));
	// Fine beds inside each unit: small shifts in tone.
	float b = y / band_height;
	float bed = mix(hash1(floor(b) + id * 7.0), hash1(floor(b) + 1.0 + id * 7.0), smoothstep(0.7, 1.0, fract(b)));
	col *= 0.86 + 0.2 * bed;
	col *= 0.95 + 0.05 * sin(b * 18.85 + sin(b * 2.0) * 2.0);
	return col;
}

// Ledge profile: each bed's top sticks out a little, unit tops more.
float ledge(float y) {
	float f = fract(y / band_height);
	float g = fract(y / unit_height);
	return smoothstep(0.0, 0.15, f) * (1.0 - smoothstep(0.85, 1.0, f)) * 0.4
			+ smoothstep(0.0, 0.04, g) * (1.0 - smoothstep(0.96, 1.0, g));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 an = abs(n);
	float warp = (fbm(world_pos.xz * 0.008) - 0.5) * 9.0 + (noise(world_pos.xz * 0.05) - 0.5) * 1.2;
	float y = world_pos.y + warp;
	vec2 side = an.x > an.z ? world_pos.zy : world_pos.xy;
	vec3 col = strata(y);
	float grain = noise(side * 6.0) * 0.5 + noise(world_pos.xz * 6.0) * 0.5;
	col *= 0.88 + 0.2 * grain;
	// Desert varnish streaks down steep faces.
	float steep = 1.0 - smoothstep(0.35, 0.7, an.y);
	float streak = fbm(vec2(side.x * 0.35, world_pos.y * 0.02));
	col = mix(col, varnish, smoothstep(0.55, 0.8, streak) * steep * 0.55);
	// Sand settles on flat tops.
	// Flat tops: bare slickrock with joints and pits, and drifts of sand.
	float flat_top = smoothstep(0.7, 0.92, n.y);
	float slab = fbm(world_pos.xz * 0.6);
	vec3 slick = col * (0.72 + 0.42 * slab) * (0.9 + 0.15 * noise(world_pos.xz * 9.0));
	float joint = smoothstep(0.94, 0.99, 1.0 - abs(noise(world_pos.xz * 0.3) * 2.0 - 1.0));
	joint = max(joint, smoothstep(0.95, 0.995, 1.0 - abs(noise(world_pos.xz * 0.9 + 7.0) * 2.0 - 1.0)) * 0.7);
	slick *= 1.0 - joint * 0.3;
	col = mix(col, slick, flat_top);
	float drift = fbm(world_pos.xz * 0.15);
	// Wind ripples and grit in the sand.
	float ripples = sin(dot(world_pos.xz, vec2(0.8, 0.6)) * 5.0 + noise(world_pos.xz * 0.7) * 6.0) * 0.5 + 0.5;
	vec3 sand_col = sand * (0.78 + 0.25 * drift) * (0.92 + 0.12 * ripples) * (0.9 + 0.2 * noise(world_pos.xz * 14.0));
	col = mix(col, sand_col, flat_top * sand_cover * smoothstep(0.5, 0.72, drift));
	col *= COLOR.rgb;
	ALBEDO = col;
	ROUGHNESS = 0.93;
	SPECULAR = 0.25;
	// Bump: layer ledges on cliffs, wind-carved noise everywhere.
	float e = 0.08;
	float dy = (ledge(y + e) - ledge(y - e)) / (2.0 * e);
	vec2 q = world_pos.xz * 0.7;
	float gx = noise(q + vec2(0.05, 0.0)) - noise(q - vec2(0.05, 0.0));
	float gz = noise(q + vec2(0.0, 0.05)) - noise(q - vec2(0.0, 0.05));
	vec3 pert = vec3(gx, 0.0, gz) * 4.0 * (1.0 - steep * 0.5) - vec3(0.0, 1.0, 0.0) * dy * 0.06 * steep;
	pert -= n * dot(pert, n);
	vec3 bent = normalize(n - pert * bump);
	NORMAL = normalize((VIEW_MATRIX * vec4(bent, 0.0)).xyz);
}
