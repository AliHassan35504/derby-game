shader_type spatial;
// The city far below an elevated interchange at night, on one big plane:
// a grid of wet streets with lane markings and streams of moving head and
// tail lights, pavements, and dark lots between them. World space.

uniform float block = 96.0;
uniform float street = 18.0;
uniform vec3 street_color : source_color = vec3(0.05, 0.05, 0.06);
uniform vec3 pavement_color : source_color = vec3(0.16, 0.16, 0.17);
uniform vec3 lot_color : source_color = vec3(0.08, 0.08, 0.09);
uniform float traffic = 1.0;

varying vec3 world_pos;

float hash1(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
			mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Moving lights along one lane: along is the coordinate down the street,
// lane picks the stream, dir is +1 or -1.
float cars(float along, float lane, float dir) {
	float speed = 12.0 + hash1(lane) * 8.0;
	float s = (along - dir * TIME * speed) / 11.0;
	float id = floor(s);
	float present = step(0.45, hash1(id + lane * 13.0));
	float f = fract(s);
	return present * (1.0 - smoothstep(0.0, 0.06, abs(f - 0.5) - 0.02));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Streets run along both axes, centred on multiples of the block size.
	vec2 off = mod(world_pos.xz + block * 0.5, block) - block * 0.5;
	vec2 cid = floor((world_pos.xz + block * 0.5) / block);
	bool on_z_street = abs(off.x) < street * 0.5;
	bool on_x_street = abs(off.y) < street * 0.5;
	float pave_w = 3.5;
	vec3 col = lot_color * (0.7 + 0.6 * noise(world_pos.xz * 0.05 + cid));
	float rough = 0.8;
	vec3 emit = vec3(0.0);
	float wet = 0.0;
	vec3 head_col = vec3(1.0, 0.92, 0.75) * 4.0;
	vec3 tail_col = vec3(1.0, 0.08, 0.04) * 3.0;
	if (on_x_street && on_z_street) {
		// Crossing: zebra stripes.
		col = street_color;
		float zebra = step(0.5, fract((world_pos.x + world_pos.z) / 1.4));
		col = mix(col, vec3(0.6), zebra * 0.25 * step(street * 0.5 - 3.0, max(abs(off.x), abs(off.y))));
		rough = 0.25;
		wet = 1.0;
	} else if (on_x_street) {
		col = street_color * (0.8 + 0.4 * noise(world_pos.xz * 3.0));
		float dash = step(0.5, fract(world_pos.x / 6.0)) * (1.0 - step(0.1, abs(off.y)));
		col = mix(col, vec3(0.7), dash * 0.6);
		float lane = cid.y * 2.0;
		float head = cars(world_pos.x, lane, 1.0) * (1.0 - step(1.1, abs(off.y - 3.0)));
		float tail = cars(world_pos.x, lane + 1.0, -1.0) * (1.0 - step(1.1, abs(off.y + 3.0)));
		emit += (head_col * head + tail_col * tail) * traffic;
		rough = 0.25;
		wet = 1.0;
	} else if (on_z_street) {
		col = street_color * (0.8 + 0.4 * noise(world_pos.xz * 3.0));
		float dash = step(0.5, fract(world_pos.z / 6.0)) * (1.0 - step(0.1, abs(off.x)));
		col = mix(col, vec3(0.7), dash * 0.6);
		float lane = cid.x * 2.0 + 50.0;
		float head = cars(world_pos.z, lane, 1.0) * (1.0 - step(1.1, abs(off.x - 3.0)));
		float tail = cars(world_pos.z, lane + 1.0, -1.0) * (1.0 - step(1.1, abs(off.x + 3.0)));
		emit += (head_col * head + tail_col * tail) * traffic;
		rough = 0.25;
		wet = 1.0;
	} else if (min(abs(off.x), abs(off.y)) < street * 0.5 + pave_w) {
		col = pavement_color * (0.85 + 0.3 * noise(world_pos.xz * 1.5));
		rough = 0.45;
		wet = 0.6;
		// Pools of street light on the pavement.
		vec2 lamp = mod(world_pos.xz, 24.0) - 12.0;
		emit += vec3(1.0, 0.6, 0.25) * (1.0 - smoothstep(1.0, 6.0, length(lamp))) * 0.25;
	}
	ALBEDO = col * (1.0 - wet * 0.3);
	ROUGHNESS = rough;
	SPECULAR = 0.5 + wet * 0.3;
	EMISSION = emit;
}
