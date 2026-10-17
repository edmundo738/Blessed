shader_type spatial;
// Superfície de água opaca e dupla face: costa legível de cima e reflexo
// azul estilizado quando a câmara fica submersa.
//
// A água não sabe o que é um rio: recebe-o do mundo em três canais.
//   UV2.x  profundidade (m)        → cor do raso ao fundo
//   UV2.y  salinidade (0..1)       → mar (ondas grandes) vs rio/lago (ondulada)
//   COLOR  velocidade, turvação, corrente 2D → correntezas, espuma, água barrenta
//
// Assim a MESMA superfície se comporta como mar aberto, rio a correr ou lago
// parado, porque quem a desenha leu o relevo — não porque há três shaders.
render_mode cull_disabled, depth_draw_opaque, diffuse_toon;

uniform vec4 deep_color : source_color = vec4(0.08, 0.31, 0.49, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.35, 0.78, 0.82, 1.0);
uniform vec4 foam_color : source_color = vec4(0.94, 0.99, 1.0, 1.0);
uniform vec4 sky_tint : source_color = vec4(0.62, 0.82, 1.0, 1.0);
uniform vec4 mud_color : source_color = vec4(0.42, 0.40, 0.24, 1.0);
uniform vec3 underwater_color : source_color = vec3(0.025, 0.10, 0.19);
uniform sampler2D flow_noise : filter_linear_mipmap, repeat_enable;
uniform float wave_speed : hint_range(0.0, 4.0) = 0.55;
uniform float wave_scale : hint_range(0.5, 40.0) = 9.0;
uniform float sun_glow : hint_range(0.0, 2.0) = 0.30;
uniform float crest_strength : hint_range(0.0, 0.8) = 0.22;
uniform float shore_foam_strength : hint_range(0.0, 1.0) = 0.52;
uniform float flow_strength : hint_range(0.0, 1.0) = 0.55;
uniform vec3 sun_dir = vec3(-0.4, 0.8, 0.3);

varying vec3 v_world;
varying float v_depth;
varying float v_salt;
varying float v_speed;
varying float v_turb;
varying vec2 v_flow;

float wave(vec2 p, float t) {
	return sin(p.x * 1.0 + t) * 0.48
		+ sin(p.y * 0.83 - t * 0.7) * 0.30
		+ sin((p.x + p.y) * 0.57 + t * 0.35) * 0.22;
}

void vertex() {
	vec3 world_before_wave = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float noise = textureLod(flow_noise, world_before_wave.xz * 0.014
		+ vec2(TIME * 0.006, -TIME * 0.004), 0.0).r;
	v_salt = UV2.y;
	v_depth = UV2.x;
	v_speed = COLOR.r;
	v_turb = COLOR.g;
	// corrente codificada em 0..1 → -1..1; sem corrente, aponta para +z
	v_flow = COLOR.ba * 2.0 - 1.0;
	if (length(v_flow) < 0.01) {
		v_flow = vec2(0.0, 1.0);
	}
	vec2 p = world_before_wave.xz * (wave_scale / 75.0);
	// Mar: ondulação larga. Rio: ondulação curta e na direção da corrente.
	// Lago/mangue: quase espelho (velocidade baixa = água parada).
	float amplitude = mix(0.030, 0.115, v_salt);
	amplitude *= mix(0.55, 1.0, clamp(v_speed * 1.6, 0.0, 1.0));
	VERTEX.y += wave(p, TIME * wave_speed + (noise - 0.5) * 0.5) * amplitude;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float depth = clamp(v_depth / 8.0, 0.0, 1.0);
	float shore = 1.0 - smoothstep(0.02, 0.85, v_depth);
	float t = TIME * wave_speed;
	vec2 p = v_world.xz * (wave_scale / 75.0);
	float broad_noise = texture(flow_noise, v_world.xz * 0.014
		+ vec2(TIME * 0.006, -TIME * 0.004)).r;
	float detail_noise = texture(flow_noise, v_world.xz * 0.054
		+ vec2(-TIME * 0.012, TIME * 0.009)).r;
	float w = wave(p, t + (broad_noise - 0.5) * 0.7) * 0.5 + 0.5;
	w = clamp(w + (detail_noise - 0.5) * 0.16, 0.0, 1.0);

	// ── cor: profundidade + salinidade + turvação ───────────────────────
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, depth * 0.94);
	// rio raso tem um verde próprio, para não se confundir com o mar
	vec3 river_col = mix(vec3(0.24, 0.52, 0.44), deep_color.rgb * 0.85, depth * 0.6);
	col = mix(col, river_col, (1.0 - v_salt) * 0.35 * (1.0 - depth * 0.4));
	// água barrenta (mangue, cheia): o barro tinge o raso, não o fundo
	float murk = v_turb * (0.35 + 0.65 * (1.0 - depth));
	col = mix(col, mud_color.rgb, clamp(murk * 0.32, 0.0, 0.45));

	// ── correntezas: riscos alinhados com a corrente, a descer o rio ────
	vec2 flow = normalize(v_flow);
	vec2 across = vec2(-flow.y, flow.x);
	float along = dot(v_world.xz, flow);
	float side = dot(v_world.xz, across);
	float streak = texture(flow_noise, vec2(along * 0.05 - TIME * (0.10 + v_speed * 0.22),
		side * 0.014 + TIME * 0.01)).r;
	streak = smoothstep(0.56, 0.86, streak);
	float running = (1.0 - v_salt) * smoothstep(0.06, 0.35, v_speed);
	col = mix(col, sky_tint.rgb, streak * running * flow_strength * 0.22);

	float wave_band = smoothstep(0.58, 0.82, w) * 0.11;
	col = mix(col, sky_tint.rgb, wave_band);
	float crest = smoothstep(0.76, 0.94, w) * crest_strength;
	// cristas e corredeiras: a água branca onde a corrente acelera
	float rapids = running * smoothstep(0.40, 0.95, v_speed) * (0.35 + streak * 0.65);
	float foam = max(crest * (0.35 + 0.45 * v_salt),
		shore * (0.24 + crest) * shore_foam_strength);
	foam = max(foam, rapids * 0.62);
	col = mix(col, foam_color.rgb, clamp(foam, 0.0, 0.72));

	vec3 n = normalize(NORMAL + vec3((w - 0.5) * 0.18, 0.0, (0.5 - w) * 0.18));
	float glint = pow(max(dot(reflect(-VIEW, n), normalize(sun_dir)), 0.0), 180.0);
	col += sky_tint.rgb * glint * sun_glow;

	// De baixo, a face da água continua visível como teto azul escuro. A névoa
	// do mundo completa a profundidade sem deixar o leito transparente através da água.
	float underwater = step(CAMERA_POSITION_WORLD.y + 0.06, v_world.y);
	vec3 submerged = mix(underwater_color, shallow_color.rgb * 0.54, 1.0 - depth);
	submerged = mix(submerged, foam_color.rgb * 0.38, crest * 0.16);
	col = mix(col, submerged, underwater);

	ALBEDO = col;
	ROUGHNESS = mix(0.42, 0.68, underwater);
	SPECULAR = mix(0.34, 0.08, underwater);
}
