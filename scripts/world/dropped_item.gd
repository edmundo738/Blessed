class_name DroppedItem
extends RigidBody3D
## Recurso largado: cai e assenta pela física do mundo; recolhe por contacto.

var item_id := ""
var amount := 1
var inv: Node
var player_ref: Node
var launch_direction := Vector3.ZERO

var _age := 0.0
var _attempt_t := 0.0
var _full_notice_sent := false
var _label: Label3D

const PICKUP_DISTANCE := 1.08
const MAX_PICKUP_HEIGHT := 1.75


func _ready() -> void:
	name = "WorldPickup_" + item_id
	collision_layer = 0
	collision_mask = 1
	mass = 0.55
	linear_damp = 0.82
	angular_damp = 2.2
	can_sleep = true
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = 0.88
	physics_material.bounce = 0.08
	physics_material_override = physics_material
	if is_instance_valid(player_ref) and player_ref is PhysicsBody3D:
		add_collision_exception_with(player_ref as PhysicsBody3D)
	var visual := Node3D.new()
	visual.name = "Display"
	add_child(visual)
	var authored := _authored_model()
	if authored != null:
		visual.scale = Vector3.ONE * (0.36 if item_id == "wood" else 0.48)
		visual.add_child(authored)
	else:
		var mi := MeshInstance3D.new()
		mi.name = "ItemMesh"
		mi.mesh = _item_mesh()
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.9
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.22
	cs.shape = sh
	add_child(cs)
	_label = Label3D.new()
	_label.name = "StackLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 15
	_label.outline_size = 3
	_label.modulate = Color("fff1d1")
	_label.position = Vector3(0.0, 0.28, 0.0)
	_label.visible = amount > 1
	_label.text = "%s ×%d" % [Db.item_name(item_id), amount]
	_label.visibility_range_end = 12.0
	visual.add_child(_label)
	if launch_direction.length_squared() < 0.01:
		launch_direction = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	linear_velocity = launch_direction.normalized() * randf_range(1.3, 2.3) + Vector3.UP * randf_range(1.6, 2.4)
	angular_velocity = Vector3(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5), randf_range(-2.5, 2.5))


func _authored_model() -> Node3D:
	var asset_id := ""
	match item_id:
		"wood": asset_id = "pickup_log"
		"leaf": asset_id = "pickup_leaf"
	if asset_id.is_empty():
		return null
	var packed := BlessedBlenderAssets.scene_for(asset_id)
	if packed == null:
		return null
	var model := packed.instantiate() as Node3D
	if model != null:
		model.name = "BlenderPickup_" + item_id
	return model


func _physics_process(delta: float) -> void:
	_age += delta
	_attempt_t = maxf(0.0, _attempt_t - delta)
	if _age < 0.32 or _attempt_t > 0.0 or not is_instance_valid(player_ref):
		return
	var player_node := player_ref as Node3D
	var horizontal := Vector2(global_position.x - player_node.global_position.x,
		global_position.z - player_node.global_position.z).length()
	if horizontal <= PICKUP_DISTANCE \
		and absf(global_position.y - player_node.global_position.y) <= MAX_PICKUP_HEIGHT:
		_try_pickup()


func _try_pickup() -> void:
	if inv == null or item_id.is_empty() or amount <= 0:
		return
	_attempt_t = 0.65
	var before := amount
	amount = int(inv.call("add", item_id, amount))
	var collected := before - amount
	if collected > 0:
		Game.bump("item_" + item_id, collected)
		Sfx.play("pick", -9.0, randf_range(0.94, 1.08))
	if amount <= 0:
		queue_free()
		return
	if is_instance_valid(_label):
		_label.text = "%s ×%d" % [Db.item_name(item_id), amount]
		_label.visible = amount > 1
	if collected == 0 and not _full_notice_sent:
		_full_notice_sent = true
		Bus.say("msg.bag_full", 2.0)


func _item_mesh() -> ArrayMesh:
	match item_id:
		"wood":
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([item_id, amount, get_instance_id()])
			return MeshKit.tapered(rng, 0.46, 0.105, 0.09, 9, 2, 0.08, true, Color("a97542"))
		"stick", "fiber":
			return MeshKit.box(Vector3(0.09, 0.32, 0.09), Color("a98b61"))
		"leaf":
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([item_id, amount, get_instance_id()])
			return MeshKit.blob(rng, 0.19, 1, 0.2, Vector3(1.0, 0.28, 0.65), Color("72b95c"))
		"stone", "flint":
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([item_id, amount, get_instance_id()])
			return MeshKit.rock(rng, 0.26)
		"torch":
			return MeshKit.box(Vector3(0.11, 0.30, 0.11), Color("df8c43"))
		_:
			return MeshKit.box(Vector3(0.22, 0.22, 0.22), Color("d5bc86"))
