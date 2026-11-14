shader_type spatial;
render_mode specular_schlick_ggx, cull_back;

uniform float wave_time = 0.0;
uniform vec3 deep_color : source_color = vec3(0.04, 0.27, 0.42);
uniform vec3 shallow_color : source_color = vec3(0.25, 0.78, 0.74);
uniform vec3 sky_color : source_color = vec3(0.7, 0.8, 0.9);
uniform int island_count = 0;
// xy = pusat pulau (x, z), z = radius garis pantai rata-rata
uniform vec4 islands[16];

varying vec3 wpos;
varying float shallow;

// Harus sama dengan scripts/waves.gd
float wave(vec2 p, float t) {
	return sin(p.x * 0.15 + t * 1.1) * 0.18
		+ sin(p.y * 0.21 - t * 0.9) * 0.14
		+ sin((p.x + p.y) * 0.33 + t * 1.7) * 0.06;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = wave(w.xz, wave_time);
	float e = 0.6;
	float hx = wave(w.xz + vec2(e, 0.0), wave_time);
	float hz = wave(w.xz + vec2(0.0, e), wave_time);
	VERTEX.y += h;
	NORMAL = normalize(vec3(h - hx, e, h - hz));

	// Air dangkal (laguna) dihitung per verteks: jauh lebih murah daripada per piksel.
	float s = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= island_count) {
			break;
		}
		float d = length(w.xz - islands[i].xy) - islands[i].z;
		s = max(s, 1.0 - smoothstep(-2.0, islands[i].z * 0.5 + 8.0, d));
	}
	shallow = s;
	wpos = w;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 base = mix(deep_color, shallow_color, shallow * 0.9);
	float ripple = sin(wpos.x * 1.7 + wave_time * 2.3) * sin(wpos.z * 1.3 - wave_time * 1.9);
	ALBEDO = mix(base, sky_color, fres * 0.4) + ripple * 0.02;
	ROUGHNESS = 0.2;
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
