shader_type spatial;
render_mode specular_schlick_ggx;

// Playfield felt with a dot grid and a glowing rim, plus a dark vignette outside it.
uniform vec3 outer_color : source_color = vec3(0.020, 0.040, 0.055);
uniform vec3 felt_color : source_color = vec3(0.055, 0.125, 0.155);
uniform vec3 accent_color : source_color = vec3(0.25, 0.80, 0.78);
uniform vec2 board_half = vec2(5.0, 8.5);
uniform float corner_radius = 0.7;

varying vec3 world_pos;

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float d = sd_round_box(p, board_half, corner_radius);
	float inside = 1.0 - smoothstep(-0.02, 0.04, d);

	float falloff = 1.0 - 0.45 * length(p / (board_half * 1.3));
	vec3 col = mix(outer_color * (1.0 - 0.04 * length(p)), felt_color * falloff, inside);

	vec2 g = fract(p * 1.25) - 0.5;
	float dot_mask = 1.0 - smoothstep(0.025, 0.055, length(g));
	col += accent_color * dot_mask * 0.10 * inside;

	float rim = exp(-abs(d) * 14.0);
	ALBEDO = col + accent_color * rim * 0.25;
	EMISSION = accent_color * rim * 0.9;
	ROUGHNESS = mix(0.95, 0.6, inside);
	SPECULAR = 0.3;
}
