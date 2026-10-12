shader_type spatial;
// Estruturas da vila: bandas toon + sombra real do motor + madeira procedural subtil.
// A base de luz e IDENTICA ao toon_terrain (ja provada em Forward+ e Compatibility);
// o que muda e o fragment(), que acrescenta pranchas e variacao para as casas nao
// parecerem caixas de cor lisa. Sem vento, sem ALPHA (nunca vai para o passe transparente).
render_mode specular_disabled;

uniform vec3 sun_dir = vec3(-0.4, 0.8, 0.3);
uniform vec4 shadow_tint : source_color = vec4(0.54, 0.56, 0.86, 1.0);
uniform float bands : hint_range(1.0, 8.0) = 4.0;
uniform float band_soft : hint_range(0.0, 1.0) = 0.55;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.26;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float light_gain : hint_range(0.2, 3.0) = 1.05;
uniform float ambient_gain : hint_range(0.0, 2.0) = 0.88;
uniform float plank_scale : hint_range(0.0, 12.0) = 5.0;
uniform float plank_strength : hint_range(0.0, 0.6) = 0.10;

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	// pranchas: linhas escuras ao longo do Y do objeto (paredes de madeira)
	float py = fract(v_obj.y * plank_scale);
	float line = smoothstep(0.0, 0.06, py) * smoothstep(0.0, 0.06, 1.0 - py);
	float grain = mix(1.0 - plank_strength, 1.0, line);
	ALBEDO = COLOR.rgb * grain;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
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
}
