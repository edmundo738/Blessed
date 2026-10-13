extends Area3D
## Item largado no mundo — fica no chão e o jogador apanha-o ao chegar perto.
## (Antes o "largar" destruía o item; agora há consequência recuperável.)
var item_id := ""
var amount := 1
var inv: Node
var player_ref: Node
var _t := 0.0


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.28, 0.28, 0.28)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.75, 0.5)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.7
	cs.shape = sh
	add_child(cs)
	monitorable = false
	body_entered.connect(_on_body)


func _process(delta: float) -> void:
	_t += delta
	rotation.y += delta * 1.5


func _on_body(body: Node) -> void:
	# pequeno atraso para não re-apanhar no mesmo instante em que larga
	if _t < 0.5 or inv == null or item_id == "":
		return
	if body == player_ref:
		inv.add(item_id, amount)
		Sfx.play("pick", -10.0, 1.1)
		queue_free()
