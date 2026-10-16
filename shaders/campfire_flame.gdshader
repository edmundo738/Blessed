shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform float flame_speed : hint_range(0.1, 4.0) = 1.0;
uniform float flame_energy : hint_range(0.5, 5.0) = 2.4;

void vertex() {
	float h = UV.y;
	float gust = sin(TIME * 7.3 + h * 8.0 + VERTEX.x * 12.0);
	float flutter = sin(TIME * 11.1 - h * 13.0 + VERTEX.z * 7.0);
	float sway = (gust * 0.65 + flutter * 0.35) * h * h * 0.075 * flame_speed;
	VERTEX.x += sway;
	VERTEX.z += flutter * h * h * 0.035 * flame_speed;
}

void fragment() {
	float h = UV.y;
	float sway = sin(TIME * 6.0 + h * 9.0) * 0.045 * h;
	float center = 0.5 + sway;
	float edge_noise = sin(UV.y * 25.0 + TIME * 8.0) * 0.025
		+ sin(UV.y * 43.0 - TIME * 5.0) * 0.012;
	float half_width = mix(0.29, 0.012, h) + edge_noise;
	float side = abs(UV.x - center);
	float body = 1.0 - smoothstep(half_width - 0.012, half_width + 0.012, side);
	float base_fade = smoothstep(0.015, 0.15, h);
	float tip_fade = 1.0 - smoothstep(0.77, 1.0, h);
	float flame_mask = body * base_fade * tip_fade;

	float core = 1.0 - smoothstep(0.035, half_width * 0.72, side);
	vec3 outer_color = mix(vec3(1.0, 0.19, 0.025), vec3(1.0, 0.60, 0.08),
		1.0 - smoothstep(0.12, 0.72, h));
	vec3 core_color = mix(vec3(1.0, 0.76, 0.20), vec3(1.0, 0.96, 0.62), core);
	vec3 color = mix(outer_color, core_color, core * 0.92);
	color *= flame_energy * (1.0 - h * 0.22);

	ALBEDO = color;
	EMISSION = color;
	ALPHA = flame_mask;
}
