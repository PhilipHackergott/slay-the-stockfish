shader_type spatial;
// Player pieces: carved bone and old ivory with hairline cracks and stains (object space, so the
// pattern travels with the piece). COLOR carries the baked AO from Blender.
#include "res://shaders/noise.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.80, 0.74, 0.62);
uniform vec3 stain_color : source_color = vec3(0.44, 0.36, 0.26);
uniform float roughness_base = 0.5;
uniform float crack_strength = 0.65;
uniform vec3 highlight_color : source_color = vec3(0.45, 0.75, 1.0);
instance uniform float glow_boost = 0.0;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	float n = sts_fbm(obj_pos * 7.0);
	float stains = smoothstep(0.5, 0.85, sts_fbm(obj_pos * 2.2 + 7.0));
	float ridge = abs(sts_noise(obj_pos * 11.0 + 3.0) - 0.5);
	float crack = 1.0 - smoothstep(0.0, 0.03, ridge);
	crack *= smoothstep(0.35, 0.6, sts_noise(obj_pos * 3.0));
	vec3 col = mix(base_color, stain_color, stains * 0.5);
	col *= 0.86 + 0.26 * n;
	col = mix(col, stain_color * 0.35, crack * crack_strength);
	col *= mix(vec3(1.0), COLOR.rgb, 0.85);
	ALBEDO = col;
	ROUGHNESS = clamp(roughness_base + 0.25 * (n - 0.5) + crack * 0.2, 0.0, 1.0);
	SPECULAR = 0.45;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = highlight_color * (fres * 1.6 + 0.12) * glow_boost;
}
