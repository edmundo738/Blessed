shader_type spatial;
render_mode diffuse_toon, specular_toon, cull_back, depth_draw_opaque;

uniform vec4 u_biome_palette[12];
uniform float u_triplanar_scale = 0.035;
uniform float u_snowline = 155.0;
uniform float u_surface_variation = 0.035;
uniform int u_transition_mask;

varying vec3 v_world_position;
varying vec3 v_world_normal;
varying vec4 v_material_indices;
varying vec4 v_material_weights;


vec4 decode_8bit_vec4(float encoded) {
	uint packed = floatBitsToUint(encoded);
	return vec4(
		float(packed & 255u),
		float((packed >> 8u) & 255u),
		float((packed >> 16u) & 255u),
		float((packed >> 24u) & 255u)
	);
}


float get_transvoxel_secondary_factor(int idata) {
	int transition_mask = u_transition_mask & 0xff;
	int cell_border_mask = (idata >> 0) & 63;
	int vertex_border_mask = (idata >> 8) & 63;
	int matching_transition = transition_mask & cell_border_mask;
	float factor = float(matching_transition != 0);
	factor *= float((vertex_border_mask & ~transition_mask) == 0);
	return factor;
}


vec3 get_transvoxel_position(vec3 vertex_pos, vec4 fdata) {
	int idata = floatBitsToInt(fdata.a);
	float secondary_factor = get_transvoxel_secondary_factor(idata);
	vec3 pos = mix(vertex_pos, fdata.xyz, secondary_factor);
	int transition_id = (idata >> 16) & 0xff;
	float transition_visible = float(transition_id == 0 || (transition_id & u_transition_mask) != 0);
	return pos * transition_visible;
}


vec3 palette_color(float index) {
	int id = clamp(int(index + 0.5), 0, 11);
	return u_biome_palette[id].rgb;
}


float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(cell, vec3(127.1, 311.7, 74.7))) * 43758.5453);
	float b = fract(sin(dot(cell + vec3(1.0, 0.0, 0.0), vec3(127.1, 311.7, 74.7))) * 43758.5453);
	float c = fract(sin(dot(cell + vec3(0.0, 1.0, 0.0), vec3(127.1, 311.7, 74.7))) * 43758.5453);
	float d = fract(sin(dot(cell + vec3(1.0, 1.0, 0.0), vec3(127.1, 311.7, 74.7))) * 43758.5453);
	float e = fract(sin(dot(cell + vec3(0.0, 0.0, 1.0), vec3(127.1, 311.7, 74.7))) * 43758.5453);
	float f1 = fract(sin(dot(cell + vec3(1.0, 0.0, 1.0), vec3(127.1, 311.7, 74.7))) * 43758.5453);
	float g = fract(sin(dot(cell + vec3(0.0, 1.0, 1.0), vec3(127.1, 311.7, 74.7))) * 43758.5453);
	float h = fract(sin(dot(cell + vec3(1.0, 1.0, 1.0), vec3(127.1, 311.7, 74.7))) * 43758.5453);
	float x0 = mix(a, b, f.x);
	float x1 = mix(c, d, f.x);
	float x2 = mix(e, f1, f.x);
	float x3 = mix(g, h, f.x);
	return mix(mix(x0, x1, f.y), mix(x2, x3, f.y), f.z);
}


void vertex() {
	VERTEX = get_transvoxel_position(VERTEX, CUSTOM0);
	v_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_material_indices = decode_8bit_vec4(CUSTOM1.x);
	v_material_weights = decode_8bit_vec4(CUSTOM1.y) / 255.0;
}


void fragment() {
	vec4 weights = max(v_material_weights, vec4(0.0));
	float weight_sum = max(weights.x + weights.y + weights.z + weights.w, 0.0001);
	weights /= weight_sum;
	vec3 color = palette_color(v_material_indices.x) * weights.x;
	color += palette_color(v_material_indices.y) * weights.y;
	color += palette_color(v_material_indices.z) * weights.z;
	color += palette_color(v_material_indices.w) * weights.w;

	vec3 normal = normalize(v_world_normal);
	float exposed_rock = smoothstep(0.28, 0.82, 1.0 - abs(normal.y));
	color = mix(color, palette_color(4.0), exposed_rock * 0.82);
	float snow = smoothstep(u_snowline, u_snowline + 34.0, v_world_position.y)
		* smoothstep(0.0, 0.35, normal.y);
	color = mix(color, palette_color(5.0), snow * 0.92);

	float grain = value_noise(v_world_position * u_triplanar_scale);
	color *= 1.0 + (grain - 0.5) * u_surface_variation;
	ALBEDO = color;
	ROUGHNESS = 1.0;
}
