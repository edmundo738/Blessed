extends SceneTree
func _initialize() -> void:
	print("VoxelBuffer class ", ClassDB.class_exists("VoxelBuffer"))
	if ClassDB.class_exists("VoxelBuffer"):
		for c in ClassDB.class_get_integer_constant_list("VoxelBuffer"):
			if str(c).contains("CHANNEL"):
				print("CONST ", c, "=", ClassDB.class_get_integer_constant("VoxelBuffer", c))
	print("SDF=", VoxelBuffer.CHANNEL_SDF, " INDICES=", VoxelBuffer.CHANNEL_INDICES,
		" WEIGHTS=", VoxelBuffer.CHANNEL_WEIGHTS)
	quit()

