class_name BlessedBlenderAssets
extends RefCounted
## Loads authored Blender GLBs if present. Code-generated meshes remain the
## fallback if a model is absent or fails to import.

const RUNTIME_DIR := "res://content/models/runtime/"
const QUATERNIUS_DIR := "res://content/models/runtime/quaternius/"
const QUATERNIUS_IDS := [
	"tree_oak", "tree_birch", "tree_willow", "tree_sakura", "tree_pine",
	"plant_bush", "plant_berry_bush", "plant_mushroom", "rock_cluster",
	"grass_clump", "fern_clump", "flower_clump", "clover_clump", "reed_clump",
]
static var _mesh_cache: Dictionary = {}


static func path_for(asset_id: String) -> String:
	var base_id := asset_id
	var lod_suffix := ""
	for level in [1, 2]:
		var suffix := "_lod%d" % level
		if base_id.ends_with(suffix):
			base_id = base_id.trim_suffix(suffix)
			lod_suffix = suffix
			break
	if base_id in QUATERNIUS_IDS:
		return QUATERNIUS_DIR + base_id + lod_suffix + ".gltf"
	return RUNTIME_DIR + asset_id + ".glb"


static func has_asset(asset_id: String) -> bool:
	return ResourceLoader.exists(path_for(asset_id))


static func scene_for(asset_id: String) -> PackedScene:
	var path := path_for(asset_id)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene


static func mesh_for(asset_id: String) -> ArrayMesh:
	if _mesh_cache.has(asset_id):
		return _mesh_cache[asset_id] as ArrayMesh
	var packed := scene_for(asset_id)
	if packed == null:
		return null
	var root := packed.instantiate()
	var mesh_node := _first_mesh(root)
	var result: ArrayMesh = mesh_node.mesh as ArrayMesh if mesh_node != null else null
	root.free()
	if result != null:
		_mesh_cache[asset_id] = result
	return result


static func lods_for(asset_id: String) -> Array[ArrayMesh]:
	var result: Array[ArrayMesh] = []
	var base := mesh_for(asset_id)
	if base == null:
		return result
	result.append(base)
	for level in range(1, 3):
		var mesh := mesh_for("%s_lod%d" % [asset_id, level])
		result.append(mesh if mesh != null else base)
	return result


static func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is ArrayMesh:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null
