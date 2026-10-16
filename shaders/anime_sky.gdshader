shader_type sky;
render_mode use_quarter_res_pass;

// BLESSED sky: three CC0 painted panoramas give the world an illustrated base;
// the sun and moon are rendered from the live day-cycle direction so they remain
// attached to the real lighting instead of floating as a baked bright spot.

uniform sampler2D sky_day : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sky_morning : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sky_night : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_dir = vec3(-0.4, 0.6, 0.3);
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform float dusk_mix : hint_range(0.0, 1.0) = 0.0;
uniform float moon_phase : hint_range(0.0, 1.0) = 0.35;
uniform float cloud_offset : hint_range(0.0, 1.0) = 0.0;

const vec2 BAKED_LUMINARY_UV = vec2(0.915, 0.220);

float wrapped_distance(float a, float b) {
	return abs(fract(a - b + 0.5) - 0.5);
}

float panorama_disk_mask(vec2 uv) {
	vec2 delta = vec2(wrapped_distance(uv.x, BAKED_LUMINARY_UV.x),
		(uv.y - BAKED_LUMINARY_UV.y) * 0.78);
	return 1.0 - smoothstep(0.034, 0.052, length(delta));
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

vec3 erase_baked_luminary(sampler2D panorama, vec2 uv) {
	vec3 color = texture(panorama, uv).rgb;
	// The Kenney panoramas share a clear patch to the right of the baked disk.
	// Borrow that same-height sky through a soft mask, then draw our moving sun/moon.
	vec3 clean_sky = texture(panorama, fract(uv + vec2(0.071, 0.0))).rgb;
	return mix(color, clean_sky, panorama_disk_mask(uv));
}

void sky() {
	if (AT_QUARTER_RES_PASS) {
		// Wind-driven cloud puffs on a separate, slower layer. The two noise scales
		// move at different speeds, creating parallax without animating the starfield.
		vec3 ray = normalize(EYEDIR);
		float above_horizon = smoothstep(-0.02, 0.10, ray.y);
		float upper_fade = 1.0 - smoothstep(0.62, 0.86, ray.y);
		vec2 projected = ray.xz / max(ray.y + 0.24, 0.18);
		vec2 near_wind = vec2(cloud_offset * 13.0, cloud_offset * 1.3);
		vec2 far_wind = vec2(-cloud_offset * 5.0, cloud_offset * 0.45);
		float broad_cloud = value_noise(projected * 0.72 + near_wind);
		float soft_cloud = value_noise(projected * 1.45 + far_wind + 23.0);
		float cloud_shape = broad_cloud * 0.72 + soft_cloud * 0.28;
		float cloud_density = smoothstep(0.58, 0.79, cloud_shape);
		vec3 cloud_tint = mix(vec3(0.075, 0.10, 0.19), vec3(0.88, 0.91, 0.98), daylight);
		cloud_tint = mix(cloud_tint, vec3(0.98, 0.62, 0.49), dusk_mix);
		COLOR = cloud_tint;
		ALPHA = cloud_density * above_horizon * upper_fade * 0.14;
	} else {

		vec2 uv = SKY_COORDS;
		vec3 day = erase_baked_luminary(sky_day, uv);
		vec3 morning = erase_baked_luminary(sky_morning, uv);
		vec3 night = erase_baked_luminary(sky_night, uv);
		vec3 color = mix(night, day, smoothstep(0.025, 0.72, daylight));
		color = mix(color, morning, clamp(dusk_mix, 0.0, 1.0));
		float cloud_alpha = clamp(QUARTER_RES_COLOR.a, 0.0, 0.18);
		color = mix(color, QUARTER_RES_COLOR.rgb, cloud_alpha);

		vec3 ray = normalize(EYEDIR);
		vec3 sun = normalize(sun_dir);
		float sun_dot = clamp(dot(ray, sun), -1.0, 1.0);
		float sun_visible = smoothstep(-0.055, 0.075, sun.y) * daylight * (1.0 - cloud_alpha * 0.70);
		float sun_disk = smoothstep(cos(0.028), cos(0.018), sun_dot);
		float sun_core = exp((sun_dot - 1.0) * 3600.0);
		float sun_halo = exp((sun_dot - 1.0) * 235.0);
		vec3 sun_color = mix(vec3(1.0, 0.89, 0.66), vec3(1.0, 0.49, 0.26), dusk_mix);
		color += sun_color * (sun_disk * 2.2 + sun_core * 0.32 + sun_halo * 0.045) * sun_visible;

		vec3 moon = -sun;
		float moon_dot = clamp(dot(ray, moon), -1.0, 1.0);
		float moon_visible = (1.0 - smoothstep(0.05, 0.42, daylight)) * smoothstep(-0.06, 0.10, moon.y)
			* (1.0 - cloud_alpha * 0.55);
		if (moon_visible > 0.001) {
			vec3 tangent = normalize(cross(moon, vec3(0.0, 1.0, 0.0)));
			vec3 bitangent = normalize(cross(tangent, moon));
			vec2 moon_uv = vec2(dot(ray, tangent), dot(ray, bitangent)) / sin(0.024);
			float radius_sq = dot(moon_uv, moon_uv);
			float moon_disk = 1.0 - smoothstep(0.94, 1.0, radius_sq);
			vec3 normal = vec3(moon_uv, sqrt(max(1.0 - radius_sq, 0.0)));
			float phase_angle = moon_phase * 6.2831853;
			vec3 moon_light = normalize(vec3(sin(phase_angle), 0.12, -cos(phase_angle)));
			float lit_side = smoothstep(-0.12, 0.12, dot(normal, moon_light));
			float crater_a = 1.0 - smoothstep(0.035, 0.075, length(moon_uv - vec2(-0.28, 0.20)));
			float crater_b = 1.0 - smoothstep(0.025, 0.055, length(moon_uv - vec2(0.24, -0.31)));
			float crater_c = 1.0 - smoothstep(0.020, 0.045, length(moon_uv - vec2(0.37, 0.18)));
			float craters = crater_a * 0.18 + crater_b * 0.12 + crater_c * 0.10;
			vec3 moon_color = mix(vec3(0.76, 0.82, 0.96), vec3(0.98, 0.96, 0.86), lit_side);
			moon_color *= 1.0 - craters;
			float moon_halo = exp((moon_dot - 1.0) * 950.0);
			color += moon_color * moon_disk * moon_visible * 1.1;
			color += vec3(0.32, 0.44, 0.78) * moon_halo * moon_visible * 0.07;
		}

		COLOR = color;
	}
}
