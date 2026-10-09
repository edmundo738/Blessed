class_name Chunk
extends Node3D
## Chunk — um quadrado de mundo gerado, usado e devolvido.
##
## Um chunk tem: malha de terreno + colisão (só nos níveis perto) + MultiMesh por
## espécie (árvores, rochas, plantas, relva) + um registo dos nós colhíveis.
## Nada aqui é guardado entre chunks: o mundo é sempre rederivado do Terrain.

const SIZE := 48.0
## Altura da saia. Era 5.0: uma parede de 5 m à volta de cada chunk, visível
## como uma grelha de muros. 1.2 m chega para tapar as costuras entre LODs e
## lê-se como sombra de contacto, não como arquitectura.
const SKIRT := 1.2
const RES := [48, 24, 12]          # quads por lado em cada LOD
const TREE_CELL := 3.0
const ROCK_CELL := 6.0
const GRASS_TARGET := 420

var cx := 0
var cz := 0
var lod := 0
var built := false
var grass_quality := 1

var terrain: Terrain
var species: SpeciesKit
var mats: Materials

## Nós colhíveis deste chunk: {pos, kind, species, hp, node}
var harvest_nodes: Array = []

var _mesh_inst: MeshInstance3D
var _body: StaticBody3D
var _decor: Array = []
var _colliders: Array = []
var _buckets: Dictionary = {}


func origin() -> Vector2:
	return Vector2(cx * SIZE, cz * SIZE)


func center() -> Vector2:
	return Vector2(cx * SIZE + SIZE * 0.5, cz * SIZE + SIZE * 0.5)


func distance_to(p: Vector3) -> float:
	var c := center()
	return Vector2(p.x - c.x, p.z - c.y).length()


func build(with_collision: bool) -> void:
	if built:
		return
	built = true
	var o := origin()
	_build_ground(o, with_collision)
	_scatter(o, with_collision)


# ══════════════════════════════════════════════════════════════════════════
#  TERRENO
# ══════════════════════════════════════════════════════════════════════════
func _build_ground(o: Vector2, with_collision: bool) -> void:
	var res: int = RES[clampi(lod, 0, RES.size() - 1)]
	var step := SIZE / float(res)
	var n := res + 1
	var heights := PackedFloat32Array()
	heights.resize(n * n)

	# 1) alturas (a única parte cara)
	for j in n:
		for i in n:
			var x := o.x + i * step
			var z := o.y + j * step
			heights[j * n + i] = terrain.height(x, z)

	# 2) malha com cor de vértice por bioma
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var buf := PackedFloat32Array()
	buf.resize(Terrain.BIOME_COUNT)
	var normals := PackedVector3Array()
	normals.resize(n * n)
	# normais a partir da grelha (barato e sem costuras)
	for j in n:
		for i in n:
			var hl := heights[j * n + maxi(i - 1, 0)]
			var hr := heights[j * n + mini(i + 1, n - 1)]
			var hd := heights[maxi(j - 1, 0) * n + i]
			var hu := heights[mini(j + 1, n - 1) * n + i]
			normals[j * n + i] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()

	for j in n:
		for i in n:
			var x := o.x + i * step
			var z := o.y + j * step
			var h := heights[j * n + i]
			var sl := clampf(Vector2(normals[j * n + i].x, normals[j * n + i].z).length()
				/ maxf(normals[j * n + i].y, 0.001) * 0.55, 0.0, 1.0)
			st.set_normal(normals[j * n + i])
			st.set_color(terrain.ground_color_s(x, z, h, sl, buf))
			st.add_vertex(Vector3(x, h, z))

	for j in res:
		for i in res:
			var a := j * n + i
			var b := j * n + i + 1
			var c := (j + 1) * n + i + 1
			var d := (j + 1) * n + i
			st.add_index(a); st.add_index(c); st.add_index(b)
			st.add_index(a); st.add_index(d); st.add_index(c)

	# 3) saia: parede vertical à volta do chunk, esconde as fendas entre chunks
	#    de LOD diferente. (Usa índices como o resto — misturar indexado com
	#    não-indexado na mesma superfície é inválido.)
	#
	#    Antes as normais eram Vector3.DOWN e a ordem dos índices era fixa:
	#    em dois dos quatro lados a face ficava virada para DENTRO do chunk e
	#    era cortada pelo cull_back, e onde aparecia estava às escuras porque a
	#    normal apontava para baixo. Agora a normal aponta para fora e a ordem
	#    dos índices decide-se pelo sinal, como MeshKit.tri faz.
	var cx := o.x + SIZE * 0.5
	var cz := o.y + SIZE * 0.5
	# O índice base da saia conta-se à mão, num Array de um elemento.
	# Dois motivos, ambos medidos em tests/diag.gd:
	#   • `st.get_vertex_count()` devolve 0 aqui, e com isso os 384 triângulos
	#     da saia apontavam todos para os vértices 0..3 (o canto do chunk);
	#   • uma lambda GDScript captura variáveis POR VALOR, por isso
	#     `skirt_base += 4` dentro dela não avança nada lá fora. O Array é uma
	#     referência e por isso o contador persiste.
	var skirt_base := [n * n]
	var skirt := func(i0: int, j0: int, i1: int, j1: int) -> void:
		var x0 := o.x + i0 * step
		var z0 := o.y + j0 * step
		var x1 := o.x + i1 * step
		var z1 := o.y + j1 * step
		var h0: float = heights[j0 * n + i0]
		var h1: float = heights[j1 * n + i1]
		var base: int = int(skirt_base[0])
		skirt_base[0] = base + 4
		# para fora = do meio da aresta para longe do centro do chunk
		var outward := Vector3((x0 + x1) * 0.5 - cx, 0.0, (z0 + z1) * 0.5 - cz)
		if outward.length_squared() < 1e-6:
			outward = Vector3(0, 0, -1)
		outward = outward.normalized()
		st.set_color(Color(0.36, 0.33, 0.30))
		st.set_normal(outward)
		st.add_vertex(Vector3(x0, h0, z0))                 # 0 = topo, início
		st.set_color(Color(0.30, 0.27, 0.25))
		st.set_normal(outward)
		st.add_vertex(Vector3(x1, h1, z1))                 # 1 = topo, fim
		st.set_color(Color(0.24, 0.22, 0.20))
		st.set_normal(outward)
		st.add_vertex(Vector3(x1, h1 - SKIRT, z1))         # 2 = base, fim
		st.set_color(Color(0.30, 0.27, 0.25))
		st.set_normal(outward)
		st.add_vertex(Vector3(x0, h0 - SKIRT, z0))         # 3 = base, início
		var t0 := Vector3(x0, h0, z0)
		var t1 := Vector3(x1, h1, z1)
		var b1 := Vector3(x1, h1 - SKIRT, z1)
		var flip := (t1 - t0).cross(b1 - t0).dot(outward) < 0.0
		if flip:
			st.add_index(base + 0); st.add_index(base + 2); st.add_index(base + 1)
			st.add_index(base + 0); st.add_index(base + 3); st.add_index(base + 2)
		else:
			st.add_index(base + 0); st.add_index(base + 1); st.add_index(base + 2)
			st.add_index(base + 0); st.add_index(base + 2); st.add_index(base + 3)
	for k in res:
		skirt.call(k, 0, k + 1, 0)
		skirt.call(k, res, k + 1, res)
		skirt.call(0, k, 0, k + 1)
		skirt.call(res, k, res, k + 1)

	var mesh := st.commit()
	mesh.surface_set_material(0, mats.terrain)
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = mesh
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_mesh_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_mesh_inst)

	if with_collision:
		var shape := HeightMapShape3D.new()
		shape.map_width = n
		shape.map_depth = n
		shape.map_data = heights
		_body = StaticBody3D.new()
		_body.position = Vector3(o.x + SIZE * 0.5, 0.0, o.y + SIZE * 0.5)
		_body.collision_layer = 1
		var col := CollisionShape3D.new()
		col.shape = shape
		_body.add_child(col)
		add_child(_body)
		_colliders.append(col)


# ══════════════════════════════════════════════════════════════════════════
#  VEGETAÇÃO / ROCHAS / RELVA
# ══════════════════════════════════════════════════════════════════════════
func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(Vector2i(cx, cz)) ^ (terrain.seed_value * 7919)
	return r


func _scatter(o: Vector2, with_collision: bool) -> void:
	var rng := _rng()
	var buckets := {}      # id -> {transforms, tints, mesh, wind, height}
	var grass_t: Array = []
	var grass_c: Array = []
	var buf := PackedFloat32Array()
	buf.resize(Terrain.BIOME_COUNT)

	# ── árvores ───────────────────────────────────────────────────────────
	var cells := int(SIZE / TREE_CELL)
	for cj in cells:
		for ci in cells:
			var x := o.x + (ci + rng.randf()) * TREE_CELL
			var z := o.y + (cj + rng.randf()) * TREE_CELL
			var h := terrain.height(x, z)
			var sl := terrain.slope(x, z)
			if h < Terrain.SEA_LEVEL + 0.5 or sl > 0.55:
				continue
			if terrain.path_distance(x, z) < 3.2:
				continue
			if terrain.village_distance(x, z) < Terrain.VILLAGE_RADIUS:
				continue
			var biome := terrain.dominant_s(x, z, h, sl)
			var density := SpeciesKit.tree_density(biome)
			if rng.randf() > density * (TREE_CELL * TREE_CELL) / 100.0:
				continue
			var id := species.pick(species.trees, biome, rng.randf())
			if id.is_empty():
				continue
			var sp: SpeciesKit.Species = species.trees[id]
			var s := rng.randf_range(sp.scale_range.x, sp.scale_range.y)
			var y := h + sp.y_offset * s
			var xform := Transform3D(Basis(Vector3.UP, rng.randf() * TAU)
				.scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s)),
				Vector3(x, y, z))
			var bi := _add(buckets, id, xform, _tint(rng), 0.0)
			harvest_nodes.append({
				"pos": Vector3(x, h, z), "kind": sp.harvest, "species": id,
				"hp": int(Db.HARVEST.get(sp.harvest, {}).get("hp", 5)),
				"radius": 0.9 * s, "height": sp.height * s,
				"alive": true, "bucket": id, "bindex": bi, "chunk": self,
			})
			if with_collision:
				_add_collider(Vector3(x, h + sp.collider_scale.y * s * 0.5, z),
					sp.collider_scale * s)

	# ── rochas ────────────────────────────────────────────────────────────
	var rc := int(SIZE / ROCK_CELL)
	for cj in rc:
		for ci in rc:
			var x := o.x + (ci + rng.randf()) * ROCK_CELL
			var z := o.y + (cj + rng.randf()) * ROCK_CELL
			var h := terrain.height(x, z)
			if h < Terrain.SEA_LEVEL - 0.5:
				continue
			if terrain.path_distance(x, z) < 2.4:
				continue
			if terrain.village_distance(x, z) < Terrain.VILLAGE_RADIUS * 0.7:
				continue
			var sl := terrain.slope(x, z)
			var biome := terrain.dominant_s(x, z, h, sl)
			if rng.randf() > 0.30:
				continue
			var id := species.pick(species.rocks, biome, rng.randf())
			if id.is_empty():
				continue
			var sp: SpeciesKit.Species = species.rocks[id]
			var s := rng.randf_range(sp.scale_range.x, sp.scale_range.y)
			var xform := Transform3D(Basis(Vector3.UP, rng.randf() * TAU)
				.scaled(Vector3(s, s * rng.randf_range(0.7, 1.1), s)),
				Vector3(x, h + sp.y_offset * s, z))
			var bi := _add(buckets, id, xform, _tint(rng), 0.0)
			if sp.harvest != "":
				harvest_nodes.append({
					"pos": Vector3(x, h, z), "kind": sp.harvest, "species": id,
					"hp": int(Db.HARVEST.get(sp.harvest, {}).get("hp", 3)),
					"radius": 0.8 * s, "height": 0.8 * s,
					"alive": true, "bucket": id, "bindex": bi, "chunk": self,
				})
				if with_collision:
					_add_collider(Vector3(x, h + 0.3 * s, z), Vector3(0.9, 0.8, 0.9) * s)

	# ── plantas ───────────────────────────────────────────────────────────
	var pc := int(SIZE / 2.5)
	for cj in pc:
		for ci in pc:
			if rng.randf() > 0.28:
				continue
			var x := o.x + (ci + rng.randf()) * 2.5
			var z := o.y + (cj + rng.randf()) * 2.5
			var h := terrain.height(x, z)
			if h < Terrain.SEA_LEVEL + 0.3:
				continue
			if terrain.path_distance(x, z) < 2.0:
				continue
			var sl := terrain.slope(x, z)
			var biome := terrain.dominant_s(x, z, h, sl)
			var id := species.pick(species.plants, biome, rng.randf())
			if id.is_empty():
				continue
			var sp: SpeciesKit.Species = species.plants[id]
			var s := rng.randf_range(sp.scale_range.x, sp.scale_range.y)
			var bi := _add(buckets, id, Transform3D(Basis(Vector3.UP, rng.randf() * TAU)
				.scaled(Vector3(s, s, s)), Vector3(x, h + sp.y_offset * s, z)),
				_tint(rng), 0.0)
			harvest_nodes.append({
				"pos": Vector3(x, h, z), "kind": sp.harvest, "species": id,
				"hp": 1, "radius": 0.9, "height": sp.height * s,
				"alive": true, "bucket": id, "bindex": bi, "chunk": self,
			})

	# ── relva (só MultiMesh, sem colisão, com fade por distância) ─────────
	if lod <= 1:
		var target := int(GRASS_TARGET * [0.35, 1.0, 2.0][clampi(grass_quality, 0, 2)])
		if lod == 1:
			target = int(target * 0.35)
		var placed := 0
		var guard := 0
		while placed < target and guard < target * 6:
			guard += 1
			var x := o.x + rng.randf() * SIZE
			var z := o.y + rng.randf() * SIZE
			var h := terrain.height(x, z)
			if h < Terrain.SEA_LEVEL + 0.35:
				continue
			var sl := terrain.slope(x, z)
			if sl > 0.5:
				continue
			if terrain.path_distance(x, z) < 2.2:
				continue
			var biome := terrain.dominant_s(x, z, h, sl)
			if rng.randf() > SpeciesKit.grass_density(biome) * 2.2:
				continue
			var s := rng.randf_range(0.75, 1.35)
			grass_t.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU)
				.scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(x, h - 0.03, z)))
			grass_c.append(terrain.ground_color_s(x, z, h, sl, buf).lightened(rng.randf_range(-0.05, 0.12)))
			placed += 1

	# ── cria os MultiMesh ─────────────────────────────────────────────────
	_buckets = buckets
	for id in buckets:
		_make_multimesh(str(id), buckets[id])
	_grass_multimesh(grass_t, grass_c)


func _tint(rng: RandomNumberGenerator) -> Color:
	var v := rng.randf_range(-0.09, 0.11)
	return Color(1.0 + v, 1.0 + v * 0.7, 1.0 + v * 0.5)


func _add(buckets: Dictionary, id: String, xform: Transform3D, tint: Color, fade: float) -> int:
	if not buckets.has(id):
		buckets[id] = {"t": [], "c": [], "fade": fade, "mm": null}
	(buckets[id]["t"] as Array).append(xform)
	(buckets[id]["c"] as Array).append(tint)
	return (buckets[id]["t"] as Array).size() - 1


func _make_multimesh(id: String, b: Dictionary) -> void:
	var t: Array = b["t"]
	var c: Array = b["c"]
	if t.is_empty():
		return
	var sp: SpeciesKit.Species = null
	var mesh: ArrayMesh = null
	if species.trees.has(id):
		sp = species.trees[id]
	elif species.rocks.has(id):
		sp = species.rocks[id]
	elif species.plants.has(id):
		sp = species.plants[id]
	if sp == null:
		return
	mesh = sp.lods[clampi(lod, 0, sp.lods.size() - 1)]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = t.size()
	for i in t.size():
		mm.instance_set_transform(i, t[i])
		var tint: Color = c[i]
		mm.instance_set_custom_data(i, Color(tint.r, tint.g, tint.b, float(b["fade"])))
	b["mm"] = mm
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mats.foliage
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	inst.visibility_range_end = 0.0
	add_child(inst)
	_decor.append(inst)


func _grass_multimesh(t: Array, c: Array) -> void:
	if t.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(cx, cz)) ^ 0x9E37
	var mesh := MeshKit.grass_tuft(rng, 4, 0.62, 0.05, Color(1, 1, 1))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = t.size()
	var fade: float = [30.0, 55.0, 85.0][clampi(grass_quality, 0, 2)]
	for i in t.size():
		mm.instance_set_transform(i, t[i])
		var col: Color = c[i]
		mm.instance_set_custom_data(i, Color(col.r, col.g, col.b, fade))
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mats.grass
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(inst)
	_decor.append(inst)


func _add_collider(pos: Vector3, size: Vector3) -> void:
	if _body == null:
		return
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = maxf(size.x, size.z) * 0.5
	shape.height = maxf(size.y, 0.4)
	col.shape = shape
	col.position = pos - _body.position
	_body.add_child(col)
	_colliders.append(col)


## Esconde a instância de um nó já colhido (MultiMesh não tem "hide").
func hide_harvest(n: Dictionary) -> void:
	n["alive"] = false
	var bid := str(n.get("bucket", ""))
	if not _buckets.has(bid):
		return
	var b: Dictionary = _buckets[bid]
	if b.get("mm") == null:
		return
	var mm: MultiMesh = b["mm"]
	var i := int(n.get("bindex", -1))
	if i < 0 or i >= mm.instance_count:
		return
	mm.instance_set_transform(i, Transform3D(
		Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), n["pos"]))


func set_lod(new_lod: int, with_collision: bool) -> void:
	if new_lod == lod and built:
		return
	lod = new_lod
	release()
	build(with_collision)


func release() -> void:
	for d in _decor:
		if is_instance_valid(d):
			d.queue_free()
	_decor.clear()
	if is_instance_valid(_mesh_inst):
		_mesh_inst.queue_free()
		_mesh_inst = null
	if is_instance_valid(_body):
		_body.queue_free()
		_body = null
	_colliders.clear()
	harvest_nodes.clear()
	_buckets.clear()
	built = false
