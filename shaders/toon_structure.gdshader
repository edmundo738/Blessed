shader_type spatial;
// Estruturas/ruínas de BLESSED — pedra com PBR estilizado (anime + material real).
// Pedra mosqueada + fendas + desgaste, roughness/specular suaves, bandas toon.
// Sem ALPHA (nunca vai para o passe transparente). Forward+ e Compatibility.
render_mode depth_draw_opaque;

uniform vec3 sun_dir = vec3(-0.4, 0.8, 0.3);
uniform vec4 shadow_tint : source_color = vec4(0.54, 0.56, 0.86, 1.0);
uniform float bands : hint_range(1.0, 8.0) = 4.0;
uniform float band_soft : hint_range(0.0, 1.0) = 0.55;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.26;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float light_gain : hint_range(0.2, 3.0) = 0.88;
uniform float ambient_gain : hint_range(0.0, 2.0) = 0.88;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.6;
uniform float bump_strength : hint_range(0.0, 1.5) = 0.6;
uniform float spec_strength : hint_range(0.0, 2.0) = 0.4;

varying vec3 v_obj;
varying vec3 v_world;

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
		p = p * 2.05 + vec2(7.3, 3.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_obj = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// triplanar simples: escolhe o plano de projeção pela normal (sem UV)
	vec3 n = abs(NORMAL);
	vec2 uv = n.y > n.x && n.y > n.z ? v_world.xz : (n.x > n.z ? v_world.zy : v_world.xy);

	float mott = fbm(uv * 1.6);              // mosqueado largo da pedra
	float fine = fbm(uv * 6.0);              // grão
	// fendas: linhas finas onde o ruído cruza um limiar
	float crack = smoothstep(0.48, 0.50, abs(fbm(uv * 3.0) - 0.5));

	vec3 stone = COLOR.rgb;
	stone *= mix(1.0, 0.6 + 0.8 * mott, detail_strength);
	stone *= 0.88 + 0.24 * fine;
	stone *= mix(1.0, 0.72, (1.0 - crack) * 0.5 * detail_strength);  // fendas escuras

	ALBEDO = stone;

	// micro-relevo da pedra
	float e = 0.35;
	float hc = fbm(uv * 5.0);
	float hx = fbm((uv + vec2(e, 0.0)) * 5.0);
	float hz = fbm((uv + vec2(0.0, e)) * 5.0);
	vec3 nrm = normalize(vec3((hc - hx) * 2.0, e, (hc - hz) * 2.0));
	NORMAL = normalize(NORMAL + nrm.xzy * bump_strength * 0.5);

	ROUGHNESS = clamp(0.82 + 0.16 * fine, 0.4, 1.0);   // pedra: maior parte fosca
	SPECULAR = 0.5;
}

void light() {
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
	vec3 col = mix(base * shadow_tint.rgb, base, clamp(band * 1.12, 0.0, 1.0));
	col = mix(col * shadow_tint.rgb, col, clamp(ATTENUATION, 0.0, 1.0));

	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	col += LIGHT_COLOR * rim * rim_strength * band;

	DIFFUSE_LIGHT += min(col, vec3(1.5)) * LIGHT_COLOR * ambient_gain;

	vec3 H = normalize(LIGHT + VIEW);
	float ndh = max(dot(NORMAL, H), 0.0);
	float gloss = 1.0 - ROUGHNESS;
	float spec = pow(ndh, mix(10.0, 120.0, gloss)) * gloss * spec_strength;
	SPECULAR_LIGHT += LIGHT_COLOR * spec * clamp(ATTENUATION, 0.0, 1.0);
	}
}
