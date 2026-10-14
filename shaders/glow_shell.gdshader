shader_type spatial;
// Additive energy shell: bright at the silhouette, clear in the middle.
// Used for pickup orbs, the Ram glow round a car and the shockwave bubble.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float power = 2.2;
uniform float strength = 1.0;
uniform float core = 0.06;

void fragment() {
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), power);
	ALBEDO = tint.rgb * (rim + core) * strength * 2.0;
}
