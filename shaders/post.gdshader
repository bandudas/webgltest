shader_type canvas_item;
// Grading noir: warna pucat, bayangan kebiruan, sorotan hangat, kontras, vignette, film grain.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float slowmo = 0.0;
uniform float ghost = 0.0;
uniform float time_s = 0.0;
uniform vec2 res = vec2(854.0, 480.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb * 1.3;
	if (ghost > 0.01) {
		// bayangan ganda tipis yang bergoyang: pandangan hantu
		vec2 off = vec2(sin(time_s * 0.7), cos(time_s * 0.53)) * 0.006 * ghost;
		c = mix(c, texture(screen_tex, SCREEN_UV + off).rgb * 1.3, 0.35 * ghost);
		c = mix(c, c * vec3(0.85, 0.95, 1.15), 0.5 * ghost);
	}
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 g = mix(vec3(l), c, 0.8 - 0.55 * slowmo);
	g += vec3(-0.012, 0.0, 0.03) * (1.0 - l) + vec3(0.035, 0.018, -0.02) * l;
	g = (g - 0.45) * (1.1 + 0.15 * slowmo) + 0.45;
	g = mix(g, g * vec3(0.95, 1.0, 1.12), slowmo * 0.6);
	vec2 d = SCREEN_UV - 0.5;
	g *= 1.0 - dot(d, d) * (0.8 + 1.2 * slowmo);
	float n = hash(floor(SCREEN_UV * res) + fract(time_s * 7.0) * 113.0) - 0.5;
	g += n * (0.055 + 0.03 * slowmo);
	COLOR = vec4(max(g, vec3(0.0)), 1.0);
}
