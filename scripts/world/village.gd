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
	_build_ruins(c, base)
	_build_elder(c, base)


const STONE_A := Color(0.68, 0.64, 0.58)
const STONE_B := Color(0.46, 0.43, 0.41)
const MOSS := Color(0.33, 0.46, 0.26)


func _stone(rng: RandomNumberGenerator, moss: float = 0.0) -> Color:
	var c := STONE_A.lerp(STONE_B, rng.randf())
	if moss > 0.0:
		c = c.lerp(MOSS, clampf(moss * rng.randf_range(0.10, 0.45), 0.0, 0.5))
	return c


func _ground_at(x: float, z: float) -> float:
	return world.ground_height(x, z)


func _block(size: Vector3, pos: Vector3, yaw: float, col: Color,
		tilt: Vector3 = Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0, size.y * 0.5, 0)
	body.rotation = Vector3(tilt.x, yaw, tilt.z)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.box(size, col)
	mi.material_override = mats.structure
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	body.add_child(cs)
	add_child(body)


func _column(rng: RandomNumberGenerator, pos: Vector3, height: float, fallen: bool) -> void:
	var col := _stone(rng, 0.5)
	var r_b := rng.randf_range(0.40, 0.48)
	var mesh := MeshKit.tapered(rng, height, r_b, r_b * 0.82, 10, 3, 0.0, true, col)
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mats.structure
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r_b
	cyl.height = height
	cs.shape = cyl
	cs.position = Vector3(0, height * 0.5, 0)
	body.add_child(cs)
	if fallen:
		body.position = pos + Vector3(0, r_b * 0.9, 0)
		body.rotation = Vector3(0.0, rng.randf() * TAU, PI * 0.5 - 0.05)
	else:
		body.position = pos + Vector3(0, -0.15, 0)
		body.rotation.y = rng.randf() * TAU
	add_child(body)
	if not fallen:
		_block(Vector3(1.25, 0.35, 1.25), pos + Vector3(0, -0.12, 0), 0.0, _stone(rng, 0.6))


func _wall(rng: RandomNumberGenerator, from: Vector3, dir: Vector3, length: float,
		max_h: float, thick: float) -> void:
	var n := maxi(int(length / 0.85), 2)
	var yaw := atan2(-dir.z, dir.x)
	for k in n:
		var t := float(k) / float(n - 1)
		var edge := 1.0 - pow(absf(t * 2.0 - 1.0), 2.4) * 0.65
		var h := max_h * edge * rng.randf_range(0.45, 1.0)
		if rng.randf() < 0.12:
			h = rng.randf_range(0.3, 0.7)
		h = maxf(h, 0.35)
		var p := from + dir * (float(k) * 0.85)
		p.y = _ground_at(p.x, p.z) - 0.1
		var jitter := Vector3(rng.randf_range(-0.04, 0.04), 0, rng.randf_range(-0.05, 0.05))
		_block(Vector3(0.88, h, thick + rng.randf_range(-0.06, 0.08)), p + jitter,
			yaw + rng.randf_range(-0.05, 0.05), _stone(rng, 0.7))


func _rubble(rng: RandomNumberGenerator, center: Vector3, radius: float, count: int) -> void:
	for i in count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var p := center + Vector3(cos(a) * r, 0, sin(a) * r)
		p.y = _ground_at(p.x, p.z)
		var sz := rng.randf_range(0.18, 0.62)
		var mesh := MeshKit.blob(rng, sz, 1, 0.30, Vector3(1.2, 0.7, 1.0), _stone(rng, 0.5))
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mats.structure
		mi.position = p + Vector3(0, sz * 0.25, 0)
		mi.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
		add_child(mi)


func _build_ruins(c: Vector2, base: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Game.world_seed ^ 0xA11CE
	var centre := Vector3(c.x, base, c.y)

	# 1. lajes do largo: grelha 7x7, com falhas, desniveis e musgo
	var slab := 2.3
	for j in range(-3, 4):
		for i in range(-3, 4):
			if rng.randf() < 0.30:
				continue
			if Vector2(i, j).length() > 3.3:
				continue
			var p := centre + Vector3(i * slab + rng.randf_range(-0.08, 0.08), 0, j * slab + rng.randf_range(-0.08, 0.08))
			p.y = base + rng.randf_range(-0.05, 0.05)
			var col := _stone(rng, 0.9)
			var body := StaticBody3D.new()
			body.position = p + Vector3(0, 0.06, 0)
			body.rotation = Vector3(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.08, 0.08), rng.randf_range(-0.03, 0.03))
			var mi := MeshInstance3D.new()
			mi.mesh = MeshKit.box(Vector3(slab - 0.14, 0.14, slab - 0.14), col)
			mi.material_override = mats.structure
			body.add_child(mi)
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(slab - 0.14, 0.14, slab - 0.14)
			cs.shape = bx
			body.add_child(cs)
			add_child(body)

	# 2. circulo de colunas: umas de pe, outras partidas
	var n_col := 9
	for i in n_col:
		var a := float(i) / float(n_col) * TAU + 0.2
		var r := 7.2 + rng.randf_range(-0.3, 0.3)
		var p := Vector3(c.x + cos(a) * r, 0, c.y + sin(a) * r)
		p.y = _ground_at(p.x, p.z)
		var roll := rng.randf()
		if roll < 0.45:
			_column(rng, p, rng.randf_range(4.2, 5.4), false)
		elif roll < 0.80:
			_column(rng, p, rng.randf_range(1.2, 2.6), false)
		else:
			_column(rng, p, rng.randf_range(3.0, 4.2), true)
			_rubble(rng, p, 1.6, 4)

	# 3. muralha exterior em arcos, com duas entradas
	var wall_r := 13.0
	for seg in 5:
		var a0 := float(seg) / 5.0 * TAU + 0.65
		var arc := TAU / 5.0 * 0.62
		var steps := 4
		for st in steps:
			var a1 := a0 + arc * float(st) / float(steps)
			var a2 := a0 + arc * float(st + 1) / float(steps)
			var p1 := Vector3(c.x + cos(a1) * wall_r, 0, c.y + sin(a1) * wall_r)
			var p2 := Vector3(c.x + cos(a2) * wall_r, 0, c.y + sin(a2) * wall_r)
			var d := p2 - p1
			var l := d.length()
			_wall(rng, p1, d / l, l, rng.randf_range(2.4, 4.0), 0.75)

	# 4. torre caida: tres paredes altas num canto
	var ta := 2.5
	var tc := Vector3(c.x + cos(ta) * 15.5, 0, c.y + sin(ta) * 15.5)
	var tdir := Vector3(cos(ta + PI * 0.5), 0, sin(ta + PI * 0.5))
	var tout := Vector3(cos(ta), 0, sin(ta))
	_wall(rng, tc - tdir * 3.6, tdir, 7.2, 6.4, 0.9)
	_wall(rng, tc - tdir * 3.6, tout, 4.5, 4.8, 0.9)
	_wall(rng, tc + tdir * 3.6, tout, 3.0, 3.4, 0.9)
	_rubble(rng, tc + tout * 2.0, 3.0, 10)

	# 5. arco partido na entrada oeste
	var ax := c.x - 9.0
	var az := c.y + 0.0
	var gp := Vector3(ax, 0, az)
	gp.y = _ground_at(ax, az)
	_block(Vector3(1.0, 4.6, 1.0), gp + Vector3(0, 0, -1.9), 0.0, _stone(rng, 0.6))
	_block(Vector3(1.0, 2.5, 1.0), gp + Vector3(0, 0, 1.9), 0.0, _stone(rng, 0.7))
	_block(Vector3(1.1, 0.8, 3.1), gp + Vector3(0, 4.6, -0.35), 0.0, _stone(rng, 0.4),
		Vector3(0.0, 0.0, -0.10))
	_rubble(rng, gp + Vector3(0, 0, 1.2), 2.2, 8)

	# 6. degraus para a plataforma norte
	var sp := Vector3(c.x, 0, c.y - 6.4)
	for k in 4:
		var q := sp + Vector3(0, 0, -float(k) * 0.9)
		q.y = base + float(k) * 0.28
		_block(Vector3(6.0 - float(k) * 0.9, 0.3, 1.0), q, 0.0, _stone(rng, 0.8))

	# 7. entulho espalhado
	_rubble(rng, centre, 14.0, 26)


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
	# NPCs humanos REMOVIDOS a pedido — as ruínas ficam sem habitantes.
	# Mantém-se só um braseiro (fonte de luz útil à noite).
	if structures != null:
		structures.place("campfire", Vector3(c.x + 1.2, base + 0.05, c.y + 1.2), 0.0, true)


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
