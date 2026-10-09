class_name SpeciesKit
extends RefCounted
## SpeciesKit — as "peças de LEGO" do mundo.
##
## Poucas espécies, bem feitas, com 3 níveis de detalhe cada. O gestor de chunks
## escolhe o LOD pela distância e reutiliza sempre a mesma malha: a variedade
## vem da semente (escala, rotação, tinta), não de geometria nova.

class Species extends RefCounted:
	var id: String
	var lods: Array[ArrayMesh] = []      # 0 = perto, 2 = longe
	var tint: Color = Color.WHITE
	var scale_range := Vector2(0.85, 1.2)
	var biomes: PackedInt32Array = PackedInt32Array()
	var weight: float = 1.0
	var harvest: String = ""
	var y_offset: float = 0.0            # quanto enterra no chão
	var collider_scale := Vector3.ONE    # para o collision shape
	var height: float = 1.0              # altura útil (sombra, som)
	var wind: float = 0.0                # 0 = rígido, 1 = balança muito


class Structure extends RefCounted:
	var id: String
	var mesh: ArrayMesh
	var size := Vector3.ONE
	var solid: bool = true
	var light: float = 0.0


var rng := RandomNumberGenerator.new()
var trees: Dictionary = {}     # id -> Species
var rocks: Dictionary = {}
var plants: Dictionary = {}
var structures: Dictionary = {}  # id -> Structure


func _init(seed_value: int) -> void:
	rng.seed = seed_value ^ 0xC0FFEE
	_build_trees()
	_build_rocks()
	_build_plants()
	_build_structures()


func _trunk(h: float, rb: float, rt: float, seg: int, tint: Color) -> ArrayMesh:
	return MeshKit.tapered(rng, h, rb, rt, seg, 4, 0.1, true, tint)


func _merge(parts: Array) -> ArrayMesh:
	## Junta várias malhas numa só (menos draw calls, um só MultiMesh por espécie).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for m in parts:
		st.append_from(m, 0, Transform3D.IDENTITY)
	return st.commit()


## Constrói uma espécie arbórea com 3 LODs reais (mesma silhueta, menos triângulos).
func _tree(id: String, trunk_h: float, trunk_rb: float, trunk_rt: float,
		trunk_tint: Color, canopy: Array, subdivs: Array, scale_r: Vector2,
		biomes: Array, weight: float, harvest: String, height_m: float,
		wind: float, coll: Vector3) -> Species:
	var s := Species.new()
	s.id = id
	s.tint = Color.WHITE
	s.scale_range = scale_r
	s.weight = weight
	s.harvest = harvest
	s.y_offset = -trunk_h * 0.12
	s.height = height_m
	s.wind = wind
	s.collider_scale = coll
	var b := PackedInt32Array()
	for x in biomes:
		b.append(int(x))
	s.biomes = b
	for li in subdivs.size():
		var lvl := int(subdivs[li])
		# LOD1 corta as bolhas secundárias; LOD2 fica com uma só silhueta.
		var max_blobs := 99
		if li == 1:
			max_blobs = 2
		elif li == 2:
			max_blobs = 1
		var parts: Array = [MeshKit.tapered(rng, trunk_h, trunk_rb, trunk_rt,
			7 if lvl >= 2 else 5, 3, 0.1, true, trunk_tint)]
		for bi in canopy.size():
			if bi >= max_blobs:
				break
			var c: Dictionary = canopy[bi]
			var blob := MeshKit.blob(rng, float(c["r"]), lvl, float(c.get("jit", 0.18)),
				c.get("scale", Vector3.ONE), c.get("tint", Color.WHITE))
			parts.append(_offset(blob, c["pos"]))
		s.lods.append(_merge(parts))
	return s


## Gera as bolhas de copa de forma determinista.
func _canopy(count: int, rmin: float, rmax: float, ybase: float, yspread: float,
		spread: float, tint: Color) -> Array:
	var out := []
	for i in count:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, spread)
		out.append({
			"r": rng.randf_range(rmin, rmax),
			"pos": Vector3(cos(a) * r, ybase + rng.randf_range(-0.25, yspread), sin(a) * r),
			"scale": Vector3(1.08, 0.82, 1.08),
			"tint": tint,
			"skip_far": i > 1,
		})
	return out


func _build_trees() -> void:
	# ── carvalho: copa larga em bolhas, a árvore "de sombra" ──────────────
	trees["oak"] = _tree("oak", 2.2, 0.30, 0.16, Color(0.42, 0.29, 0.21),
		_canopy(5, 0.95, 1.25, 2.15, 0.5, 0.85, Color(0.30, 0.72, 0.34)),
		[1, 1, 0], Vector2(0.9, 1.35), [Terrain.B_MEADOW, Terrain.B_FOREST], 1.0,
		"tree_oak", 3.6, 0.55, Vector3(0.7, 3.4, 0.7))

	# ── bétula: tronco claro, copa pequena e clara ────────────────────────
	trees["birch"] = _tree("birch", 3.0, 0.17, 0.10, Color(0.86, 0.85, 0.80),
		_canopy(4, 0.7, 0.95, 2.6, 0.5, 0.6, Color(0.55, 0.80, 0.36)),
		[1, 1, 0], Vector2(0.85, 1.25),
		[Terrain.B_FOREST, Terrain.B_MEADOW, Terrain.B_SNOW], 0.8,
		"tree_birch", 3.8, 0.7, Vector3(0.45, 3.6, 0.45))

	# ── cerejeira: a assinatura anime ─────────────────────────────────────
	trees["sakura"] = _tree("sakura", 2.0, 0.26, 0.14, Color(0.40, 0.26, 0.26),
		_canopy(6, 0.85, 1.15, 2.0, 0.55, 0.95, Color(1.0, 0.68, 0.82)),
		[1, 1, 0], Vector2(0.95, 1.3), [Terrain.B_GROVE, Terrain.B_MEADOW], 1.0,
		"tree_sakura", 3.2, 0.85, Vector3(0.6, 3.0, 0.6))

	# ── pinheiro: cones empilhados (mais barato e lê-se bem ao longe) ─────
	var pine := Species.new()
	pine.id = "pine"
	pine.tint = Color.WHITE
	pine.scale_range = Vector2(0.9, 1.4)
	pine.weight = 1.0
	pine.harvest = "tree_pine"
	pine.y_offset = -0.2
	pine.height = 4.8
	pine.wind = 0.25
	pine.collider_scale = Vector3(0.6, 4.6, 0.6)
	var pb := PackedInt32Array([Terrain.B_FOREST, Terrain.B_ROCK, Terrain.B_SNOW])
	pine.biomes = pb
	for segs in [9, 6, 4]:
		var parts: Array = [MeshKit.tapered(rng, 3.4, 0.22, 0.10, segs, 3, 0.05, true,
			Color(0.34, 0.24, 0.18))]
		for i in 4:
			var t := float(i) / 3.0
			parts.append(_offset(
				MeshKit.cone(lerpf(1.5, 0.55, t), lerpf(1.5, 1.1, t), segs, Color(0.16, 0.42, 0.26)),
				Vector3(0, 0.9 + t * 2.6, 0)))
		pine.lods.append(_merge(parts))
	trees["pine"] = pine


func _build_rocks() -> void:
	for i in 3:
		var m := MeshKit.rock(rng, lerpf(0.55, 1.15, float(i) / 2.0))
		var s := Species.new()
		s.id = "rock_%d" % i
		s.lods = [m, m, m]
		s.tint = Color(0.85, 0.85, 0.92)
		s.scale_range = Vector2(0.8, 1.5)
		s.biomes = PackedInt32Array([Terrain.B_ROCK, Terrain.B_MEADOW, Terrain.B_SAND, Terrain.B_MARSH])
		s.weight = 1.0 if i != 2 else 0.45
		s.harvest = "rock"
		s.y_offset = -0.18
		s.height = 1.0
		s.collider_scale = Vector3.ONE
		rocks[s.id] = s
	# pedregulho pequeno que se apanha à mão
	var flint := MeshKit.rock(rng, 0.24)
	var fs := Species.new()
	fs.id = "flint_node"
	fs.lods = [flint, flint, flint]
	fs.tint = Color(0.7, 0.7, 0.75)
	fs.scale_range = Vector2(0.7, 1.2)
	fs.biomes = PackedInt32Array([Terrain.B_SAND, Terrain.B_ROCK, Terrain.B_MEADOW])
	fs.weight = 0.5
	fs.harvest = "flint_node"
	fs.y_offset = -0.05
	fs.height = 0.3
	rocks["flint_node"] = fs


func _build_plants() -> void:
	# arbusto de bagas
	var bush := MeshKit.blob(rng, 0.42, 2, 0.24, Vector3(1.15, 0.85, 1.15), Color(0.24, 0.55, 0.28))
	var bs := Species.new()
	bs.id = "bush"
	bs.lods = [bush, bush, bush]
	bs.tint = Color(1, 1, 1)
	bs.scale_range = Vector2(0.8, 1.3)
	bs.biomes = PackedInt32Array([Terrain.B_MEADOW, Terrain.B_FOREST, Terrain.B_GROVE])
	bs.weight = 1.0
	bs.harvest = "bush"
	bs.y_offset = -0.1
	bs.height = 0.7
	bs.wind = 1.0
	plants["bush"] = bs

	# cogumelo
	var mush_parts: Array = [
		MeshKit.tapered(rng, 0.16, 0.045, 0.05, 5, 1, 0.0, false, Color(0.92, 0.88, 0.8)),
		_offset(MeshKit.cone(0.16, 0.13, 8, Color(0.86, 0.30, 0.28)), Vector3(0, 0.14, 0)),
	]
	var ms := Species.new()
	ms.id = "mushroom"
	ms.lods = [_merge(mush_parts), _merge(mush_parts), _merge(mush_parts)]
	ms.scale_range = Vector2(0.8, 1.4)
	ms.biomes = PackedInt32Array([Terrain.B_FOREST, Terrain.B_MARSH])
	ms.weight = 0.8
	ms.harvest = "mushroom"
	ms.height = 0.3
	plants["mushroom"] = ms


func _build_structures() -> void:
	_add_struct("campfire", _merge([
		MeshKit.blob(rng, 0.55, 1, 0.25, Vector3(1.3, 0.45, 1.3), Color(0.55, 0.53, 0.58)),
		_offset(MeshKit.tapered(rng, 0.5, 0.09, 0.05, 5, 2, 0.2, false, Color(0.36, 0.24, 0.18)),
			Vector3(0.05, 0.1, 0)),
		_offset(MeshKit.tapered(rng, 0.45, 0.08, 0.04, 5, 2, -0.25, false, Color(0.42, 0.28, 0.2)),
			Vector3(-0.08, 0.08, 0.05)),
	]), Vector3(1.2, 0.8, 1.2), true, 9.0)

	_add_struct("wall", MeshKit.box(Vector3(3.0, 2.4, 0.28), Color(0.62, 0.44, 0.30)),
		Vector3(3.0, 2.4, 0.28), true, 0.0)
	_add_struct("floor", MeshKit.box(Vector3(3.0, 0.22, 3.0), Color(0.70, 0.52, 0.36)),
		Vector3(3.0, 0.22, 3.0), true, 0.0)
	_add_struct("pillar", MeshKit.box(Vector3(0.34, 2.8, 0.34), Color(0.55, 0.39, 0.27)),
		Vector3(0.34, 2.8, 0.34), true, 0.0)
	_add_struct("bed", _merge([
		MeshKit.box(Vector3(1.1, 0.22, 2.1), Color(0.5, 0.36, 0.25)),
		_offset(MeshKit.box(Vector3(1.0, 0.26, 1.9), Color(0.35, 0.62, 0.35)), Vector3(0, 0.22, 0)),
	]), Vector3(1.1, 0.5, 2.1), true, 0.0)
	_add_struct("torch", _merge([
		MeshKit.tapered(rng, 0.9, 0.06, 0.045, 5, 2, 0.0, false, Color(0.4, 0.28, 0.18)),
		_offset(MeshKit.blob(rng, 0.14, 1, 0.2, Vector3.ONE, Color(1.0, 0.7, 0.3)), Vector3(0, 0.95, 0)),
	]), Vector3(0.3, 1.1, 0.3), false, 5.0)


func _add_struct(id: String, mesh: ArrayMesh, size: Vector3, solid: bool, light: float) -> void:
	var s := Structure.new()
	s.id = id
	s.mesh = mesh
	s.size = size
	s.solid = solid
	s.light = light
	structures[id] = s


## Desloca uma malha (não há forma direta em ArrayMesh, por isso reconstrói).
static func _offset(mesh: ArrayMesh, off: Vector3) -> ArrayMesh:
	## Desloca uma malha sem lhe perder nada.
	##
	## A versão anterior reconstruía a superfície à mão e lia as cores com
	## `int(order[k])`. As malhas do MeshKit NÃO são indexadas, por isso `order`
	## caía no array de vértices e `int(Vector3)` devolve 0: todas as copas
	## ficavam com a cor do vértice 0 — na prática, pretas. `append_from` copia
	## vértices, normais, cores, UV e índices e aplica a transformação.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(mesh, 0, Transform3D(Basis.IDENTITY, off))
	return st.commit()


## Escolhe uma espécie válida para o bioma, com peso.
func pick(pool: Dictionary, biome: int, r: float) -> String:
	var ids: Array = []
	var total := 0.0
	for k in pool:
		var s: Species = pool[k]
		if biome in s.biomes:
			ids.append(k)
			total += s.weight
	if ids.is_empty() or total <= 0.0:
		return ""
	var t := r * total
	for k in ids:
		t -= (pool[k] as Species).weight
		if t <= 0.0:
			return k
	return str(ids.back())


## Densidade de árvores por bioma (árvores por 100 m²).
static func tree_density(biome: int) -> float:
	match biome:
		Terrain.B_FOREST: return 2.6
		Terrain.B_GROVE: return 2.0
		Terrain.B_MEADOW: return 0.35
		Terrain.B_MARSH: return 0.5
		Terrain.B_ROCK: return 0.25
		Terrain.B_SNOW: return 0.35
		Terrain.B_SAND: return 0.05
	return 0.2


## Densidade de relva por bioma (tufos por m²).
static func grass_density(biome: int) -> float:
	match biome:
		Terrain.B_MEADOW: return 0.55
		Terrain.B_FOREST: return 0.35
		Terrain.B_GROVE: return 0.45
		Terrain.B_MARSH: return 0.6
		Terrain.B_ROCK: return 0.08
		Terrain.B_SNOW: return 0.05
		Terrain.B_SAND: return 0.04
	return 0.2
