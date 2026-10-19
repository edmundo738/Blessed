shader_type spatial;
// Personagem de BLESSED — toon macio, cor por vértice, sem texturas.
//
// O corpo é construído em GDScript (player_body.gd): cada peça traz a sua cor
// de vértice e este shader é a única superfície que lhes dá luz. A banda toon
// é propositadamente mais larga que a do terreno (a roupa lê-se melhor com
// poucos degraus) e o rim separa a silhueta do fundo, que é o que faz um
// personagem low-poly parecer desenhado em vez de "um monte de cápsulas".
render_mode depth_draw_opaque, cull_back;

uniform vec4 shadow_tint : source_color = vec4(0.48, 0.52, 0.82, 1.0);
uniform float bands : hint_range(1.0, 8.0) = 3.0;
uniform float band_soft : hint_range(0.0, 1.0) = 0.55;
uniform float light_gain : hint_range(0.2, 3.0) = 0.98;
uniform float ambient_gain : hint_range(0.0, 2.0) = 0.82;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.32;
uniform float rim_power : hint_range(0.5, 8.0) = 2.8;
uniform vec3 sun_dir = vec3(-0.4, 0.8, 0.3);

varying vec3 v_world;
varying vec3 v_world_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.82;
	SPECULAR = 0.35;
	// Um fio de luz nas arestas: o cabelo e os ombros ganham contorno.
	float edge = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), rim_power);
	EMISSION = COLOR.rgb * edge * rim_strength * 0.16;
}

void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		// Fogueira: queda radial contínua, como no resto do mundo.
		float local_diffuse = max(dot(NORMAL, LIGHT), 0.0);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * local_diffuse
			* clamp(ATTENUATION, 0.0, 1.0) * 0.9;
	} else {
		float ndl = dot(NORMAL, LIGHT);
		float lit = ndl * 0.5 + 0.5;
		float band = floor(lit * bands) / bands;
		band = mix(band, lit, band_soft);
		vec3 base = ALBEDO * light_gain;
		vec3 col = mix(base * shadow_tint.rgb, base, clamp(band * 1.12, 0.0, 1.0));
		float shadow = clamp(ATTENUATION, 0.0, 1.0);
		col = mix(col * shadow_tint.rgb, col, shadow);
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
		col += LIGHT_COLOR * rim * rim_strength * band;
		DIFFUSE_LIGHT += min(col, vec3(1.6)) * LIGHT_COLOR * ambient_gain;
	}
}
