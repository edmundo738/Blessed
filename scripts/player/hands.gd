extends Node3D
## Hands — braços e objeto em 1ª pessoa, feitos de caixas e animados à mão.
##
## Não há modelo nem animação importada: o braço é uma caixa afinada, a mão é
## uma caixa pequena, o objeto é a malha da espécie. O "peso" vem de uma mola
## que atrasa o braço em relação à câmara e de um balanço ligado aos passos.

var arm_r: Node3D
var arm_l: Node3D
var held: MeshInstance3D
var _asset_root: Node3D
var rng := RandomNumberGenerator.new()

var swing_t := -1.0
var swing_speed := 1.0
var bob_t := 0.0
var recoil := 0.0


func _ready() -> void:
	rng.seed = 99
	position = Vector3(0.19, -0.24, -0.42)
	arm_r = _make_arm(Color(0.93, 0.78, 0.68), Vector3(0.075, 0.075, 0.42))
	arm_r.position = Vector3(0, 0, 0)
	arm_r.rotation_degrees = Vector3(-8, 6, 0)
	add_child(arm_r)
	arm_l = _make_arm(Color(0.90, 0.75, 0.65), Vector3(0.07, 0.07, 0.38))
	arm_l.position = Vector3(-0.30, -0.02, -0.05)
	arm_l.rotation_degrees = Vector3(-6, -8, 0)
	arm_l.visible = false
	add_child(arm_l)
	held = MeshInstance3D.new()
	held.position = Vector3(0.03, -0.06, -0.44)
	arm_r.add_child(held)


func _make_arm(tint: Color, size: Vector3) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.box(size, tint)
	mi.position = Vector3(0, 0, -size.z * 0.5)
	n.add_child(mi)
	var hand := MeshInstance3D.new()
	hand.mesh = MeshKit.box(Vector3(size.x * 1.15, size.y * 1.1, size.x * 1.2), tint.lightened(0.05))
	hand.position = Vector3(0, 0, -size.z * 1.02)
	n.add_child(hand)
	return n


## Põe na mão a malha do item (ou esvazia).
func set_held(mesh: ArrayMesh, mat: Material = null) -> void:
	held.mesh = mesh
	held.material_override = mat
	held.visible = mesh != null
	arm_l.visible = mesh != null


## Gera uma silhueta clara para o item equipado, visível na 1.ª pessoa.
func set_item(item_id: String) -> void:
	if is_instance_valid(_asset_root):
		_asset_root.queue_free()
	_asset_root = null
	var asset_id := ""
	match item_id:
		"axe": asset_id = "tool_axe"
		"pickaxe": asset_id = "tool_pickaxe"
	var authored := BlessedBlenderAssets.scene_for(asset_id) if not asset_id.is_empty() else null
	if authored != null:
		var model := authored.instantiate() as Node3D
		if model != null:
			_asset_root = model
			_asset_root.name = "BlenderTool_" + item_id
			_asset_root.scale = Vector3.ONE * 0.72
			_asset_root.rotation_degrees = Vector3(0.0, 0.0, -16.0)
			_asset_root.position = Vector3(0.0, -0.12, 0.0)
			held.add_child(_asset_root)
			held.mesh = null
			# MeshInstance visibility hides its whole subtree, including the GLB tool.
			held.visible = true
			arm_l.visible = true
			return
	held.visible = true
	var parts: Array = []
	match item_id:
		"axe":
			parts = [[MeshKit.box(Vector3(0.055, 0.48, 0.055), Color("a97542")),
				Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-28)), Vector3(-0.04, 0.10, 0))],
				[MeshKit.box(Vector3(0.28, 0.16, 0.09), Color("cbd8d5")),
				Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-28)), Vector3(0.08, 0.29, 0))]]
		"pickaxe":
			parts = [[MeshKit.box(Vector3(0.055, 0.48, 0.055), Color("a97542")),
				Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-24)), Vector3(-0.04, 0.10, 0))],
				[MeshKit.box(Vector3(0.34, 0.09, 0.08), Color("cbd8d5")),
				Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-12)), Vector3(0.02, 0.31, 0))]]
		"torch":
			parts = [[MeshKit.box(Vector3(0.08, 0.48, 0.08), Color("8b5b35")),
				Transform3D(Basis.IDENTITY, Vector3(0, 0.08, 0))],
				[MeshKit.blob(rng, 0.13, 1, 0.1, Vector3(0.8, 1.3, 0.8), Color("ff9b40")),
				Transform3D(Basis.IDENTITY, Vector3(0, 0.36, 0))]]
		"rod":
			parts = [[MeshKit.box(Vector3(0.035, 0.68, 0.035), Color("9b693d")),
				Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-22)), Vector3(0, 0.18, 0))]]
		"wood", "stick":
			parts = [[MeshKit.box(Vector3(0.08, 0.38, 0.08), Color("a97542")),
				Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-24)), Vector3(0, 0.12, 0))]]
		"stone", "flint":
			parts = [[MeshKit.blob(rng, 0.16, 1, 0.12, Vector3(1.0, 0.7, 0.8), Color("9ba6a3")),
				Transform3D(Basis.IDENTITY, Vector3(0, 0.12, 0))]]
		"berry", "bush_berry", "mushroom", "meat_raw", "meat_cooked", "fish_raw", "fish_cooked":
			var tint := Color("c84444") if item_id == "berry" or item_id == "bush_berry" else Color("d88472")
			parts = [[MeshKit.blob(rng, 0.16, 1, 0.14, Vector3(1.0, 0.8, 0.85), tint),
				Transform3D(Basis.IDENTITY, Vector3(0, 0.12, 0))]]
		"bottle", "water":
			parts = [[MeshKit.box(Vector3(0.16, 0.32, 0.14), Color("8fcfd0")),
				Transform3D(Basis.IDENTITY, Vector3(0, 0.12, 0))],
				[MeshKit.box(Vector3(0.08, 0.07, 0.08), Color("dbc995")),
				Transform3D(Basis.IDENTITY, Vector3(0, 0.32, 0))]]
		_:
			if item_id.begins_with("meat") or item_id == "stew":
				parts = [[MeshKit.blob(rng, 0.16, 1, 0.1, Vector3(1.0, 0.7, 0.8), Color("b96a48")),
					Transform3D(Basis.IDENTITY, Vector3(0, 0.12, 0))]]
	if parts.is_empty():
		set_held(null)
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		st.append_from(part[0], 0, part[1])
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.82
	set_held(mesh, mat)


func swing(duration: float = 0.34) -> void:
	swing_t = 0.0
	swing_speed = 1.0 / maxf(duration, 0.05)
	recoil = 1.0


func recoil_kick(amount: float = 0.25) -> void:
	recoil = maxf(recoil, amount)


func _process(delta: float) -> void:
	# mola de respiração + balanço dos passos
	bob_t += delta * 1.6
	var breathe := sin(bob_t) * 0.006
	var sway := Vector3(sin(bob_t * 0.8) * 0.008, breathe, cos(bob_t * 0.6) * 0.006)
	if swing_t >= 0.0:
		swing_t += delta * swing_speed
		if swing_t > 1.0:
			swing_t = -1.0
	var s := swing_t
	var arc := 0.0
	if s >= 0.0:
		# curva de balanço: sobe rápido, desce com peso
		arc = sin(clampf(s, 0.0, 1.0) * PI)
	arm_r.position = Vector3(0, 0, 0) + sway + Vector3(0, -arc * 0.10, arc * 0.13)
	arm_r.rotation_degrees = Vector3(-8 - arc * 55.0, 6 + arc * 8.0, arc * 6.0)
	arm_l.position = Vector3(-0.30, -0.02, -0.05) + sway * 0.7 \
		+ Vector3(0, -arc * 0.03, arc * 0.05)
	arm_l.rotation_degrees = Vector3(-6 - arc * 14.0, -8, 0)
	recoil = maxf(0.0, recoil - delta * 3.0)
	position.z = -0.42 + recoil * 0.04
