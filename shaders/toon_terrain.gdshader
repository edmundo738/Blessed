shader_type spatial;
// Terreno de BLESSED — PBR ESTILIZADO (anime + resposta de material real).
//
// Ideia: materiais respondem como PBR (roughness/specular/AO/normal) mas a luz
// mantém as bandas toon. É o que fazem os anime "bonitos" (Genshin/Honkai/Zelda):
// PBR por baixo, toon por cima — realista sem ser fotorealista.
//
// Tudo PROCEDURAL (sem assets):
//   • albedo: bioma (vertex) + variação macro/micro + grão + estratos na rocha
//     + estrias finas na relva/areia;
//   • normal: micro-relevo (finite differences) => granulado que apanha a luz;
//   • roughness: por superfície (rocha fosca, neve/húmido brilhante);
//   • specular: reflexo suave controlado pela roughness;
//   • AO de fenda.
// Forward+ e Compatibility.
render_mode depth_draw_opaque;

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
uniform float spec_strength : hint_range(0.0, 2.0) = 0.55;

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

	// ── albedo ──
	vec3 base = COLOR.rgb;
	base *= mix(1.0, 0.55 + 0.9 * macro, detail_strength);
	base *= mix(1.0, 0.72 + 0.56 * micro, detail_strength);

	// estrias finas nas superfícies planas (relva/areia/terra) — leitura de material
	float streak = vnoise(p * vec2(7.0, 2.2)) * 0.6 + vnoise(p * vec2(15.0, 4.0)) * 0.4;
	base *= mix(1.0, 0.86 + 0.28 * streak, (1.0 - smoothstep(0.30, 0.60, v_slope)) * detail_strength);

	// rocha exposta nas encostas, com estratos (camadas) + variação
	float rock_mask = smoothstep(0.34, 0.68, v_slope + (micro - 0.5) * 0.22);
	float strata = fbm(vec2(p.x * 0.25 + p.y * 0.05, p.y * 2.6));
	vec3 rock_col = vec3(0.36, 0.345, 0.33) * (0.55 + 0.55 * strata + 0.25 * grain);
	base = mix(base, rock_col, rock_mask * rock_amount);

	// AO de fenda
	float ao = mix(1.0, 0.70, smoothstep(0.22, 0.88, v_slope));
	base *= ao;
	base *= 0.93 + 0.14 * grain;

	ALBEDO = base;

	// ── normal "crocante" (micro-relevo) ──
	float e = 0.45;
	float hc = bump_h(p * 2.6);
	float hx = bump_h((p + vec2(e, 0.0)) * 2.6);
	float hz = bump_h((p + vec2(0.0, e)) * 2.6);
	vec3 nrm = normalize(vec3((hc - hx) * 2.2, e, (hc - hz) * 2.2));
	float rock_inf = smoothstep(0.28, 0.70, v_slope);
	NORMAL = normalize(NORMAL + nrm.xzy * (bump_strength * (0.35 + 0.9 * rock_inf)));

	// ── roughness por superfície (PBR estilizado) ──
	// rocha = fosca; neve/coisas claras = mais brilhantes; húmido perto do mar = liso
	float lum = dot(base, vec3(0.33));
	float snow_ish = smoothstep(0.62, 0.85, lum);
	float r = mix(0.86, 0.97, rock_inf);            // rocha fosca
	r = mix(r, 0.45, snow_ish * 0.7);               // neve: brilho fino
	r *= 0.9 + 0.2 * grain;
	ROUGHNESS = clamp(r, 0.25, 1.0);
	SPECULAR = 0.5;
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

	// specular estilizado: reflexo suave, mais nítido onde é mais liso (PBR-ish)
	vec3 H = normalize(LIGHT + VIEW);
	float ndh = max(dot(NORMAL, H), 0.0);
	float gloss = 1.0 - ROUGHNESS;
	float spec = pow(ndh, mix(10.0, 140.0, gloss)) * gloss * spec_strength;
	SPECULAR_LIGHT += LIGHT_COLOR * spec * shadow * vec3(1.0, 0.98, 0.94);
}
