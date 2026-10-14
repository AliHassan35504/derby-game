shader_type spatial;
// Spectators for a MultiMesh of small boxes: each copy's colour is its
// shirt, and custom data r is a phase so the crowd bobs and jumps out of
// step, with a Mexican wave running round the stands. g > 0.5 marks a fan
// waving a phone light.

uniform float excitement = 1.0;
uniform float wave_speed = 0.35;

varying vec4 custom;
varying vec3 shirt;
varying float local_y;

void vertex() {
	custom = INSTANCE_CUSTOM;
	shirt = COLOR.rgb;
	local_y = VERTEX.y;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float angle = atan(origin.z, origin.x);
	float wave = smoothstep(0.85, 1.0, sin(angle * 2.0 - TIME * wave_speed * 6.2832));
	float bob = max(sin(TIME * (5.0 + custom.r * 4.0) + custom.r * 40.0), 0.0) * 0.12;
	// Arms up and a jump as the wave passes.
	VERTEX.y += (bob + wave * 0.5) * excitement * step(-0.2, VERTEX.y);
	VERTEX.y *= 1.0 + wave * 0.35 * step(0.0, VERTEX.y);
}

void fragment() {
	// Head on top, shirt below, dark legs.
	vec3 skin = mix(vec3(0.85, 0.65, 0.5), vec3(0.35, 0.22, 0.15), custom.b);
	vec3 col = local_y > 0.3 ? skin : (local_y < -0.1 ? vec3(0.08) : shirt);
	ALBEDO = col;
	ROUGHNESS = 0.9;
	EMISSION = custom.g > 0.5 && local_y > 0.3 ? vec3(0.9, 0.95, 1.0) * 2.5 * step(0.5, fract(TIME * 0.7 + custom.r * 7.0)) : vec3(0.0);
}
