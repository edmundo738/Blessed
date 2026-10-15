shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D grass_texture : source_color, filter_linear_mipmap;
uniform sampler2D wind_noise : filter_linear_mipmap, repeat_enable;
uniform vec2 wind_direction = vec2(0.82, 0.57);
uniform float wind_strength : hint_range(0.0, 1.0) = 0.24;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.0;
uniform float wind_scale : hint_range(0.005, 0.2) = 0.035;
uniform float fade_begin : hint_range(0.0, 100.0) = 38.0;
uniform float fade_end : hint_range(0.0, 120.0) = 58.0;

varying vec2 v_uv;
varying vec3 v_color;
varying vec4 v_instance;
varying vec3 v_world;
varying float v_fade;

void vertex() {
	v_uv = UV;
	v_color = COLOR.rgb;
	v_instance = INSTANCE_CUSTOM;
	vec3 instance_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float blade_height = clamp(1.0 - UV.y, 0.0, 1.0);
	vec2 noise_uv = instance_origin.xz * wind_scale
		+ wind_direction * TIME * wind_speed * 0.018;
	float gust = textureLod(wind_noise, noise_uv, 0.0).r;
	float fine_wind = textureLod(wind_noise, noise_uv * 2.7
		+ vec2(0.37, 0.61), 0.0).r;
	float bend = ((gust - 0.5) * 1.5 + (fine_wind - 0.5) * 0.35)
		* wind_strength * blade_height * blade_height;
	vec3 local_wind = (inverse(MODEL_MATRIX)
		* vec4(wind_direction.x, 0.0, wind_direction.y, 0.0)).xyz;
	local_wind = normalize(vec3(local_wind.x, 0.0, local_wind.z));
	VERTEX.xz += local_wind.xz * bend;

	float distance_to_camera = distance(instance_origin, CAMERA_POSITION_WORLD);
	v_fade = 1.0 - smoothstep(fade_begin, fade_end, distance_to_camera);
	VERTEX.y *= v_fade;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float palette = step(0.5, v_uv.x);
	vec3 lush_a = textureLod(grass_texture, vec2(0.081, v_uv.y), 0.0).rgb;
	vec3 lush_b = textureLod(grass_texture, vec2(0.191, v_uv.y), 0.0).rgb;
	vec3 dry_a = textureLod(grass_texture, vec2(0.027, v_uv.y), 0.0).rgb;
	vec3 dry_b = textureLod(grass_texture, vec2(0.136, v_uv.y), 0.0).rgb;
	vec3 lush = mix(lush_a, lush_b, palette);
	vec3 dry = mix(dry_a, dry_b, palette);
	float dryness = clamp(v_instance.r, 0.0, 1.0);
	float variation = clamp(v_instance.g, 0.0, 1.0);
	vec3 palette_color = mix(lush, dry, dryness);
	vec3 biome_tint = mix(vec3(0.78, 1.02, 0.76), vec3(1.08, 0.88, 0.54), dryness);
	float color_variation = mix(0.90, 1.08, variation);
	ALBEDO = palette_color * biome_tint * v_color * color_variation;
	ROUGHNESS = 0.94;
	SPECULAR = 0.04;
}

void light() {
	// A fogueira ilumina as folhas com uma queda contínua; o sol conserva
	// o recorte toon suave da direção principal.
	if (!LIGHT_IS_DIRECTIONAL) {
		float local_diffuse = max(dot(NORMAL, LIGHT), 0.0);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * local_diffuse
			* clamp(ATTENUATION, 0.0, 1.0);
	} else {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	float band = floor(ndl * 3.0) / 3.0;
	band = mix(band, ndl, 0.62);
	vec3 col = ALBEDO * mix(vec3(0.48, 0.55, 0.72), vec3(1.0), band);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	col += LIGHT_COLOR * rim * 0.18 * band;
	DIFFUSE_LIGHT += col * LIGHT_COLOR * v_fade;
	}
}
