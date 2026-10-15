shader_type spatial;
// Alpha cards para folhas: mantém a máscara, anima a copa e usa prepass de
// profundidade para que as camadas visíveis não redesenhem o interior todo.
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.42;
uniform vec4 shadow_tint : source_color = vec4(0.45, 0.50, 0.82, 1.0);
uniform float bands : hint_range(1.0, 8.0) = 3.0;
uniform float band_soft : hint_range(0.0, 1.0) = 0.48;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.36;
uniform float ambient_gain : hint_range(0.0, 2.0) = 0.78;
uniform float wind_strength : hint_range(0.0, 1.0) = 0.12;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.1;
uniform float wind_height = 6.0;

varying vec3 v_color;
varying vec3 v_tint;
varying float v_height;

void vertex() {
	v_color = COLOR.rgb;
	v_tint = mix(vec3(1.0), INSTANCE_CUSTOM.rgb, 0.20);
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float height_factor = clamp(VERTEX.y / max(wind_height, 0.1), 0.0, 1.0);
	v_height = height_factor;
	float phase = dot(origin.xz, vec2(0.11, 0.073)) + TIME * wind_speed;
	float gust = sin(dot(origin.xz, vec2(-0.037, 0.052)) - TIME * wind_speed * 0.61);
	float sway = (sin(phase) + gust * 0.30) * wind_strength * height_factor * height_factor;
	VERTEX.x += sway * 0.72;
	VERTEX.z += sway * 0.50;
}

void fragment() {
	vec4 texel = texture(albedo_texture, UV) * albedo_tint;
	// Máscara binária: sem blending semitransparente nas bordas das folhas.
	float covered = step(alpha_cutoff, texel.a);
	ALBEDO = texel.rgb * v_color * v_tint * mix(0.62, 1.04, v_height);
	ALPHA = covered;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.84;
	SPECULAR = 0.12;
}

void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		float local_diffuse = max(dot(NORMAL, LIGHT), 0.0);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * local_diffuse
			* clamp(ATTENUATION, 0.0, 1.0);
	} else {
	float ndl = dot(NORMAL, LIGHT);
	float lit = ndl * 0.5 + 0.5;
	float band = floor(lit * bands) / bands;
	band = mix(band, lit, band_soft);
	vec3 col = mix(ALBEDO * shadow_tint.rgb, ALBEDO, clamp(band * 1.1, 0.0, 1.0));
	col = mix(col * shadow_tint.rgb, col, clamp(ATTENUATION, 0.0, 1.0));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	col += LIGHT_COLOR * rim * rim_strength * (0.35 + band);
	DIFFUSE_LIGHT += col * LIGHT_COLOR * ambient_gain;
	}
}
