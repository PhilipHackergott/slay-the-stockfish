shader_type spatial;
render_mode unshaded;
// Emissive bits: skull eyes, rook windows, candle flames, runes. Values above 1 feed the glow.

uniform vec3 color : source_color = vec3(0.4, 0.75, 1.0);
uniform float energy = 4.0;
uniform float pulse_speed = 2.2;
uniform float pulse_depth = 0.18;
uniform float flicker = 0.0;

void fragment() {
	float p = 1.0 - pulse_depth + pulse_depth * sin(TIME * pulse_speed + NODE_POSITION_WORLD.x * 1.7);
	float fl = 1.0 - flicker * (0.5 + 0.5 * sin(TIME * 17.0 + NODE_POSITION_WORLD.z * 5.0)) * (0.5 + 0.5 * sin(TIME * 7.3));
	ALBEDO = color * energy * p * fl;
}
