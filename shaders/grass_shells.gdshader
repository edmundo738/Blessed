shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_toon;

// Conchas opacas sobre a superfície real do terreno. A forma das folhas é
// reconstruída por célula no fragmento; cada camada sobe a secção e afina as
// lâminas. Não há transparência alfa nem um nó por folha.
uniform float wind_strength : hint_range(0.0, 1.0) = 0.34;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.15;
uniform float blade_cells_per_meter : hint_range(4.0, 14.0) = 9.2;
uniform vec4 meadow_base : source_color = vec4(0.18, 0.39, 0.15, 1.0);
uniform vec4 meadow_light : source_color = vec4(0.40, 0.66, 0.24, 1.0);
uniform vec4 dry_base : source_color = vec4(0.48, 0.43, 0.16, 1.0);
uniform vec4 dry_light : source_color = vec4(0.78, 0.66, 0.27, 1.0);

varying vec3 world_pos;
varying float shell_level;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	shell_level = UV2.x;
	float gust = sin(world_pos.x * 0.047 + world_pos.z * 0.031 + TIME * wind_speed);
	float breeze = sin(world_pos.x * 0.019 - world_pos.z * 0.026 - TIME * wind_speed * 0.63);
	float bend = shell_level * shell_level * wind_strength * (gust * 0.72 + breeze * 0.28);
	VERTEX.x += bend * 0.72;
	VERTEX.z += bend * 0.43;
}

void fragment() {
	vec2 blade_cell = floor(world_pos.xz * blade_cells_per_meter);
	vec2 local = fract(world_pos.xz * blade_cells_per_meter);
	float blade_seed = hash21(blade_cell + vec2(17.13, 91.7));
	float blade_present = step(blade_seed, COLOR.r);
	float angle = hash21(blade_cell + vec2(47.2, 12.8)) * 6.2831853;
	vec2 direction = vec2(cos(angle), sin(angle));
	vec2 across_axis = vec2(-direction.y, direction.x);
	vec2 center = vec2(hash21(blade_cell + vec2(7.3, 2.1)),
	hash21(blade_cell + vec2(29.7, 63.4))) * 0.28 + vec2(0.36);
	float blade_length = mix(0.56, 0.86, hash21(blade_cell + vec2(11.8, 52.2)));
	float blade_height = mix(0.27, 0.49, hash21(blade_cell + vec2(83.1, 6.4)));
	float physical_height = shell_level * 0.36;
	float vertical = clamp(physical_height / blade_height, 0.0, 1.0);
	vec2 local_leaf = local - center - direction * vertical * 0.14;
	float along = dot(local_leaf, direction);
	float across = abs(dot(local_leaf, across_axis));
	float along_t = clamp(along / blade_length, 0.0, 1.0);
	float half_width = mix(0.115, 0.014, along_t) * (1.0 - vertical * 0.58) + 0.004;
	float blade_shape = step(0.0, along) * step(along, blade_length)
		* step(across, half_width) * step(physical_height, blade_height);

	// Desaparecimento por dither de células: sem faixa de popping no alcance do LOD.
	float distance_to_camera = distance(CAMERA_POSITION_WORLD, world_pos);
	float distance_fade = 1.0 - smoothstep(88.0, 126.0, distance_to_camera);
	float fade_noise = hash21(blade_cell + vec2(101.7, 37.9));
	float keep_blade = step(fade_noise, distance_fade);
	float mask = blade_shape * blade_present * keep_blade;
	ALPHA = mask;
	ALPHA_SCISSOR_THRESHOLD = 0.5;

	float variation = hash21(blade_cell + vec2(9.2, 144.5));
	vec3 lush = mix(meadow_base.rgb, meadow_light.rgb, variation * 0.82 + vertical * 0.18);
	vec3 dry = mix(dry_base.rgb, dry_light.rgb, variation * 0.78 + vertical * 0.22);
	float shade = mix(0.72, 1.08, shell_level);
	ALBEDO = mix(lush, dry, clamp(COLOR.g, 0.0, 1.0)) * shade;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
