shader_type sky;

uniform vec3 top_color : source_color = vec3(0.16, 0.42, 0.86);
uniform vec3 horizon_color : source_color = vec3(0.68, 0.82, 0.96);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.7);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float star_amount = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(-0.02, 0.55, y));
	if (y < 0.0) {
		col = horizon_color * 0.85;
	}

	float sd = max(dot(d, normalize(sun_dir)), 0.0);
	col += sun_color * (pow(sd, 900.0) * 6.0 + pow(sd, 12.0) * 0.25);

	float md = max(dot(d, normalize(moon_dir)), 0.0);
	col += vec3(0.85, 0.9, 1.0) * smoothstep(0.9990, 0.9994, md) * star_amount;
	col += vec3(0.25, 0.3, 0.45) * pow(md, 40.0) * 0.3 * star_amount;

	if (star_amount > 0.01 && y > 0.0) {
		vec3 p = d * 140.0;
		vec3 id = floor(p);
		float h = hash(id);
		if (h > 0.985) {
			float s = 1.0 - smoothstep(0.05, 0.22, length(fract(p) - 0.5));
			col += vec3(s * star_amount * (0.4 + 0.6 * hash(id + 3.1)));
		}
	}
	COLOR = col;
}
