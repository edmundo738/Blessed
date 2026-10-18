class_name World
extends Node3D
## World — gestora de chunks, água, céu e luz.
##
## Regras de estabilidade:
##   • nunca constrói mais do que cabe no orçamento de um frame (por omissão 5 ms)
##   • os chunks são reaproveitados de um pool, não criados de raiz
##   • o LOD é decidido pela distância e só muda quando precisa mesmo
##   • a colisão existe só onde o jogador pode estar

var terrain: Terrain
var species: SpeciesKit
var ecology: Ecosystem
var mats: Materials
var voxel_terrain: Node
var voxel_material: ShaderMaterial
var _voxel_generator: Resource
var _voxel_viewers: Array[Node] = []
var use_voxel_terrain := false

var chunks: Dictionary = {}          # Vector2i -> Chunk
var _rm := RenderingServer.get_current_rendering_method()  # forward_plus | mobile | gl_compatibility
var harvest_state := {}              # key -> tempo absoluto (s de jogo) em que volta
# B-03: respawn estilo Minecraft — minérios/arvores longos, plantas curto.
const RESPAWN_DAYS := {"wood": 14.0, "stone": 21.0, "iron": 30.0, "flint": 21.0,
	"fiber": 2.0, "plant": 1.5}
const RESPAWN_DEFAULT := 7.0
const FELLED_TREE_SCENE: PackedScene = preload("res://scenes/world/felled_tree.tscn")
var _pool: Array = []
var felled_trees: Dictionary = {}
var _felled_tree_nodes: Dictionary = {}
var _target := Vector3.ZERO
var _last_center := Vector2i(999999, 999999)
var _last_lod_target := Vector2(INF, INF)

var view_distance := 160.0
var build_budget_ms := 5.0
var shadows_enabled := true
const LOD_THRESHOLDS := [60.0, 120.0, 180.0]
const LOD_HYSTERESIS := 8.0

var sun: DirectionalLight3D
var env_node: WorldEnvironment
var environment: Environment
var water: Node3D
var sky_resource: Sky
var sky_visible := true
var underwater_active := false
var wind := 0.16
var _last_sky_sync_msec := -1000


func _ready() -> void:
	name = "World"
	terrain = Terrain.new(Game.world_seed)
	species = SpeciesKit.new(Game.world_seed)
	ecology = Ecosystem.new(Game.world_seed)
	mats = Materials.new()
	mats.set_wind(wind)
	_build_environment()
	_build_sky()
	_build_water()
	_build_voxel_terrain()
	Game.register_saver(self)
	Bus.settings_changed.connect(_apply_settings)
	_apply_settings()


# ══════════════════════════════════════════════════════════════════════════
#  CÉU / LUZ / ÁGUA
# ══════════════════════════════════════════════════════════════════════════
func _build_environment() -> void:
	# Sol e WorldEnvironment vêm da CENA (world.tscn) se lá estiverem — assim
	# podes editá-los como NODES no Godot. Senão, o código cria-os (igual a antes).
	env_node = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node == null:
		env_node = WorldEnvironment.new()
		env_node.name = "WorldEnvironment"
		add_child(env_node)
	environment = env_node.environment
	if environment == null:
		environment = Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0.55, 0.72, 0.92)
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(0.62, 0.74, 0.92)
		environment.ambient_light_energy = 0.6
		environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		environment.tonemap_exposure = 1.05
		environment.fog_enabled = true
		environment.fog_light_color = Color(0.72, 0.83, 0.95)
		environment.fog_density = 0.0035
		environment.fog_sky_affect = 0.35
		environment.glow_enabled = true
		environment.glow_intensity = 0.2
		environment.glow_strength = 0.9
		environment.glow_bloom = 0.0
		environment.adjustment_enabled = true
		environment.adjustment_saturation = 1.04
		env_node.environment = environment
	# Controlled bloom: it gives the sun a soft cinematic edge without washing
	# out the whole image or adding a fake translucent sphere to the sky.
	environment.glow_enabled = true
	environment.glow_intensity = 0.62
	environment.glow_strength = 0.82
	environment.glow_bloom = 0.06

	sun = get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "Sun"
		sun.light_energy = 1.25
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 120.0
		sun.light_angular_distance = 1.2
		add_child(sun)


func _build_sky() -> void:
	# Native Godot sky: no giant sphere over the scene and no per-pixel multi-octave
	# cloud noise. The panorama textures carry the painted cloud shapes; a small
	# live shader layer keeps the sun and moon aligned with the day/night lighting.
	sky_resource = Sky.new()
	sky_resource.sky_material = mats.sky
	sky_resource.radiance_size = Sky.RADIANCE_SIZE_128
	sky_resource.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	environment.sky = sky_resource
	environment.background_mode = Environment.BG_SKY
	sky_visible = true


func set_sky_visible(value: bool) -> void:
	sky_visible = value
	if environment != null:
		environment.background_mode = Environment.BG_SKY if value else Environment.BG_COLOR


func _build_water() -> void:
	water = Node3D.new()
	water.name = "Water"
	add_child(water)


## O addon nativo é opcional por plataforma. No Windows, o campo SDF e o
## Transvoxel substituem a malha de altura; Web e plataformas sem extensão
## continuam a usar o backend antigo sem carregar classes inexistentes.
func _build_voxel_terrain() -> void:
	use_voxel_terrain = false
	voxel_terrain = null
	_voxel_generator = null
	if not ClassDB.class_exists("VoxelLodTerrain") \
			or not ClassDB.class_exists("VoxelMesherTransvoxel") \
			or not ClassDB.class_exists("VoxelViewer"):
		return
	var generator_script := load("res://scripts/world/voxel_generator.gd")
	if generator_script == null:
		push_warning("Voxel Tools está disponível, mas o gerador SDF não carregou; usando terreno compatível")
		return
	var voxel_shader := load("res://shaders/voxel_toon_terrain.gdshader") as Shader
	if voxel_shader == null:
		push_warning("Shader de terreno voxel não carregou; usando terreno compatível")
		return
	_voxel_generator = generator_script.new()
	_voxel_generator.call("configure", terrain)
	var mesher := ClassDB.instantiate("VoxelMesherTransvoxel") as Resource
	var terrain_node := ClassDB.instantiate("VoxelLodTerrain") as Node
	if mesher == null or terrain_node == null:
		push_warning("Voxel Tools não conseguiu criar o mesher Transvoxel; usando terreno compatível")
		return
	mesher.set("texturing_mode", 1) # TEXTURES_MIXEL4_S4: 4 pesos de bioma por vértice
	mesher.set("transitions_enabled", true)
	voxel_material = _make_voxel_material(voxel_shader)
	terrain_node.name = "SmoothVoxelTerrain"
	terrain_node.set("generator", _voxel_generator)
	terrain_node.set("mesher", mesher)
	terrain_node.set("material", voxel_material)
	_terrain_node_set(terrain_node, "mesh_block_size", 16)
	_terrain_node_set(terrain_node, "view_distance", int(view_distance))
	_terrain_node_set(terrain_node, "lod_count", 4)
	_terrain_node_set(terrain_node, "lod_distance", 48.0)
	_terrain_node_set(terrain_node, "generate_collisions", true)
	_terrain_node_set(terrain_node, "collision_lod_count", 2)
	_terrain_node_set(terrain_node, "collision_layer", 1)
	_terrain_node_set(terrain_node, "collision_mask", 1)
	_terrain_node_set(terrain_node, "threaded_update_enabled", true)
	# O addon exige um shader de dither próprio para LOD fade. O shader actual
	# trata as costuras Transvoxel, então mantemos o fade desligado até integrar
	# esse segundo caminho correctamente.
	_terrain_node_set(terrain_node, "lod_fade_duration", 0.0)
	add_child(terrain_node)
	voxel_terrain = terrain_node
	use_voxel_terrain = true
	print("WORLD TERRAIN backend=Smooth SDF / Transvoxel | LOD=4 | caves=karst prototype")


func _terrain_node_set(node: Object, property_name: String, value: Variant) -> void:
	if node == null:
		return
	for property: Dictionary in node.get_property_list():
		if str(property.get("name", "")) == property_name:
			node.set(property_name, value)
			return


func _make_voxel_material(voxel_shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = voxel_shader
	var palette := PackedColorArray()
	for i in Terrain.BIOME_COUNT:
		palette.append(Db.biome_color(i, Terrain.BIOME_COLOR[i]))
	material.set_shader_parameter("u_biome_palette", palette)
	material.set_shader_parameter("u_snowline", Db.terrain_num("snowline_base", 150.0))
	return material


func attach_voxel_viewer(owner: Node3D) -> Node:
	if not use_voxel_terrain or owner == null:
		return null
	var viewer := ClassDB.instantiate("VoxelViewer") as Node3D
	if viewer == null:
		return null
	viewer.name = "VoxelViewer"
	viewer.set("requires_visuals", true)
	viewer.set("requires_collisions", true)
	viewer.set("view_distance", int(view_distance))
	owner.add_child(viewer)
	_voxel_viewers.append(viewer)
	return viewer


## O jogador não pode receber gravidade antes de o chunk LOD0 e a colisão
## do spawn terem sido construídos. O gerador de altura conhece o chão antes
## de o VoxelLodTerrain acabar o trabalho; tratá-los como simultâneos fazia o
## corpo cair através do mundo no arranque.
func voxel_collision_ready_at(p: Vector3) -> bool:
	if not use_voxel_terrain:
		return true
	if not is_instance_valid(voxel_terrain) or not voxel_terrain.has_method("is_area_meshed"):
		return false
	var area := AABB(p + Vector3(-2.0, -4.0, -2.0), Vector3(4.0, 8.0, 4.0))
	return bool(voxel_terrain.call("is_area_meshed", area, 0))


func _rebuild_voxel_backend() -> void:
	if not use_voxel_terrain:
		return
	var viewer_owners: Array[Node3D] = []
	for viewer: Node in _voxel_viewers:
		if not is_instance_valid(viewer):
			continue
		var owner := viewer.get_parent() as Node3D
		if owner != null:
			viewer_owners.append(owner)
			owner.remove_child(viewer)
		viewer.free()
	_voxel_viewers.clear()
	if is_instance_valid(voxel_terrain):
		remove_child(voxel_terrain)
		voxel_terrain.free()
	voxel_terrain = null
	use_voxel_terrain = false
	_build_voxel_terrain()
	for owner: Node3D in viewer_owners:
		if is_instance_valid(owner):
			attach_voxel_viewer(owner)


## O céu e a luz seguem a hora do jogo.
func update_time(hour: float, daylight: float, phase: String) -> void:
	var dir := Game.sun_direction()
	sun.rotation = Vector3(0, 0, 0)
	# `dir` é a direção para onde a luz VIAJA (já vem negada em Game.sun_direction()).
	# O nó tem de ficar do lado OPOSTO, senão o sol nasce debaixo do terreno e
	# ilumina tudo por baixo — foi isso que deixou o chão às escuras.
	var night := 1.0 - daylight
	# Uma só DirectionalLight faz de sol de dia e de lua de noite: quando o sol
	# desce do horizonte a energia chega a 0 e a luz passa para a posição da lua
	# (oposta), azulada e fraca — assim a noite tem luz direcional e sombras
	# vindas da lua, em vez de o sol a iluminar o chão por baixo.
	var sun_elev := (-dir).normalized().y
	if sun_elev > -0.02:
		sun.look_at_from_position(-dir * 200.0, Vector3.ZERO, Vector3.UP)
		sun.light_color = Game.sun_color()
		sun.light_energy = 1.3 * clampf((sun_elev + 0.02) / 0.27, 0.0, 1.0)
	else:
		sun.look_at_from_position(dir * 200.0, Vector3.ZERO, Vector3.UP)
		sun.light_color = Color(0.55, 0.66, 1.0)
		sun.light_energy = 0.30 * clampf((dir.normalized().y - 0.02) / 0.3, 0.0, 1.0)
	sun.visible = true

	var dusk := 0.0
	if phase == "dusk" or phase == "dawn":
		dusk = clampf(1.0 - absf(daylight - 0.45) * 3.0, 0.0, 1.0)
	var now_msec := Time.get_ticks_msec()
	var refresh_sky := now_msec - _last_sky_sync_msec >= 200
	if refresh_sky:
		_last_sky_sync_msec = now_msec
	mats.apply_time(dir, daylight, dusk, refresh_sky)

	environment.ambient_light_energy = lerpf(0.58, 0.26, night)
	var fog_color := Color(0.72, 0.83, 0.95).lerp(Color(0.07, 0.09, 0.18), night)
	fog_color = fog_color.lerp(Color(1.0, 0.62, 0.42), dusk * 0.5)
	environment.fog_light_color = Color(0.12, 0.39, 0.52) if underwater_active else fog_color
	environment.fog_density = 0.018 if underwater_active else lerpf(0.0032, 0.0062, night)
	environment.fog_sky_affect = 0.42 if underwater_active else 0.18
	environment.background_color = environment.fog_light_color
	environment.ambient_light_color = environment.fog_light_color.lightened(0.1)
	if underwater_active:
		environment.ambient_light_energy = 0.36


func set_underwater(value: bool) -> void:
	if underwater_active == value:
		return
	underwater_active = value
	update_time(Game.hour, Game.daylight(), Game.current_phase())


# ══════════════════════════════════════════════════════════════════════════
#  CHUNKS
# ══════════════════════════════════════════════════════════════════════════
## Onde o jogador nasce (definido por main.gd ANTES de os chunks existirem) e o
## raio que fica limpo de vegetação à volta dele.
##
## PORQUE: nascer dentro de um tronco é nascer preso — a colisão da árvore fecha
## o jogador na própria malha, e a primeira coisa que se vê é o interior de um
## caqui. Antes a escolha do ponto só evitava água, inclinação e fogueiras, e o
## mato era espalhado sem saber de nada.
const SPAWN_CLEAR_RADIUS := 4.5
var spawn_clear := Vector3(0.0, -16384.0, 0.0)


func set_spawn_clear(p: Vector3) -> void:
	spawn_clear = p


func is_clear_of_spawn(x: float, z: float) -> bool:
	if spawn_clear.y < -16000.0:
		return true
	var dx := x - spawn_clear.x
	var dz := z - spawn_clear.z
	return dx * dx + dz * dz > SPAWN_CLEAR_RADIUS * SPAWN_CLEAR_RADIUS


func set_target(p: Vector3) -> void:
	_target = p


func radius() -> int:
	# O VoxelLodTerrain assume o horizonte; chunks secundários concentram
	# relva, água e objetos na zona jogável para não duplicar a carga da malha.
	var chunk_distance := minf(view_distance, 144.0) if use_voxel_terrain else view_distance
	return clampi(int(ceil(chunk_distance / Chunk.SIZE)), 1, 7)


func _process(_delta: float) -> void:
	var c := Vector2i(int(floor(_target.x / Chunk.SIZE)), int(floor(_target.z / Chunk.SIZE)))
	var r := radius()
	if c == _last_center:
		if Vector2(_target.x, _target.z).distance_to(_last_lod_target) < 24.0:
			return
	_last_center = c
	_last_lod_target = Vector2(_target.x, _target.z)
	_update_chunks(c, r)


func _update_chunks(c: Vector2i, r: int) -> void:
	var deadline := Time.get_ticks_msec() + int(build_budget_ms)
	var wanted := {}
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var key := Vector2i(c.x + dx, c.y + dz)
			var center := Vector2((key.x + 0.5) * Chunk.SIZE, (key.y + 0.5) * Chunk.SIZE)
			var distance := center.distance_to(Vector2(_target.x, _target.z))
			if distance > view_distance + Chunk.SIZE * 0.72:
				continue
			var previous := int((chunks.get(key) as Chunk).lod) if chunks.has(key) else -1
			wanted[key] = _lod_for_distance(distance, previous)
	# liberta o que já não interessa
	for key in chunks.keys():
		if not wanted.has(key):
			var old: Chunk = chunks[key]
			old.release()
			_pool.append(old)
			chunks.erase(key)
			Bus.chunk_released.emit(key.x, key.y)
	# cria/atualiza o que falta (mais perto primeiro)
	var order := wanted.keys()
	order.sort_custom(func(a, b):
		var da := Vector2((a.x + 0.5) * Chunk.SIZE, (a.y + 0.5) * Chunk.SIZE).distance_squared_to(Vector2(_target.x, _target.z))
		var db := Vector2((b.x + 0.5) * Chunk.SIZE, (b.y + 0.5) * Chunk.SIZE).distance_squared_to(Vector2(_target.x, _target.z))
		return da < db)
	for key in order:
		var lod: int = wanted[key]
		var with_col := lod == 0
		if chunks.has(key):
			var ch: Chunk = chunks[key]
			if ch.lod != lod:
				ch.set_lod(lod, with_col)
			continue
		if Time.get_ticks_msec() > deadline:
			_last_center = Vector2i(999999, 999999)  # volta a tentar no próximo frame
			return
		var ch2 := _take_chunk(key, lod)
		chunks[key] = ch2
		ch2.build(with_col)
		Bus.chunk_ready.emit(key.x, key.y)
		if Time.get_ticks_msec() > deadline:
			_last_center = Vector2i(999999, 999999)
			return


func _take_chunk(key: Vector2i, lod: int) -> Chunk:
	var ch: Chunk
	if _pool.is_empty():
		ch = Chunk.new()
		add_child(ch)
	else:
		ch = _pool.pop_back()
	# Chunks reciclados também precisam receber o gerador/sistemas da semente
	# actual. Sem isto, carregar uma partida podia misturar terreno de duas seeds.
	ch.terrain = terrain
	ch.species = species
	ch.ecology = ecology
	ch.mats = mats
	ch.world = self
	ch.name = "Chunk_%d_%d" % [key.x, key.y]
	ch.cx = key.x
	ch.cz = key.y
	ch.lod = lod
	ch.water_root = water
	return ch


func _now() -> float:
	return (Game.day - 1) * Game.DAY_SECONDS + Game.hour / 24.0 * Game.DAY_SECONDS


func harvest_key(pos: Vector3, species: String) -> String:
	return "%d|%d|%d|%s" % [roundi(pos.x * 10.0), roundi(pos.y * 10.0), roundi(pos.z * 10.0), species]


func mark_harvested(n: Dictionary) -> void:
	var k := harvest_key(n["pos"] as Vector3, str(n.get("species", "")))
	var days: float = RESPAWN_DAYS.get(str(n.get("kind", "")), RESPAWN_DEFAULT)
	harvest_state[k] = _now() + days * Game.DAY_SECONDS


func is_harvested(pos: Vector3, species: String) -> bool:
	var k := harvest_key(pos, species)
	if not harvest_state.has(k):
		return false
	return _now() < float(harvest_state[k])


## Nós colhíveis perto de um ponto (o sistema de interação usa isto).
func harvestables_near(p: Vector3, radius: float) -> Array:
	var out := []
	var c := Vector2i(int(floor(p.x / Chunk.SIZE)), int(floor(p.z / Chunk.SIZE)))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := Vector2i(c.x + dx, c.y + dz)
			if not chunks.has(key):
				continue
			var ch: Chunk = chunks[key]
			for n in ch.harvest_nodes:
				if (n["pos"] as Vector3).distance_to(p) <= radius:
					out.append(n)
	return out


## Esconde um nó colhido (delega no chunk dono).
func hide_harvest(n: Dictionary) -> void:
	var ch: Node = n.get("chunk")
	if ch != null and is_instance_valid(ch) and ch.has_method("hide_harvest"):
		ch.call("hide_harvest", n)


func fell_tree(n: Dictionary) -> void:
	var tree_id := str(n.get("species", ""))
	if not species.trees.has(tree_id):
		return
	var tree_spec: SpeciesKit.Species = species.trees[tree_id]
	var key := harvest_key(n["pos"] as Vector3, tree_id)
	var base: Transform3D = n.get("base_transform", Transform3D.IDENTITY)
	var pos: Vector3 = n["pos"]
	var scale := base.basis.get_scale()
	var fell_height := float(n.get("height", tree_spec.height))
	if not tree_spec.trunk_lods.is_empty():
		fell_height = tree_spec.trunk_lods[0].get_aabb().size.y * absf(scale.y)
	var yields: Dictionary = Db.HARVEST.get(str(n.get("kind", "")), {}).get("yields", {})
	var logs := maxi(int(yields.get("wood", 1)), 1)
	var direction := 1.0 if posmod(roundi(pos.x), 2) == 0 else -1.0
	var data := {
		"species": tree_id,
		"position": [pos.x, pos.y, pos.z],
		"rotation_y": base.basis.get_euler().y,
		"scale": [scale.x, scale.y, scale.z],
		"y_offset": base.origin.y - pos.y,
		"height": fell_height,
		"trunk_radius": maxf(float(n.get("collider_radius", 0.42)) * 0.34, 0.16),
		"remaining_logs": logs,
		"direction": direction,
	}
	felled_trees[key] = data
	_spawn_felled_tree(key, data)


func _spawn_felled_tree(key: String, data: Dictionary) -> void:
	if _felled_tree_nodes.has(key) and is_instance_valid(_felled_tree_nodes[key]):
		return
	var tree_id := str(data.get("species", ""))
	if not species.trees.has(tree_id):
		return
	var spec: SpeciesKit.Species = species.trees[tree_id]
	var raw_pos: Array = data.get("position", [0.0, 0.0, 0.0])
	var pos := Vector3(float(raw_pos[0]), float(raw_pos[1]), float(raw_pos[2]))
	var raw_scale: Array = data.get("scale", [1.0, 1.0, 1.0])
	var scale := Vector3(float(raw_scale[0]), float(raw_scale[1]), float(raw_scale[2]))
	var base := Transform3D(Basis(Vector3.UP, float(data.get("rotation_y", 0.0)))
		.scaled(scale), Vector3(0.0, float(data.get("y_offset", 0.0)), 0.0))
	# Material do abate: NADA de `mats.foliage` (translúcido, sem resposta à luz e
	# com vento) num tronco caído. `mats.structure` é o material sólido e toon —
	# o tronco passa a receber luz e sombra como qualquer objeto do mundo.
	# Árvores abatidas usam a malha separada do tronco (procedural), por isso
	# recebem material sólido de madeira mesmo quando a árvore em pé é importada.
	var local_mat: Material = mats.structure if not spec.trunk_lods.is_empty() \
		else (null if spec.materials_authored else mats.structure)
	var node := FELLED_TREE_SCENE.instantiate() as Node3D
	if node == null:
		return
	node.name = "FelledTree_%s" % tree_id
	node.position = to_local(pos) + Vector3(float(data.get("fall_offset_x", 0.0)), 0.0, 0.0)
	node.rotation.z = float(data.get("fall_rotation", 0.0))
	add_child(node)
	var felled_mesh: ArrayMesh = spec.lods[0]
	if not spec.trunk_lods.is_empty():
		felled_mesh = spec.trunk_lods[0]
	node.call("configure", felled_mesh, local_mat, base, float(data.get("height", spec.height)),
		float(data.get("trunk_radius", 0.22)), int(data.get("remaining_logs", 1)),
		self, key, tree_id, float(data.get("direction", 1.0)))
	_felled_tree_nodes[key] = node
	if bool(data.get("settled", false)):
		# veio de um save: já está deitada, assentar e pronto
		node.call("apply_settled", float(data.get("fall_rotation", 0.0)),
			float(data.get("fall_offset_x", 0.0)))
	else:
		node.call("begin_fall")


func felled_tree_log_taken(key: String, remaining: int) -> void:
	if remaining <= 0:
		felled_trees.erase(key)
		_felled_tree_nodes.erase(key)
		return
	if felled_trees.has(key):
		felled_trees[key]["remaining_logs"] = remaining


func felled_tree_settled(key: String) -> void:
	if felled_trees.has(key):
		felled_trees[key]["settled"] = true
		var node := _felled_tree_nodes.get(key) as Node3D
		if is_instance_valid(node):
			felled_trees[key]["fall_rotation"] = node.rotation.z
			felled_trees[key]["fall_offset_x"] = node.position.x - to_local(Vector3(
				float(felled_trees[key]["position"][0]),
				float(felled_trees[key]["position"][1]),
				float(felled_trees[key]["position"][2]))).x


func ground_height(x: float, z: float) -> float:
	return terrain.height(x, z)


func water_surface_height(x: float, z: float) -> float:
	return terrain.water_surface_height(x, z)


## A amostra completa (corrente, salinidade, tipo) para o jogador e os objetos.
func water_sample(x: float, z: float) -> Dictionary:
	return terrain.water_sample(x, z) if terrain != null else {}


func is_in_water(p: Vector3) -> bool:
	var surface := terrain.water_surface_height(p.x, p.z)
	if surface < -99999.0:
		return false
	return p.y < surface + 0.65 and terrain.height(p.x, p.z) < surface - 0.35


func _apply_quality() -> void:
	## Iluminacao + atmosfera por perfil/renderizador.
	## Volumetric fog e SSR so existem em Forward+; SSAO tambem em Compatibility.
	## Toggles e valores vem de data/quality.json (Db.quality_*); sem dados, usa
	## o comportamento embutido (q>=1 / q>=2).
	if environment == null:
		return
	var q := int(Game.settings.get("quality", 1))
	var fp := _rm == "forward_plus"
	var preset := Db.quality_preset(q, {"ssao": q >= 1, "volumetric_fog": q >= 1, "ssr": q >= 2, "dof": q >= 1})
	var ssao_on := bool(preset.get("ssao", q >= 1))
	var fog_on := bool(preset.get("volumetric_fog", q >= 1))
	var ssr_on := bool(preset.get("ssr", q >= 2))
	var dof_on := bool(Game.settings.get("dof", true))
	# tonemap cinematografico + exposicao controlada (contra os "brancos" V-02)
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = Db.quality_value("tonemap_exposure", 0.98)
	environment.tonemap_white = Db.quality_value("tonemap_white", 6.0)
	# profundidade atmosferica via depth fog (todos os renderers)
	environment.fog_aerial_perspective = Db.quality_value("fog_aerial_perspective", 0.45)
	# SSAO (profundidade de contacto): Forward+ e Compatibility; Mobile nao
	if _rm != "mobile":
		environment.ssao_enabled = ssao_on
		environment.ssao_radius = Db.quality_value("ssao_radius", 1.1)
		environment.ssao_intensity = Db.quality_value("ssao_intensity", 1.3)
	# nevoeiro volumetrico: SO Forward+
	if fp and fog_on:
		environment.volumetric_fog_enabled = true
		environment.volumetric_fog_density = Db.quality_value("fog_density", 0.018)
		environment.volumetric_fog_albedo = Color(0.76, 0.83, 0.93)
		environment.volumetric_fog_length = Db.quality_value("fog_length", 96.0)
		environment.volumetric_fog_sky_affect = Db.quality_value("fog_sky_affect", 0.4)
	else:
		environment.volumetric_fog_enabled = false
	# reflexos screen-space: SO Forward+, so perfil cinematografico
	if fp and ssr_on:
		environment.ssr_enabled = true
		environment.ssr_max_steps = int(Db.quality_value("ssr_max_steps", 64))
	else:
		environment.ssr_enabled = false
	# profundidade de campo (DoF): da a "sensacao de profundidade" cinematografica.
	# CameraAttributesPractical; so Forward+/Mobile (nao Compatibility).
	if env_node != null:
		if _rm != "gl_compatibility" and dof_on:
			var ca := CameraAttributesPractical.new()
			ca.dof_blur_far_enabled = true
			ca.dof_blur_far_distance = Db.quality_value("dof_far_distance", 55.0)
			ca.dof_blur_far_transition = Db.quality_value("dof_far_transition", 45.0)
			ca.dof_blur_amount = Db.quality_value("dof_blur_amount", 0.06)
			env_node.camera_attributes = ca
		else:
			env_node.camera_attributes = null


func _apply_settings() -> void:
	view_distance = clampf(float(Game.settings["view_distance"]), 60.0, 240.0)
	shadows_enabled = int(Game.settings["shadows"]) > 0
	if is_instance_valid(voxel_terrain):
		_terrain_node_set(voxel_terrain, "view_distance", int(view_distance))
	for viewer: Node in _voxel_viewers:
		if is_instance_valid(viewer):
			viewer.set("view_distance", int(view_distance))
	if sun:
		sun.shadow_enabled = shadows_enabled
		sun.directional_shadow_max_distance = [60.0, 120.0, 200.0][clampi(int(Game.settings["shadows"]), 0, 2)]
	if environment:
		environment.fog_enabled = true
		environment.fog_mode = Environment.FOG_MODE_DEPTH
		environment.fog_depth_begin = view_distance * 0.48
		environment.fog_depth_end = view_distance * 1.20
		environment.fog_depth_curve = 1.35
		# B-01: glow e um toggle proprio; film_grain ja nao o forca (condicao era sempre verdadeira)
		environment.glow_enabled = bool(Game.settings.get("glow", false))
		environment.glow_intensity = clampf(float(Game.settings.get("glow_intensity", 0.40)), 0.0, 1.0)
	_apply_quality()
	_last_center = Vector2i(999999, 999999)


func _lod_for_distance(distance: float, previous: int = -1) -> int:
	if previous < 0 or previous > 3:
		if distance <= LOD_THRESHOLDS[0]: return 0
		if distance <= LOD_THRESHOLDS[1]: return 1
		if distance <= LOD_THRESHOLDS[2]: return 2
		return 3
	var lod := previous
	while lod < 3 and distance > LOD_THRESHOLDS[lod] + LOD_HYSTERESIS:
		lod += 1
	while lod > 0 and distance < LOD_THRESHOLDS[lod - 1] - LOD_HYSTERESIS:
		lod -= 1
	return lod


func save_data() -> Dictionary:
	return {"seed": Game.world_seed, "harvest_state": harvest_state,
		"felled_trees": felled_trees.duplicate(true)}


func load_data(_d: Dictionary) -> void:
	harvest_state = _d.get("harvest_state", {}) if _d.get("harvest_state") is Dictionary else {}
	for node in _felled_tree_nodes.values():
		if is_instance_valid(node):
			node.queue_free()
	_felled_tree_nodes.clear()
	felled_trees = _d.get("felled_trees", {}) if _d.get("felled_trees") is Dictionary else {}
	# recria o gerador com a semente carregada (Game.load_game já atualizou Game.world_seed).
	# Sem isto, o terreno continuava a ser gerado com a semente anterior ao carregar (dessincronização).
	terrain = Terrain.new(Game.world_seed)
	species = SpeciesKit.new(Game.world_seed)
	ecology = Ecosystem.new(Game.world_seed)
	_rebuild_voxel_backend()
	Bus.world_reseeded.emit()
	for key in chunks.keys():
		(chunks[key] as Chunk).release()
	chunks.clear()
	for key in felled_trees.keys():
		_spawn_felled_tree(str(key), felled_trees[key])
	_last_center = Vector2i(999999, 999999)
