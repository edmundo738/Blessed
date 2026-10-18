extends SceneTree
func _initialize() -> void:
	var started := Time.get_ticks_msec()
	var ter := Terrain.new(20260109)
	print("WFC_REGION solved=", ter.region_grammar.solved,
		" attempts=", ter.region_grammar.solve_attempts,
		" contradictions=", ter.region_grammar.contradiction_count,
		" cells=", ter.region_grammar.tiles.size())
	var counts := PackedInt32Array()
	counts.resize(RegionGrammar.TYPE_COUNT)
	for tile in ter.region_grammar.tiles:
		counts[tile] += 1
	print("WFC_COUNTS ", counts)
	print("WATER ", ter.water.stats())
	var gen = load("res://scripts/world/voxel_generator.gd").new()
	gen.configure(ter)
	var buffer := VoxelBuffer.new()
	buffer.create(16, 16, 16)
	gen._generate_block(buffer, Vector3i(80, -8, -16), 0)
	var sdf_channel := VoxelBuffer.CHANNEL_SDF
	print("VOXEL sample sdf=", buffer.get_voxel_f(8, 8, 8, sdf_channel),
		" surface=", ter.height(88.0, -8.0),
		" indices=", buffer.get_voxel(8, 12, 8, VoxelBuffer.CHANNEL_INDICES),
		" weights=", buffer.get_voxel(8, 12, 8, VoxelBuffer.CHANNEL_WEIGHTS))
	print("PROBE_MS ", Time.get_ticks_msec() - started)
	quit()

