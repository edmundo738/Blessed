shader_type spatial;
// Folhagem anime: vento no vértice + bandas de luz + tinta por instância.
// INSTANCE_CUSTOM: xyz = tinta da instância, w = raio de desaparecimento (0 = não some).
render_mode specular_disabled;

uniform vec4 shadow_tint : source_color = vec4(0.52, 0.56, 0.88, 1.0);
uniform float bands : hint_range(1.0, 8.0) = 3.0;
uniform float band_soft : hint_range(0.0, 1.0) = 0.12;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.40;
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;
uniform float light_gain : hint_range(0.2, 3.0) = 1.10;
uniform float ambient_gain : hint_range(0.0, 2.0) = 0.90;

uniform float wind_strength : hint_range(0.0, 1.0) = 0.14;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.0;
uniform float wind_height = 1.0;
uniform float sway_pivot = 0.0;

varying vec3 v_tint;
varying float v_fade;

void vertex() {
	v_tint = mix(vec3(1.0), INSTANCE_CUSTOM.xyz, step(0.01, dot(INSTANCE_CUSTOM.xyz, vec3(1.0))));
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	// vento: desloca proporcionalmente à altura no objeto
	float h = clamp((VERTEX.y - sway_pivot) / max(wind_height, 0.001), 0.0, 1.0);
	float ph = origin.x * 0.31 + origin.z * 0.23 + TIME * wind_speed;
	vec2 sway = vec2(sin(ph), cos(ph * 0.77)) * wind_strength * h * h;
	VERTEX.x += sway.x;
	VERTEX.z += sway.y;

	// desaparecimento por distância: o tufo encolhe em vez de fazer alpha blend
	float fade_from = INSTANCE_CUSTOM.w;
	if (fade_from > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float d = distance(wp, INV_VIEW_MATRIX[3].xyz);
		float k = 1.0 - smoothstep(fade_from, fade_from * 1.35, d);
		v_fade = k;
		vec3 pivot = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		world_pos = mix(pivot, world_pos, k);
		VERTEX = (inverse(MODEL_MATRIX) * vec4(world_pos, 1.0)).xyz;
	} else {
		v_fade = 1.0;
	}
}

void fragment() {
	ALBEDO = COLOR.rgb * v_tint;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	// NÃO escrever ALPHA aqui. Em Godot 4, escrever ALPHA num shader espacial
	// põe o material no passe TRANSPARENTE — e este shader é partilhado pela
	// folhagem, pela erva e pelas ESTRUTURAS, por isso as casas e as árvores
	// ficavam todas translúcidas, a ver-se umas através das outras ("raio X").
	// O desaparecimento à distância já está feito no vertex(): a instância
	// encolhe até colapsar no pivot, o que chega para a fazer sumir.
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = ndl * 0.5 + 0.5;
	float band = floor(lit * bands) / bands;
	band = mix(band, lit, band_soft);

	vec3 base = ALBEDO * light_gain;
	vec3 col = mix(base * shadow_tint.rgb, base, clamp(band * 1.1, 0.0, 1.0));
	col = mix(col * shadow_tint.rgb, col, clamp(ATTENUATION, 0.0, 1.0));

	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	col += LIGHT_COLOR * rim * rim_strength * (0.4 + band);

	DIFFUSE_LIGHT += col * LIGHT_COLOR * ambient_gain * v_fade;
}
