shader_type spatial;
// Pilar cahaya di atas peti harta, supaya terlihat dari jauh.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.75, 0.25);
uniform float height = 40.0;
uniform float strength = 1.0;
varying float ly;

void vertex() {
	ly = VERTEX.y / height + 0.5;
}

void fragment() {
	float edge = pow(abs(dot(NORMAL, VIEW)), 1.5);
	float pulse = 0.85 + 0.15 * sin(TIME * 2.5 - ly * 6.0);
	ALBEDO = color * (1.0 - ly) * edge * pulse * 0.6 * strength;
}
