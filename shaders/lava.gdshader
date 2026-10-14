shader_type spatial;
// A molten lava lake in world space: slow-drifting plates of dark cooling
// crust split by glowing cracks, with brighter upwellings that pulse. heat
// (set by the map) brightens everything during an eruption. A gentle swell
// moves the surface.

render_mode cull_disabled;

uniform vec3 crust : source_color = vec3(0.07, 0.04, 0.03);
uniform vec3 hot : source_color = vec3(1.0, 0.36, 0.05);
uniform vec3 white_hot : source_color = vec3(1.0, 0.85, 0.4);
uniform float heat = 0.0;
uniform float swell = 0.5;
uniform float vent_radius = 70.0;

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
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}
// Distance to the nearest edge between cells: the cracks between plates.
float cracks(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash2(i + g), hash2(i + g + 17.3));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += (sin(w.x * 0.05 + TIME * 0.4) + sin(w.z * 0.07 - TIME * 0.3)) * swell;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 flow = vec2(TIME * 0.35, TIME * 0.12);
	float warp = fbm(p * 0.02 + flow * 0.02);
	// Hot pools where the lake wells up, glowing veins winding between the
	// crust, and small cracked plates over the pools.
	float upwell = smoothstep(0.45, 0.8, fbm(p * 0.011 - flow * 0.025));
	// Hottest round the vent in the middle of the lake.
	upwell = max(upwell, smoothstep(vent_radius, vent_radius * 0.25, length(p)) * 0.85);
	float vein_noise = fbm(p * 0.025 + vec2(warp * 2.5) + flow * 0.015);
	float veins = 1.0 - smoothstep(0.0, 0.035 + 0.08 * upwell + 0.04 * heat, abs(vein_noise - 0.5));
	float c = cracks(p * 0.11 + vec2(warp * 2.0) + flow * 0.04);
	float plates = (1.0 - smoothstep(0.0, 0.05 + 0.12 * upwell, c)) * smoothstep(0.1, 0.6, upwell + 0.25);
	float pulse = 0.75 + 0.25 * sin(TIME * 1.3 + warp * 12.0);
	float h = clamp(max(veins, plates) + upwell * pulse * 0.55 + heat * 0.2, 0.0, 1.0);
	vec3 col = mix(crust * (0.7 + 0.6 * fbm(p * 0.5)), hot, h);
	col = mix(col, white_hot, smoothstep(0.75, 1.0, h) * 0.6);
	ALBEDO = col * 0.4;
	EMISSION = mix(crust * 0.1, hot * 1.8 + white_hot * h * 0.9, h * h) * (1.0 + heat * 0.8);
	ROUGHNESS = mix(0.95, 0.4, h);
}
