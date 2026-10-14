shader_type spatial;
// Dark asphalt road with worn edge lines and a dashed centre line. Object
// space: local X across the road, local Z along it.

uniform vec3 asphalt : source_color = vec3(0.13, 0.13, 0.14);
uniform vec3 line_color : source_color = vec3(0.92, 0.78, 0.2);
uniform float road_width = 5.0;

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

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec2 uv = local_pos.xz;
	float grit = noise(uv * 18.0) * 0.5 + noise(uv * 61.0) * 0.5;
	float patches = noise(uv * 0.4);
	vec3 col = asphalt * (0.75 + 0.5 * grit) * (0.85 + 0.3 * patches);
	float rough = 0.85 + 0.1 * grit;

	if (abs(local_normal.y) > 0.5) {
		float half_w = road_width * 0.5;
		float edge_line = step(half_w - 0.35, abs(uv.x)) * step(abs(uv.x), half_w - 0.2);
		float dash = step(0.5, fract(uv.y / 4.0));
		float centre = step(abs(uv.x), 0.08) * dash;
		float wear = smoothstep(0.3, 0.7, noise(uv * 3.0));
		float paint = max(edge_line, centre) * wear;
		vec3 paint_col = edge_line > 0.5 ? vec3(0.9) : line_color;
		col = mix(col, paint_col, paint);
		rough = mix(rough, 0.6, paint);
	} else {
		col *= 0.7;
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	NORMAL_MAP = normalize(vec3(0.5 + (grit - 0.5) * 0.3, 0.5 + (noise(uv * 30.0) - 0.5) * 0.3, 1.0));
}
