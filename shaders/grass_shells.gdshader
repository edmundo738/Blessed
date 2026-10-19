shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// ─────────────────────────────────────────────────────────────────────────────
// RELVA POR NÍVEIS (shell texturing) — o modelo de pelagem, como nos diagramas
// ─────────────────────────────────────────────────────────────────────────────
// A relva NÃO é geometria de lâminas. É UM campo de alturas (content/fx/grass/
// grass_fur.png, gerado por tools/make_grass_masks.py) desenhado em fatias
// horizontais empilhadas: a fatia i é o mesmo plano do terreno levantado
// `shell_height * i / layers`.
//
//   Fur Model .............. cada texel guarda até que altura há fio ali
//   Layer Approximation .... a fatia i desenha o fio em corte transversal
//   Density Layers ......... tirar fios (não cortá-los) dá comprimentos diferentes
//   Spike effect ........... a máscara afina a lâmina até à ponta; a ponta é o
//                            ponto mais alto, logo os níveis superiores só têm
//                            pontas finas em vez de placas largas
//
// Porque é que isto substitui a versão anterior: as fatias desenhavam *formas
// de lâmina em código* por pixel, com larguras de 34% da célula. Duas fatias
// seguidas ficavam a 4,5 cm uma da outra mas cada uma desenhava uma lâmina
// larga e compacta — o olho lê isso como placas empilhadas, exatamente o
// "picotado em camadas" reportado. Aqui a espessura horizontal vem da máscara
// (lâminas de ~5 mm) e a leitura vertical vem do campo de alturas.
//
// Custo: zero de geometria nova por lâmina, uma leitura de textura por pixel.

uniform sampler2D grass_mask : filter_linear_mipmap, repeat_enable;
// R = altura do fio (0 = sem fio), G = tom do fio, B = tufos de larga escala
uniform sampler2D grass_streak : filter_linear_mipmap, repeat_enable;
// R = riscas de vento, G = ruído fino, B = manchas de secura
uniform sampler2D wind_noise : filter_linear_mipmap, repeat_enable;

uniform float mask_scale : hint_range(0.05, 3.0) = 0.36;   // metros por repetição
uniform float shell_height : hint_range(0.05, 1.5) = 0.30;  // altura do volume
uniform float grow : hint_range(0.0, 1.0) = 1.0;            // 0 = relva por crescer
uniform float coverage_gain : hint_range(0.0, 2.0) = 1.0;
uniform float density_min : hint_range(0.0, 1.0) = 0.30;    // densidade no horizonte
uniform float density_near : hint_range(0.0, 400.0) = 34.0;
uniform float density_far : hint_range(0.0, 500.0) = 110.0;
uniform float size_mid : hint_range(0.0, 400.0) = 62.0;
uniform float size_far : hint_range(0.0, 500.0) = 96.0;

uniform vec2 wind_direction = vec2(0.82, 0.57);
uniform float wind_strength : hint_range(0.0, 1.5) = 0.30;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.15;
uniform float wind_scale : hint_range(0.005, 0.2) = 0.026;
uniform float streak_strength : hint_range(0.0, 1.0) = 0.30;

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec4 shadow_tint : source_color = vec4(0.48, 0.52, 0.86, 1.0);
uniform float bands : hint_range(1.0, 8.0) = 3.0;
uniform float band_soft : hint_range(0.0, 1.0) = 0.46;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.30;
uniform float ambient_gain : hint_range(0.0, 2.0) = 0.78;
uniform float light_gain : hint_range(0.2, 3.0) = 0.92;

varying vec3 v_world;
varying vec3 v_tint;
varying float v_shell;
varying float v_cover;
varying float v_dryness;
varying float v_bend;

void vertex() {
	// COLOR = cor da relva do bioma (ver Terrain.grass_tint_of); UV = cobertura e
	// secura; UV2.x = altura relativa do nível. A tinta vem do vértice para que
	// cada ponto do campo tenha a cor da relva que ali cresce, e não a cor de
	// uma paleta única — foi o choque entre as duas que produziu o picotado.
	v_shell = UV2.x;
	v_cover = UV.x;
	v_dryness = UV.y;
	v_tint = COLOR.rgb;
	vec3 origin = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 wuv = origin.xz * wind_scale + wind_direction * TIME * wind_speed * 0.012;
	float gust = textureLod(wind_noise, wuv, 0.0).r;
	float breeze = textureLod(wind_noise, wuv * 2.7 + vec2(0.37, 0.61), 0.0).r;
	// As fatias superiores afastam-se mais: é isto que dá o efeito de varrer.
	v_bend = ((gust - 0.5) * 1.7 + (breeze - 0.5) * 0.5) * wind_strength
		* v_shell * v_shell;
	VERTEX.x += v_bend * wind_direction.x;
	VERTEX.z += v_bend * wind_direction.y;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float distance_to_camera = distance(CAMERA_POSITION_WORLD, v_world);
	// O horizonte é pintado pelo terreno; aqui a densidade cai sem nunca
	// desaparecer de repente (nada de anéis a saltar).
	float far_fade = 1.0 - smoothstep(size_far, size_far + 34.0, distance_to_camera);
	if (far_fade <= 0.002) {
		discard;
	}

	// ── o campo de alturas ───────────────────────────────────────────────
	vec2 muv = v_world.xz / mask_scale;
	vec4 mask = texture(grass_mask, muv);
	float blade_height = mask.r * grow;
	if (v_shell > blade_height) {
		discard;
	}

	// ── densidade: tira-se fio, não se corta ─────────────────────────────
	float thinning = mix(1.0, density_min,
		smoothstep(density_near, density_far, distance_to_camera));
	float cover = clamp(v_cover * coverage_gain * far_fade, 0.0, 1.0);
	// os tufos modulam a densidade: onde a massa é alta há mais fio
	float keep = cover * thinning * (0.45 + 0.95 * mask.b);
	if (mask.g > keep) {
		discard;
	}

	// ── cor ──────────────────────────────────────────────────────────────
	// A tinta vem do vértice (cor da relva do bioma). O que se acrescenta aqui é
	// a rampa base-escura → ponta-clara, que dá volume à lâmina, mais a variação
	// por fio. As lâminas e o chão por baixo delas ficam da MESMA cor: é isso que
	// faz um campo de lâminas sub-pixel ler-se como relva e não como ruído.
	float vertical = clamp(v_shell / max(blade_height, 0.001), 0.0, 1.0);
	vec2 streak_uv = v_world.xz * (1.0 / max(mask_scale * 3.1, 0.05));
	vec3 streak = texture(grass_streak, streak_uv).rgb;
	float tone = clamp(mask.g * 0.55 + streak.g * 0.45, 0.0, 1.0);
	float dryness = clamp(v_dryness + (streak.b - 0.5) * 0.55, 0.0, 1.0);
	vec3 color = v_tint * mix(0.54, 1.06, vertical);
	color *= mix(0.88, 1.10, tone);
	color *= mix(vec3(1.0), vec3(1.16, 1.02, 0.72), dryness);
	ALBEDO = color;
	ROUGHNESS = 0.94;
	SPECULAR = 0.04;
	AO = mix(0.40, 1.0, smoothstep(0.0, 0.85, vertical));
	AO_LIGHT_AFFECT = 0.55;
}

void light() {
	// Lume local (fogueira) contínuo; só o sol/lua conservam bandas suaves.
	if (!LIGHT_IS_DIRECTIONAL) {
		float local_diffuse = max(dot(NORMAL, LIGHT), 0.0);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * local_diffuse
			* clamp(ATTENUATION, 0.0, 1.0);
	} else {
		float ndl = dot(NORMAL, LIGHT);
		float lit = ndl * 0.5 + 0.5;
		float band = floor(lit * bands) / bands;
		band = mix(band, lit, band_soft);
		vec3 base = ALBEDO * light_gain;
		vec3 col = mix(base * shadow_tint.rgb, base, clamp(band * 1.08, 0.0, 1.0));
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
		col += LIGHT_COLOR * rim * rim_strength * band;
		DIFFUSE_LIGHT += min(col, vec3(1.6)) * LIGHT_COLOR * ambient_gain;
	}
}
