shader_type spatial;
// Space station plating. Object space on a road or pad box: off-white
// panels with dark seams and rivet rows, yellow and black hazard bands down
// both edges, and blue guide lights along the centre (on pads, a ring of
// them round a landing circle). Sides and the world-space mode (structure
// round the arena) are plain panelling with grime.

uniform vec3 panel : source_color = vec3(0.78, 0.79, 0.8);
uniform vec3 hazard : source_color = vec3(1.0, 0.75, 0.05);
uniform vec3 guide : source_color = vec3(0.2, 0.6, 1.0);
uniform float road_width = 5.0;
uniform bool pad = false;
uniform float pad_size = 14.0;
uniform bool world_mode = false;

varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 world_pos;
varying vec3 world_normal;

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
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = world_mode ? abs(world_normal) : abs(local_normal);
	vec3 pos = world_mode ? world_pos : local_pos;
	vec2 uv = n.y > 0.5 ? pos.xz : (n.x > n.z ? pos.zy : pos.xy);
	vec2 cell = floor(uv / vec2(1.25, 2.5));
	float tone = hash2(cell);
	vec3 col = panel * (0.86 + 0.14 * tone) * COLOR.rgb;
	vec2 f = abs(fract(uv / vec2(1.25, 2.5)) - 0.5);
	float seam = 1.0 - smoothstep(0.46, 0.49, max(f.x * 1.0, f.y));
	// Far away the seams are thinner than a pixel: fade them to their average.
	float far_blend = smoothstep(0.08, 0.3, max(fwidth(uv.x / 1.25), fwidth(uv.y / 2.5)));
	seam = mix(seam, 0.93, far_blend);
	col *= 0.55 + 0.45 * seam;
	float grime = noise(uv * 0.6) * noise(uv * 3.1);
	col *= 1.0 - grime * 0.25;
	vec3 emit = vec3(0.0);
	float metal = 0.35;
	float rough = 0.45 + tone * 0.2;
	if (!world_mode && local_normal.y > 0.5) {
		if (pad) {
			float half_s = pad_size * 0.5;
			float edge = step(half_s - 0.8, max(abs(uv.x), abs(uv.y)));
			float stripe = step(0.5, fract((uv.x + uv.y) * 0.6));
			col = mix(col, mix(hazard, vec3(0.04), stripe), edge);
			float r = length(uv);
			float ring = step(abs(r - half_s * 0.55), 0.12);
			col = mix(col, guide * 0.5, ring);
			float ang = atan(uv.y, uv.x);
			float dots = step(0.86, fract(ang / 6.2832 * 16.0)) * step(abs(r - half_s * 0.55), 0.3);
			emit = guide * (ring * 0.6 + dots * 3.0);
		} else {
			float half_w = road_width * 0.5;
			float edge = step(half_w - 0.42, abs(uv.x));
			float stripe = step(0.5, fract(uv.y * 0.6 + abs(uv.x) * 0.6));
			col = mix(col, mix(hazard, vec3(0.04), stripe), edge);
			float centre = step(abs(uv.x), 0.12) * step(0.7, fract(uv.y / 3.0));
			emit = guide * centre * 2.5;
			col = mix(col, guide, centre);
		}
		metal = 0.2;
	}
	ALBEDO = col;
	EMISSION = emit;
	METALLIC = metal;
	ROUGHNESS = rough;
}
