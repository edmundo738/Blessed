class_name LabScene
extends Node3D
## LabScene — o laboratório jogável (Etapa 2).
##
## Ergue o LabWorld em 3D: mesh suave por pedaços com colisão que a
## acompanha, água por células, vegetação por afinidade (nós colhíveis),
## estações como plataformas coloridas e o Player real a nascer em terra
## firme. O LabDev (modo deus) vive ao lado e fala com esta cena.
##
## Como entrar: abrir scenes/lab.tscn no Godot e F5 (cena direta), ou
## correr o projeto com `-- labscene` para o teste automático.

const CHUNK_MAT := preload("res://shaders/toon_terrain.gdshader")

var lab: LabWorld
var player: Player
var inv: Inventory
var seed_value := 1337

var _chunks: Dictionary = {}  # Vector2i -> {mesh: MeshInstance3D, body: StaticBody3D, shape: CollisionShape3D}
var _water_inst: MeshInstance3D
var _grass: Dictionary = {}  # Vector2i -> MultiMeshInstance3D
var _grass_growth: Dictionary = {}  # Vector2i -> 0..1 (recrescimento)
var _grass_root: Node3D
var _blade_mesh: ArrayMesh
var _props_root: Node3D
var _stations_root: Node3D
var _underwater := false
var _sun: DirectionalLight3D
var _env: WorldEnvironment

const SPECIES_KIND := {
	"oak": "tree_oak", "birch": "tree_birch", "sakura": "tree_sakura",
	"pine": "tree_pine", "willow": "tree_willow",
}
# ── ferramentas de escavacao ───────────────────────────────────────────────
# A diferenca entre ferramentas NAO e so velocidade: e raio x profundidade
# x ritmo x MATERIAL que cada uma consegue atacar (desenho classico:
# Deep Rock hardness 1-3 / Astroneer dureza por profundidade).
#   mao ..... raio curto, superficial, so areia e topsoil solto
#   pa ...... raio largo, ritmo rapido, terra/areia — inutil na rocha
#   picareta  raio curto, ritmo lento, e a unica que parte rocha
const TOOLS := {
	"hand": {"label": "Mão", "radius": 1.5, "depth": 0.20, "interval": 0.22},
	"shovel": {"label": "Pá", "radius": 2.3, "depth": 0.38, "interval": 0.14},
	"pickaxe": {"label": "Picareta", "radius": 1.3, "depth": 0.30, "interval": 0.28},
}
const TOOL_ORDER: Array[String] = ["hand", "shovel", "pickaxe"]
const YIELD_ITEM := {0: "sand", 1: "soil", 2: "stone"}  # M_SAND/M_DIRT/M_ROCK


static func tool_can(tool: String, mat: int, dug_depth: float) -> bool:
	if mat == LabWorld.M_ROCK:
		return tool == "pickaxe"
	if mat == LabWorld.M_DIRT and dug_depth > LabWorld.LAYER_TOP:
		return tool != "hand"  # terra compacta: mao nao entra
	return true


## Escavar/aterrar COM ferramenta num ponto do mundo. Devolve o que
## aconteceu (material, volume, rendimento) para HUD/drops/testes lerem.
## Quem chama nao decide regras: a identificacao do material vive aqui.
func tool_dig(tool: String, x: float, z: float, fill_mode: bool = false) -> Dictionary:
	var prof: Dictionary = TOOLS.get(tool, TOOLS["hand"])
	var mat := lab.material_at(x, z)
	if fill_mode:
		if tool == "pickaxe":
			return {"ok": false, "material": mat, "reason": "fill_pickaxe"}
		var added: float = lab.fill(x, z, float(prof["radius"]), float(prof["depth"]))
		rebuild_area(x, z, float(prof["radius"]) + 6.0)
		return {"ok": true, "material": mat, "removed": -added, "yield_item": ""}
	if not tool_can(tool, mat, lab.depth_dug(x, z)):
		return {"ok": false, "material": mat, "reason": "tool"}
	var removed: float = lab.dig(x, z, float(prof["radius"]), float(prof["depth"]))
	rebuild_area(x, z, float(prof["radius"]) + 6.0)
	return {"ok": true, "material": mat, "removed": removed,
			"yield_item": str(YIELD_ITEM.get(mat, "soil"))}


const SPECIES_COLOR := {
	"oak": Color(0.16, 0.42, 0.20), "birch": Color(0.45, 0.62, 0.35),
	"sakura": Color(0.92, 0.62, 0.72), "pine": Color(0.10, 0.32, 0.24),
	"willow": Color(0.35, 0.55, 0.30),
}


func _ready() -> void:
	name = "LabScene"
	lab = LabWorld.new(seed_value)
	_build_environment()
	_build_terrain()
	_build_water()
	_build_grass_all()
	_build_props()
	_build_stations()
	_spawn_player()
	var dev := LabDev.new()
	dev.name = "LabDev"
	add_child(dev)
	dev.setup(self)


# ── ambiente mínimo (o do World grande não entra aqui) ─────────────────────
func _build_environment() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.light_energy = 1.25
	_sun.shadow_enabled = true
	_sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	add_child(_sun)
	_env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.72, 0.92)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.74, 0.92)
	e.ambient_light_energy = 0.65
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.72, 0.83, 0.95)
	e.fog_density = 0.0028
	_env.environment = e
	add_child(_env)


# ── terreno: mesh + colisão por pedaço ─────────────────────────────────────
func _build_terrain() -> void:
	var cc := LabMesh.chunk_count()
	for cj in cc:
		for ci in cc:
			_make_chunk(ci, cj)


func _make_chunk(ci: int, cj: int) -> void:
	var data := LabMesh.build_chunk(lab, ci, cj)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data["arrays"])
	var mi := MeshInstance3D.new()
	mi.name = "LabChunk_%d_%d" % [ci, cj]
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mi.material_override = mat
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "LabGround_%d_%d" % [ci, cj]
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("lab_ground", true)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(data["faces"])
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	_chunks[Vector2i(ci, cj)] = {"mesh": mi, "body": body, "shape": cs}


func _rebuild_chunk(ci: int, cj: int) -> void:
	if ci < 0 or cj < 0 or ci >= LabMesh.chunk_count() or cj >= LabMesh.chunk_count():
		return
	var entry: Dictionary = _chunks[Vector2i(ci, cj)]
	var data := LabMesh.build_chunk(lab, ci, cj)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data["arrays"])
	(entry["mesh"] as MeshInstance3D).mesh = mesh
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(data["faces"])
	(entry["shape"] as CollisionShape3D).shape = shape
	if _grass_root != null:
		_build_grass_chunk(ci, cj)


## Reconstrói só os pedaços tocados por (x,z,raio) + a água inteira
## (a água é barata e o nível de uma célula pode mudar longe do buraco).
func rebuild_area(x: float, z: float, radius_m: float) -> void:
	var cell := 5.0
	var chunk_m := float(LabMesh.CHUNK_CELLS) * cell
	var half := LabWorld.SIZE * 0.5
	var ci0 := clampi(int(floor((x - radius_m + half) / chunk_m)), 0, LabMesh.chunk_count() - 1)
	var ci1 := clampi(int(floor((x + radius_m + half) / chunk_m)), 0, LabMesh.chunk_count() - 1)
	var cj0 := clampi(int(floor((z - radius_m + half) / chunk_m)), 0, LabMesh.chunk_count() - 1)
	var cj1 := clampi(int(floor((z + radius_m + half) / chunk_m)), 0, LabMesh.chunk_count() - 1)
	for cj in range(cj0, cj1 + 1):
		for ci in range(ci0, ci1 + 1):
			_grass_growth[Vector2i(ci, cj)] = 0.15  # relva perturbada: recresce
			_rebuild_chunk(ci, cj)
	_build_water()
	reseat_props(x, z, radius_m + 10.0)


func _build_water() -> void:
	if _water_inst != null and is_instance_valid(_water_inst):
		_water_inst.queue_free()
	var data := LabMesh.build_water(lab)
	if int(data["quads"]) == 0:
		_water_inst = null
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data["arrays"])
	_water_inst = MeshInstance3D.new()
	_water_inst.name = "LabWater"
	_water_inst.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.35
	_water_inst.material_override = mat
	_water_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water_inst)


# ── relva: MultiMesh por pedaço, gerada dos campos (nunca Node por lâmina) ─
# A relva e DERIVADA da superficie atual: ao construir cada pedaço de 50 m,
# amostram-se os pontos e decide-se densidade por humidade/bioma/declive e
# material. Escavar muda os campos -> o rebuild local faz a relva sumir onde
# ficou terra exposta/molhado/rocha, e o recrescimento (_grass_growth
# 0->1 em ~24 s) traz-la de volta onde voltou a ser prado. Custo por frame
# zero: so se reconstrói o pedaço tocado (e os que estão a recrescer, em
# degraus quantizados para não reconstruir todos os frames).
const GRASS_PER_CELL := 6
const GRASS_GROW_SECONDS := 24.0


func _build_grass_all() -> void:
	if _grass_root != null and is_instance_valid(_grass_root):
		_grass_root.queue_free()
	_grass_root = Node3D.new()
	_grass_root.name = "LabGrass"
	add_child(_grass_root)
	_grass.clear()
	var cc := LabMesh.chunk_count()
	for cj in cc:
		for ci in cc:
			_grass_growth[Vector2i(ci, cj)] = 1.0
			_build_grass_chunk(ci, cj)


func _make_blade_mesh() -> ArrayMesh:
	if _blade_mesh != null:
		return _blade_mesh
	var verts := PackedVector3Array([
		Vector3(-0.14, 0.0, 0.0), Vector3(0.14, 0.0, 0.0), Vector3(0.0, 0.85, 0.0),
		Vector3(0.0, 0.0, -0.14), Vector3(0.0, 0.0, 0.14), Vector3(0.0, 0.85, 0.0)])
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for v in verts:
		normals.append(Vector3.UP)
		colors.append(Color(0.30, 0.48, 0.20) if v.y < 0.1 else Color(0.55, 0.78, 0.34))
	var idx := PackedInt32Array([0, 1, 2, 3, 4, 5])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	_blade_mesh = ArrayMesh.new()
	_blade_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _blade_mesh


static func _hash01(a: int, b: int, c: int) -> float:
	var h := int(posmod(a * 374761393 + b * 668265263 + c * 2147483647 + 1337 * 97, 100000))
	return float(h) / 100000.0


## Densidade 0..1 da relva num ponto, lida da superficie ATUAL.
## Zero onde: agua, areia, rocha, declive forte, ou terra ja escavada
## (camada exposta nao tem relva — le-se o estrato).
func grass_density(x: float, z: float) -> float:
	var s := lab.sample(x, z)
	if int(s["water_kind"]) != 0 or float(s["height"]) < 0.5:
		return 0.0
	var mat := int(s["material"])
	if mat == LabWorld.M_SAND or mat == LabWorld.M_ROCK:
		return 0.0
	if float(s["slope"]) > 0.38:
		return 0.0
	if float(s["depth_dug"]) > 0.10:
		return 0.0
	var biome_factor := 0.55
	match int(s["biome"]):
		LabWorld.B_MEADOW:
			biome_factor = 1.0
		LabWorld.B_FOREST:
			biome_factor = 0.70
		LabWorld.B_GROVE:
			biome_factor = 0.85
		LabWorld.B_MARSH:
			biome_factor = 0.90
		LabWorld.B_DRY:
			biome_factor = 0.30
		LabWorld.B_BEACH, LabWorld.B_ROCK:
			biome_factor = 0.0
	return clampf((0.25 + float(s["moisture"]) * 0.85) * biome_factor, 0.0, 1.0)


func _build_grass_chunk(ci: int, cj: int) -> void:
	if _grass_root == null:
		return
	var key := Vector2i(ci, cj)
	var growth := float(_grass_growth.get(key, 1.0))
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var seg := LabMesh.CHUNK_CELLS
	for gj in range(cj * seg, cj * seg + seg):
		for gi in range(ci * seg, ci * seg + seg):
			for k in GRASS_PER_CELL:
				var ox := _hash01(gi, gj, k * 3 + 1)
				var oz := _hash01(gi, gj, k * 3 + 2)
				var p := lab.grid_pos(gi, gj) + Vector2(ox - 0.5, oz - 0.5) * LabWorld.CELL * 0.9
				var d := grass_density(p.x, p.y) * growth
				if _hash01(gi, gj, k * 3 + 3) > d:
					continue
				var h := lab.height(p.x, p.y)
				var scale := 0.7 + _hash01(gi, gj, k + 40) * 0.7
				var basis := Basis(Vector3.UP, _hash01(gi, gj, k + 80) * TAU).scaled(Vector3.ONE * scale)
				transforms.append(Transform3D(basis, Vector3(p.x, h - 0.03, p.y)))
				colors.append(Color(0.85 + ox * 0.3, 0.9 + oz * 0.2, 0.8))
	var mmi := _grass.get(key) as MultiMeshInstance3D
	if mmi == null:
		mmi = MultiMeshInstance3D.new()
		mmi.name = "LabGrass_%d_%d" % [ci, cj]
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 1.0
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_grass_root.add_child(mmi)
		_grass[key] = mmi
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _make_blade_mesh()
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	mmi.multimesh = mm
	# AABB explicita: sem ela o Godot descarta o pedaco com o AABB da
	# lamina original (~1 m) e a relva some ao mover a camara.
	mmi.custom_aabb = AABB(
		Vector3(ci * 50.0 - 200.0, -6.0, cj * 50.0 - 200.0),
		Vector3(56.0, 48.0, 56.0))


func grass_count(ci: int, cj: int) -> int:
	var mmi := _grass.get(Vector2i(ci, cj)) as MultiMeshInstance3D
	if mmi == null or mmi.multimesh == null:
		return 0
	return mmi.multimesh.instance_count


## Tempo de recrescimento: pedacos perturbados voltam 0->1 em degraus de
## 1/4 (reconstruir no maximo 4x por pedaco durante o crescimento).
func advance_growth(seconds: float) -> void:
	if lab == null:
		return
	for key in _grass_growth.keys():
		var g := float(_grass_growth[key])
		if g >= 1.0:
			continue
		var step_before := int(g * 4.0)
		g = minf(1.0, g + seconds / GRASS_GROW_SECONDS)
		_grass_growth[key] = g
		if int(g * 4.0) != step_before or g >= 1.0:
			_build_grass_chunk((key as Vector2i).x, (key as Vector2i).y)


func _process(delta: float) -> void:
	advance_growth(delta)


# ── objectos assentam ou caem: nada flutua ─────────────────────────────────
# Depois de qualquer deformacao local, cada prop na area compara o chao
# onde nasceu (meta lab_ground_y) com o chao novo:
#   desceu pouco  -> assenta (y acompanha a malha)
#   arvore perdeu >= 1 m de chao -> CAI (rotacao fisica a volta da base)
#   e vira drops da especie; pedra apenas assenta/rola para o novo fundo.
# So os props da area tocada sao visitados — custo proporcional ao buraco.
func reseat_props(x: float, z: float, radius_m: float) -> void:
	if _props_root != null:
		for node in _props_root.get_children():
			var body := node as Node3D
			if body == null or body.has_meta("lab_felled"):
				continue
			var dx := body.global_position.x - x
			var dz := body.global_position.z - z
			if dx * dx + dz * dz > radius_m * radius_m:
				continue
			var new_h := lab.height(body.global_position.x, body.global_position.z)
			var ground := float(body.get_meta("lab_ground_y", new_h))
			var kind := str(body.get_meta("lab_kind", ""))
			if kind.begins_with("tree") and ground - new_h >= 1.0:
				_fell_tree(body)
				continue
			body.position.y = new_h + (0.3 if kind == "rock" else 0.0)
			body.set_meta("lab_ground_y", new_h)
	if _stations_root != null:
		for node in _stations_root.get_children():
			var n3 := node as Node3D
			if n3 == null or not n3.has_meta("lab_station_off"):
				continue
			var dx := n3.global_position.x - x
			var dz := n3.global_position.z - z
			if dx * dx + dz * dz > radius_m * radius_m:
				continue
			n3.position.y = lab.height(n3.global_position.x, n3.global_position.z) \
					+ float(n3.get_meta("lab_station_off"))


## A arvore cai: rotacao com ease-in (acelera como peso real) a volta da
## base, e no fim vira os drops da sua especie — o tronco colhivel do
## bosque (H3) nasce desta mesma queda no mundo grande.
func _fell_tree(body: Node3D) -> void:
	body.set_meta("lab_felled", true)
	var kind := str(body.get_meta("lab_kind", ""))
	var at := body.global_position + Vector3(0, 0.8, 0)
	var yields: Dictionary = Db.HARVEST.get(kind, {}).get("yields", {})
	# direcao de queda determinista pela posicao (sem sorteio solto)
	var dir := 1.0 if int(body.global_position.x * 3.0 + body.global_position.z) % 2 == 0 else -1.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(body, "rotation:z", dir * 1.52, 0.85)
	tween.tween_callback(func() -> void:
		if is_instance_valid(body):
			body.queue_free())
	if inv != null:
		for id in yields.keys():
			DroppedItem.spawn(self, str(id), int(yields[id]), at, inv, player)
	print("LABFELL ", kind, " em ", body.global_position, " -> ", yields)


# ── vegetação e pedras: nós reais, colhíveis pelo raycast do LabDev ───────
func _build_props() -> void:
	if _props_root != null and is_instance_valid(_props_root):
		_props_root.queue_free()
	_props_root = Node3D.new()
	_props_root.name = "LabProps"
	add_child(_props_root)
	var species_ids := ["oak", "birch", "sakura", "pine", "willow"]
	var placed := 0
	for j in range(2, LabWorld.N - 2, 2):
		for i in range(2, LabWorld.N - 2, 2):
			if placed > 650:
				break
			var p := lab.grid_pos(i, j)
			var s := lab.sample(p.x, p.y)
			if int(s["water_kind"]) != 0 or float(s["height"]) < 0.4:
				continue
			var best := ""
			var best_d := 0.30
			for sp in species_ids:
				if lab.vegetation_present(p.x, p.y, sp):
					var d := lab.species_density(p.x, p.y, sp)
					if d > best_d:
						best_d = d
						best = sp
			if best != "":
				_add_tree(p.x, p.y, best)
				placed += 1
			elif lab.biome_at(p.x, p.y) == LabWorld.B_ROCK or (i * 7 + j * 13) % 29 == 0:
				_add_rock(p.x, p.y)
				placed += 1


func _add_tree(x: float, z: float, species: String) -> void:
	var h := lab.height(x, z)
	var body := StaticBody3D.new()
	body.name = "LabTree_" + species
	body.position = Vector3(x, h, z)
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("lab_species", species)
	body.set_meta("lab_kind", SPECIES_KIND[species])
	body.set_meta("lab_ground_y", h)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.42
	cyl.height = 4.6
	shape.shape = cyl
	shape.position = Vector3(0, 2.3, 0)
	body.add_child(shape)
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.16
	tm.bottom_radius = 0.30
	tm.height = 2.6
	trunk.mesh = tm
	trunk.position = Vector3(0, 1.3, 0)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.36, 0.25, 0.16)
	trunk.material_override = tmat
	body.add_child(trunk)
	var canopy := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 1.9 if species != "pine" else 1.4
	cm.height = 3.4 if species != "pine" else 4.6
	canopy.mesh = cm
	canopy.position = Vector3(0, 4.1, 0)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = SPECIES_COLOR[species]
	canopy.material_override = cmat
	body.add_child(canopy)
	_props_root.add_child(body)


func _add_rock(x: float, z: float) -> void:
	var h := lab.height(x, z)
	var body := StaticBody3D.new()
	body.name = "LabRock"
	body.position = Vector3(x, h + 0.3, z)
	body.rotation.y = float((int(x * 10.0) + int(z * 7.0)) % 360)
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("lab_species", "rock")
	body.set_meta("lab_kind", "rock")
	body.set_meta("lab_ground_y", h)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.1, 1.2)
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.4, 1.1, 1.2)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.48, 0.47, 0.50)
	mi.material_override = mat
	body.add_child(mi)
	_props_root.add_child(body)


# ── estações: plataformas coloridas; nomes só em modo dev ──────────────────
func _build_stations() -> void:
	_stations_root = Node3D.new()
	_stations_root.name = "LabStations"
	add_child(_stations_root)
	var palette := [Color(0.95, 0.85, 0.30), Color(0.30, 0.80, 0.40), Color(0.85, 0.45, 0.30),
			Color(0.60, 0.45, 0.90), Color(0.30, 0.60, 0.95), Color(0.95, 0.55, 0.75),
			Color(0.35, 0.85, 0.80), Color(0.90, 0.70, 0.45)]
	var n := 0
	for st in lab.stations:
		var x := float(st.get("x", 0.0))
		var z := float(st.get("z", 0.0))
		var y := lab.height(x, z)
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 3.2
		cm.bottom_radius = 3.2
		cm.height = 0.18
		disc.mesh = cm
		disc.position = Vector3(x, y + 0.10, z)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = palette[n % palette.size()]
		disc.material_override = mat
		disc.name = "Station_" + str(st.get("id", n))
		disc.set_meta("lab_station_off", 0.10)
		_stations_root.add_child(disc)
		var label := Label3D.new()
		label.name = "StationLabel"
		label.text = str(st.get("label", st.get("id", "")))
		label.position = Vector3(x, y + 3.4, z)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 72
		label.modulate = Color(1, 1, 1, 0.95)
		label.visible = false
		label.set_meta("lab_dev_label", true)
		label.set_meta("lab_station_off", 3.4)
		_stations_root.add_child(label)
		n += 1


func set_station_labels_visible(v: bool) -> void:
	for node in _stations_root.get_children():
		if node.has_meta("lab_dev_label"):
			(node as Node3D).visible = v


# ── jogador ────────────────────────────────────────────────────────────────
func _spawn_player() -> void:
	player = Player.new()
	add_child(player)
	inv = Inventory.new()
	add_child(inv)
	var spawn := Vector3(10.0, 0.0, 10.0)
	for st in lab.stations:
		if str(st.get("id", "")) == "spawn_meadow":
			spawn = Vector3(float(st["x"]), 0.0, float(st["z"]))
			break
	spawn.y = lab.height(spawn.x, spawn.z) + 1.2
	player.global_position = spawn
	player.velocity = Vector3.ZERO


func respawn_player() -> void:
	if player == null:
		return
	var p := Vector3(10.0, 0.0, 10.0)
	p.y = lab.height(p.x, p.z) + 1.2
	player.global_position = p
	player.velocity = Vector3.ZERO


## Destroi e reconstrói o mundo inteiro (nova LabWorld, mesma seed).
func reset_world() -> void:
	lab = LabWorld.new(seed_value)
	for key in _grass_growth.keys():
		_grass_growth[key] = 1.0
	var cc := LabMesh.chunk_count()
	for cj in cc:
		for ci in cc:
			_rebuild_chunk(ci, cj)
	_build_water()
	_build_props()
	respawn_player()


# ── API que o Player espera do "mundo" (pai) ───────────────────────────────
func ground_height(x: float, z: float) -> float:
	return lab.height(x, z)


func water_surface_height(x: float, z: float) -> float:
	var s := lab.sample(x, z)
	return float(s["water_level"]) if int(s["water_kind"]) > 0 else -100000.0


func water_sample(x: float, z: float) -> Dictionary:
	var s := lab.sample(x, z)
	s["level"] = float(s["water_level"])
	s["depth"] = float(s["water_depth"])
	s["salt"] = 1.0 if int(s["water_kind"]) == 1 else 0.0
	s["flow"] = Vector2.ZERO
	s["speed"] = 0.0
	return s


func is_in_water(p: Vector3) -> bool:
	var s := lab.sample(p.x, p.z)
	if int(s["water_kind"]) == 0:
		return false
	var wl := float(s["water_level"])
	return p.y < wl + 0.65 and lab.height(p.x, p.z) < wl - 0.35


func set_underwater(v: bool) -> void:
	_underwater = v
	if _env != null and _env.environment != null:
		_env.environment.fog_density = 0.018 if v else 0.0028
