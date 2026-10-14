shader_type spatial;
// Stadium track deck: dark asphalt with red and white kerbs along both
// edges and a dashed centre line. Jump kickers (anything standing above the
// deck top) get yellow and black chevrons so they read from far away. Pads
// get a chequered border instead. Object space: local X across, Z along.

uniform vec3 asphalt : source_color = vec3(0.11, 0.11, 0.12);
uniform vec3 kerb_red : source_color = vec3(0.85, 0.08, 0.06);
uniform vec3 hazard : source_color = vec3(1.0, 0.78, 0.05);
uniform float road_width = 5.0;
// Height of the flat deck's top in object space.
uniform float deck_top = 0.225;
uniform bool pad = false;
uniform float pad_size = 14.0;

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
	float grit = noise(uv * 18.0) * 0.5 + noise(uv * 57.0) * 0.5;
	vec3 col = asphalt * (0.75 + 0.5 * grit);
	float rough = 0.8 + 0.1 * grit;
	vec3 emit = vec3(0.0);
	bool kicker = !pad && local_pos.y > deck_top + 0.03;
	if (local_normal.y > 0.5) {
		if (pad) {
			float half_s = pad_size * 0.5;
			float border = step(half_s - 1.1, max(abs(uv.x), abs(uv.y)));
			vec2 cell = floor(uv / 0.55);
			float check = mod(cell.x + cell.y, 2.0);
			col = mix(col, mix(vec3(0.92), vec3(0.04), check), border);
			// A painted ring in the middle.
			float r = length(uv);
			float ring = step(abs(r - half_s * 0.45), 0.18);
			col = mix(col, vec3(0.9, 0.9, 0.85), ring * 0.8);
		} else if (kicker) {
			float chevron = step(0.5, fract(uv.y * 0.9 + abs(uv.x) * 0.45));
			col = mix(hazard, vec3(0.03), chevron);
			emit = hazard * (1.0 - chevron) * 0.25;
			rough = 0.5;
		} else {
			float half_w = road_width * 0.5;
			float kerb = step(half_w - 0.45, abs(uv.x));
			float stripe = step(0.5, fract(uv.y / 2.0));
			col = mix(col, mix(kerb_red, vec3(0.92), stripe), kerb);
			float dash = step(0.55, fract(uv.y / 5.0)) * step(abs(uv.x), 0.09);
			col = mix(col, vec3(0.85), dash);
			rough = mix(rough, 0.55, kerb);
		}
	} else if (kicker) {
		// The kicker's face over the gap: hazard stripes.
		float s = step(0.5, fract((local_pos.x + local_pos.y) * 1.2));
		col = mix(hazard, vec3(0.03), s);
		emit = hazard * (1.0 - s) * 0.3;
	} else {
		col = mix(vec3(0.85, 0.85, 0.86), kerb_red, step(0.5, fract(uv.y / 2.0))) * 0.6;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = emit;
}
