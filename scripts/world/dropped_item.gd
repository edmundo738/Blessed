extends Area3D
## Recurso no mundo: aparece no local da colheita, cai, repousa e só entra na
## mochila depois de o jogador se aproximar e o pickup viajar até ele.

var item_id := ""
var amount := 1
var inv: Node
var player_ref: Node
var launch_direction := Vector3.ZERO

var _age := 0.0
var _spawn_position := Vector3.ZERO
var _ground_y := 0.0
var _spawn_captured := false
var _magnetizing := false
var _attempt_t := 0.0
var _label: Label3D

const FALL_TIME := 0.72
const MAGNET_RADIUS := 2.7
const PICKUP_RADIUS := 0.62


func _ready() -> void:
	name = "WorldPickup_" + item_id
	monitoring = true
	monitorable = false
	var visual := Node3D.new()
	visual.name = "Display"
	add_child(visual)
	var authored := _authored_model()
	if authored != null:
		visual.add_child(authored)
	else:
		var mi := MeshInstance3D.new()
		mi.name = "ItemMesh"
		mi.mesh = _item_mesh()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.9
		mi.material_override = mat
		visual.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.34
	cs.shape = sh
	add_child(cs)
	_label = Label3D.new()
	_label.name = "StackLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 24
	_label.outline_size = 5
	_label.modulate = Color("fff1d1")
	_label.position = Vector3(0.0, 0.42, 0.0)
	_label.text = "%s  ×%d" % [Db.item_name(item_id), amount]
	visual.add_child(_label)
	body_entered.connect(_on_body)


func _authored_model() -> Node3D:
	var asset_id := ""
	match item_id:
		"wood": asset_id = "pickup_log"
		"leaf": asset_id = "pickup_leaf"
		"berry": asset_id = "pickup_berry"
	if asset_id.is_empty():
		return null
	var packed := BlessedBlenderAssets.scene_for(asset_id)
	if packed == null:
		return null
	var model := packed.instantiate() as Node3D
	if model != null:
		model.name = "BlenderPickup_" + item_id
	return model


func _process(delta: float) -> void:
	_age += delta
	_attempt_t -= delta
	if not _spawn_captured:
		_spawn_position = global_position
		var world := get_parent()
		_ground_y = global_position.y - 0.42
		if world != null and world.has_method("ground_height"):
			_ground_y = float(world.call("ground_height", global_position.x, global_position.z))
		_spawn_captured = true
	_animate_drop(delta)
	if _age < 0.4 or not is_instance_valid(player_ref):
		return
	var target := (player_ref as Node3D).global_position + Vector3(0.0, 0.82, 0.0)
	var distance := global_position.distance_to(target)
	if distance <= MAGNET_RADIUS:
		_magnetizing = true
	if not _magnetizing:
		return
	global_position = global_position.lerp(target, 1.0 - exp(-4.2 * delta))
	if distance <= PICKUP_RADIUS and _attempt_t <= 0.0:
		_try_pickup()


func _animate_drop(delta: float) -> void:
	rotation.y += delta * (1.4 if not _magnetizing else 3.0)
	if _age < FALL_TIME:
		var t := clampf(_age / FALL_TIME, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - t, 2.0)
		var horizontal := launch_direction * (0.45 * eased)
		var arc := sin(t * PI) * 0.62
		global_position = _spawn_position + horizontal + Vector3(0.0, arc - 0.42 * eased, 0.0)
	else:
		var hover := 0.035 * sin(_age * 2.2)
		global_position.y = _ground_y + 0.17 + hover


func _on_body(body: Node) -> void:
	if body == player_ref and _age >= 0.4:
		_magnetizing = true


func _try_pickup() -> void:
	if inv == null or item_id.is_empty() or amount <= 0:
		return
	_attempt_t = 0.7
	var before := amount
	amount = int(inv.call("add", item_id, amount))
	var collected := before - amount
	if collected > 0:
		Game.bump("item_" + item_id, collected)
		Bus.ui_message.emit("+%d %s" % [collected, Db.item_name(item_id)], 1.7)
		Sfx.play("pick", -9.0, randf_range(0.94, 1.08))
	if amount <= 0:
		queue_free()
		return
	if is_instance_valid(_label):
		_label.text = "%s  ×%d" % [Db.item_name(item_id), amount]
	if collected == 0:
		_magnetizing = false
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
		"berry":
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([item_id, amount, get_instance_id()])
			return MeshKit.blob(rng, 0.16, 1, 0.12, Vector3.ONE, Color("c83b54"))
		"stone", "flint":
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([item_id, amount, get_instance_id()])
			return MeshKit.rock(rng, 0.26)
		"torch":
			return MeshKit.box(Vector3(0.11, 0.30, 0.11), Color("df8c43"))
		_:
			return MeshKit.box(Vector3(0.22, 0.22, 0.22), Color("d5bc86"))
