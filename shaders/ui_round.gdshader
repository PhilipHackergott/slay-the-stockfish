shader_type canvas_item;
// Round medallion mask for the Gemini icons and portraits (they ship without alpha).

uniform float radius = 0.49;
uniform float soft = 0.015;
uniform float dim = 0.0;
uniform float desat = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float r = length(UV - vec2(0.5));
	c.a *= smoothstep(radius, radius - soft, r);
	float g = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	c.rgb = mix(c.rgb, vec3(g), desat) * (1.0 - dim);
	COLOR = c * COLOR;
}
