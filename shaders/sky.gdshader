shader_type sky;
// Night void: indigo zenith, violet mist band at the horizon, a darker abyss below, stars, and a
// big pale moon (placed by direction, it may sit low in the void so the game camera sees it).
#include "res://shaders/noise.gdshaderinc"

uniform vec3 zenith : source_color = vec3(0.035, 0.03, 0.10);
uniform vec3 horizon : source_color = vec3(0.24, 0.22, 0.45);
uniform vec3 abyss : source_color = vec3(0.05, 0.045, 0.11);
uniform vec3 moon_color : source_color = vec3(0.93, 0.94, 1.0);
uniform vec3 moon_dir = vec3(-0.42, -0.2, -0.88);
uniform float moon_radius = 0.075;
uniform float moon_energy = 2.4;

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon, zenith, pow(clamp(h, 0.0, 1.0), 0.5));
	col = mix(col, abyss, smoothstep(-0.02, -0.65, h));
	float mist = sts_fbm(d * 3.0 + vec3(TIME * 0.01, 0.0, 0.0));
	col += horizon * 0.25 * mist * smoothstep(0.5, 0.0, abs(h + 0.08));
	float star = step(0.9968, sts_hash1(floor(d * 260.0))) * smoothstep(0.05, 0.5, h);
	col += vec3(star) * 1.2;
	vec3 md = normalize(moon_dir);
	float c = dot(d, md);
	float ang = acos(clamp(c, -1.0, 1.0));
	float disc = smoothstep(moon_radius, moon_radius * 0.96, ang);
	float craters = 0.82 + 0.18 * sts_fbm(d * 60.0);
	col = mix(col, moon_color * moon_energy * craters, disc);
	col += moon_color * (exp(-ang * 28.0) * 0.5 + exp(-ang * 6.0) * 0.12 + exp(-ang * 2.2) * 0.05);
	COLOR = col;
}
