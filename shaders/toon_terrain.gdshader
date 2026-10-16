shader_type spatial;
// Terreno de BLESSED — materiais procedurais por classe + luz toon com resposta PBR.
//
// Cada vértice traz pesos de CLASSE de material (escritos por chunk.gd):
//     UV  = (relva, terra/lama)      UV2 = (areia, estratos de badlands)
//     COLOR.rgb = tinta do bioma     COLOR.a = neve
// A rocha vem da inclinação e da altitude. Tudo é calculado em espaço de mundo,
// por isso não há costuras entre chunks nem entre LODs.
//
// REGRA DE OURO (bug da versão anterior): NENHUM padrão pode ser esticado numa
// direção fixa do mundo. As "estrias" a vec2(7, 2.2) alinhavam-se com o eixo Z e,
// em perspectiva, convergiam para o horizonte como um borrão radial. Aqui todos os
// padrões são isotrópicos (ruído, voronoi) ou, nas paredes verticais, projetados no
// plano da parede (rocha) — nunca esticados.
//
// Todo o detalhe desvanece com a distância (anti-aliasing + custo).
render_mode depth_draw_opaque;

uniform vec3 sun_dir = vec3(-0.4, 0.8, 0.3);
uniform vec4 shadow_tint : source_color = vec4(0.56, 0.60, 0.90, 1.0);
uniform float bands : hint_range(1.0, 8.0) = 3.0;
uniform float band_soft : hint_range(0.0, 1.0) = 0.50;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.22;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float light_gain : hint_range(0.2, 3.0) = 0.82;
uniform float ambient_gain : hint_range(0.0, 2.0) = 0.85;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.85;
uniform float bump_strength : hint_range(0.0, 3.0) = 1.0;
uniform float spec_strength : hint_range(0.0, 2.0) = 0.55;
uniform float detail_fade_near = 45.0;
uniform float detail_fade_far = 230.0;
// Chão por baixo da relva: de perto vê-se TERRA (castanha, o solo onde a relva
// cresce) entre as lâminas; a partir de ~20 m o que domina é a cor da própria
// relva, senão o campo lia-se como poeira com pontos verdes por cima.
uniform float soil_near = 4.0;
uniform float soil_far = 20.0;
uniform float soil_strength : hint_range(0.0, 1.0) = 0.85;
uniform float soil_red = 0.30;
uniform float soil_green = 0.21;
uniform float soil_blue = 0.14;

varying vec3 v_world;
varying vec3 v_wn;
varying float v_slope;

// ── ruídos ────────────────────────────────────────────────────────────────
// hash inteiro (PCG): exacto a qualquer distância da origem. O hash antigo com fract(p*123.34)
// perdia precisão em float32 a milhares de metros e desenhava riscas radiais no chão.
float hash21(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));
	uint h = q.x * 1597334677u ^ q.y * 3812015801u;
	h = (h ^ (h >> 15u)) * 2246822519u;
	h = (h ^ (h >> 13u)) * 3266489917u;
	h ^= h >> 16u;
	return float(h & 0xFFFFFFu) / 16777216.0;
}

vec2 hash22(vec2 p) {
	return vec2(hash21(p), hash21(p + vec2(31.0, 17.0)));
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

float fbm3(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(11.3, 7.7);
		a *= 0.5;
	}
	return v / 0.875;
}

// voronoi: x = distância ao centro mais próximo, y = ao segundo, z = id da célula
vec3 voro(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash22(i + g);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				id = hash21(i + g + 7.7);
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec3(sqrt(f1), sqrt(f2), id);
}

// filtro anti-aliasing: 1 = detalhe visível, 0 = mais fino do que o pixel (frequência em ciclos/metro)
float aa(float freq, float fp) {
	return 1.0 - smoothstep(0.30, 0.80, fp * freq);
}

// ── classes de material: cada uma devolve albedo, altura (para a normal) e roughness ──
// k = 0..1 intensidade do detalhe (já com o desvanecimento por distância)

void cls_grass(vec2 p, vec3 base, float k, float fp, float soil_mix, out vec3 alb, out float h, out float rough) {
	float macro = fbm3(p * 0.018);                       // manchas de 50 m: viçoso vs seco
	float clump = vnoise(p * 1.6);                       // tufos de ~60 cm
	float fine = vnoise(p * 9.0);                        // lâminas
	vec3 lush = base * vec3(0.92, 1.08, 0.86);
	vec3 dry = base * vec3(1.18, 1.02, 0.62) + vec3(0.03, 0.02, 0.0);
	vec3 c = mix(dry, lush, smoothstep(0.30, 0.72, macro));
	c *= mix(1.0, 0.72 + 0.50 * clump, k);
	c *= mix(1.0, 0.86 + 0.28 * fine, k * aa(9.0, fp));
	// salpicos redondos (tufos claros e sombras), centro jitterado: nunca em quadrados
	vec2 g1 = p * 5.0;
	vec2 id1 = floor(g1);
	vec2 o1 = hash22(id1) * 0.5 + 0.25;
	float d1 = length(fract(g1) - o1);
	float on1 = step(0.80, hash21(id1 + 5.5));
	c = mix(c, c * 1.22, on1 * (1.0 - smoothstep(0.10, 0.30, d1)) * k * 0.6 * aa(5.0, fp));
	vec2 g2 = p * 3.1 + 40.0;
	vec2 id2 = floor(g2);
	vec2 o2 = hash22(id2) * 0.5 + 0.25;
	float d2 = length(fract(g2) - o2);
	float on2 = step(0.84, hash21(id2 + 9.1));
	c = mix(c, c * 0.70, on2 * (1.0 - smoothstep(0.12, 0.34, d2)) * k * 0.55 * aa(3.1, fp));

	// O solo por baixo: entre as lâminas de relva vê-se terra, não uma tela
	// verde. `base` é a cor do bioma, por isso cada pradaria tem a sua terra
	// (a savana fica mais clara e poeirenta, a floresta mais escura e húmida).
	vec3 soil = vec3(soil_red, soil_green, soil_blue);
	soil = mix(soil, base * vec3(0.66, 0.52, 0.40), 0.42);
	soil *= 0.82 + 0.36 * macro;                       // manchas de humidade
	soil *= mix(1.0, 0.80 + 0.34 * clump, k);          // grumos
	float grain = vnoise(p * 22.0);
	soil *= mix(1.0, 0.88 + 0.24 * grain, k * aa(22.0, fp));
	// raízes: a terra imediatamente sob a relva é mais escura
	soil = mix(soil, soil * 0.72, on2 * 0.5 * k);

	vec3 grassy = c;
	alb = mix(grassy, soil, clamp(soil_mix, 0.0, 1.0));
	h = mix((clump * 0.6 + fine * 0.4 * aa(9.0, fp)) * 0.8,
		(vnoise(p * 12.0) * 0.5 + clump * 0.5), clamp(soil_mix, 0.0, 1.0));
	rough = 0.92;
}

void cls_dirt(vec2 p, vec3 base, float k, float fp, out vec3 alb, out float h, out float rough) {
	vec3 v = voro(p * 0.85);
	float edge = v.y - v.x;
	float crack = 1.0 - smoothstep(0.0, 0.07, edge);     // fendas de secagem
	float plate = 0.80 + 0.40 * v.z;                     // cada placa com o seu tom
	float macro = fbm3(p * 0.03);
	float puddle = smoothstep(0.58, 0.68, fbm3(p * 0.11 + 4.0));   // poças de lama húmida
	vec3 c = base * plate * (0.78 + 0.5 * macro);
	c = mix(c, c * 0.45, crack * k * aa(12.0, fp));
	// seixos
	float pb = hash21(floor(p * 7.0));
	vec2 cell = fract(p * 7.0) - 0.5;
	float peb = step(0.90, pb) * (1.0 - smoothstep(0.10, 0.22, length(cell)));
	c = mix(c, vec3(0.50, 0.46, 0.41) * (0.8 + 0.4 * hash21(floor(p * 7.0) + 2.0)), peb * k * aa(7.0, fp));
	c = mix(c, c * vec3(0.55, 0.50, 0.48), puddle * 0.8);   // lama molhada: escura
	alb = c;
	h = (v.x * 0.9 + (1.0 - crack) * 0.4 + peb * 0.5) * (1.0 - puddle * 0.9);
	rough = mix(0.95, 0.18, puddle);
}

void cls_sand(vec2 p, vec3 base, float k, float fp, out vec3 alb, out float h, out float rough) {
	float warp = fbm3(p * 0.045) * 9.0;
	// ondulações de vento: sinusoide com fase deformada (curvas, não linhas rectas)
	vec2 dir = normalize(vec2(0.82, 0.57));
	float ph = (dot(p, dir) + warp) * 2.4 + fbm3(p * 0.35) * 3.2;
	float rip = 0.5 + 0.5 * sin(ph);
	float crest = pow(rip, 1.6);
	float macro = fbm3(p * 0.02);
	vec3 c = base * mix(0.86, 1.10, crest);
	c *= 0.88 + 0.28 * macro;
	c = mix(c, c * vec3(1.06, 0.93, 0.80), (1.0 - crest) * 0.5 * k);  // vales mais quentes
	float grain = hash21(floor(p * 55.0));
	c *= 1.0 + (grain - 0.5) * 0.10 * k * aa(55.0, fp);
	alb = c;
	h = crest * 0.9 + vnoise(p * 7.0) * 0.12 * aa(7.0, fp);
	rough = 0.82;
}

const vec3 STRATA_PAL[6] = vec3[6](
	vec3(0.78, 0.50, 0.27), vec3(0.60, 0.29, 0.17), vec3(0.88, 0.74, 0.55),
	vec3(0.70, 0.38, 0.22), vec3(0.42, 0.23, 0.16), vec3(0.82, 0.58, 0.46)
);

void cls_strata(vec2 p, float wy, vec3 base, float k, float fp, out vec3 alb, out float h, out float rough) {
	// camadas geológicas: bandas horizontais pela ALTURA, deformadas por ruído
	float b = wy * 0.55 + fbm3(p * 0.03) * 2.2 + vnoise(p * 0.45) * 0.35;
	float id = floor(b);
	float fr = fract(b);
	int i0 = int(mod(id, 6.0));
	int i1 = int(mod(id + 1.0, 6.0));
	vec3 c0 = STRATA_PAL[i0];
	vec3 c1 = STRATA_PAL[i1];
	vec3 c = mix(c0, c1, smoothstep(0.88, 1.0, fr));
	c *= 1.0 - (0.14 - 0.24 * vnoise(p * 2.2) + 0.12) * aa(2.2, fp) * 0.0 + (vnoise(p * 2.2) - 0.5) * 0.24 * aa(2.2, fp);
	c = mix(c, base, 0.18);
	float line = smoothstep(0.0, 0.05, fr) * smoothstep(1.0, 0.95, fr);
	c *= mix(1.0, mix(0.78, 1.0, line), aa(4.0, fp));
	alb = c;
	h = fr * 0.6 + vnoise(p * 3.0) * 0.4 * aa(3.0, fp);
	rough = 0.94;
}

// rocha: coordenadas rp no PLANO da superfície (não esticadas nas paredes)
void cls_rock(vec2 rp, vec2 p, vec3 base, float k, float fp, float flatness, out vec3 alb, out float h, out float rough) {
	float macro = fbm3(rp * 0.07);
	vec3 v = voro(rp * 0.34);
	float crack = 1.0 - smoothstep(0.0, 0.035, v.y - v.x);
	vec3 cool = vec3(0.45, 0.45, 0.48);
	vec3 warm = vec3(0.52, 0.45, 0.38);
	vec3 c = mix(cool, warm, macro) * (0.72 + 0.50 * v.z);
	// estratificação suave
	float strat = 0.5 + 0.5 * sin(rp.y * 2.8 + fbm3(rp * 0.2) * 3.0);
	c *= 0.90 + 0.18 * strat;
	c = mix(c, c * 0.62, crack * k * aa(8.0, fp));
	// musgo e líquen nas partes menos inclinadas
	float moss = smoothstep(0.52, 0.72, fbm3(p * 0.16 + 9.0)) * smoothstep(0.30, 0.85, flatness);
	c = mix(c, vec3(0.28, 0.40, 0.20) * (0.8 + 0.4 * vnoise(p * 3.0)), moss * 0.75 * k);
	vec2 lc = fract(rp * 4.0) - 0.5;
	float lich = step(0.985, hash21(floor(rp * 4.0))) * (1.0 - smoothstep(0.06, 0.16, length(lc))) * k * aa(4.0, fp);
	c = mix(c, vec3(0.76, 0.58, 0.25), lich * 0.8);
	alb = c;
	h = v.x * 1.2 + (1.0 - crack * aa(8.0, fp)) * 0.5 + vnoise(rp * 4.0) * 0.3 * aa(4.0, fp);
	rough = 0.95;
}

void cls_snow(vec2 p, float k, float fp, out vec3 alb, out float h, out float rough) {
	float n = fbm3(p * 0.4);
	vec3 c = vec3(0.92, 0.95, 1.0) * (0.93 + 0.07 * n);
	c = mix(c, vec3(0.80, 0.86, 0.96), smoothstep(0.55, 0.9, vnoise(p * 0.08)) * 0.5);
	alb = c;
	h = vnoise(p * 2.5) * 0.35 * aa(2.5, fp) + vnoise(p * 7.0) * 0.12 * aa(7.0, fp);
	rough = 0.52;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_slope = clamp(1.0 - v_wn.y, 0.0, 1.0);
}

void fragment() {
	vec2 p = v_world.xz;
	float fp = max(length(dFdx(v_world)), length(dFdy(v_world)));   // metros por pixel (no plano visível)
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float k = detail_strength * (1.0 - smoothstep(detail_fade_near, detail_fade_far, dist));
	float kb = bump_strength * (1.0 - smoothstep(detail_fade_near * 0.6, detail_fade_far * 0.7, dist));

	// pesos de classe (relva, terra, areia, estratos)
	vec4 wc = vec4(UV.x, UV.y, UV2.x, UV2.y);
	float tot = wc.x + wc.y + wc.z + wc.w;
	if (tot < 0.001) {
		wc = vec4(1.0, 0.0, 0.0, 0.0);
		tot = 1.0;
	}
	wc /= tot;
	float snow_w = COLOR.a;

	float slope = v_slope;
	float nz = abs(v_wn.z);
	float nx = abs(v_wn.x);
	// coordenadas no plano da parede para a rocha
	vec2 rp = (nz > nx) ? vec2(v_world.x, v_world.y) : vec2(v_world.z, v_world.y);
	rp = mix(p, rp, smoothstep(0.18, 0.5, slope));             // chão plano usa XZ; paredes usam o plano da parede

	// máscara de rocha: declive + altitude, com ruído para não ter fronteira recta
	float rn = vnoise(p * 0.35) - 0.5;
	float rock_m = smoothstep(0.30, 0.62, slope + rn * 0.20);
	rock_m = max(rock_m, smoothstep(95.0, 140.0, v_world.y) * (0.4 + 0.6 * smoothstep(0.10, 0.4, slope)));
	float snow_m = snow_w * (1.0 - smoothstep(0.42, 0.72, slope));

	vec3 a_g; vec3 a_d; vec3 a_s; vec3 a_t; vec3 a_r; vec3 a_n;
	float h_g = 0.0; float h_d = 0.0; float h_s = 0.0; float h_t = 0.0; float h_r = 0.0; float h_n = 0.0;
	float r_g = 0.9; float r_d = 0.9; float r_s = 0.9; float r_t = 0.9; float r_r = 0.9; float r_n = 0.5;
	vec3 base = COLOR.rgb;
	vec3 alb = vec3(0.0);
	float hgt = 0.0;
	float rgh = 0.0;
	float soil_mix = soil_strength * (1.0 - smoothstep(soil_near, soil_far, dist));
	if (wc.x > 0.01) { cls_grass(p, base, k, fp, soil_mix, a_g, h_g, r_g); alb += a_g * wc.x; hgt += h_g * wc.x; rgh += r_g * wc.x; }
	if (wc.y > 0.01) { cls_dirt(p, base, k, fp, a_d, h_d, r_d); alb += a_d * wc.y; hgt += h_d * wc.y; rgh += r_d * wc.y; }
	if (wc.z > 0.01) { cls_sand(p, base, k, fp, a_s, h_s, r_s); alb += a_s * wc.z; hgt += h_s * wc.z; rgh += r_s * wc.z; }
	if (wc.w > 0.01) { cls_strata(p, v_world.y, base, k, fp, a_t, h_t, r_t); alb += a_t * wc.w; hgt += h_t * wc.w; rgh += r_t * wc.w; }
	float flatness = 1.0 - slope;
	if (rock_m > 0.01) {
		cls_rock(rp, p, base, k, fp, flatness, a_r, h_r, r_r);
		alb = mix(alb, a_r, rock_m);
		hgt = mix(hgt, h_r, rock_m);
		rgh = mix(rgh, r_r, rock_m);
	}
	if (snow_m > 0.01) {
		cls_snow(p, k, fp, a_n, h_n, r_n);
		alb = mix(alb, a_n, snow_m);
		hgt = mix(hgt, h_n, snow_m);
		rgh = mix(rgh, r_n, snow_m);
	}

	// variação de cor de larga escala, sempre presente (mesmo longe): quebra o "plástico"
	float far_var = fbm3(p * 0.006);
	alb *= mix(0.88, 1.10, far_var);
	// oclusão de fenda em declives acentuados
	alb *= mix(1.0, 0.72, smoothstep(0.22, 0.88, slope));

	ALBEDO = alb;
	ROUGHNESS = clamp(rgh, 0.15, 1.0);
	SPECULAR = 0.5;

	// ── normal: o gradiente da altura do material, calculado por diferenças finitas ──
	// (recalcula só as classes dominantes; desvanece com a distância)
	if (kb > 0.02) {
		float e = 0.30;
		float h1 = 0.0;
		float h2 = 0.0;
		float dh;
		float dr;
		vec3 da;
		vec2 px = p + vec2(e, 0.0);
		vec2 pz = p + vec2(0.0, e);
		if (wc.x > 0.01) { cls_grass(px, base, 0.0, fp, soil_mix, da, dh, dr); h1 += dh * wc.x; cls_grass(pz, base, 0.0, fp, soil_mix, da, dh, dr); h2 += dh * wc.x; }
		if (wc.y > 0.01) { cls_dirt(px, base, 0.0, fp, da, dh, dr); h1 += dh * wc.y; cls_dirt(pz, base, 0.0, fp, da, dh, dr); h2 += dh * wc.y; }
		if (wc.z > 0.01) { cls_sand(px, base, 0.0, fp, da, dh, dr); h1 += dh * wc.z; cls_sand(pz, base, 0.0, fp, da, dh, dr); h2 += dh * wc.z; }
		if (wc.w > 0.01) { cls_strata(px, v_world.y, base, 0.0, fp, da, dh, dr); h1 += dh * wc.w; cls_strata(pz, v_world.y, base, 0.0, fp, da, dh, dr); h2 += dh * wc.w; }
		vec3 bump = vec3(-(h1 - hgt), 0.0, -(h2 - hgt)) / e;
		if (rock_m > 0.01) {
			vec2 rpx = rp + vec2(e, 0.0);
			vec2 rpy = rp + vec2(0.0, e);
			float rh = 0.0;
			float rx; float ry;
			cls_rock(rpx, p, base, 0.0, fp, flatness, da, rx, dr);
			cls_rock(rpy, p, base, 0.0, fp, flatness, da, ry, dr);
			rh = h_r;
			vec2 g = vec2(rx - rh, ry - rh) / e;
			vec3 rb = (nz > nx) ? vec3(-g.x, -g.y, 0.0) : vec3(0.0, -g.y, -g.x);
			rb = mix(vec3(-g.x, 0.0, -g.y), rb, smoothstep(0.18, 0.5, slope));
			bump = mix(bump, rb * 1.4, rock_m);
		}
		vec3 wbump = bump * kb * 0.55;
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(wbump, 0.0)).xyz);
	}
}

void light() {
	// A luz local da fogueira mantém a queda radial contínua; só o sol e a lua
	// usam bandas toon, que antes recortavam o círculo em placas facetadas.
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
	vec3 shaded = base * shadow_tint.rgb;
	vec3 col = mix(shaded, base, clamp(band * 1.12, 0.0, 1.0));

	float shadow = clamp(ATTENUATION, 0.0, 1.0);
	col = mix(col * shadow_tint.rgb, col, shadow);

	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	col += LIGHT_COLOR * rim * rim_strength * band;

	DIFFUSE_LIGHT += min(col, vec3(1.5)) * LIGHT_COLOR * ambient_gain;

	// brilho estilizado dependente da roughness: lama molhada e neve brilham, rocha e terra não
	vec3 H = normalize(LIGHT + VIEW);
	float ndh = max(dot(NORMAL, H), 0.0);
	float gloss = 1.0 - ROUGHNESS;
	float spec = pow(ndh, mix(10.0, 160.0, gloss)) * gloss * spec_strength;
	SPECULAR_LIGHT += LIGHT_COLOR * spec * shadow * vec3(1.0, 0.98, 0.94);
	}
}
