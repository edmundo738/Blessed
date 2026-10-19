shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// ─────────────────────────────────────────────────────────────────────────────
// TUFOS DE RELVA (cartões de geometria) — o detalhe dos primeiros metros
// ─────────────────────────────────────────────────────────────────────────────
// A malha é o tufo desenhado por MeshKit.grass_card_clump(): lâminas triangulares
// com silhueta na própria geometria e gradiente de cor por vértice (base escura,
// ponta clara). Aqui junta-se:
//
//  · a MESMA máscara de relva dos níveis — os tufos só aparecem onde o campo diz
//    que há fio, portanto a mancha/patchiness é coerente entre cartões e fatias;
//  · vento por instância (ruído em espaço de mundo, não por objeto), para o
//    campo todo ondular na mesma direção;
//  · normais inclinadas para cima na ponta, que é o truque que dá brilho à relva
//    em vez de folhas foscas (Grass Rendering Series, parte 2).

uniform sampler2D grass_mask : filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_streak : filter_linear_mipmap, repeat_enable;
uniform sampler2D wind_noise : filter_linear_mipmap, repeat_enable;

uniform float mask_scale : hint_range(0.05, 3.0) = 0.36;
uniform float mask_min : hint_range(0.0, 1.0) = 0.16;   // cobertura mínima para nascer
uniform float grow : hint_range(0.0, 1.0) = 1.0;
uniform float blade_height = 0.72;                      // altura local máxima do tufo
uniform float fade_begin : hint_range(0.0, 200.0) = 46.0;
uniform float fade_end : hint_range(0.0, 250.0) = 74.0;

uniform vec2 wind_direction = vec2(0.82, 0.57);
uniform float wind_strength : hint_range(0.0, 1.5) = 0.24;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.0;
uniform float wind_scale : hint_range(0.005, 0.2) = 0.035;

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec4 shadow_tint : source_color = vec4(0.45, 0.50, 0.82, 1.0);
uniform float bands : hint_range(1.0, 8.0) = 3.0;
uniform float band_soft : hint_range(0.0, 1.0) = 0.48;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.34;
uniform float ambient_gain : hint_range(0.0, 2.0) = 0.78;
uniform float light_gain : hint_range(0.2, 3.0) = 0.95;

varying vec2 v_uv;
varying vec3 v_color;
varying vec4 v_instance;
varying vec3 v_world;
varying float v_height;
varying float v_fade;

void vertex() {
	v_uv = UV;
	v_color = COLOR.rgb;
	v_instance = INSTANCE_CUSTOM;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_height = clamp(VERTEX.y / max(blade_height, 0.001), 0.0, 1.0);

	// vento: amostrado na posição da instância, portanto o tufo todo acompanha o
	// mesmo sopro que as fatias de relva usam.
	vec2 wuv = origin.xz * wind_scale + wind_direction * TIME * wind_speed * 0.018;
	float gust = textureLod(wind_noise, wuv, 0.0).r;
	float breeze = textureLod(wind_noise, wuv * 2.7 + vec2(0.37, 0.61), 0.0).r;
	float bend = ((gust - 0.5) * 1.5 + (breeze - 0.5) * 0.35)
		* wind_strength * v_height * v_height;
	vec3 local_wind = (inverse(MODEL_MATRIX)
		* vec4(wind_direction.x, 0.0, wind_direction.y, 0.0)).xyz;
	local_wind = normalize(vec3(local_wind.x, 0.0, local_wind.z));
	VERTEX.xz += local_wind.xz * bend;

	float distance_to_camera = distance(origin, CAMERA_POSITION_WORLD);
	v_fade = 1.0 - smoothstep(fade_begin, fade_end, distance_to_camera);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// a relva cresce a partir do chão, não aparece já alta
	VERTEX.y *= clamp(grow, 0.35, 1.0);
}

void fragment() {
	if (v_fade <= 0.002) {
		discard;
	}
	vec2 muv = v_world.xz / mask_scale;
	vec4 mask = texture(grass_mask, muv);
	// fora das manchas de relva não nasce tufo nenhum
	float patch = clamp(mask.b * 1.25, 0.0, 1.0);
	if (patch * (0.35 + 0.75 * v_instance.g) < mask_min) {
		discard;
	}
	vec3 streak = texture(grass_streak, v_world.xz * (1.0 / max(mask_scale * 3.1, 0.05))).rgb;

	float dryness = clamp(v_instance.r * 0.72 + (streak.b - 0.5) * 0.5, 0.0, 1.0);
	float tone = clamp(mask.g * 0.5 + streak.g * 0.5, 0.0, 1.0);
	// v_color = rampa da malha (base escura → ponta clara) × cor da relva do
	// bioma, que chunk.gd escreve como cor de instância. Sem atlas de cor: as
	// lâminas têm de sair da mesma família do chão por baixo delas.
	vec3 color = v_color * mix(0.58, 1.04, v_height);
	color *= mix(0.88, 1.12, tone);
	color *= mix(vec3(1.0), vec3(1.16, 1.02, 0.72), dryness);
	color *= mix(0.94, 1.06, v_instance.g);
	ALBEDO = color;
	ROUGHNESS = 0.92;
	SPECULAR = 0.06;
	AO = mix(0.42, 1.0, smoothstep(0.0, 0.9, v_height));
	AO_LIGHT_AFFECT = 0.55;

	// A normal da lâmina inclina-se para cima ao longo do comprimento: é o que
	// põe brilho na ponta em vez de a deixar fosca (Grass Rendering Series, #2).
	// `FRONT_FACING` só existe aqui, no fragment — daí o desvio de normal não
	// viver no light().
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), v_height));
	if (!FRONT_FACING) {
		// O motor inverte a normal nas costas (é o que faz sentido para uma
		// parede fina); aqui a normal de relva aponta sempre para cima.
		NORMAL = -NORMAL;
	}
}

void light() {
	// A normal da lâmina é inclinada para cima ao longo do comprimento: é o que
	// cria o brilho nas pontas em vez de uma folha fosca.
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
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
		col += LIGHT_COLOR * rim * rim_strength * band * v_height;
		DIFFUSE_LIGHT += min(col, vec3(1.6)) * LIGHT_COLOR * ambient_gain;
	}
}
