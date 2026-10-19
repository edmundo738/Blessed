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

	# 2. fragmentos de ruína compostos por WFC. A topologia (paredes que se
	# ligam) vem de um pequeno exemplo; variações visuais partilham os mesmos
	# conectores, para a diversidade não abrir buracos nem criar peças soltas.
	_build_wfc_ruin(c, rng)

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


const RUIN_GRID := 9
const RUIN_CELL := 2.3
const RUIN_VARIANTS := 3
const RUIN_DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const RUIN_OPPOSITE_BITS := [4, 8, 1, 2]


func _build_wfc_ruin(c: Vector2, rng: RandomNumberGenerator) -> void:
	var occupied := PackedByteArray()
	occupied.resize(RUIN_GRID * RUIN_GRID)
	# Mapa-exemplo: muralha antiga quase fechada, uma entrada e um braço interno.
	# O solver aprende os conectores norte/leste/sul/oeste desta composição.
	for x in range(2, 7):
		occupied[2 * RUIN_GRID + x] = 1
		occupied[6 * RUIN_GRID + x] = 1
	for z in range(3, 6):
		occupied[z * RUIN_GRID + 2] = 1
		occupied[z * RUIN_GRID + 6] = 1
	occupied[4 * RUIN_GRID + 2] = 0 # entrada ocidental
	occupied[4 * RUIN_GRID + 6] = 0 # quebra do lado oriental
	for x in range(3, 6):
		occupied[4 * RUIN_GRID + x] = 1
	occupied[4 * RUIN_GRID + 4] = 0 # corredor interior aberto

	var signatures := PackedByteArray()
	signatures.resize(RUIN_GRID * RUIN_GRID)
	var frequency := PackedFloat32Array()
	frequency.resize(16)
	for z in range(1, RUIN_GRID - 1):
		for x in range(1, RUIN_GRID - 1):
			var index := z * RUIN_GRID + x
			if occupied[index] == 0:
				continue
			var mask := 0
			for direction in 4:
				var neighbor: Vector2i = Vector2i(x, z) + RUIN_DIRS[direction]
				if occupied[neighbor.y * RUIN_GRID + neighbor.x] != 0:
					mask |= 1 << direction
			signatures[index] = mask
			frequency[mask] += 1.0

	var tile_count := 16 * RUIN_VARIANTS
	var allowed := PackedInt64Array()
	allowed.resize(tile_count * 4)
	var weights := PackedFloat32Array()
	weights.resize(tile_count)
	for tile in tile_count:
		var mask: int = int(tile / RUIN_VARIANTS)
		var variant: int = tile % RUIN_VARIANTS
		var variant_weight: float = [1.0, 0.52, 0.18][variant]
		if mask == 0:
			variant_weight = [3.2, 0.82, 0.15][variant]
		weights[tile] = (frequency[mask] + 0.10) * variant_weight
		for direction in 4:
			var bit := 1 << direction
			var neighbor_mask := 0
			for other in tile_count:
				var other_mask: int = int(other / RUIN_VARIANTS)
				var has_port: bool = (mask & bit) != 0
				var has_mate: bool = (other_mask & RUIN_OPPOSITE_BITS[direction]) != 0
				if has_port == has_mate:
					neighbor_mask |= 1 << other
			allowed[tile * 4 + direction] = neighbor_mask

	var fixed: Dictionary = {}
	for edge in RUIN_GRID:
		fixed[edge] = 0
		fixed[(RUIN_GRID - 1) * RUIN_GRID + edge] = 0
		fixed[edge * RUIN_GRID] = 0
		fixed[edge * RUIN_GRID + RUIN_GRID - 1] = 0
	# O centro fica livre para o largo, NPCs e fogo; a ruína constrói-se à volta.
	for z in range(3, 6):
		for x in range(3, 6):
			fixed[z * RUIN_GRID + x] = 0

	var solver := WFC2D.new()
	var solved := solver.solve(RUIN_GRID, RUIN_GRID, allowed, weights,
		Game.world_seed ^ 0x5E771E, PackedFloat32Array(), fixed, 0)
	var layout: PackedInt32Array = solved["tiles"]
	if not bool(solved["success"]):
		push_warning("Ruína WFC usou layout vazio após %d contradições" % int(solved["contradictions"]))
		return
	var half := float(RUIN_GRID - 1) * RUIN_CELL * 0.5
	for z in RUIN_GRID:
		for x in RUIN_GRID:
			var tile := layout[z * RUIN_GRID + x]
			var mask: int = int(tile / RUIN_VARIANTS)
			var variant: int = tile % RUIN_VARIANTS
			var center := Vector3(c.x + float(x) * RUIN_CELL - half, 0.0,
				c.y + float(z) * RUIN_CELL - half)
			center.y = _ground_at(center.x, center.z)
			if mask == 0:
				if variant == 1:
					_rubble(rng, center, 0.65, 2)
				elif variant == 2:
					_column(rng, center, rng.randf_range(1.1, 2.4), false)
				continue
			var height: float = [3.7, 2.4, 1.25][variant]
			for direction: int in [1, 2]: # cada ligação é construída uma vez (E e S)
				if (mask & (1 << direction)) == 0:
					continue
				var step := Vector3(RUIN_DIRS[direction].x, 0.0, RUIN_DIRS[direction].y) * RUIN_CELL
				_wfc_wall_segment(rng, center, center + step, height, variant)
			if _bit_count(mask) >= 3 and rng.randf() < 0.38:
				_column(rng, center, rng.randf_range(2.0, 4.0), false)


func _wfc_wall_segment(rng: RandomNumberGenerator, from: Vector3, to: Vector3,
		max_height: float, damage: int) -> void:
	var delta := to - from
	var length := Vector2(delta.x, delta.z).length()
	var count := maxi(int(ceil(length / 0.78)), 2)
	var yaw := atan2(-delta.z, delta.x)
	for i in count:
		if damage >= 2 and rng.randf() < 0.25:
			continue
		var t := (float(i) + 0.5) / float(count)
		var p := from.lerp(to, t)
		p.y = _ground_at(p.x, p.z)
		var h := max_height * rng.randf_range(0.44, 1.0)
		if damage >= 1 and rng.randf() < 0.34:
			h *= rng.randf_range(0.36, 0.65)
		if rng.randf() < 0.10:
			h = rng.randf_range(0.3, 0.7)
		_block(Vector3(length / float(count) + 0.08, h, 0.62), p, yaw,
			_stone(rng, 0.5 + float(damage) * 0.16),
			Vector3(rng.randf_range(-0.035, 0.035), 0.0, rng.randf_range(-0.045, 0.045)))


func _bit_count(mask: int) -> int:
	var value := mask
	var count := 0
	while value != 0:
		value &= value - 1
		count += 1
	return count


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
