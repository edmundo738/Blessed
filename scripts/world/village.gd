class_name Village
extends Node3D
## Village — a aldeia procedural à volta do ponto fixo do mapa.
##
## É o único lugar "feito à mão" do mundo, e ainda assim é derivado do Terrain:
## as casas assentam na altura real do chão e viram-se para o largo.

var world: World
var structures: Structures
var npc_root: Node3D
var species: SpeciesKit
var mats: Materials
var npcs: Array = []


func build() -> void:
	if world == null:
		return
	var ter := world.terrain
	var c := ter.village_center()
	var base := ter.village_height()
	_build_square(c, base)
	_build_huts(c, base)
	_build_elder(c, base)
	_build_props(c, base)


func _build_square(c: Vector2, base: float) -> void:
	# chão batido do largo
	var mesh := MeshKit.box(Vector3(16.0, 0.16, 16.0), Color(0.62, 0.50, 0.38))
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mats.structure
	body.add_child(mi)
	body.position = Vector3(c.x, base - 0.02, c.y)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(16.0, 0.16, 16.0)
	col.shape = box
	body.add_child(col)
	add_child(body)


func _build_huts(c: Vector2, base: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Game.world_seed ^ 0xA11CE
	for i in 5:
		var a := (float(i) / 5.0) * TAU + 0.3
		var r := rng.randf_range(9.5, 12.5)
		var p := Vector3(c.x + cos(a) * r, base, c.y + sin(a) * r)
		var w := rng.randf_range(3.2, 4.4)
		var d := rng.randf_range(3.2, 4.4)
		var h := rng.randf_range(2.4, 3.0)
		_hut(p, w, d, h, -a + PI * 0.5, rng)


func _hut(p: Vector3, w: float, d: float, h: float, rot: float,
		rng: RandomNumberGenerator) -> void:
	var body := StaticBody3D.new()
	body.position = p
	body.rotation.y = rot
	add_child(body)

	var wood := Color(0.60, 0.43, 0.30).lerp(Color(0.72, 0.55, 0.38), rng.randf())
	# chão
	_part(body, MeshKit.box(Vector3(w, 0.2, d), wood.darkened(0.15)),
		Vector3(0, 0.1, 0), Vector3(w, 0.2, d))
	# quatro paredes com uma abertura à frente
	var t := 0.22
	_part(body, MeshKit.box(Vector3(w, h, t), wood), Vector3(0, h * 0.5, -d * 0.5),
		Vector3(w, h, t))
	_part(body, MeshKit.box(Vector3(w, h, t), wood), Vector3(0, h * 0.5, d * 0.5),
		Vector3(w, h, t))
	_part(body, MeshKit.box(Vector3(t, h, d), wood), Vector3(-w * 0.5, h * 0.5, 0),
		Vector3(t, h, d))
	_part(body, MeshKit.box(Vector3(t, h, d), wood), Vector3(w * 0.5, h * 0.5, 0),
		Vector3(t, h, d))
	# telhado de duas águas
	var roof := Color(0.42, 0.28, 0.26).lerp(Color(0.55, 0.36, 0.30), rng.randf())
	var slant := MeshKit.box(Vector3(w * 1.15, 0.14, d * 0.72), roof)
	var r1 := MeshInstance3D.new()
	r1.mesh = slant
	r1.material_override = mats.structure
	r1.position = Vector3(0, h + 0.55, -d * 0.26)
	r1.rotation.x = -0.55
	body.add_child(r1)
	var r2 := MeshInstance3D.new()
	r2.mesh = slant
	r2.material_override = mats.structure
	r2.position = Vector3(0, h + 0.55, d * 0.26)
	r2.rotation.x = 0.55
	body.add_child(r2)
	# fogueira pequena ao lado
	if rng.randf() < 0.7:
		var off := Vector3(rng.randf_range(-1, 1) * 2.0, 0, d * 0.5 + 1.4)
		var lp := (body.global_transform * off)
		structures.place("campfire", Vector3(lp.x, world.ground_height(lp.x, lp.z), lp.z),
			0.0, rng.randf() < 0.6)


func _part(parent: Node, mesh: ArrayMesh, pos: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mats.structure
	mi.position = pos
	parent.add_child(mi)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = pos
	parent.add_child(col)


func _build_elder(c: Vector2, base: float) -> void:
	if structures != null:
		structures.place("campfire", Vector3(c.x + 1.2, base + 0.05, c.y + 1.2), 0.0, true)
	var npc: Npc = load("res://scripts/entities/npc.gd").new()
	npc.id = "elder"
	npc.display_key = "npc.elder.name"
	npc.personality = {"warmth": 0.72, "curiosity": 0.55, "fear": 0.30, "talkative": 0.8}
	npc.player = get_parent().get_node_or_null("Player")
	npc.world = world
	npc.structures = structures
	npc.add_to_group("npcs")
	npc_root.add_child(npc)
	npc.global_position = Vector3(c.x - 2.0, base + 0.05, c.y - 1.6)
	npc.home = npc.global_position
	npcs.append(npc)


func _build_props(c: Vector2, base: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Game.world_seed ^ 0xBEEF
	for i in 10:
		var a := rng.randf() * TAU
		var r := rng.randf_range(6.0, 13.0)
		var p := Vector3(c.x + cos(a) * r, 0, c.y + sin(a) * r)
		p.y = world.ground_height(p.x, p.z)
		if rng.randf() < 0.5:
			structures.place("pillar", p, rng.randf() * TAU, false)
		else:
			structures.place("wall", p, snappedf(rng.randf() * TAU, PI * 0.5), false)
