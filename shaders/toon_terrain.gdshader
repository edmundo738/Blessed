shader_type spatial;
// Terreno anime: bandas de luz analíticas + sombra projetada real do motor.
// Funciona em Forward+ e em Compatibility (não usa nenhuma feature exclusiva).
render_mode specular_disabled;

uniform vec3 sun_dir = vec3(-0.4, 0.8, 0.3);
uniform vec4 shadow_tint : source_color = vec4(0.56, 0.60, 0.90, 1.0);
uniform float bands : hint_range(1.0, 8.0) = 3.0;
uniform float band_soft : hint_range(0.0, 1.0) = 0.18;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.30;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float light_gain : hint_range(0.2, 3.0) = 1.05;
uniform float ambient_gain : hint_range(0.0, 2.0) = 0.85;

varying vec3 v_world;
varying float v_slope;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// encostas muito inclinadas ficam um pouco mais escuras (leitura de forma)
	v_slope = clamp(1.0 - NORMAL.y, 0.0, 1.0);
}

void fragment() {
	ALBEDO = COLOR.rgb * mix(1.0, 0.90, v_slope);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = ndl * 0.5 + 0.5;
	// quantiza em degraus — é isto que "desenha" o terreno
	float band = floor(lit * bands) / bands;
	band = mix(band, lit, band_soft);

	vec3 base = ALBEDO * light_gain;
	vec3 shaded = base * shadow_tint.rgb;
	vec3 col = mix(shaded, base, clamp(band * 1.12, 0.0, 1.0));

	// sombra real (árvores, estruturas, o próprio terreno)
	float shadow = clamp(ATTENUATION, 0.0, 1.0);
	col = mix(col * shadow_tint.rgb, col, shadow);

	// luz de recorte: separa o terreno do fundo, estilo cel
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	col += LIGHT_COLOR * rim * rim_strength * band;

	DIFFUSE_LIGHT += col * LIGHT_COLOR * ambient_gain;
}
