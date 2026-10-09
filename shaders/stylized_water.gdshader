shader_type spatial;
// Água estilizada — OPACA.
//
// Duas razões, ambas documentadas pela própria documentação do Godot:
//
// 1. Escrever ALPHA num shader espacial põe o material no passe TRANSPARENTE,
//    onde a ordenação é por objecto e não por triângulo ("surfaces in the back
//    appearing to be in front"). Este plano tem 1400x1400 m: uma superfície
//    transparente deste tamanho é meio caminho andado para se ver o mundo
//    através dela.
//
// 2. `hint_depth_texture` não serve aqui. A doc diz que materiais transparentes
//    nem aparecem em hint_depth_texture, e a reconstrução da profundidade muda
//    entre renderers: Forward+/Mobile usam NDC 0..1, o Compatibility usa
//    NDC -1..1 — e desde o Godot 4.3 o depth buffer é "reverse-z", com o near
//    em 1.0 em vez de 0.0. O código anterior usava a convenção do Forward+ e
//    a exportação web corre em Compatibility, por isso a "profundidade" da
//    água era lixo. Sem a textura de profundidade o mesmo shader dá o mesmo
//    resultado nos dois renderers.
//
// A espuma de margem passa a vir das bandas de onda, não da profundidade real.
render_mode depth_draw_opaque, cull_back, diffuse_toon;

uniform vec4 deep_color : source_color = vec4(0.10, 0.36, 0.52, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.34, 0.78, 0.82, 1.0);
uniform vec4 foam_color : source_color = vec4(0.94, 0.98, 1.00, 1.0);
uniform vec4 sky_tint : source_color = vec4(0.62, 0.82, 1.00, 1.0);
uniform float wave_speed : hint_range(0.0, 4.0) = 0.55;
uniform float wave_scale : hint_range(0.5, 40.0) = 9.0;
uniform float sun_glow : hint_range(0.0, 2.0) = 0.6;
uniform vec3 sun_dir = vec3(-0.4, 0.8, 0.3);

varying vec3 v_world;

float wave(vec2 p, float t) {
	return sin(p.x * 1.0 + t) * 0.5 + sin(p.y * 1.37 - t * 0.83) * 0.5;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = v_world.xz * 0.35;
	VERTEX.y += wave(p, TIME * wave_speed) * 0.06;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 p = v_world.xz * wave_scale * 0.1;
	float w = wave(p, t) * 0.5 + 0.5;

	// bandas duras — é o "traço" do desenho
	float band = floor(w * 4.0) / 4.0;
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, band);
	col = mix(col, col * 1.22 + vec3(0.05), step(0.75, w) * 0.5);

	// crista de espuma nas bandas mais altas
	col = mix(col, foam_color.rgb, step(0.93, w) * 0.7);

	// reflexo falso: brilho onde a normal aponta ao sol
	vec3 n = normalize(NORMAL + vec3(band * 0.12, 0.0, (1.0 - band) * 0.12));
	float glow = pow(max(dot(reflect(-VIEW, n), normalize(sun_dir)), 0.0), 18.0);
	col += sky_tint.rgb * glow * sun_glow;

	ALBEDO = col;
	ROUGHNESS = 0.15;
	SPECULAR = 0.6;
}
