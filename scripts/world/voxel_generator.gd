extends VoxelGeneratorScript
## Campo SDF nativo para o backend Transvoxel.
##
## A altura-base e a hidrologia são lidas da mesma Terrain usada por água,
## vegetação, fauna e gameplay. Depois de configurado, o objeto é imutável:
## `_generate_block` pode ser chamado pelas threads de geração do Voxel Tools.

const CHANNEL_SDF := VoxelBuffer.CHANNEL_SDF
const CHANNEL_INDICES := VoxelBuffer.CHANNEL_INDICES
const CHANNEL_WEIGHTS := VoxelBuffer.CHANNEL_WEIGHTS
const CAVE_MIN_DEPTH := 9.0
const CAVE_MAX_DEPTH := 52.0

var terrain: Terrain
var _cave_a: FastNoiseLite
var _cave_b: FastNoiseLite


func configure(p_terrain: Terrain) -> void:
	terrain = p_terrain
	_cave_a = _make_noise(terrain.seed_value + 1801, 0.037, 3)
	_cave_b = _make_noise(terrain.seed_value + 1802, 0.041, 3)


func _make_noise(noise_seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	noise.fractal_gain = 0.5
	noise.fractal_lacunarity = 2.0
	return noise


func _get_used_channels_mask() -> int:
	return (1 << CHANNEL_SDF) | (1 << CHANNEL_INDICES) | (1 << CHANNEL_WEIGHTS)


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	if terrain == null:
		out_buffer.fill_f(100.0, CHANNEL_SDF)
		return
	# Mixel4 pede quatro índices únicos e pesos que somem a 15. Define o
	# material neutro no interior; só a faixa perto de superfícies é substituída.
	out_buffer.fill(0x3210, CHANNEL_INDICES)
	out_buffer.fill(0x0001, CHANNEL_WEIGHTS)
	var size: Vector3i = out_buffer.get_size()
	var lod_step := 1 << lod
	var biome_weights := PackedFloat32Array()
	biome_weights.resize(Terrain.BIOME_COUNT)
	var region_weights := PackedFloat32Array()
	region_weights.resize(RegionGrammar.TYPE_COUNT)
	var material_indices := PackedInt32Array()
	material_indices.resize(4)
	var material_weights := PackedInt32Array()
	material_weights.resize(4)
	var material_band := maxf(3.0, float(lod_step) * 3.0)

	for z in size.z:
		var world_z := float(origin_in_voxels.z + (z << lod))
		for x in size.x:
			var world_x := float(origin_in_voxels.x + (x << lod))
			var surface_y := terrain.height(world_x, world_z)
			# O material-base vem dos mesmos pesos do terreno desenhado no fallback.
			# A normal da malha adiciona a exposição rochosa no shader para paredões.
			terrain.biome_weights_s(world_x, world_z, surface_y, 0.0, biome_weights,
				region_weights)
			_pack_materials(biome_weights, material_indices, material_weights)
			var packed_indices := _pack_nibbles(material_indices)
			var packed_weights := _pack_nibbles(material_weights)
			var cave_strength := terrain.geology.cave_potential_at(world_x, world_z)
			for y in size.y:
				var world_y := float(origin_in_voxels.y + (y << lod))
				var sdf := world_y - surface_y
				var depth := surface_y - world_y
				var write_material := absf(sdf) <= material_band
				if depth > CAVE_MIN_DEPTH and depth < CAVE_MAX_DEPTH and cave_strength > 0.42:
					var n1 := absf(_cave_a.get_noise_3d(world_x, world_y, world_z))
					var n2 := absf(_cave_b.get_noise_3d(world_x + 83.0, world_y - 41.0,
						world_z + 29.0))
					var tube_sdf := maxf(n1, n2) * 15.0 - lerpf(1.7, 2.8, cave_strength)
					var vertical_sdf := maxf(CAVE_MIN_DEPTH - depth, depth - CAVE_MAX_DEPTH)
					var cave_sdf := maxf(tube_sdf, vertical_sdf)
					# Diferença SDF: remove os espaços de caverna da massa de rocha.
					sdf = maxf(sdf, -cave_sdf)
					write_material = write_material or absf(cave_sdf) <= material_band
				out_buffer.set_voxel_f(sdf, x, y, z, CHANNEL_SDF)
				# A malha só lê os canais de material junto às superfícies. Manter
				# o formato predefinido no interior reduz chamadas nativas por bloco.
				if write_material:
					out_buffer.set_voxel(packed_indices, x, y, z, CHANNEL_INDICES)
					out_buffer.set_voxel(packed_weights, x, y, z, CHANNEL_WEIGHTS)


func _pack_materials(weights: PackedFloat32Array, ids: PackedInt32Array,
		quantized: PackedInt32Array) -> void:
	var selected_mask := 0
	var total := 0.0
	for slot in 4:
		var id := -1
		var best_weight := -1.0
		for candidate in Terrain.BIOME_COUNT:
			if (selected_mask & (1 << candidate)) != 0:
				continue
			if weights[candidate] > best_weight:
				best_weight = weights[candidate]
				id = candidate
		if id < 0:
			id = 0
		ids[slot] = id
		selected_mask |= 1 << id
		total += maxf(weights[id], 0.0)
	var sum := 0
	for slot in 4:
		var id := ids[slot]
		var q := int(roundf(maxf(weights[id], 0.0) / maxf(total, 0.0001) * 15.0))
		quantized[slot] = clampi(q, 0, 15)
		sum += quantized[slot]
	quantized[0] = clampi(quantized[0] + (15 - sum), 0, 15)


func _pack_nibbles(values: PackedInt32Array) -> int:
	var packed := 0
	for i in 4:
		packed |= (values[i] & 0xF) << (i * 4)
	return packed
