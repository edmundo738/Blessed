shader_type spatial;
// Superfície de água opaca e dupla face: costa legível de cima e reflexo
// azul estilizado quando a câmara fica submersa.
render_mode cull_disabled, depth_draw_opaque, diffuse_toon;

uniform vec4 deep_color : source_color = vec4(0.08, 0.31, 0.49, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.35, 0.78, 0.82, 1.0);
uniform vec4 foam_color : source_color = vec4(0.94, 0.99, 1.0, 1.0);
uniform vec4 sky_tint : source_color = vec4(0.62, 0.82, 1.0, 1.0);
uniform vec3 underwater_color : source_color = vec3(0.025, 0.10, 0.19);
uniform sampler2D flow_noise : filter_linear_mipmap, repeat_enable;
uniform float wave_speed : hint_range(0.0, 4.0) = 0.55;
uniform float wave_scale : hint_range(0.5, 40.0) = 9.0;
uniform float sun_glow : hint_range(0.0, 2.0) = 0.30;
uniform float crest_strength : hint_range(0.0, 0.8) = 0.22;
uniform float shore_foam_strength : hint_range(0.0, 1.0) = 0.52;
uniform vec3 sun_dir = vec3(-0.4, 0.8, 0.3);

varying vec3 v_world;
varying float v_depth;
varying float v_ocean;

float wave(vec2 p, float t) {
	return sin(p.x * 1.0 + t) * 0.48
		+ sin(p.y * 0.83 - t * 0.7) * 0.30
		+ sin((p.x + p.y) * 0.57 + t * 0.35) * 0.22;
}

void vertex() {
	vec3 world_before_wave = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float noise = textureLod(flow_noise, world_before_wave.xz * 0.014
		+ vec2(TIME * 0.006, -TIME * 0.004), 0.0).r;
	vec2 p = world_before_wave.xz * (wave_scale / 75.0);
	v_ocean = UV2.y;
	float amplitude = mix(0.035, 0.11, v_ocean);
	VERTEX.y += wave(p, TIME * wave_speed + (noise - 0.5) * 0.5) * amplitude;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_depth = UV2.x;
}

void fragment() {
	float depth = clamp(v_depth / 8.0, 0.0, 1.0);
	float shore = 1.0 - smoothstep(0.02, 0.85, v_depth);
	float t = TIME * wave_speed;
	vec2 p = v_world.xz * (wave_scale / 75.0);
	float broad_noise = texture(flow_noise, v_world.xz * 0.014
		+ vec2(TIME * 0.006, -TIME * 0.004)).r;
	float detail_noise = texture(flow_noise, v_world.xz * 0.054
		+ vec2(-TIME * 0.012, TIME * 0.009)).r;
	float w = wave(p, t + (broad_noise - 0.5) * 0.7) * 0.5 + 0.5;
	w = clamp(w + (detail_noise - 0.5) * 0.16, 0.0, 1.0);

	vec3 col = mix(shallow_color.rgb, deep_color.rgb, depth * 0.94);
	float wave_band = smoothstep(0.58, 0.82, w) * 0.11;
	col = mix(col, sky_tint.rgb, wave_band);
	float crest = smoothstep(0.76, 0.94, w) * crest_strength;
	float foam = max(crest * 0.55, shore * (0.24 + crest) * shore_foam_strength);
	col = mix(col, foam_color.rgb, clamp(foam, 0.0, 0.68));

	vec3 n = normalize(NORMAL + vec3((w - 0.5) * 0.18, 0.0, (0.5 - w) * 0.18));
	float glint = pow(max(dot(reflect(-VIEW, n), normalize(sun_dir)), 0.0), 180.0);
	col += sky_tint.rgb * glint * sun_glow;

	// De baixo, a face da água continua visível como teto azul escuro. A névoa
	// do mundo completa a profundidade sem deixar o leito transparente através da água.
	float underwater = step(CAMERA_POSITION_WORLD.y + 0.06, v_world.y);
	vec3 submerged = mix(underwater_color, shallow_color.rgb * 0.54, 1.0 - depth);
	submerged = mix(submerged, foam_color.rgb * 0.38, crest * 0.16);
	col = mix(col, submerged, underwater);

	ALBEDO = col;
	ROUGHNESS = mix(0.42, 0.68, underwater);
	SPECULAR = mix(0.34, 0.08, underwater);
}
