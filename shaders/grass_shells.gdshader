shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Volumetric shells stay attached to the terrain. Two broad, tapered blades
// are sampled in each cell; their color comes from the same atlas as the near
// cards, so the near/mid transition shares one palette.
uniform sampler2D grass_texture : source_color, filter_linear_mipmap;
uniform sampler2D wind_noise : filter_linear_mipmap, repeat_enable;
uniform vec2 wind_direction = vec2(0.82, 0.57);
uniform float wind_strength : hint_range(0.0, 1.0) = 0.34;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.15;
uniform float blade_cells_per_meter : hint_range(4.0, 14.0) = 8.2;
uniform float shell_height = 0.36;

varying vec3 world_pos;
varying float shell_level;
varying float coverage;
varying float dryness;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float blade_mask(vec2 local, vec2 cell, float height, float seed_offset) {
	float seed = hash21(cell + vec2(seed_offset, seed_offset * 1.73));
	float angle = hash21(cell + vec2(seed_offset * 2.61, 37.8)) * 6.2831853;
	vec2 direction = vec2(cos(angle), sin(angle));
	vec2 across_axis = vec2(-direction.y, direction.x);
	vec2 center = vec2(
		hash21(cell + vec2(seed_offset * 3.3, 4.7)),
		hash21(cell + vec2(17.4, seed_offset * 2.9))) * 0.82 + vec2(0.09);
	float blade_length = mix(0.94, 1.24,
		hash21(cell + vec2(seed_offset * 4.1, 52.2)));
	float blade_height = mix(0.28, 0.50,
		hash21(cell + vec2(83.1, seed_offset * 1.9)));
	float vertical = clamp(height / blade_height, 0.0, 1.0);
	vec2 leaf = local - center - direction * vertical * 0.12;
	float along = dot(leaf, direction);
	float across = abs(dot(leaf, across_axis));
	float along_t = clamp(along / blade_length, 0.0, 1.0);
	float half_width = mix(0.34, 0.035, along_t) * (1.0 - vertical * 0.50) + 0.008;
	float shape = step(0.0, along) * step(along, blade_length)
		* step(across, half_width) * step(height, blade_height);
	return shape * step(seed, coverage);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	shell_level = UV2.x;
	coverage = COLOR.r;
	dryness = COLOR.g;
	vec2 noise_uv = world_pos.xz * 0.026
		+ wind_direction * TIME * wind_speed * 0.012;
	float gust = textureLod(wind_noise, noise_uv, 0.0).r;
	float breeze = sin(world_pos.x * 0.019 - world_pos.z * 0.026
		- TIME * wind_speed * 0.55);
	float bend = shell_level * shell_level * wind_strength
		* ((gust - 0.5) * 1.55 + breeze * 0.20);
	VERTEX.x += bend * wind_direction.x;
	VERTEX.z += bend * wind_direction.y;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 scaled = world_pos.xz * blade_cells_per_meter;
	vec2 cell = floor(scaled);
	vec2 local = fract(scaled);
	float physical_height = shell_level * shell_height;
	float first = blade_mask(local, cell, physical_height, 17.13);
	float second = blade_mask(local, cell, physical_height, 53.71);
	float blade_shape = max(first, second);

	float distance_to_camera = distance(CAMERA_POSITION_WORLD, world_pos);
	float distance_fade = 1.0 - smoothstep(84.0, 122.0, distance_to_camera);
	float fade_noise = hash21(cell + vec2(101.7, 37.9));
	float mask = blade_shape * step(fade_noise, distance_fade);
	if (mask < 0.5) {
		discard;
	}

	float vertical = clamp(physical_height / 0.50, 0.0, 1.0);
	float variation = hash21(cell + vec2(9.2, 144.5));
	float green_strip = mix(0.081, 0.191, variation);
	float dry_strip = mix(0.027, 0.136, variation);
	vec3 lush = textureLod(grass_texture,
		vec2(green_strip, 1.0 - vertical), 0.0).rgb;
	vec3 dry = textureLod(grass_texture,
		vec2(dry_strip, 1.0 - vertical), 0.0).rgb;
	vec3 color = mix(lush, dry, clamp(dryness, 0.0, 1.0));
	ALBEDO = color * mix(0.78, 1.08, shell_level);
	ROUGHNESS = 0.96;
	SPECULAR = 0.02;
}

void light() {
	// Lume local contínuo; somente a luz direcional mantém as bandas suaves.
	if (!LIGHT_IS_DIRECTIONAL) {
		float local_diffuse = max(dot(NORMAL, LIGHT), 0.0);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * local_diffuse
			* clamp(ATTENUATION, 0.0, 1.0);
	} else {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	float band = mix(floor(ndl * 3.0) / 3.0, ndl, 0.56);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * mix(0.48, 1.0, band);
	}
}
