shader_type spatial;
// Água estilizada: bandas de cor, espuma na margem e reflexo falso do céu.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon;

uniform vec4 deep_color : source_color = vec4(0.10, 0.36, 0.52, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.34, 0.78, 0.82, 1.0);
uniform vec4 foam_color : source_color = vec4(0.94, 0.98, 1.00, 1.0);
uniform vec4 sky_tint : source_color = vec4(0.62, 0.82, 1.00, 1.0);
uniform float depth_range : hint_range(0.1, 12.0) = 3.0;
uniform float foam_width : hint_range(0.05, 3.0) = 0.85;
uniform float wave_speed : hint_range(0.0, 4.0) = 0.55;
uniform float wave_scale : hint_range(0.5, 40.0) = 9.0;
uniform float alpha : hint_range(0.0, 1.0) = 0.86;
uniform float sun_glow : hint_range(0.0, 2.0) = 0.6;
uniform vec3 sun_dir = vec3(-0.4, 0.8, 0.3);
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

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
	// profundidade real -> margens claras
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	up.xyz /= up.w;
	float water_depth = clamp((VIEW_MATRIX[3].y - up.y) - VERTEX.z, 0.0, 20.0);

	float k = clamp(water_depth / depth_range, 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, k);

	// bandas de onda (o "traço" do desenho)
	float t = TIME * wave_speed;
	vec2 p = v_world.xz * wave_scale * 0.1;
	float w = wave(p, t) * 0.5 + 0.5;
	w = floor(w * 4.0) / 4.0;
	col = mix(col, col * 1.22 + vec3(0.05), w * 0.5);

	// espuma onde a água acaba
	float shore = 1.0 - smoothstep(0.0, foam_width, water_depth);
	float sparkle = step(0.72, fract(sin(dot(floor(v_world.xz * 6.0), vec2(12.9898, 78.233))) * 43758.5453));
	col = mix(col, foam_color.rgb, clamp(shore * (0.55 + 0.45 * sparkle), 0.0, 1.0));

	// reflexo falso: brilho onde a normal aponta ao sol
	vec3 n = normalize(NORMAL + vec3(w * 0.12, 0.0, (1.0 - w) * 0.12));
	float glow = pow(max(dot(reflect(-VIEW, n), sun_dir), 0.0), 18.0);
	col += sky_tint.rgb * glow * sun_glow;

	ALBEDO = col;
	ALPHA = alpha;
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
}
