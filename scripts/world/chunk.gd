class_name Chunk
extends Node3D
## Chunk — um quadrado de mundo gerado, usado e devolvido.
##
## Um chunk tem: malha de terreno + colisão (só nos níveis perto) + MultiMesh por
## espécie (árvores, rochas, plantas) + um registo dos nós colhíveis.
## Nada aqui é guardado entre chunks: o mundo é sempre rederivado do Terrain.

const SIZE := 48.0
## Altura da saia. Era 5.0: uma parede de 5 m à volta de cada chunk, visível
## como uma grelha de muros. 1.2 m chega para tapar as costuras entre LODs e
## lê-se como sombra de contacto, não como arquitectura.
const SKIRT := 1.2
const RES := [48, 24, 12, 6]       # detalhe cai por faixa; o anel distante só desenha terreno
const TREE_CELL := 3.0
const ROCK_CELL := 6.0
const WATER_LOD_RES := [24, 16, 12, 8] # costa suave perto, malha reduzida ao longe
const GRASS_SHELL_HEIGHT := 0.36

var cx := 0
var cz := 0
var lod := 0
var built := false

var terrain: Terrain
var species: SpeciesKit
var mats: Materials
var water_root: Node3D

## Nós colhíveis deste chunk: {pos, kind, species, hp, node}
var world: Node = null                # definido pelo World; usado para respawn
var harvest_nodes: Array = []

var _mesh_inst: MeshInstance3D
var _grass_shell_inst: MeshInstance3D
var _grass_cards_inst: MultiMeshInstance3D
var _water_inst: MeshInstance3D
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
	_build_water(o)
	if lod < 3:
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
	var grass_cover := PackedFloat32Array()
	grass_cover.resize(n * n)
	var grass_dryness := PackedFloat32Array()
	grass_dryness.resize(n * n)
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
			var gc := terrain.ground_color_s(x, z, h, sl, buf)
			grass_cover[j * n + i] = terrain.grass_coverage_s(h, sl, buf)
			grass_dryness[j * n + i] = terrain.grass_dryness(buf)
			# classes de material para o shader do terreno (ver toon_terrain.gdshader)
			gc.a = clampf(buf[Terrain.B_SNOW], 0.0, 1.0)
			st.set_color(gc)
			st.set_uv(Vector2(
				buf[Terrain.B_MEADOW] + buf[Terrain.B_FOREST] + buf[Terrain.B_GROVE]
					+ buf[Terrain.B_SAVANNA] * 0.8 + buf[Terrain.B_MARSH] * 0.6,
				buf[Terrain.B_DIRT] + buf[Terrain.B_MUD] + buf[Terrain.B_MARSH] * 0.4
					+ buf[Terrain.B_SAVANNA] * 0.2))
			st.set_uv2(Vector2(
				buf[Terrain.B_SAND] + buf[Terrain.B_DESERT],
				buf[Terrain.B_BADLANDS]))
			st.add_vertex(Vector3(x, h, z))

	for j in res:
		for i in res:
			var a := j * n + i
			var b := j * n + i + 1
			var c := (j + 1) * n + i + 1
			var d := (j + 1) * n + i
			st.add_index(a); st.add_index(b); st.add_index(c)
			st.add_index(a); st.add_index(c); st.add_index(d)

	# 3) SEM SAIA.
	#    A saia (parede vertical à volta do chunk) foi removida. Medida com
	#    tools/render_shot.py (o rasterizador por software que dá olhos a este
	#    projecto): de qualquer ângulo baixo ou debaixo de água, a saia aparecia
	#    como uma franja de dentes cinzentos nos limites dos chunks — exactamente
	#    o "faixas verticais que acompanham o terreno" reportado. Apontá-la para
	#    fora ou para dentro só trocava o ângulo em que fazia lixo; a única forma
	#    de a franja desaparecer é não a desenhar. As costuras entre LODs ficam
	#    tapadas pelo próprio overlap das grelhas vizinhas (passo partilhado).

	var mesh := st.commit()
	mesh.surface_set_material(0, mats.terrain)
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = mesh
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_mesh_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_mesh_inst)
	if lod < 3:
		# Mantém os mesmos níveis de altura nos três LODs para não abrir uma
		# costura vertical quando dois chunks vizinhos usam resoluções distintas.
		var shell_layers := 8
		_build_grass_shells(o, n, step, heights, normals, grass_cover,
			grass_dryness, shell_layers)
	if lod == 0:
		_build_grass_cards(o, n, step, heights, normals, grass_cover, grass_dryness)

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


## Relva shell: o mesmo terreno é desenhado em fatias finas. O shader recorta
## cada lâmina num passe opaco, reduzindo a largura até à ponta, e anima os
## níveis superiores para o vento parecer mover um volume contínuo.
func _build_grass_shells(o: Vector2, n: int, step: float,
		heights: PackedFloat32Array, normals: PackedVector3Array,
		coverage: PackedFloat32Array, dryness: PackedFloat32Array, layers: int) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var layer_vertices := n * n
	for layer in layers:
		var layer_t := float(layer + 1) / float(layers)
		for j in n:
			for i in n:
				var idx := j * n + i
				var x := o.x + i * step
				var z := o.y + j * step
				var normal := normals[idx]
				var pos := Vector3(x, heights[idx], z) + normal * GRASS_SHELL_HEIGHT * layer_t
				st.set_normal(normal)
				st.set_color(Color(coverage[idx], dryness[idx], 0.0, 1.0))
				st.set_uv(Vector2(x, z))
				st.set_uv2(Vector2(layer_t, 0.0))
				st.add_vertex(pos)
		var base := layer * layer_vertices
		for j in RES[clampi(lod, 0, RES.size() - 1)]:
			for i in RES[clampi(lod, 0, RES.size() - 1)]:
				var a: int = base + j * n + i
				var b: int = a + 1
				var c: int = a + n + 1
				var d: int = a + n
				st.add_index(a); st.add_index(b); st.add_index(c)
				st.add_index(a); st.add_index(c); st.add_index(d)
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	mesh.surface_set_material(0, mats.grass_shell)
	_grass_shell_inst = MeshInstance3D.new()
	_grass_shell_inst.name = "GrassShells"
	_grass_shell_inst.mesh = mesh
	_grass_shell_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grass_shell_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_grass_shell_inst.extra_cull_margin = 0.8
	add_child(_grass_shell_inst)
	_decor.append(_grass_shell_inst)


## Folhas mais largas perto do jogador. Uma malha partilhada é desenhada por
## MultiMesh; cobertura, inclinação e secura vêm da grelha já calculada para o
## terreno, evitando amostrar ruído procedural outra vez para cada tufo.
func _build_grass_cards(o: Vector2, n: int, step: float,
		heights: PackedFloat32Array, normals: PackedVector3Array,
		coverage: PackedFloat32Array, dryness: PackedFloat32Array) -> void:
	if mats.grass_card_mesh == null:
		return
	var quality := clampi(int(Game.settings.get("quality", 1)), 0, 2)
	var spacing: float = [1.02, 0.90, 0.80][quality]
	var cells: int = int(ceil(SIZE / spacing))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cx, terrain.seed_value, cz))
	var transforms: Array[Transform3D] = []
	var instance_data: Array[Color] = []
	for iz in cells:
		for ix in cells:
			var x: float = o.x + (float(ix) + rng.randf_range(0.08, 0.92)) * spacing
			var z: float = o.y + (float(iz) + rng.randf_range(0.08, 0.92)) * spacing
			if x >= o.x + SIZE or z >= o.y + SIZE:
				continue
			var field := _sample_grass_grid(coverage, n, step, x, z, o)
			if field < 0.07:
				continue
			var density := clampf((field - 0.07) / 0.48, 0.0, 1.0)
			density = density * density * (3.0 - 2.0 * density) * 0.94
			if rng.randf() > density:
				continue
			var dry := _sample_grass_grid(dryness, n, step, x, z, o)
			var height := _sample_grass_grid(heights, n, step, x, z, o)
			var normal := _sample_grass_normal(normals, n, step, x, z, o)
			var orientation := Basis(Quaternion(Vector3.UP, normal)) \
				* Basis(Vector3.UP, rng.randf() * TAU)
			var scale := rng.randf_range(0.82, 1.28)
			var height_scale := scale * lerpf(1.05, 0.78, dry) * rng.randf_range(0.92, 1.12)
			orientation = orientation.scaled(Vector3(scale, height_scale, scale))
			transforms.append(Transform3D(orientation, Vector3(x, height, z)))
			instance_data.append(Color(dry, rng.randf(), 0.0, 1.0))
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mats.grass_card_mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		multimesh.set_instance_custom_data(i, instance_data[i])
	var min_height := heights[0]
	var max_height := heights[0]
	for sampled_height in heights:
		min_height = minf(min_height, sampled_height)
		max_height = maxf(max_height, sampled_height)
	multimesh.custom_aabb = AABB(Vector3(o.x - 2.0, min_height - 2.0, o.y - 2.0),
		Vector3(SIZE + 4.0, max_height - min_height + 5.0, SIZE + 4.0))
	_grass_cards_inst = MultiMeshInstance3D.new()
	_grass_cards_inst.name = "GrassCards"
	_grass_cards_inst.multimesh = multimesh
	_grass_cards_inst.material_override = mats.grass_cards
	_grass_cards_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grass_cards_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_grass_cards_inst.extra_cull_margin = 0.8
	add_child(_grass_cards_inst)
	_decor.append(_grass_cards_inst)


func _sample_grass_grid(values: PackedFloat32Array, n: int, step: float,
		x: float, z: float, o: Vector2) -> float:
	var gx := clampf((x - o.x) / step, 0.0, float(n - 1))
	var gz := clampf((z - o.y) / step, 0.0, float(n - 1))
	var ix := mini(int(floor(gx)), n - 2)
	var iz := mini(int(floor(gz)), n - 2)
	var tx := gx - float(ix)
	var tz := gz - float(iz)
	var a := lerpf(values[iz * n + ix], values[iz * n + ix + 1], tx)
	var b := lerpf(values[(iz + 1) * n + ix], values[(iz + 1) * n + ix + 1], tx)
	return lerpf(a, b, tz)


func _sample_grass_normal(values: PackedVector3Array, n: int, step: float,
		x: float, z: float, o: Vector2) -> Vector3:
	var gx := clampf((x - o.x) / step, 0.0, float(n - 1))
	var gz := clampf((z - o.y) / step, 0.0, float(n - 1))
	var ix := mini(int(floor(gx)), n - 2)
	var iz := mini(int(floor(gz)), n - 2)
	var tx := gx - float(ix)
	var tz := gz - float(iz)
	var a := values[iz * n + ix].lerp(values[iz * n + ix + 1], tx)
	var b := values[(iz + 1) * n + ix].lerp(values[(iz + 1) * n + ix + 1], tx)
	return a.lerp(b, tz).normalized()


## A superfície de água é recortada à altura do terreno em cada chunk. Isto
## deixa a costa visível e cria uma boca contínua para o rio, sem um plano que
## cubra o solo seco ou siga o jogador.
func _build_water(o: Vector2) -> void:
	if water_root == null or mats == null:
		return
	var water_res: int = WATER_LOD_RES[clampi(lod, 0, WATER_LOD_RES.size() - 1)]
	var n := water_res + 1
	var step := SIZE / float(water_res)
	var levels := PackedFloat32Array()
	levels.resize(n * n)
	var depths := PackedFloat32Array()
	depths.resize(n * n)
	var has_water := false
	for j in n:
		for i in n:
			var x := o.x + i * step
			var z := o.y + j * step
			var water_sample := terrain.water_info(x, z)
			var level := water_sample.x
			var idx := j * n + i
			levels[idx] = level
			if level > -99999.0:
				depths[idx] = water_sample.y
			has_water = has_water or level > -99999.0
	if not has_water:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in water_res:
		for i in water_res:
			var a := j * n + i
			var b := a + 1
			var c := a + n + 1
			var d := a + n
			var pa := Vector2(o.x + i * step, o.y + j * step)
			var pb := Vector2(pa.x + step, pa.y)
			var pc := Vector2(pa.x + step, pa.y + step)
			var pd := Vector2(pa.x, pa.y + step)
			_add_clipped_water_triangle(st, pa, levels[a], depths[a], pb, levels[b], depths[b],
				pc, levels[c], depths[c])
			_add_clipped_water_triangle(st, pa, levels[a], depths[a], pc, levels[c], depths[c],
				pd, levels[d], depths[d])
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	mesh.surface_set_material(0, mats.water)
	_water_inst = MeshInstance3D.new()
	_water_inst.name = "WaterSurface_%d_%d" % [cx, cz]
	_water_inst.mesh = mesh
	_water_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	water_root.add_child(_water_inst)


func _add_clipped_water_triangle(st: SurfaceTool, a: Vector2, la: float, da: float,
		b: Vector2, lb: float, db: float, c: Vector2, lc: float, dc: float) -> void:
	var polygon: Array[Dictionary] = [
		{"p": a, "level": la, "depth": da, "wet": la > -99999.0},
		{"p": b, "level": lb, "depth": db, "wet": lb > -99999.0},
		{"p": c, "level": lc, "depth": dc, "wet": lc > -99999.0},
	]
	var clipped: Array[Dictionary] = []
	for i in 3:
		var current: Dictionary = polygon[i]
		var next: Dictionary = polygon[(i + 1) % 3]
		var current_wet := bool(current["wet"])
		var next_wet := bool(next["wet"])
		if current_wet and next_wet:
			clipped.append(next)
		elif current_wet and not next_wet:
			clipped.append(_water_boundary(current, next, true))
		elif not current_wet and next_wet:
			clipped.append(_water_boundary(current, next, false))
			clipped.append(next)
	if clipped.size() < 3:
		return
	for i in range(1, clipped.size() - 1):
		_add_water_face(st, clipped[0], clipped[i], clipped[i + 1])


func _water_boundary(a: Dictionary, b: Dictionary, start_wet: bool) -> Dictionary:
	var pa: Vector2 = a["p"]
	var pb: Vector2 = b["p"]
	var low := 0.0
	var high := 1.0
	for _i in 7:
		var mid := (low + high) * 0.5
		var p := pa.lerp(pb, mid)
		var wet := terrain.water_surface_height(p.x, p.y) > -99999.0
		if wet == start_wet:
			low = mid
		else:
			high = mid
	var wet_t := low if start_wet else high
	var wet_point := pa.lerp(pb, wet_t)
	var level := terrain.water_surface_height(wet_point.x, wet_point.y)
	if level < -99999.0:
		var fallback_t := clampf(wet_t + (0.015 if start_wet else -0.015), 0.0, 1.0)
		var fallback := pa.lerp(pb, fallback_t)
		level = terrain.water_surface_height(fallback.x, fallback.y)
	return {"p": pa.lerp(pb, (low + high) * 0.5), "level": level,
		"depth": 0.0, "wet": true}


func _add_water_face(st: SurfaceTool, a: Dictionary, b: Dictionary, c: Dictionary) -> void:
	var pa: Vector2 = a["p"]
	var pb: Vector2 = b["p"]
	var pc: Vector2 = c["p"]
	var va := Vector3(pa.x, float(a["level"]), pa.y)
	var vb := Vector3(pb.x, float(b["level"]), pb.y)
	var vc := Vector3(pc.x, float(c["level"]), pc.y)
	# Mar fica no nível 0; o rio nasce acima dele e desce até à foz. UV2.y
	# controla a força das ondas, portanto o mar recebe 1 e o rio 0.
	var da := Vector2(float(a["depth"]), 1.0 if float(a["level"]) <= 0.4 else 0.0)
	var db := Vector2(float(b["depth"]), 1.0 if float(b["level"]) <= 0.4 else 0.0)
	var dc := Vector2(float(c["depth"]), 1.0 if float(c["level"]) <= 0.4 else 0.0)
	if (vb - va).cross(vc - va).y < 0.0:
		var swap := vb
		vb = vc
		vc = swap
		var swap_uv := db
		db = dc
		dc = swap_uv
	for vertex in [[va, da], [vb, db], [vc, dc]]:
		var p: Vector3 = vertex[0]
		var water_data: Vector2 = vertex[1]
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(p.x, p.z) * 0.12)
		st.set_uv2(water_data)
		st.add_vertex(p)


# ══════════════════════════════════════════════════════════════════════════
#  VEGETAÇÃO / ROCHAS
# ══════════════════════════════════════════════════════════════════════════
func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(Vector2i(cx, cz)) ^ (terrain.seed_value * 7919)
	return r


func _scatter(o: Vector2, with_collision: bool) -> void:
	var rng := _rng()
	var buckets := {}      # id -> {transforms, tints, mesh, wind, height}
	var seaweed_t: Array[Transform3D] = []
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
			if world != null and world.is_harvested(Vector3(x, h, z), id):
				continue
			var xform := Transform3D(Basis(Vector3.UP, rng.randf() * TAU)
				.scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s)),
				Vector3(x, y, z))
			var bi := _add(buckets, id, xform, _tint(rng), 0.0)
			var tree_collider: CollisionShape3D = null
			if with_collision:
				tree_collider = _add_collider(
					Vector3(x, h + sp.collider_scale.y * s * 0.5, z), sp.collider_scale * s)
			harvest_nodes.append({
				"pos": Vector3(x, h, z), "kind": sp.harvest, "species": id,
				"hp": int(Db.HARVEST.get(sp.harvest, {}).get("hp", 5)),
				"radius": 0.9 * s, "height": sp.height * s,
				"collider_radius": sp.collider_scale.x * s,
				"collider": tree_collider,
				"base_transform": xform,
				"alive": true, "bucket": id, "bindex": bi, "chunk": self,
			})

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
			if sp.harvest != "" and world != null and world.is_harvested(Vector3(x, h, z), id):
				continue
			var s := rng.randf_range(sp.scale_range.x, sp.scale_range.y)
			var xform := Transform3D(Basis(Vector3.UP, rng.randf() * TAU)
				.scaled(Vector3(s, s * rng.randf_range(0.7, 1.1), s)),
				Vector3(x, h + sp.y_offset * s, z))
			var bi := _add(buckets, id, xform, _tint(rng), 0.0)
			if sp.harvest != "":
				var rock_collider: CollisionShape3D = null
				if with_collision:
					rock_collider = _add_collider(Vector3(x, h + 0.3 * s, z),
						Vector3(0.9, 0.8, 0.9) * s)
				harvest_nodes.append({
					"pos": Vector3(x, h, z), "kind": sp.harvest, "species": id,
					"hp": int(Db.HARVEST.get(sp.harvest, {}).get("hp", 3)),
					"radius": 0.8 * s, "height": 0.8 * s,
					"collider": rock_collider,
					"alive": true, "bucket": id, "bindex": bi, "chunk": self,
				})

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
			if world != null and world.is_harvested(Vector3(x, h, z), id):
				continue
			var s := rng.randf_range(sp.scale_range.x, sp.scale_range.y)
			var bi := _add(buckets, id, Transform3D(Basis(Vector3.UP, rng.randf() * TAU)
				.scaled(Vector3(s, s, s)), Vector3(x, h + sp.y_offset * s, z)),
				_tint(rng), 0.0)
			harvest_nodes.append({
				"pos": Vector3(x, h, z), "kind": sp.harvest, "species": id,
				"hp": 1, "radius": 0.9, "height": sp.height * s,
				"alive": true, "bucket": id, "bindex": bi, "chunk": self,
			})

	# ── algas em prateleiras rasas ─────────────────────────────────────────
	# O asset é uma instância MultiMesh; só colocamos em profundidade onde a
	# silhueta fica abaixo da superfície e continua legível através da água.
	if lod == 0 and BlessedBlenderAssets.has_asset("seaweed_cluster"):
		for i in 40:
			var x := o.x + rng.randf() * SIZE
			var z := o.y + rng.randf() * SIZE
			var h := terrain.height(x, z)
			var depth := Terrain.SEA_LEVEL - h
			if not terrain.is_ocean(x, z) or depth < 0.8 or depth > 2.1 or rng.randf() > 0.68:
				continue
			var scale := rng.randf_range(0.55, 0.92)
			seaweed_t.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU)
				.scaled(Vector3(scale, scale, scale)), Vector3(x, h + 0.05, z)))

	# ── cria os MultiMesh ─────────────────────────────────────────────────
	_buckets = buckets
	for id in buckets:
		_make_multimesh(str(id), buckets[id])
	_seaweed_multimesh(seaweed_t)


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
	# Os modelos de copa usam cartões alfa. Mantemos a máscara e os LODs do
	# artista, mas animamos os vértices por instância em vez de deixar folhas imóveis.
	if sp.materials_authored and (species.trees.has(id) or id == "bush"):
		mesh = mats.wind_foliage_mesh(mesh, sp.height)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true  # sem isto a cor de vértice é multiplicada por 0 => preto
	mm.mesh = mesh
	mm.instance_count = t.size()
	var tree_bounds := AABB()
	var has_tree_bounds := false
	for i in t.size():
		var xform: Transform3D = t[i]
		mm.set_instance_transform(i, xform)
		mm.set_instance_color(i, Color.WHITE)
		var tint: Color = c[i]
		mm.set_instance_custom_data(i, Color(tint.r, tint.g, tint.b, float(b["fade"])))
		if species.trees.has(id) or id == "bush":
			# O shader abana as copas para fora da caixa estática da malha; fornece
			# limites conservadores por chunk para o culling não cortar folhas ao vento.
			var scale_x := xform.basis.x.length()
			var scale_y := xform.basis.y.length()
			var scale_z := xform.basis.z.length()
			var radius := maxf(1.5, sp.height * 0.45) * maxf(scale_x, scale_z) + 0.8
			var p: Vector3 = xform.origin
			var low := Vector3(p.x - radius, p.y - 1.0, p.z - radius)
			var high := Vector3(p.x + radius, p.y + sp.height * scale_y + 1.0,
				p.z + radius)
			if not has_tree_bounds:
				tree_bounds = AABB(low, high - low)
				has_tree_bounds = true
			else:
				tree_bounds = tree_bounds.expand(low).expand(high)
	if has_tree_bounds:
		mm.custom_aabb = tree_bounds
	b["mm"] = mm
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = null if sp.materials_authored else mats.foliage
	var keeps_realtime_shadow := lod == 0 and species.trees.has(id)
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if keeps_realtime_shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	inst.visibility_range_end = 0.0
	add_child(inst)
	_decor.append(inst)


func _seaweed_multimesh(transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var mesh := BlessedBlenderAssets.mesh_for("seaweed_cluster")
	if mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = "UnderwaterSeaweed"
	inst.multimesh = mm
	inst.material_override = mats.foliage
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(inst)
	_decor.append(inst)


func _add_collider(pos: Vector3, size: Vector3) -> CollisionShape3D:
	if _body == null:
		return null
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = maxf(size.x, size.z) * 0.5
	shape.height = maxf(size.y, 0.4)
	col.shape = shape
	col.position = pos - _body.position
	_body.add_child(col)
	_colliders.append(col)
	return col


## Esconde a instância de um nó já colhido (MultiMesh não tem "hide").
func hide_harvest(n: Dictionary) -> void:
	n["alive"] = false
	if str(n.get("kind", "")).begins_with("tree"):
		if world != null and world.has_method("fell_tree"):
			world.call("fell_tree", n)
	var old_collider := n.get("collider") as CollisionShape3D
	if is_instance_valid(old_collider):
		old_collider.set_deferred("disabled", true)
		old_collider.queue_free()
		_colliders.erase(old_collider)
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
	mm.set_instance_transform(i, Transform3D(
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
	if is_instance_valid(_water_inst):
		var water_parent := _water_inst.get_parent()
		if water_parent != null:
			water_parent.remove_child(_water_inst)
		_water_inst.queue_free()
		_water_inst = null
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
