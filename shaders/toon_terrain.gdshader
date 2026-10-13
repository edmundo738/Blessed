shader_type spatial;
// Terreno de BLESSED — anime + detalhe "crocante".
//
// Sem assets de textura: todo o detalhe é PROCEDURAL.
//   • ALBEDO: cor de bioma (vertex) + variação macro/micro + grão.
//   • NORMAL: perturbada por um micro-relevo (finite differences de um ruído) =>
//     é isto que dá o aspeto granulado/crocante que apanha a luz, em vez de liso.
//   • por superfície: rocha com relevo forte e angular; areia/terra com grão fino;
//     relva com tufos; tudo a escurecer nas fendas (AO de encosta).
// Mantém as bandas toon (o estilo). Forward+ e Compatibility.
render_mode specular_disabled;

uniform vec3 sun_dir = vec3(-0.4, 0.8, 0.3);
uniform vec4 shadow_tint : source_color = vec4(0.56, 0.60, 0.90, 1.0);
uniform float bands : hint_range(1.0, 8.0) = 3.0;
uniform float band_soft : hint_range(0.0, 1.0) = 0.45;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.30;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float light_gain : hint_range(0.2, 3.0) = 0.82;
uniform float ambient_gain : hint_range(0.0, 2.0) = 0.85;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.60;
uniform float bump_strength : hint_range(0.0, 1.5) = 0.70;
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
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(11.3, 7.7);
		a *= 0.5;
	}
	return v;
}

// micro-relevo barato (para a normal) — 2 octavas, amostrado em grelha fina
float bump_h(vec2 p) {
	return vnoise(p) * 0.6 + vnoise(p * 2.3 + 5.0) * 0.4;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_slope = clamp(1.0 - NORMAL.y, 0.0, 1.0);
}

void fragment() {
	vec2 p = v_world.xz;
	float macro = fbm(p * 0.035);            // manchas largas
	float micro = fbm(p * 0.9);              // grão médio
	float grain = fbm(p * 3.2);              // micro-detail

	// ── albedo: bioma + variação (quebra o "plasticina lisa") ──
	vec3 base = COLOR.rgb;
	base *= mix(1.0, 0.55 + 0.9 * macro, detail_strength);
	base *= mix(1.0, 0.72 + 0.56 * micro, detail_strength);

	// rocha exposta nas encostas (com padrão angular)
	float rock_mask = smoothstep(0.34, 0.68, v_slope + (micro - 0.5) * 0.22);
	vec3 rock_col = vec3(0.36, 0.345, 0.33) * (0.60 + 0.70 * fbm(p * 1.7 + 3.0));
	rock_col *= 0.85 + 0.3 * grain;
	base = mix(base, rock_col, rock_mask * rock_amount);

	// fendas escuras (AO de encosta) + realce de grão
	base *= mix(1.0, 0.70, smoothstep(0.22, 0.88, v_slope));
	base *= 0.93 + 0.14 * grain;

	ALBEDO = base;

	// ── normal "crocante": micro-relevo por finite differences ──
	// mais forte na rocha (angular), mais fino nas superfícies planas (areia/terra/relva)
	float e = 0.45;
	float hc = bump_h(p * 2.6);
	float hx = bump_h((p + vec2(e, 0.0)) * 2.6);
	float hz = bump_h((p + vec2(0.0, e)) * 2.6);
	vec3 nrm = normalize(vec3((hc - hx) * 2.2, e, (hc - hz) * 2.2));
	float rock_inf = smoothstep(0.28, 0.70, v_slope);
	float amt = bump_strength * (0.35 + 0.9 * rock_inf);
	NORMAL = normalize(NORMAL + nrm.xzy * amt);

	ROUGHNESS = mix(0.92, 0.72, rock_inf);
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
