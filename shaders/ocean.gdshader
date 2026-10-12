shader_type spatial;
// Animated open sea: summed directional waves move the vertices, with deep and
// shallow colours, sun glints, fresnel and foam on the crests.

render_mode cull_disabled;

uniform vec3 deep_color : source_color = vec3(0.02, 0.12, 0.2);
uniform vec3 shallow_color : source_color = vec3(0.08, 0.32, 0.4);
uniform vec3 foam_color : source_color = vec3(0.9, 0.95, 1.0);
uniform float wave_height = 0.9;
uniform float wave_speed = 1.0;

varying float crest;
varying vec3 world_pos;

float wave(vec2 p, vec2 dir, float freq, float speed, float t) {
	return sin(dot(p, normalize(dir)) * freq + t * speed);
}

float height_at(vec2 p, float t) {
	float h = 0.0;
	h += wave(p, vec2(1.0, 0.3), 0.06, 0.9, t) * 1.0;
	h += wave(p, vec2(-0.4, 1.0), 0.11, 1.3, t) * 0.5;
	h += wave(p, vec2(0.8, -0.7), 0.23, 1.9, t) * 0.22;
	h += wave(p, vec2(-1.0, -0.2), 0.47, 2.7, t) * 0.08;
	return h * wave_height;
}

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
			mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	float t = TIME * wave_speed;
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float h = height_at(p, t);
	VERTEX.y += h;
	float e = 0.5;
	float hx = height_at(p + vec2(e, 0.0), t);
	float hz = height_at(p + vec2(0.0, e), t);
	NORMAL = normalize(vec3(h - hx, e, h - hz));
	crest = h / max(wave_height, 0.001);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 col = mix(deep_color, shallow_color, clamp(crest * 0.5 + 0.5, 0.0, 1.0) * 0.6);
	float ripples = noise(world_pos.xz * 0.8 + TIME * 0.3) * noise(world_pos.xz * 2.3 - TIME * 0.2);
	float foam = smoothstep(0.75, 1.05, crest + ripples * 0.4);
	col = mix(col, foam_color, foam * 0.7);
	ALBEDO = col;
	ROUGHNESS = mix(0.04, 0.6, foam);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	RIM = 0.15;
	EMISSION = shallow_color * fresnel * 0.15;
}
