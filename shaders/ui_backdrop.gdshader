shader_type canvas_item;
// Modal backdrop: blurs and darkens what is behind it, with a cold vignette.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur = 2.6;
uniform float dim = 0.55;
uniform vec3 tint : source_color = vec3(0.015, 0.005, 0.03);

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur).rgb;
	float v = smoothstep(0.25, 0.85, length(UV - 0.5));
	c = mix(c, tint, clamp(dim + v * 0.3 * (dim / 0.55), 0.0, 1.0));
	COLOR = vec4(c, 1.0);
}
