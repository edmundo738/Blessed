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
	var materials_authored: bool = false # material Blender preservado no GLB
	## Tronco + ramos SEM copa: é o que fica quando a árvore cai. Sem isto a
	## árvore abatida era o modelo inteiro (copa incluída) com o material das
	## FOLHAS — translúcido e sem resposta à luz. Era este o "fica com uma cor
	## esquisita, mais plana, como se a luz já não a afetasse".
	var trunk_lods: Array[ArrayMesh] = []


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
	# metadados data-driven (data/species.json) por cima da geometria gerada
	for id in trees:
		_apply_meta("trees", trees[id])
	for id in rocks:
		_apply_meta("rocks", rocks[id])
	for id in plants:
		_apply_meta("plants", plants[id])


## Aplica metadados data-driven sobre uma espécie já construída (sem dados = nada muda).
func _apply_meta(kind: String, s: Species) -> void:
	var meta := Db.species_meta(kind, s.id)
	if meta.is_empty():
		return
	if meta.has("weight"):
		s.weight = float(meta["weight"])
	if meta.has("harvest"):
		s.harvest = str(meta["harvest"])
	if meta.has("height"):
		s.height = float(meta["height"])
	if meta.has("wind"):
		s.wind = float(meta["wind"])
	var sc = meta.get("scale", null)
	if typeof(sc) == TYPE_ARRAY and sc.size() >= 2:
		s.scale_range = Vector2(float(sc[0]), float(sc[1]))
	var bl = meta.get("biomes", null)
	if typeof(bl) == TYPE_ARRAY:
		var b := PackedInt32Array()
		for bid in bl:
			var idx := Db.biome_index(str(bid))
			if idx >= 0:
				b.append(idx)
		if b.size() > 0:
			s.biomes = b


func _trunk(h: float, rb: float, rt: float, seg: int, tint: Color) -> ArrayMesh:
	return MeshKit.tapered(rng, h, rb, rt, seg, 4, 0.1, true, tint)


func _merge(parts: Array) -> ArrayMesh:
	## Junta várias malhas numa só (menos draw calls, um só MultiMesh por espécie).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for m in parts:
		st.append_from(m, 0, Transform3D.IDENTITY)
	return st.commit()


## Ramo afunilado que liga o tronco às massas da copa.
## Mantém as árvores como um único mesh por espécie/LOD para preservar o batching.
func _branch(start: Vector3, finish: Vector3, radius: float, tint: Color) -> ArrayMesh:
	var delta := finish - start
	if delta.length_squared() < 0.0001:
		return MeshKit.tapered(rng, 0.01, radius, radius * 0.5, 4, 1, 0.0, false, tint)
	var axis := delta.normalized()
	var local_mesh := MeshKit.tapered(rng, delta.length(), radius, radius * 0.38,
		5, 2, 0.04, false, tint)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var basis := Basis(Quaternion(Vector3.UP, axis))
	st.append_from(local_mesh, 0, Transform3D(basis, start))
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
		# cópia só do tronco/ramos, feita ANTES de entrarem as bolhas de copa
		var trunk_parts: Array = parts.duplicate()
		for bi in canopy.size():
			if bi >= max_blobs:
				break
			var c: Dictionary = canopy[bi]
			# Ramos visíveis apenas nos LOD próximos; o LOD distante conserva a silhueta
			# com menos triângulos e não acrescenta custo de geometria onde mal se nota.
			if li < 2 and bi < (2 if li == 1 else canopy.size()):
				var branch_end: Vector3 = c["pos"] * 0.76
				var branch_start := Vector3(0.0, trunk_h * 0.46, 0.0)
				var branch := _branch(branch_start, branch_end,
					maxf(trunk_rt * 0.55, float(c["r"]) * 0.075), trunk_tint)
				parts.append(branch)
				trunk_parts.append(branch)
			var blob := MeshKit.blob(rng, float(c["r"]), lvl, float(c.get("jit", 0.18)),
				c.get("scale", Vector3.ONE), c.get("tint", Color.WHITE))
			parts.append(_offset(blob, c["pos"]))
		s.lods.append(_merge(parts))
		s.trunk_lods.append(_merge(trunk_parts))
	var blender_lods := BlessedBlenderAssets.lods_for("tree_" + id)
	if not blender_lods.is_empty():
		s.lods = blender_lods
		# Um GLB é uma malha só: não há tronco separado. A árvore abatida usa o
		# modelo inteiro (aceitável: é o que o artista desenhou) — o que NÃO se
		# aceita é ela levar o material das folhas.
		s.trunk_lods = blender_lods
		s.materials_authored = true
		# Imported models use a ground-level origin; do not sink their root into terrain.
		s.y_offset = 0.0
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


## Arbusto em grupos de folhas sobrepostos, com silhueta estável em cada LOD.
func _shrub(lobes: int, radius: float, tint: Color) -> ArrayMesh:
	var parts: Array = []
	for i in lobes:
		var angle := float(i) / float(lobes) * TAU
		var ring := radius * (0.28 if i > 0 else 0.0)
		var pos := Vector3(cos(angle) * ring, radius * (0.34 if i > 0 else 0.48), sin(angle) * ring)
		var leaf_tint := tint.lightened(rng.randf_range(-0.06, 0.09))
		var leaf := MeshKit.blob(rng, radius * rng.randf_range(0.42, 0.58), 1,
			0.16, Vector3(1.0, 0.82, 1.0), leaf_tint)
		parts.append(_offset(leaf, pos))
	return _merge(parts)


func _build_trees() -> void:
	# ── carvalho: copa larga em bolhas, a árvore "de sombra" ──────────────
	trees["oak"] = _tree("oak", 3.5, 0.38, 0.18, Color(0.42, 0.29, 0.21),
		_canopy(7, 1.05, 1.45, 3.5, 0.7, 1.1, Color(0.30, 0.72, 0.34)),
		[2, 1, 0], Vector2(0.92, 1.28), [Terrain.B_MEADOW, Terrain.B_FOREST], 1.0,
		"tree_oak", 6.8, 0.55, Vector3(0.9, 6.2, 0.9))

	# ── bétula: tronco claro, copa pequena e clara ────────────────────────
	trees["birch"] = _tree("birch", 4.5, 0.21, 0.08, Color(0.86, 0.85, 0.80),
		_canopy(5, 0.72, 1.0, 4.2, 0.7, 0.8, Color(0.55, 0.80, 0.36)),
		[2, 1, 0], Vector2(0.88, 1.24),
		[Terrain.B_FOREST, Terrain.B_MEADOW, Terrain.B_SNOW], 0.8,
		"tree_birch", 7.1, 0.7, Vector3(0.6, 6.9, 0.6))

	# ── cerejeira: a assinatura anime ─────────────────────────────────────
	trees["sakura"] = _tree("sakura", 3.2, 0.31, 0.14, Color(0.40, 0.26, 0.26),
		_canopy(7, 0.95, 1.28, 3.0, 0.65, 1.0, Color(1.0, 0.68, 0.82)),
		[2, 1, 0], Vector2(0.95, 1.25), [Terrain.B_GROVE, Terrain.B_MEADOW], 1.0,
		"tree_sakura", 5.8, 0.85, Vector3(0.8, 5.5, 0.8))

	# Salgueiro: copa pendente, frequente apenas em bosques húmidos.
	trees["willow"] = _tree("willow", 4.0, 0.31, 0.12, Color(0.42, 0.29, 0.21),
		_canopy(6, 0.95, 1.3, 4.1, 0.7, 1.25, Color(0.34, 0.65, 0.32)),
		[2, 1, 0], Vector2(0.92, 1.3), [Terrain.B_GROVE, Terrain.B_MARSH, Terrain.B_MEADOW], 0.58,
		"tree_willow", 7.4, 0.95, Vector3(1.2, 7.0, 1.2))

	# ── pinheiro: cones empilhados (mais barato e lê-se bem ao longe) ─────
	var pine := Species.new()
	pine.id = "pine"
	pine.tint = Color.WHITE
	pine.scale_range = Vector2(0.9, 1.4)
	pine.weight = 1.0
	pine.harvest = "tree_pine"
	pine.y_offset = -0.2
	pine.height = 8.4
	pine.wind = 0.25
	pine.collider_scale = Vector3(0.75, 8.0, 0.75)
	var pb := PackedInt32Array([Terrain.B_FOREST, Terrain.B_ROCK, Terrain.B_SNOW])
	pine.biomes = pb
	for segs in [11, 7, 4]:
		var pine_trunk := MeshKit.tapered(rng, 6.8, 0.27, 0.06, segs, 3, 0.05, true,
			Color(0.34, 0.24, 0.18))
		var parts: Array = [pine_trunk]
		# o abate do pinheiro fica com o mastro, sem os cones (que são as folhas)
		pine.trunk_lods.append(pine_trunk)
		for i in 7:
			var t := float(i) / 6.0
			parts.append(_offset(
				MeshKit.cone(lerpf(1.9, 0.42, t), lerpf(1.65, 0.34, t), segs,
					Color(0.16, 0.42, 0.26).lightened(t * 0.08)),
				Vector3(0, 0.9 + t * 5.7, 0)))
		pine.lods.append(_merge(parts))
	var pine_lods := BlessedBlenderAssets.lods_for("tree_pine")
	if not pine_lods.is_empty():
		pine.lods = pine_lods
		pine.materials_authored = true
		pine.y_offset = 0.0
	trees["pine"] = pine


func _build_rocks() -> void:
	var blender_rocks := BlessedBlenderAssets.lods_for("rock_cluster")
	for i in 3:
		var m: ArrayMesh = blender_rocks[clampi(i, 0, blender_rocks.size() - 1)] \
			if not blender_rocks.is_empty() else \
			MeshKit.rock(rng, lerpf(0.55, 1.15, float(i) / 2.0))
		var s := Species.new()
		s.id = "rock_%d" % i
		if blender_rocks.is_empty():
			# ATENÇÃO: `s.lods = A if cond else [m, m, m]` NÃO funciona — o array
			# literal não sobrevive à conversão para Array[ArrayMesh] dentro do
			# ternário e o resultado saía VAZIO (medido nesta build: tamanho 0).
			# Espécie sem LODs = MultiMesh com mesh=null: as rochas não apareciam
			# no mundo e a instância morta rebentava a build web a quem lhe lesse
			# a malha. Com o array tipado construído à parte fica correto.
			var fallback: Array[ArrayMesh] = [m, m, m]
			s.lods = fallback
		else:
			s.lods = blender_rocks
		s.tint = Color(0.85, 0.85, 0.92)
		s.scale_range = Vector2(0.8, 1.5)
		s.biomes = PackedInt32Array([Terrain.B_ROCK, Terrain.B_MEADOW, Terrain.B_SAND, Terrain.B_MARSH])
		s.weight = 1.0 if i != 2 else 0.45
		s.harvest = "rock"
		s.y_offset = -0.18
		s.height = 1.0
		s.collider_scale = Vector3.ONE
		s.materials_authored = not blender_rocks.is_empty()
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
	# Arbusto simples; a recolha fornece fibra e folhas, sem fruto inventado.
	var bs := Species.new()
	bs.id = "bush"
	bs.lods = [_shrub(7, 0.50, Color(0.24, 0.55, 0.28)),
		_shrub(4, 0.50, Color(0.24, 0.55, 0.28)),
		_shrub(2, 0.50, Color(0.24, 0.55, 0.28))]
	var bush_lods := BlessedBlenderAssets.lods_for("plant_bush")
	if not bush_lods.is_empty():
		bs.lods = bush_lods
		bs.materials_authored = true
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
	var mushroom_lods := BlessedBlenderAssets.lods_for("plant_mushroom")
	if not mushroom_lods.is_empty():
		ms.lods = mushroom_lods
		ms.materials_authored = true
	ms.scale_range = Vector2(0.8, 1.4)
	ms.biomes = PackedInt32Array([Terrain.B_FOREST, Terrain.B_MARSH])
	ms.weight = 0.8
	ms.harvest = "mushroom"
	ms.height = 0.3
	plants["mushroom"] = ms


func _build_structures() -> void:
	# Fogueira. Antes era um chumaço de pedra com dois pauzinhos — não lia como
	# lareira e não dava vontade de acender. Agora tem as três coisas que fazem
	# uma fogueira: um ANEL de pedras (o sítio onde se faz), um leito de CINZA
	# (diz que ali já ardeu), e LENHA em estrela inclinada para dentro, que é a
	# forma como se empilha madeira para arder bem. É o objeto central do
	# primeiro dia; tem de se reconhecer de longe.
	var fogo: Array = [MeshKit.blob(rng, 0.44, 1, 0.16, Vector3(1.25, 0.26, 1.25),
		Color(0.21, 0.20, 0.20))]
	for i in 9:
		var a := TAU * float(i) / 9.0 + 0.15
		var raio := 0.46 + (0.04 if i % 2 == 0 else 0.0)
		# Pedra de granito, um pouco escurecida na cara interior (a que apanha
		# com a cinza): pedras brancas de cal faziam a fogueira parecer um monte
		# de neve.
		var tom := Color(0.52, 0.51, 0.50).lerp(Color(0.66, 0.64, 0.61), float(i % 3) / 2.0)
		fogo.append(_offset(MeshKit.rock(rng, 0.145 + 0.03 * float(i % 3), tom),
			Vector3(cos(a) * raio, 0.045, sin(a) * raio)))
	# Lenha RADIAL: quatro achas deitadas com as pontas a encontrarem-se no
	# centro, sobre o leito de cinza. É assim que se monta uma fogueira de
	# verdade — e lê-se logo como fogueira, mesmo sem chama.
	for i in 4:
		var b := TAU * float(i) / 4.0 + 0.35
		var comp := 0.62 + 0.10 * float(i % 2)
		var lenha: ArrayMesh = MeshKit.tapered(rng, comp, 0.062, 0.048, 5, 2, 0.0, false,
			Color(0.33, 0.21, 0.14))
		var dir := Vector3(-cos(b) * 0.86, 0.51, -sin(b) * 0.86).normalized()
		fogo.append(_placed_rot(lenha, Vector3(cos(b) * 0.34, 0.075, sin(b) * 0.34), dir))
	# Tições queimados no meio (a parte que ficou preta do fogo anterior).
	for i in 3:
		var c := TAU * float(i) / 3.0 + 1.1
		fogo.append(_offset(MeshKit.tapered(rng, 0.30, 0.032, 0.026, 4, 1, 0.55, false,
			Color(0.16, 0.14, 0.13)), Vector3(cos(c) * 0.09, 0.035, sin(c) * 0.09)))
	_add_struct("campfire", _merge(fogo), Vector3(1.3, 0.9, 1.3), true, 9.0)

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
	# Bancada: a mesa onde se fazem ferramentas a sério. Tem de ser visível de
	# longe (é um marco de progressão) — tampo, quatro pernas e ferramentas em
	# cima, para se perceber o que é antes de chegar perto.
	_add_struct("workbench", _merge([
		_offset(MeshKit.box(Vector3(1.5, 0.12, 0.9), Color(0.62, 0.45, 0.30)),
			Vector3(0, 0.92, 0)),
		_offset(MeshKit.box(Vector3(0.13, 0.9, 0.13), Color(0.48, 0.34, 0.22)),
			Vector3(-0.6, 0.45, -0.32)),
		_offset(MeshKit.box(Vector3(0.13, 0.9, 0.13), Color(0.48, 0.34, 0.22)),
			Vector3(0.6, 0.45, -0.32)),
		_offset(MeshKit.box(Vector3(0.13, 0.9, 0.13), Color(0.48, 0.34, 0.22)),
			Vector3(-0.6, 0.45, 0.32)),
		_offset(MeshKit.box(Vector3(0.13, 0.9, 0.13), Color(0.48, 0.34, 0.22)),
			Vector3(0.6, 0.45, 0.32)),
		# uma serra/lâmina e um cabo em cima
		_offset(MeshKit.box(Vector3(0.52, 0.05, 0.11), Color(0.74, 0.74, 0.78)),
			Vector3(-0.28, 1.03, 0.12)),
		_offset(MeshKit.box(Vector3(0.09, 0.09, 0.36), Color(0.4, 0.28, 0.18)),
			Vector3(0.44, 1.02, -0.1)),
	]), Vector3(1.6, 1.06, 1.0), true, 0.0)

	# Cofre: caixa de madeira com tampa e ferragens — lê-se como "guardar".
	_add_struct("chest", _merge([
		MeshKit.box(Vector3(0.94, 0.62, 0.66), Color(0.60, 0.42, 0.26)),
		_offset(MeshKit.box(Vector3(0.98, 0.16, 0.70), Color(0.48, 0.33, 0.20)),
			Vector3(0, 0.36, 0)),
		_offset(MeshKit.box(Vector3(0.16, 0.20, 0.06), Color(0.78, 0.72, 0.42)),
			Vector3(0, 0.22, 0.34)),
	]), Vector3(1.0, 0.86, 0.72), true, 0.0)

	# Cadeira: assento, costas e quatro pernas.
	_add_struct("chair", _merge([
		MeshKit.box(Vector3(0.52, 0.09, 0.50), Color(0.62, 0.45, 0.30)),
		_offset(MeshKit.box(Vector3(0.52, 0.62, 0.09), Color(0.60, 0.43, 0.28)),
			Vector3(0, 0.36, -0.21)),
		_offset(MeshKit.box(Vector3(0.09, 0.46, 0.09), Color(0.48, 0.34, 0.22)),
			Vector3(-0.21, -0.24, -0.2)),
		_offset(MeshKit.box(Vector3(0.09, 0.46, 0.09), Color(0.48, 0.34, 0.22)),
			Vector3(0.21, -0.24, -0.2)),
		_offset(MeshKit.box(Vector3(0.09, 0.46, 0.09), Color(0.48, 0.34, 0.22)),
			Vector3(-0.21, -0.24, 0.2)),
		_offset(MeshKit.box(Vector3(0.09, 0.46, 0.09), Color(0.48, 0.34, 0.22)),
			Vector3(0.21, -0.24, 0.2)),
	]), Vector3(0.6, 1.0, 0.56), false, 0.0)

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


## Como `_offset`, mas com rotação: uma lenha deitada e inclinada para dentro
## não se consegue pôr com uma translação só.
static func _placed_rot(mesh: ArrayMesh, off: Vector3, dir: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up := dir.normalized()
	var right := Vector3(0, 1, 0).cross(up)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var fwd := up.cross(right).normalized()
	st.append_from(mesh, 0, Transform3D(Basis(right, up, fwd), off))
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
	return Db.biome_density(biome, "tree", _tree_density_default(biome))


static func _tree_density_default(biome: int) -> float:
	match biome:
		Terrain.B_FOREST: return 2.6
		Terrain.B_GROVE: return 2.0
		Terrain.B_MEADOW: return 0.35
		Terrain.B_MARSH: return 0.5
		Terrain.B_ROCK: return 0.25
		Terrain.B_SNOW: return 0.35
		Terrain.B_SAND: return 0.05
		Terrain.B_DESERT: return 0.04
		Terrain.B_BADLANDS: return 0.02
		Terrain.B_SAVANNA: return 0.6
		Terrain.B_DIRT: return 0.1
		Terrain.B_MUD: return 0.12
	return 0.2


## Densidade de relva por bioma (tufos por m²).
static func grass_density(biome: int) -> float:
	return Db.biome_density(biome, "grass", _grass_density_default(biome))


static func _grass_density_default(biome: int) -> float:
	match biome:
		Terrain.B_MEADOW: return 0.55
		Terrain.B_FOREST: return 0.35
		Terrain.B_GROVE: return 0.45
		Terrain.B_MARSH: return 0.6
		Terrain.B_ROCK: return 0.08
		Terrain.B_SNOW: return 0.05
		Terrain.B_SAND: return 0.04
		Terrain.B_DESERT: return 0.06
		Terrain.B_BADLANDS: return 0.03
		Terrain.B_SAVANNA: return 0.40
		Terrain.B_DIRT: return 0.12
		Terrain.B_MUD: return 0.18
	return 0.2
