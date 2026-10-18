shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform float flame_speed : hint_range(0.1, 4.0) = 1.0;
uniform float flame_energy : hint_range(0.5, 5.0) = 2.4;
// Camadas da mesma chama: o núcleo é estreito (slim baixo) e mexe-se mais
// depressa. Sem estes dois valores a chama era um cone laranja, igual em todas
// as camadas — que é exactamente o que fazia o fogo parecer mal feito.
uniform float slim : hint_range(0.05, 1.0) = 0.62;
uniform float width : hint_range(0.1, 2.0) = 1.0;

// Ruído barato e contínuo (sem textura): soma de senos com períodos que não
// são múltiplos uns dos outros, para não se ver o padrão a repetir.
float fbm2(vec2 p, float t) {
	float v = sin(p.x * 3.1 + t) * 0.5 + sin(p.y * 2.3 - t * 1.7) * 0.3
		+ sin((p.x + p.y) * 1.7 + t * 2.9) * 0.2;
	return v * 0.5 + 0.5;
}

void vertex() {
	float h = UV.y;
	float gust = sin(TIME * 7.3 + h * 8.0 + VERTEX.x * 12.0);
	float flutter = sin(TIME * 11.1 - h * 13.0 + VERTEX.z * 7.0);
	float sway = (gust * 0.65 + flutter * 0.35) * h * h * 0.075 * flame_speed;
	VERTEX.x += sway;
	VERTEX.z += flutter * h * h * 0.035 * flame_speed;
	// A camada estreita sobe mais: o núcleo da chama puxa para cima.
	VERTEX.y *= mix(1.0, 1.18, 1.0 - slim);
}

void fragment() {
	float h = UV.y;
	float sway = sin(TIME * 6.0 + h * 9.0) * 0.045 * h;
	float center = 0.5 + sway;
	// A largura vem da camada (width) e o perfil é exponencial: uma chama real
	// é grossa em baixo e afina depressa, não em linha reta.
	float half_width = width * (0.5 * slim) * pow(1.0 - h, 1.35) + 0.012;
	float edge_noise = (fbm2(vec2(UV.y * 6.0, UV.x * 2.0), TIME * 1.4) - 0.5) * 0.10
		+ sin(UV.y * 43.0 - TIME * 5.0) * 0.012;
	half_width += edge_noise * (0.35 + h);
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
