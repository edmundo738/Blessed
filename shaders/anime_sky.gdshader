shader_type spatial;
// Céu anime num domo invertido (em vez de `shader_type sky`).
//
// Porquê um domo: os built-ins do sky shader mudaram entre versões do Godot 4
// (o `EYE_DIRECTION` já não existe no 4.7). Num shader espacial tenho `VERTEX`
// em espaço de objeto, que é exatamente a direção — e funciona igual em
// Forward+, em Compatibility e no export web. O domo segue a câmara e não roda.
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled;

uniform vec3 sun_dir = vec3(-0.4, 0.6, 0.3);
uniform vec4 zenith_day : source_color = vec4(0.24, 0.55, 0.95, 1.0);
uniform vec4 horizon_day : source_color = vec4(0.80, 0.92, 1.00, 1.0);
uniform vec4 zenith_dusk : source_color = vec4(0.26, 0.24, 0.52, 1.0);
uniform vec4 horizon_dusk : source_color = vec4(1.00, 0.56, 0.38, 1.0);
uniform vec4 zenith_night : source_color = vec4(0.03, 0.05, 0.13, 1.0);
uniform vec4 horizon_night : source_color = vec4(0.09, 0.13, 0.26, 1.0);
uniform vec4 cloud_color : source_color = vec4(1.00, 1.00, 1.00, 1.0);
uniform vec4 cloud_shadow : source_color = vec4(0.68, 0.74, 0.92, 1.0);

uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform float dusk_mix : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_amount : hint_range(0.0, 1.5) = 0.55;
uniform float cloud_speed : hint_range(0.0, 0.2) = 0.006;
uniform float star_amount : hint_range(0.0, 1.0) = 1.0;
uniform float sun_size : hint_range(0.0, 0.05) = 0.012;
uniform float glow_strength : hint_range(0.0, 3.0) = 1.0;

varying vec3 v_dir;

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
		p *= 2.02;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	// espaço de objeto = direção, porque o domo não roda
	v_dir = normalize(VERTEX);
}

void fragment() {
	vec3 d = v_dir;
	float up = clamp(d.y * 0.5 + 0.5, 0.0, 1.0);

	vec3 zen = mix(zenith_night.rgb, zenith_day.rgb, daylight);
	vec3 hor = mix(horizon_night.rgb, horizon_day.rgb, daylight);
	zen = mix(zen, zenith_dusk.rgb, dusk_mix);
	hor = mix(hor, horizon_dusk.rgb, dusk_mix);

	// gradiente em bandas: fundo pintado à mão
	float g = floor(pow(up, 1.15) * 5.0) / 5.0;
	vec3 col = mix(hor, zen, mix(g, pow(up, 1.15), 0.45));

	// sol
	float sd = max(dot(d, normalize(sun_dir)), 0.0);
	col += vec3(1.0, 0.93, 0.72) * smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.25, sd) * daylight;
	col += vec3(1.0, 0.70, 0.42) * pow(sd, 48.0) * glow_strength * 0.5;

	// lua
	vec3 moon_dir = -normalize(sun_dir);
	float md = max(dot(d, moon_dir), 0.0);
	col += vec3(0.85, 0.90, 1.00) * smoothstep(0.9975, 0.9995, md) * (1.0 - daylight);
	col += vec3(0.55, 0.65, 0.95) * pow(md, 220.0) * (1.0 - daylight) * 0.6;

	// estrelas
	if (star_amount > 0.001 && daylight < 0.6) {
		vec2 sc = d.xz / max(abs(d.y) + 0.25, 0.05) * 26.0;
		float star = step(0.9965, hash21(floor(sc)));
		float tw = 0.6 + 0.4 * sin(TIME * 2.2 + hash21(floor(sc)) * 30.0);
		col += vec3(0.9, 0.95, 1.0) * star * tw * star_amount
			* (1.0 - daylight * 1.6) * step(0.02, d.y);
	}

	// nuvens em bandas duras
	if (d.y > 0.01) {
		vec2 cp = d.xz / (d.y + 0.12) * 0.55
			+ vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4);
		float n = fbm(cp * 1.6);
		float cov = smoothstep(0.62 - cloud_amount * 0.35, 0.72 - cloud_amount * 0.25, n);
		cov *= smoothstep(0.0, 0.12, d.y);
		float lit = step(0.5, n - cov * 0.25);
		vec3 cc = mix(cloud_shadow.rgb, cloud_color.rgb, lit);
		cc = mix(cc * 0.35 + vec3(0.02, 0.03, 0.07), cc, clamp(daylight * 1.6, 0.0, 1.0));
		col = mix(col, cc, clamp(cov * 1.25, 0.0, 1.0) * 0.95);
	}

	// névoa no horizonte
	col = mix(col, hor, pow(1.0 - up, 7.0) * 0.6);

	ALBEDO = col;
	ALPHA = 1.0;
}
