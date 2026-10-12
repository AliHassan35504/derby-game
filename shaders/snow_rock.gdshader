shader_type spatial;
// Dark granite with snow lying on everything that faces up. Snow cover
// breaks up with noise and thins on steep faces; it glints with tiny
// sparkles that shift as the camera moves. World space; the vertex colour
// tints the rock.

uniform vec3 rock : source_color = vec3(0.3, 0.31, 0.34);
uniform vec3 rock_dark : source_color = vec3(0.15, 0.15, 0.17);
uniform vec3 snow : source_color = vec3(0.9, 0.93, 0.98);
uniform vec3 snow_shadow : source_color = vec3(0.62, 0.7, 0.86);
uniform float snow_amount = 0.6;
uniform float sparkle = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
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
		p = p * 2.07 + vec2(1.3, 7.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 an = abs(n);
	vec2 side = an.x > an.z ? world_pos.zy : world_pos.xy;
	vec2 p = an.y > 0.7 ? world_pos.xz : side;
	// Granite: mottled, with dark cracks and pale veins.
	float m = fbm(p * 0.25);
	float crack = smoothstep(0.92, 0.98, 1.0 - abs(noise(p * 0.6) * 2.0 - 1.0));
	vec3 col = mix(rock_dark, rock, m) * COLOR.rgb;
	col *= 1.0 - crack * 0.5;
	col += vec3(0.12) * smoothstep(0.96, 0.99, 1.0 - abs(noise(p * 1.3 + 4.0) * 2.0 - 1.0));
	// Snow on upward faces.
	float cover = n.y + (fbm(world_pos.xz * 0.08) - 0.5) * 0.6 + (snow_amount - 0.5);
	float snow_mask = smoothstep(0.45, 0.62, cover);
	// Wind-packed snow with soft ripples, bluer where it faces away.
	float ripple = noise(world_pos.xz * vec2(0.6, 2.0)) * 0.5 + noise(world_pos.xz * 4.0) * 0.5;
	vec3 snow_col = mix(snow_shadow, snow, 0.75 + 0.25 * ripple);
	col = mix(col, snow_col, snow_mask);
	ALBEDO = col;
	ROUGHNESS = mix(0.82, 0.55, snow_mask);
	SPECULAR = mix(0.3, 0.45, snow_mask);
	// Sparkles: tiny cells that light up for some view directions.
	vec3 cell = floor(world_pos * 22.0);
	vec3 view_world = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;
	float glint = hash3(cell + floor(view_world * 7.0) * 17.0);
	float dist_fade = 1.0 - smoothstep(25.0, 70.0, length(VERTEX));
	EMISSION = vec3(1.0, 0.98, 0.94) * step(0.996, glint) * snow_mask * sparkle * dist_fade * 3.0;
	vec2 bump = vec2(noise(p * 2.0) - 0.5, noise(p * 2.0 + 9.0) - 0.5);
	NORMAL_MAP = normalize(vec3(0.5 + bump.x * mix(0.6, 0.15, snow_mask), 0.5 + bump.y * mix(0.6, 0.15, snow_mask), 1.0));
}
