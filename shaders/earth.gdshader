shader_type spatial;
// The Earth seen from low orbit, on a big sphere: deep oceans with a sun
// glint, continents (procedural, in direction space so they wrap the
// sphere), drifting clouds and a soft blue limb where the atmosphere
// thickens. City lights glow on the night side.

uniform vec3 ocean : source_color = vec3(0.02, 0.09, 0.25);
uniform vec3 shallow : source_color = vec3(0.05, 0.25, 0.4);
uniform vec3 land : source_color = vec3(0.22, 0.3, 0.14);
uniform vec3 desert : source_color = vec3(0.55, 0.45, 0.3);
uniform vec3 atmosphere : source_color = vec3(0.35, 0.6, 1.0);
uniform vec3 centre = vec3(0.0, -4800.0, 0.0);

varying vec3 world_pos;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x), u.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}
float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		v += a * noise3(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 d = normalize(world_pos - centre);
	float continents = fbm3(d * 9.0 + vec3(3.1, 0.0, 1.7));
	float is_land = smoothstep(0.52, 0.56, continents);
	float coast = smoothstep(0.47, 0.52, continents) * (1.0 - is_land);
	float dry = smoothstep(0.45, 0.65, fbm3(d * 22.0 + 8.0));
	vec3 ground = mix(land, desert, dry) * (0.8 + 0.4 * fbm3(d * 60.0));
	vec3 col = mix(ocean, shallow, coast);
	col = mix(col, ground, is_land);
	float clouds = smoothstep(0.5, 0.75, fbm3(d * 14.0 + vec3(TIME * 0.002, 0.0, TIME * 0.001)));
	clouds = max(clouds, smoothstep(0.62, 0.8, fbm3(d * 40.0 - vec3(0.0, TIME * 0.003, 0.0))) * 0.7);
	col = mix(col, vec3(0.95), clouds);
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float limb = pow(1.0 - facing, 3.0);
	ALBEDO = col;
	ROUGHNESS = mix(0.25, 0.9, max(is_land, clouds));
	SPECULAR = mix(0.8, 0.2, max(is_land, clouds));
	// The atmosphere scatters blue light at grazing angles.
	EMISSION = atmosphere * limb * 0.9 + col * 0.04;
}
