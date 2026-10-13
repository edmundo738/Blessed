shader_type spatial;
// Terreno de BLESSED — anime + detalhe real.
// A cor base vem do bioma (vertex color), mas por cima há TEXTURA procedural:
//   • variação macro (manchas largas) + micro (grão) — acaba o "plasticina lisa";
//   • rocha exposta em encostas íngremes (splat por inclinação, com ruído);
//   • AO de fenda (encostas escuras) e realce nos topos;
//   • grão fino que apanha a luz.
// Mantém as bandas toon (o estilo). Funciona em Forward+ e Compatibility.
render_mode specular_disabled;

uniform vec3 sun_dir = vec3(-0.4, 0.8, 0.3);
uniform vec4 shadow_tint : source_color = vec4(0.56, 0.60, 0.90, 1.0);
uniform float bands : hint_range(1.0, 8.0) = 3.0;
uniform float band_soft : hint_range(0.0, 1.0) = 0.45;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.30;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float light_gain : hint_range(0.2, 3.0) = 0.82;
uniform float ambient_gain : hint_range(0.0, 2.0) = 0.85;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.55;
uniform float rock_amount : hint_range(0.0, 1.0) = 0.85;

varying vec3 v_world;
varying float v_slope;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(11.3, 7.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_slope = clamp(1.0 - NORMAL.y, 0.0, 1.0);
}

void fragment() {
	vec2 p = v_world.xz;
	float macro = fbm(p * 0.035);            // manchas largas (variação de terreno)
	float micro = fbm(p * 0.9);              // grão fino
	float grain = fbm(p * 3.5);              // micro-detail que apanha a luz

	// cor base do bioma, com variação (quebra o aspecto liso)
	vec3 base = COLOR.rgb;
	base *= mix(1.0, 0.55 + 0.9 * macro, detail_strength);       // patchiness larga
	base *= mix(1.0, 0.72 + 0.56 * micro, detail_strength);      // grão médio

	// rocha exposta nas encostas (splat por inclinação, fronteira com ruído)
	float rock_mask = smoothstep(0.34, 0.68, v_slope + (micro - 0.5) * 0.22);
	vec3 rock_col = vec3(0.36, 0.345, 0.33) * (0.62 + 0.66 * fbm(p * 1.7 + 3.0));
	rock_col *= 0.85 + 0.3 * grain;
	base = mix(base, rock_col, rock_mask * rock_amount);

	// fendas mais escuras (AO de encosta) + topos realçados
	base *= mix(1.0, 0.70, smoothstep(0.22, 0.88, v_slope));
	base *= 0.94 + 0.12 * grain;

	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = ndl * 0.5 + 0.5;
	float band = floor(lit * bands) / bands;
	band = mix(band, lit, band_soft);

	vec3 base = ALBEDO * light_gain;
	vec3 shaded = base * shadow_tint.rgb;
	vec3 col = mix(shaded, base, clamp(band * 1.12, 0.0, 1.0));

	float shadow = clamp(ATTENUATION, 0.0, 1.0);
	col = mix(col * shadow_tint.rgb, col, shadow);

	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	col += LIGHT_COLOR * rim * rim_strength * band;

	DIFFUSE_LIGHT += min(col, vec3(1.5)) * LIGHT_COLOR * ambient_gain;
}
