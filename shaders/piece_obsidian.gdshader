shader_type spatial;
// Engine pieces: faceted obsidian with molten ember cracks. Voronoi cells in object space give
// each facet its own normal tilt; cell borders glow and pulse.
#include "res://shaders/noise.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.045, 0.038, 0.045);
uniform vec3 ember_color : source_color = vec3(1.0, 0.33, 0.07);
uniform float ember_energy = 3.2;
uniform float facet_scale = 5.6;
uniform float crack_width = 0.046;
uniform float facet_tilt = 0.32;
uniform vec3 highlight_color : source_color = vec3(1.0, 0.45, 0.12);
// Cool moonlit rim so dark pieces separate from the dark squares.
uniform vec3 rim_color : source_color = vec3(0.42, 0.48, 0.95);
uniform float rim_strength = 0.32;
instance uniform float glow_boost = 0.0;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	vec3 cell;
	vec2 f = sts_voronoi(obj_pos * facet_scale, cell);
	float edge = f.y - f.x;
	float crack = 1.0 - smoothstep(0.0, crack_width, edge);
	vec3 rnd = sts_hash3(cell) * 2.0 - 1.0;
	vec3 tilt = (VIEW_MATRIX * MODEL_MATRIX * vec4(rnd, 0.0)).xyz;
	NORMAL = normalize(NORMAL + tilt * facet_tilt);
	float live = step(0.33, sts_hash3(cell + 3.7).x);
	float pulse = 0.7 + 0.3 * sin(TIME * 1.8 + cell.x * 3.1 + cell.y * 1.7 + cell.z * 2.3);
	float ao = COLOR.r;
	ALBEDO = (base_color + vec3(0.025) * rnd.x) * mix(1.0, ao, 0.7) * (1.0 - crack * 0.6);
	ROUGHNESS = 0.16 + 0.18 * sts_hash3(cell).y;
	METALLIC = 0.25;
	SPECULAR = 0.75;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = ember_color * ember_energy * crack * live * pulse * mix(0.4, 1.0, ao)
		+ rim_color * fres * rim_strength
		+ highlight_color * (fres * 1.6 + 0.1) * glow_boost;
}
