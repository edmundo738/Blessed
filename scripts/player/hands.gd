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
var _skin := StandardMaterial3D.new()
var _cloth := StandardMaterial3D.new()
var _trim := StandardMaterial3D.new()

var swing_t := -1.0
var swing_speed := 1.0
var bob_t := 0.0
var recoil := 0.0
var move_speed := 0.0
var swimming := false
var _two_handed := false
var _pitch := 0.0
var _sway := Vector3.ZERO

signal swung


func _ready() -> void:
	rng.seed = 99
	_skin.vertex_color_use_as_albedo = true
	_skin.albedo_color = Color("e3b99d")
	_skin.roughness = 0.86
	_cloth.vertex_color_use_as_albedo = true
	_cloth.albedo_color = Color("596b61")
	_cloth.roughness = 0.94
	_trim.vertex_color_use_as_albedo = true
	_trim.albedo_color = Color("b28b55")
	_trim.roughness = 0.78
	position = Vector3(0.0, -0.07, -0.30)
	arm_r = _make_arm(1)
	arm_r.position = Vector3(0.40, -0.33, -0.04)
	arm_r.rotation_degrees = Vector3(-18, 8, -9)
	arm_r.scale = Vector3.ONE * 0.68
	add_child(arm_r)
	arm_l = _make_arm(-1)
	arm_l.position = Vector3(-0.36, -0.34, -0.16)
	arm_l.rotation_degrees = Vector3(-26, -14, 16)
	arm_l.scale = Vector3.ONE * 0.74
	arm_l.visible = false
	add_child(arm_l)
	held = MeshInstance3D.new()
	held.position = Vector3(0.02, -0.12, -0.50)
	held.rotation_degrees = Vector3(0, 0, -5)
	arm_r.add_child(held)


func _make_arm(side: int) -> Node3D:
	var n := Node3D.new()
	# Ombro: uma pequena massa de tecido antes da manga. Sem isto o braço
	# nascia de um tubo cortado no ar.
	var shoulder := _ellipsoid(Vector3(0.095, 0.075, 0.10), _cloth)
	shoulder.position = Vector3(0.0, -0.005, -0.025)
	n.add_child(shoulder)
	var sleeve := MeshInstance3D.new()
	var sleeve_mesh := CapsuleMesh.new()
	sleeve_mesh.radius = 0.070
	sleeve_mesh.height = 0.36
	sleeve_mesh.radial_segments = 10
	sleeve_mesh.rings = 4
	sleeve.mesh = sleeve_mesh
	sleeve.material_override = _cloth
	sleeve.rotation.x = PI * 0.5
	sleeve.position = Vector3(0.0, 0.012, -0.17)
	n.add_child(sleeve)
	# Punho dobrado: a manga aperta e o antebraço de pele continua.
	var cuff := MeshInstance3D.new()
	var cuff_mesh := CylinderMesh.new()
	cuff_mesh.top_radius = 0.073
	cuff_mesh.bottom_radius = 0.068
	cuff_mesh.height = 0.060
	cuff_mesh.radial_segments = 10
	cuff.mesh = cuff_mesh
	cuff.material_override = _trim
	cuff.rotation.x = PI * 0.5
	cuff.position = Vector3(0.0, 0.012, -0.345)
	n.add_child(cuff)
	var forearm := MeshInstance3D.new()
	var fm := MeshKit.tapered(rng, 0.105, 0.054, 0.046, 8, 2, 0.0, false,
		Color.WHITE)
	forearm.mesh = fm
	forearm.material_override = _skin
	forearm.rotation.x = -PI * 0.5
	forearm.position = Vector3(0.0, 0.010, -0.350)
	n.add_child(forearm)
	var wrist := _ellipsoid(Vector3(0.052, 0.046, 0.040), _skin)
	wrist.position = Vector3(0.0, 0.008, -0.456)
	n.add_child(wrist)
	# Palma ligeiramente côncava, com a base dos dedos marcada.
	var palm := _ellipsoid(Vector3(0.098, 0.058, 0.115), _skin)
	palm.position = Vector3(0.0, -0.010, -0.510)
	n.add_child(palm)
	for finger in 4:
		var length := 0.105 - absf(float(finger) - 1.5) * 0.010
		var x := (float(finger) - 1.5) * 0.043
		var knuckle := _ellipsoid(Vector3(0.020, 0.020, 0.026), _skin)
		knuckle.position = Vector3(x, -0.006, -0.565)
		n.add_child(knuckle)
		var f := _ellipsoid(Vector3(0.017, 0.019, length), _skin)
		f.position = Vector3(x, -0.024, -0.585 - length * 0.22)
		# Dedos fechados em volta do cabo: a mão agarra, não aponta.
		f.rotation.x = -0.62
		n.add_child(f)
	var thumb := _ellipsoid(Vector3(0.027, 0.025, 0.078), _skin)
	thumb.position = Vector3(0.093 * float(side), -0.004, -0.515)
	thumb.rotation.y = -0.62 * float(side)
	thumb.rotation.x = -0.35
	n.add_child(thumb)
	return n


func _ellipsoid(scale: Vector3, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 4
	part.mesh = sphere
	part.scale = scale
	part.material_override = material
	return part


## Põe na mão a malha do item (ou esvazia).
func set_held(mesh: ArrayMesh, mat: Material = null) -> void:
	held.mesh = mesh
	held.material_override = mat
	held.visible = mesh != null
	# A mão de apoio foi escondida: o rig de duas mãos ainda não está bom o
	# suficiente para aparecer (o antebraço ficava um toco a flutuar). Uma mão
	# firme no cabo é melhor do que duas a fingir.
	arm_l.visible = false


## Gera uma silhueta clara para o item equipado, visível na 1.ª pessoa.
func set_item(item_id: String) -> void:
	_two_handed = item_id in ["axe", "pickaxe", "rod", "primitive_axe",
		"primitive_pickaxe"]
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
			# Escala e inclinação de EMPUNHADURA: o modelo do Blender cresce em
			# Y, por isso sem inclinação a cabeça do machado ficava em pé à
			# altura dos olhos e parecia um totem. Rodado para a frente, o cabo
			# entra na mão e a cabeça lê-se na diagonal.
			_asset_root.scale = Vector3.ONE * 0.55
			_asset_root.rotation_degrees = Vector3(-18.0, 8.0, 22.0)
			_asset_root.position = Vector3(0.0, -0.10, -0.08)
			held.add_child(_asset_root)
			held.mesh = null
			# MeshInstance visibility hides its whole subtree, including the GLB tool.
			held.visible = true
			arm_l.visible = false
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
			parts = [[MeshKit.box(Vector3(0.055, 0.42, 0.055), Color("765136")),
				Transform3D(Basis.IDENTITY, Vector3(0, 0.06, 0))],
				[MeshKit.box(Vector3(0.11, 0.10, 0.09), Color("4b4238")),
				Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0))],
				[MeshKit.cone(0.070, 0.20, 7, Color("e88432")),
				Transform3D(Basis.IDENTITY, Vector3(0, 0.30, 0))],
				[MeshKit.cone(0.038, 0.135, 7, Color("ffd477")),
				Transform3D(Basis.IDENTITY, Vector3(0, 0.31, -0.012))]]
		"rod":
			parts = [[MeshKit.box(Vector3(0.035, 0.68, 0.035), Color("9b693d")),
				Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-22)), Vector3(0, 0.18, 0))]]
		"wood", "stick":
			parts = [[MeshKit.box(Vector3(0.08, 0.38, 0.08), Color("a97542")),
				Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-24)), Vector3(0, 0.12, 0))]]
		"stone", "flint":
			parts = [[MeshKit.blob(rng, 0.16, 1, 0.12, Vector3(1.0, 0.7, 0.8), Color("9ba6a3")),
				Transform3D(Basis.IDENTITY, Vector3(0, 0.12, 0))]]
		"mushroom", "meat_raw", "meat_cooked", "fish_raw", "fish_cooked":
			var tint := Color("d88472")
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
	swung.emit()


func recoil_kick(amount: float = 0.25) -> void:
	recoil = maxf(recoil, amount)


## Movimento do corpo chega aqui: as mãos têm de saber se estão a andar, a
## correr ou a nadar. Sem isto ficavam sempre na pose de repouso enquanto o
## mundo passava — o clássico "braços de papelão" da primeira pessoa.
func set_motion(speed: float, is_swimming: bool, pitch: float) -> void:
	move_speed = speed
	swimming = is_swimming
	_pitch = pitch


func _process(delta: float) -> void:
	# mola de respiração + balanço dos passos
	bob_t += delta * (1.6 + move_speed * 0.55)
	var breathe := sin(bob_t) * 0.006
	var walk := clampf(move_speed / 6.2, 0.0, 1.2)
	var sway := Vector3(sin(bob_t * 0.8) * 0.008, breathe + sin(bob_t * 3.1) * 0.012 * walk,
		cos(bob_t * 0.6) * 0.006)
	_sway = _sway.lerp(sway, 1.0 - exp(-10.0 * delta))
	if swing_t >= 0.0:
		swing_t += delta * swing_speed
		if swing_t > 1.0:
			swing_t = -1.0
	var s := swing_t
	var arc := 0.0
	if s >= 0.0:
		# curva de balanço: sobe rápido, desce com peso
		arc = sin(clampf(s, 0.0, 1.0) * PI)

	# Correr inclina as mãos para trás e aperta o gesto; nadar leva-as à frente
	# e alterna as braçadas. A ferramenta continua a ser o centro da ação.
	var run_dip := walk * 0.055
	var swim_x := 0.0
	var swim_y := 0.0
	var swim_rot := 0.0
	if swimming:
		var stroke := sin(bob_t * 3.0)
		swim_x = -0.10
		swim_y = 0.02 + absf(stroke) * 0.08
		swim_rot = -0.85 + stroke * 0.45
	arm_r.position = Vector3(0.40 + _sway.x + swim_x, -0.33 + _sway.y + run_dip + swim_y,
		-0.04 + _sway.z + walk * 0.05)
	arm_r.rotation_degrees = Vector3(-18 - arc * 58.0 - walk * 5.0 + rad_to_deg(swim_rot),
		6 + arc * 8.0, -9 + arc * 6.0 + sin(bob_t * 2.2) * 1.4)
	if arm_l.visible:
		arm_l.position = Vector3(-0.10 + _sway.x * 0.6, -0.30 + _sway.y * 0.7,
			-0.38 + _sway.z + arc * 0.02)
		arm_l.rotation_degrees = Vector3(-58 - arc * 12.0, -10, 28 - arc * 4.0)
	recoil = maxf(0.0, recoil - delta * 3.0)
	# O recuo empurra a arma para o jogador e levanta-a ligeiramente: é a mão
	# a absorver o choque, não a câmara a teleportar.
	position.z = -0.42 + recoil * 0.055 + (0.06 if swimming else 0.0)
	position.y = -0.07 + sin(bob_t * 2.1) * 0.004 + walk * 0.012
	held.position = Vector3(0.02, -0.12, -0.50 + recoil * 0.02)
	held.rotation_degrees = Vector3(-4.0 - _pitch * 7.0, 0.0, -5.0 + arc * 10.0)
