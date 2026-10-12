shader_type spatial;
// A slowly drifting sea of clouds seen from above.

render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec3 cloud_color : source_color = vec3(0.97, 0.98, 1.0);
uniform vec3 shadow_color : source_color = vec3(0.68, 0.74, 0.84);
uniform float scale = 0.012;

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
		p = p * 2.1 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz * scale + vec2(TIME * 0.004, TIME * 0.002);
	float d = fbm(p);
	float density = smoothstep(0.35, 0.75, d);
	float light = smoothstep(0.3, 0.9, fbm(p * 1.7 + 3.0));
	ALBEDO = mix(shadow_color, cloud_color, light);
	float fade = 1.0 - smoothstep(600.0, 1400.0, length(world_pos.xz));
	ALPHA = clamp(density * 0.95 + 0.25, 0.0, 1.0) * fade;
}
