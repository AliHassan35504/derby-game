shader_type spatial;
// A visible beam of light in hazy air, for searchlights and floodlights:
// additive, brightest along the beam's axis (where you look through the
// most air) and fading towards its far end. Put it on an open cone whose
// UV.y runs in metres from 0 at the lamp to length at the far end (as
// MeshKit.tube makes it).

render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec3 colour : source_color = vec3(0.9, 0.93, 1.0);
uniform float strength = 0.35;
uniform float flicker = 0.0;
uniform float length = 100.0;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float along = clamp(UV.y / length, 0.0, 1.0);
	float fade = pow(1.0 - along, 1.6) * smoothstep(0.0, 0.04, along);
	float wobble = 1.0 - flicker * 0.15 * sin(TIME * 23.0 + UV.x * 3.0);
	ALBEDO = colour * strength * pow(facing, 4.0) * fade * wobble;
}
