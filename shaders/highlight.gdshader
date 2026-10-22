shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Square markers: kind 0 = move dot, 1 = capture ring, 2 = square edge glow (selected, last move).

instance uniform vec4 tint : source_color = vec4(0.4, 0.72, 1.0, 1.0);
instance uniform float kind = 0.0;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float a;
	if (kind < 0.5) {
		a = smoothstep(0.34, 0.24, r) * 0.95 + smoothstep(0.95, 0.2, r) * 0.22;
	} else if (kind < 1.5) {
		a = smoothstep(0.13, 0.0, abs(r - 0.8)) + smoothstep(1.0, 0.5, r) * 0.12;
	} else {
		vec2 q = abs(uv);
		float e = max(q.x, q.y);
		a = smoothstep(0.72, 0.98, e) * 0.85 + 0.10;
	}
	float pulse = 0.82 + 0.18 * sin(TIME * 3.2);
	ALBEDO = tint.rgb * a * pulse * 1.6 * tint.a;
	ALPHA = clamp(a * tint.a, 0.0, 1.0);
}
