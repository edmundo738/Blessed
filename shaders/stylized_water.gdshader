shader_type spatial;
// Água anime: superfície translúcida, cor por profundidade do leito e ondas
// com cristas recortadas. A profundidade vem nos UV2 gerados pelo terreno, sem
// uma leitura de depth texture por pixel; isso funciona nos renderers suportados.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon;

uniform vec4 deep_color : source_color = vec4(0.10, 0.36, 0.52, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.34, 0.78, 0.82, 1.0);
uniform vec4 foam_color : source_color = vec4(0.94, 0.98, 1.00, 1.0);
uniform vec4 sky_tint : source_color = vec4(0.62, 0.82, 1.00, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 0.82;
uniform float wave_speed : hint_range(0.0, 4.0) = 0.55;
uniform float wave_scale : hint_range(0.5, 40.0) = 9.0;
uniform float sun_glow : hint_range(0.0, 2.0) = 0.30;
uniform float crest_strength : hint_range(0.0, 0.8) = 0.22;
uniform float shore_foam_strength : hint_range(0.0, 1.0) = 0.52;
uniform vec3 sun_dir = vec3(-0.4, 0.8, 0.3);

varying vec3 v_world;

// Tres oitavas em frequencias incomensuraveis: o resultado e uma ondulacao
// organica, sem a grelha de "bolas" que dois sinus puros + floor() criavam.
float wave(vec2 p, float t) {
	return sin(p.x * 1.0 + t) * 0.5
		+ sin(p.y * 0.83 - t * 0.7) * 0.3
		+ sin((p.x + p.y) * 0.57 + t * 0.35) * 0.2;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = v_world.xz * 0.12;   // ondas largas e contínuas entre chunks
	float amplitude = mix(0.035, 0.11, UV2.y);
	VERTEX.y += wave(p, TIME * wave_speed) * amplitude;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 p = v_world.xz * 0.12;
	float w = wave(p, t) * 0.5 + 0.5;   // suave, SEM floor() -> sem plateaus/bolas
	float depth = clamp(UV2.x / 8.0, 0.0, 1.0);
	float shore = 1.0 - smoothstep(0.0, 0.85, UV2.x);

	// A cor vem da espessura da água; o movimento só acrescenta leitura de onda.
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, depth * 0.92);
	float wave_band = smoothstep(0.58, 0.80, w) * 0.13;
	col = mix(col, sky_tint.rgb, wave_band);

	// Linhas claras estilizadas nas cristas e espuma limitada às margens rasas.
	float crest = smoothstep(0.74, 0.93, w) * crest_strength;
	float foam = max(crest * 0.55, shore * (0.24 + crest) * shore_foam_strength);
	col = mix(col, foam_color.rgb, clamp(foam, 0.0, 0.72));

	// reflexo largo do sol (brilho de agua, nao um holofote)
	vec3 n = normalize(NORMAL + vec3((w - 0.5) * 0.2, 0.0, (0.5 - w) * 0.2));
	float glint = pow(max(dot(reflect(-VIEW, n), normalize(sun_dir)), 0.0), 240.0);
	col += sky_tint.rgb * glint * sun_glow;

	ALBEDO = col;
	ALPHA = alpha;
	ROUGHNESS = 0.22;
	SPECULAR = 0.24;
}
