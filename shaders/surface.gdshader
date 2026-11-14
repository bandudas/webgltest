shader_type spatial;
render_mode unshaded;
#include "res://shaders/lit.gdshaderinc"

uniform sampler2D tex_albedo : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rough : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = true;
uniform bool use_rough_tex = true;
uniform vec3 tint : source_color = vec3(1.0);
uniform float tile = 1.0;
uniform float rough = 1.0;
uniform float spec_amt = 0.5;
uniform vec3 emission : source_color = vec3(0.0);

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_wtan = normalize((MODEL_MATRIX * vec4(TANGENT, 0.0)).xyz);
	v_wbin = normalize((MODEL_MATRIX * vec4(BINORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV / tile;
	vec3 alb = texture(tex_albedo, uv).rgb * tint;
	float r = use_rough_tex ? texture(tex_rough, uv).r * rough : rough;
	vec3 n = use_normal ? lit_normal(texture(tex_normal, uv).rgb, 1.0) : normalize(v_wnrm);
	ALBEDO = lit_shade(alb, n, r, spec_amt, CAMERA_POSITION_WORLD) + emission;
}
