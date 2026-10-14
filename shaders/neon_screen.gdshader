shader_type spatial;
// An animated advertising screen for night scenes: slow-moving bands of
// colour, a scrolling stripe and a scanline grain. Unshaded and bright, so
// it glows. Uses UV (0..1 on a QuadMesh or PlaneMesh face).

render_mode unshaded;

uniform vec3 colour_a : source_color = vec3(1.0, 0.1, 0.6);
uniform vec3 colour_b : source_color = vec3(0.1, 0.6, 1.0);
uniform float brightness = 2.2;
uniform float seed = 0.0;

void fragment() {
	vec2 uv = UV;
	float t = TIME * 0.4 + seed * 10.0;
	float wave = sin(uv.x * 6.0 + t * 2.0 + sin(uv.y * 4.0 + t) * 1.5) * 0.5 + 0.5;
	vec3 col = mix(colour_a, colour_b, wave);
	float stripe = step(0.85, fract(uv.y * 3.0 - t * 0.5));
	col = mix(col, vec3(1.0), stripe * 0.6);
	float blink = step(0.5, fract(t * 0.25 + seed));
	float circle = 1.0 - smoothstep(0.18, 0.2, length((uv - vec2(0.7, 0.5)) * vec2(1.6, 1.0)));
	col = mix(col, vec3(1.0, 0.95, 0.6), circle * blink * 0.8);
	float scan = 0.85 + 0.15 * sin(uv.y * 400.0);
	float edge = smoothstep(0.0, 0.02, uv.x) * smoothstep(0.0, 0.02, 1.0 - uv.x) * smoothstep(0.0, 0.03, uv.y) * smoothstep(0.0, 0.03, 1.0 - uv.y);
	ALBEDO = col * scan * edge * brightness;
}
