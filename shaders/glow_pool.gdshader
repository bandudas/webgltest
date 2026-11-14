shader_type spatial;
// Genangan cahaya palsu di tanah di bawah lampu jalan (trik klasik era PS2: murah, tanpa lampu tambahan).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.6, 0.28);
uniform float strength = 0.55;

void fragment() {
	vec2 d = UV - 0.5;
	float a = 1.0 - smoothstep(0.0, 0.5, length(d));
	ALBEDO = color * a * a * strength;
}
