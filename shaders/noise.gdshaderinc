// Shared value noise and voronoi helpers.

float sts_hash1(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

vec3 sts_hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

float sts_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(sts_hash1(i + vec3(0, 0, 0)), sts_hash1(i + vec3(1, 0, 0)), f.x),
	               mix(sts_hash1(i + vec3(0, 1, 0)), sts_hash1(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(sts_hash1(i + vec3(0, 0, 1)), sts_hash1(i + vec3(1, 0, 1)), f.x),
	               mix(sts_hash1(i + vec3(0, 1, 1)), sts_hash1(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float sts_fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * sts_noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

// Returns (F1, F2) distances and the id of the nearest cell.
vec2 sts_voronoi(vec3 p, out vec3 cell) {
	vec3 ip = floor(p);
	vec3 fp = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	cell = ip;
	for (int z = -1; z <= 1; z++)
	for (int y = -1; y <= 1; y++)
	for (int x = -1; x <= 1; x++) {
		vec3 o = vec3(float(x), float(y), float(z));
		vec3 r = o + sts_hash3(ip + o) - fp;
		float d = dot(r, r);
		if (d < d1) { d2 = d1; d1 = d; cell = ip + o; }
		else if (d < d2) { d2 = d; }
	}
	return vec2(sqrt(d1), sqrt(d2));
}
