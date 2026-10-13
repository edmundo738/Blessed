shader_type spatial;
// Céu de BLESSED num domo invertido (funciona igual em Forward+, Mobile e Compatibility).
//
// Camadas, de trás para a frente:
//   1. gradiente atmosférico suave (zénite → horizonte, com dispersão no pôr do sol)
//   2. estrelas pontuais (grelha 3D, brilho e cor variáveis, cintilação discreta)
//   3. lua com fases e crateras, e halo
//   4. sol: disco redondo + halo + brilho largo (HDR só no disco, para o bloom)
//   5. nuvens em duas camadas (cumulus iluminado pela direção do sol + cirros finos)
//   6. bruma de horizonte
//
// BUG CORRIGIDO: o sol aparecia como um hexágono porque `v_dir` (interpolado por
// triângulo) era usado sem normalizar no fragment. Agora normaliza-se por pixel.
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled;

uniform vec3 sun_dir = vec3(-0.4, 0.6, 0.3);
uniform vec4 zenith_day : source_color = vec4(0.16, 0.38, 0.78, 1.0);
uniform vec4 horizon_day : source_color = vec4(0.66, 0.80, 0.93, 1.0);
uniform vec4 zenith_dusk : source_color = vec4(0.17, 0.17, 0.42, 1.0);
uniform vec4 horizon_dusk : source_color = vec4(0.98, 0.52, 0.32, 1.0);
uniform vec4 zenith_night : source_color = vec4(0.015, 0.025, 0.075, 1.0);
uniform vec4 horizon_night : source_color = vec4(0.055, 0.085, 0.17, 1.0);
uniform vec4 cloud_color : source_color = vec4(1.00, 0.98, 0.95, 1.0);
uniform vec4 cloud_shadow : source_color = vec4(0.52, 0.58, 0.76, 1.0);

uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform float dusk_mix : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_amount : hint_range(0.0, 1.5) = 0.55;
uniform float cloud_speed : hint_range(0.0, 0.2) = 0.006;
uniform float star_amount : hint_range(0.0, 1.0) = 1.0;
uniform float sun_radius : hint_range(0.005, 0.1) = 0.032;   // raio angular em radianos (~1.8°)
uniform float moon_radius : hint_range(0.005, 0.1) = 0.040;
uniform float moon_phase : hint_range(0.0, 1.0) = 0.62;      // 0 nova, 0.5 cheia
uniform float glow_strength : hint_range(0.0, 3.0) = 1.0;

varying vec3 v_dir;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
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
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_dir = VERTEX;   // o domo não roda: espaço de objeto = direção
}

void fragment() {
	vec3 d = normalize(v_dir);
	vec3 S = normalize(sun_dir);
	float y = d.y;
	float sd = dot(d, S);

	// ── 1. gradiente atmosférico ────────────────────────────────────────
	vec3 zen = mix(zenith_night.rgb, zenith_day.rgb, daylight);
	vec3 hor = mix(horizon_night.rgb, horizon_day.rgb, daylight);
	zen = mix(zen, zenith_dusk.rgb, dusk_mix);
	hor = mix(hor, horizon_dusk.rgb, dusk_mix);
	float h = clamp(y, 0.0, 1.0);
	vec3 col = mix(hor, zen, pow(h, 0.5));
	// dispersão: o céu perto do sol aquece (mais forte quando o sol está baixo)
	float near_sun = pow(max(sd, 0.0), 5.0);
	vec3 warm = mix(vec3(1.0, 0.86, 0.62), vec3(1.0, 0.45, 0.22), dusk_mix);
	col += warm * near_sun * (0.12 + 0.45 * dusk_mix) * daylight * glow_strength;
	// abaixo do horizonte: tom do horizonte escurecido (o terreno tapa quase tudo)
	col = mix(col, hor * 0.55, smoothstep(0.0, -0.25, y));

	// ── 2. estrelas ─────────────────────────────────────────────────────
	float night = clamp(1.0 - daylight * 1.7, 0.0, 1.0);
	if (star_amount > 0.001 && night > 0.001 && y > -0.02) {
		vec3 sp = d * 190.0;
		vec3 cell = floor(sp);
		vec3 fp = fract(sp) - 0.5;
		float r = hash31(cell);
		float present = step(0.975, r);
		vec3 jitter = (vec3(hash31(cell + 3.1), hash31(cell + 7.7), hash31(cell + 11.3)) - 0.5) * 0.6;
		float dist = length(fp - jitter);
		float mag = pow(hash31(cell + 19.9), 3.0);
		float star = smoothstep(0.17 + mag * 0.10, 0.0, dist) * present * (0.35 + 0.65 * mag);
		float tw = 0.85 + 0.15 * sin(TIME * (1.5 + r * 3.0) + r * 40.0);
		vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.88, 0.72), hash31(cell + 29.0));
		col += tint * star * tw * star_amount * night * smoothstep(0.0, 0.18, y) * 1.6;
	}

	// ── 3. lua ──────────────────────────────────────────────────────────
	vec3 M = -S;
	float md = dot(d, M);
	float m_ang = acos(clamp(md, -1.0, 1.0));
	float moon_vis = (1.0 - smoothstep(0.35, 0.85, daylight)) * smoothstep(-0.05, 0.08, M.y);
	if (moon_vis > 0.001) {
		vec3 t = normalize(cross(M, vec3(0.0, 1.0, 0.0)));
		vec3 b = cross(t, M);
		vec2 uv = vec2(dot(d, t), dot(d, b)) / sin(moon_radius);
		float rr = length(uv);
		float disc = 1.0 - smoothstep(0.96, 1.0, rr);
		vec3 n = vec3(uv, sqrt(max(1.0 - rr * rr, 0.0)));
		float ph = moon_phase * 6.28318;
		vec3 L = normalize(vec3(sin(ph), 0.15, -cos(ph) * 0.9 + 0.1));
		float lit = smoothstep(-0.04, 0.10, dot(n, L));
		float crater = fbm(uv * 3.2 + 4.0);
		float maria = fbm(uv * 1.4 + 11.0);
		vec3 surf = vec3(0.93, 0.94, 0.90) * mix(0.62, 1.05, crater) * mix(0.82, 1.0, maria);
		col += surf * (0.12 + 0.88 * lit) * disc * moon_vis * 1.15;
		col += vec3(0.50, 0.62, 0.95) * exp(-m_ang * 18.0) * moon_vis * 0.22;
	}

	// ── 4. sol ──────────────────────────────────────────────────────────
	float s_ang = acos(clamp(sd, -1.0, 1.0));
	float sun_vis = smoothstep(-0.10, 0.04, S.y);
	float sdisc = 1.0 - smoothstep(sun_radius * 0.92, sun_radius, s_ang);
	vec3 sun_col = mix(vec3(1.0, 0.95, 0.82), vec3(1.0, 0.62, 0.32), dusk_mix);
	col += sun_col * sdisc * 3.2 * sun_vis * daylight;                       // HDR: dá o bloom
	col += sun_col * exp(-s_ang * 26.0) * 0.55 * glow_strength * sun_vis * daylight;
	col += sun_col * exp(-s_ang * 6.0) * 0.14 * glow_strength * sun_vis * daylight;

	// ── 5. nuvens ───────────────────────────────────────────────────────
	if (y > 0.005) {
		vec2 wind = vec2(TIME * cloud_speed, TIME * cloud_speed * 0.35);
		// cumulus
		vec2 cp = d.xz / (y + 0.14) * 0.62 + wind;
		float n = fbm(cp * 1.5);
		float t0 = 0.64 - cloud_amount * 0.30;
		float cov = smoothstep(t0, t0 + 0.26, n);
		// densidade deslocada na direção do sol: a diferença dá a face iluminada
		vec2 toward = normalize(S.xz + vec2(0.0001)) * 0.05;
		float n_s = fbm((cp + toward) * 1.5);
		float rim = clamp(0.5 + (n - n_s) * 5.0, 0.0, 1.0);
		float core = smoothstep(t0 + 0.10, t0 + 0.55, n);         // miolo espesso = mais escuro
		vec3 sun_lit = mix(cloud_color.rgb, horizon_dusk.rgb * 1.1, dusk_mix * 0.85);
		vec3 shade = mix(cloud_shadow.rgb, zen * 0.9 + 0.1, 0.35);
		shade = mix(shade, horizon_dusk.rgb * 0.55 + zenith_dusk.rgb * 0.35, dusk_mix * 0.6);
		vec3 cc = mix(shade, sun_lit, clamp(rim * (1.0 - core * 0.55) + 0.18, 0.0, 1.0));
		// forro prateado junto ao sol
		cc += sun_col * pow(max(sd, 0.0), 10.0) * (1.0 - core) * 0.35 * daylight;
		// de noite: cinza-azulado, aquecido ao de leve pela lua
		vec3 night_cc = vec3(0.025, 0.035, 0.075) + vec3(0.30, 0.36, 0.55) * pow(max(md, 0.0), 8.0) * moon_vis * 0.5;
		cc = mix(night_cc, cc, clamp(daylight * 1.5, 0.0, 1.0));
		float fade = smoothstep(0.0, 0.16, y);
		col = mix(col, cc, clamp(cov, 0.0, 1.0) * 0.96 * fade);

		// cirros: camada fina e esticada, muito mais alta
		vec2 hp = d.xz / (y + 0.35) * vec2(0.45, 1.4) + wind * 1.7 + 31.0;
		float hn = fbm(hp * 1.2);
		float hc = smoothstep(0.55, 0.85, hn) * 0.42 * fade;
		vec3 hc_col = mix(vec3(0.03, 0.04, 0.08), mix(sun_lit, vec3(1.0), 0.4), clamp(daylight * 1.5, 0.0, 1.0));
		col = mix(col, hc_col, hc);
	}

	// ── 6. bruma de horizonte ───────────────────────────────────────────
	col = mix(col, hor, pow(1.0 - clamp(y, 0.0, 1.0), 6.0) * 0.55);

	ALBEDO = col;
	// Sem ALPHA: o domo é opaco; `depth_draw_never` + render_priority -100
	// fazem-no desenhar primeiro e nunca tapar nada (como um skybox).
}
