// Pencahayaan satu pass untuk semua lampu (pengganti OmniLight3D).
// Renderer Compatibility menggambar ulang objek per lampu; di sini semua lampu dihitung sekaligus.

global uniform float neon0;
global uniform float neon1;
global uniform float neon2;

uniform int light_count = 0;
uniform vec4 lpos[10];   // xyz = posisi dunia, w = jangkauan (m)
uniform vec4 lcol[10];   // rgb = warna x energi, w = kanal kedip (-1 = tidak berkedip, 0..2 = neon)
uniform vec3 ambient : source_color = vec3(0.15, 0.16, 0.22);
uniform vec3 moon_dir = vec3(-0.45, 0.75, 0.35);
uniform vec3 moon_col : source_color = vec3(0.08, 0.1, 0.16);

varying vec3 v_wpos;
varying vec3 v_wnrm;
varying vec3 v_wtan;
varying vec3 v_wbin;

float _flick(float ch) {
	if (ch < -0.5) return 1.0;
	if (ch < 0.5) return neon0;
	if (ch < 1.5) return neon1;
	return neon2;
}


vec3 lit_normal(vec3 nm, float strength) {
	vec3 t = nm * 2.0 - 1.0;
	t.xy *= strength;
	return normalize(v_wtan * t.x + v_wbin * t.y + v_wnrm * t.z);
}

// Mengembalikan warna akhir: albedo * cahaya_difus + kilau.
vec3 lit_shade(vec3 albedo, vec3 n, float rough, float spec_amt, vec3 cam) {
	vec3 v = normalize(cam - v_wpos);
	vec3 diff = ambient + moon_col * max(dot(n, normalize(moon_dir)), 0.0);
	vec3 spec = vec3(0.0);
	float shin = mix(80.0, 6.0, rough);
	for (int i = 0; i < 10; i++) {
		if (i >= light_count) break;
		vec3 d = lpos[i].xyz - v_wpos;
		float dist = length(d);
		float att = clamp(1.0 - dist / lpos[i].w, 0.0, 1.0);
		if (att <= 0.0) continue;
		att *= att;
		vec3 l = d / dist;
		vec3 c = lcol[i].rgb * _flick(lcol[i].w) * att;
		diff += c * max(dot(n, l), 0.0);
		vec3 h = normalize(l + v);
		spec += c * pow(max(dot(n, h), 0.0), shin) * (1.0 - rough) * spec_amt;
	}
	return albedo * diff + spec;
}
