shader_type spatial;
// Board squares and stone: world-space marble veins or basalt speckle, with a bump from noise.
#include "res://shaders/noise.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.78, 0.76, 0.72);
uniform vec3 vein_color : source_color = vec3(0.40, 0.38, 0.40);
uniform float vein_amount = 0.7;
uniform float vein_scale = 1.4;
uniform float speckle = 0.0;
uniform float roughness_base = 0.38;
uniform float bump = 0.25;
uniform float scale = 1.0;
uniform float moss = 0.0;
uniform vec3 moss_color : source_color = vec3(0.13, 0.17, 0.10);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float height_at(vec3 p) {
	return sts_fbm(p * 3.0 * scale);
}

void fragment() {
	vec3 p = wpos * scale;
	float n = sts_fbm(p * 1.3);
	float v = abs(sin((p.x * 1.7 + p.z * 0.9 + p.y * 0.6 + n * 4.5) * vein_scale));
	float veins = pow(1.0 - v, 10.0) * vein_amount;
	vec3 col = mix(base_color, vein_color, clamp(veins, 0.0, 1.0));
	col *= 0.86 + 0.22 * sts_fbm(p * 8.0);
	float sp = step(1.0 - speckle * 0.08, sts_hash1(floor(p * 60.0)));
	col = mix(col, col * 1.9 + 0.05, sp);
	float up = clamp(wnrm.y, 0.0, 1.0);
	float moss_mask = moss * smoothstep(0.55, 0.75, sts_fbm(p * 0.9 + 4.0)) * smoothstep(0.4, 0.9, up);
	col = mix(col, moss_color, moss_mask);
	col *= mix(vec3(1.0), COLOR.rgb, 0.9);
	ALBEDO = col;
	ROUGHNESS = clamp(roughness_base + 0.2 * (n - 0.5) + moss_mask * 0.4, 0.0, 1.0);
	float e = 0.02;
	float h0 = height_at(wpos);
	vec3 g = vec3(height_at(wpos + vec3(e, 0, 0)) - h0, height_at(wpos + vec3(0, e, 0)) - h0,
		height_at(wpos + vec3(0, 0, e)) - h0) / e;
	vec3 gv = (VIEW_MATRIX * vec4(g, 0.0)).xyz;
	NORMAL = normalize(NORMAL - gv * bump * 0.05);
}
