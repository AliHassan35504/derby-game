shader_type spatial;
// Weathered timber for trestles, posts and beams: grey-brown sun-bleached
// wood with grain running along the member, dark checks (cracks) and tar
// streaks near joints. Works from the mesh UVs (MeshKit gives every face
// UVs in metres), so the grain follows each face.

uniform vec3 wood : source_color = vec3(0.47, 0.36, 0.25);
uniform vec3 bleached : source_color = vec3(0.62, 0.58, 0.52);
uniform float weathering = 0.5;

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
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// The longer UV axis on a face runs along the member.
	vec2 uv = UV;
	vec2 g = vec2(uv.x * 14.0, uv.y * 0.8);
	float grain = fbm(g + fbm(g * 0.5) * 1.5);
	float rings = sin(g.x * 2.0 + grain * 6.0) * 0.5 + 0.5;
	vec3 col = mix(wood * 0.75, wood, grain * 0.7 + rings * 0.3);
	float weather = fbm(world_pos.xz * 0.2 + world_pos.y * 0.15);
	col = mix(col, bleached * (0.8 + 0.3 * grain), weather * weathering);
	// Checks: thin dark cracks along the grain.
	float check = smoothstep(0.92, 0.97, noise(vec2(uv.x * 40.0, uv.y * 1.5)));
	col *= 1.0 - check * 0.6;
	col *= COLOR.rgb;
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
	NORMAL_MAP = normalize(vec3(0.5 + (grain - 0.5) * 0.35 - check * 0.3, 0.5, 1.0));
}
