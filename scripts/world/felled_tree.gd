class_name FelledTree
extends AnimatableBody3D
## Árvore abatida: continua no mundo como obstáculo e entrega cada toro por F.

var world_owner: Node
var record_key := ""
var species_id := ""
var height := 6.0
var trunk_radius := 0.24
var fall_direction := 1.0
var remaining_logs := 0
var _tree_mesh: MeshInstance3D
var _trunk_collider: CollisionShape3D


func configure(mesh: ArrayMesh, material: Material, local_transform: Transform3D,
		full_height: float, radius: float, logs: int, owner: Node,
		key: String, tree_id: String, direction: float) -> void:
	_tree_mesh = get_node("TreeMesh") as MeshInstance3D
	_trunk_collider = get_node("TrunkCollider") as CollisionShape3D
	_tree_mesh.mesh = mesh
	_tree_mesh.material_override = material
	_tree_mesh.transform = local_transform
	height = maxf(full_height, 1.0)
	trunk_radius = maxf(radius, 0.14)
	remaining_logs = maxi(logs, 1)
	world_owner = owner
	record_key = key
	species_id = tree_id
	fall_direction = direction
	var capsule := CapsuleShape3D.new()
	capsule.radius = trunk_radius
	capsule.height = maxf(height * 0.92, trunk_radius * 2.0)
	_trunk_collider.shape = capsule
	_trunk_collider.position = Vector3(0.0, capsule.height * 0.47, 0.0)
	add_to_group("fellable_logs")


func begin_fall() -> void:
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_parallel(true)
	tween.tween_property(self, "rotation:z", -fall_direction * 1.43, 0.82) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position:x", position.x + fall_direction * 0.22, 0.82) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.finished.connect(func():
		if is_instance_valid(world_owner) and world_owner.has_method("felled_tree_settled"):
			world_owner.call("felled_tree_settled", record_key))


func interaction_target() -> Dictionary:
	if remaining_logs <= 0:
		return {}
	var point := global_position + Vector3(fall_direction * height * 0.42,
		maxf(trunk_radius * 2.2, 0.55), 0.0)
	return {"kind": "felled_tree", "pos": point}


func take_log() -> bool:
	if remaining_logs <= 0:
		return false
	remaining_logs -= 1
	if is_instance_valid(world_owner) and world_owner.has_method("felled_tree_log_taken"):
		world_owner.call("felled_tree_log_taken", record_key, remaining_logs)
	if remaining_logs <= 0:
		_trunk_collider.set_deferred("disabled", true)
		queue_free()
	return true
