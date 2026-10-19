shader_type spatial;
// Relva geométrica instanciada: poucas lâminas, vento analítico e iluminação
// estilizada. Este shader não escreve ALPHA para ficar no passe opaco.
render_mode cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform bool use_texture = false;
uniform vec4 shadow_tint : source_color = vec4(0.45, 0.50, 0.82, 1.0);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float bands : hint_range(1.0, 8.0) = 3.0;
uniform float band_soft : hint_range(0.0, 1.0) = 0.48;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.42;
uniform float ambient_gain : hint_range(0.0, 2.0) = 0.74;
uniform float wind_strength : hint_range(0.0, 1.0) = 0.22;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.6;
uniform float wind_height = 0.75;

varying vec2 v_uv;
varying vec3 v_color;
varying vec3 v_tint;
varying float v_height;
varying float v_layer;
varying float v_fade;

void vertex() {
	v_uv = UV;
	v_color = COLOR.rgb;
	v_tint = mix(vec3(1.0), INSTANCE_CUSTOM.rgb, 0.20);
	v_layer = clamp(COLOR.a, 0.0, 1.0);
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = clamp(VERTEX.y / max(wind_height, 0.001), 0.0, 1.0);
	v_height = h;
	float phase = dot(origin.xz, vec2(0.11, 0.073)) + TIME * wind_speed;
	float gust = sin(dot(origin.xz, vec2(-0.037, 0.052)) - TIME * wind_speed * 0.61);
	float sway = (sin(phase) + gust * 0.32) * wind_strength * h * h;
	VERTEX.x += sway * 0.82;
	VERTEX.z += sway * 0.57;

	float fade_from = INSTANCE_CUSTOM.a;
	if (fade_from > 0.0) {
		float d = distance(origin, INV_VIEW_MATRIX[3].xyz);
		v_fade = 1.0 - smoothstep(fade_from, fade_from * 1.35, d);
		VERTEX *= v_fade;
	} else {
		v_fade = 1.0;
	}
}

void fragment() {
	vec4 texel = vec4(1.0);
	if (use_texture) {
		texel = texture(albedo_texture, v_uv) * albedo_tint;
	}
	// Os tufos procedurais já têm silhueta triangular na própria malha.
	// A cor alfa do vértice guarda a camada e dá variação sem duplicar overdraw.
	ALBEDO = (use_texture ? texel.rgb : vec3(1.0)) * v_color * v_tint;
	ALBEDO *= mix(0.58, 0.98, v_height) * mix(1.0, 0.88, v_layer);
	ROUGHNESS = 0.82;
	SPECULAR = 0.12;
}

void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		float local_diffuse = max(dot(NORMAL, LIGHT), 0.0);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * local_diffuse
			* clamp(ATTENUATION, 0.0, 1.0) * v_fade;
	} else {
	float ndl = dot(NORMAL, LIGHT);
	float lit = ndl * 0.5 + 0.5;
	float band = floor(lit * bands) / bands;
	band = mix(band, lit, band_soft);
	vec3 base = ALBEDO;
	vec3 col = mix(base * shadow_tint.rgb, base, clamp(band * 1.1, 0.0, 1.0));
	col = mix(col * shadow_tint.rgb, col, clamp(ATTENUATION, 0.0, 1.0));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	col += LIGHT_COLOR * rim * rim_strength * (0.35 + band);
	DIFFUSE_LIGHT += col * LIGHT_COLOR * ambient_gain * v_fade;
	}
}
