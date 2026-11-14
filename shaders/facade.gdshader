shader_type spatial;
render_mode unshaded;
#include "res://shaders/lit.gdshaderinc"
// Fasad gedung: tekstur foto bata + jendela prosedural (sebagian menyala).
// UV mesh dalam meter: UV.x = sepanjang dinding, -UV.y = tinggi dari dasar gedung.

uniform sampler2D tex_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rough : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = true;
uniform float tile = 3.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float ground_floor = 4.2;
uniform float top_h = 20.0;
uniform float floor_h = 3.3;
uniform float win_w = 2.8;
uniform float seed = 0.0;
uniform float lit_ratio = 0.3;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1)) + seed * 17.13) * 43758.5453);
}

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_wtan = normalize((MODEL_MATRIX * vec4(TANGENT, 0.0)).xyz);
	v_wbin = normalize((MODEL_MATRIX * vec4(BINORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV / tile;
	vec3 alb = texture(tex_albedo, uv).rgb * tint;
	float r = texture(tex_rough, uv).r;
	vec3 n = use_normal ? lit_normal(texture(tex_normal, uv).rgb, 1.0) : normalize(v_wnrm);
	float spec = 0.25;
	vec3 emis = vec3(0.0);

	float h = -UV.y;
	if (abs(v_wnrm.y) < 0.5 && h > ground_floor && h < top_h - 0.8) {
		vec2 cell = vec2(UV.x / win_w, (h - ground_floor) / floor_h);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		float inside = step(0.24, f.x) * step(f.x, 0.76) * step(0.2, f.y) * step(f.y, 0.8);
		float frame = step(0.2, f.x) * step(f.x, 0.8) * step(0.14, f.y) * step(f.y, 0.86);
		if (inside > 0.5) {
			alb = vec3(0.025, 0.03, 0.04);
			r = 0.06;
			spec = 1.0;
			n = normalize(v_wnrm);
			if (hash(id) < lit_ratio) {
				vec3 warm = mix(vec3(1.0, 0.68, 0.34), vec3(0.55, 0.7, 1.0), step(0.85, hash(id + 7.0)));
				float curtain = 0.45 + 0.55 * hash(id + 3.0);
				emis = warm * curtain * mix(0.55, 1.0, smoothstep(0.2, 0.8, f.y)) * 1.3;
			}
		} else if (frame > 0.5) {
			alb = mix(alb, vec3(0.32, 0.3, 0.28), 0.6);
			n = normalize(v_wnrm);
		}
	}
	ALBEDO = lit_shade(alb, n, r, spec, CAMERA_POSITION_WORLD) + emis;
}
