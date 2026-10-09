class_name World
extends Node3D
## World — gestora de chunks, água, céu e luz.
##
## Regras de estabilidade:
##   • nunca constrói mais do que cabe no orçamento de um frame (por omissão 5 ms)
##   • os chunks são reaproveitados de um pool, não criados de raiz
##   • o LOD é decidido pela distância e só muda quando precisa mesmo
##   • a relva e a colisão existem só onde o jogador pode estar

var terrain: Terrain
var species: SpeciesKit
var mats: Materials

var chunks: Dictionary = {}          # Vector2i -> Chunk
var _pool: Array = []
var _target := Vector3.ZERO
var _last_center := Vector2i(999999, 999999)

var view_distance := 160.0
var grass_quality := 1
var build_budget_ms := 5.0
var shadows_enabled := true

var sun: DirectionalLight3D
var env_node: WorldEnvironment
var environment: Environment
var water: MeshInstance3D
var sky_dome: MeshInstance3D
var wind := 0.16


func _ready() -> void:
	name = "World"
	terrain = Terrain.new(Game.world_seed)
	species = SpeciesKit.new(Game.world_seed)
	mats = Materials.new()
	_build_environment()
	_build_sky_dome()
	_build_water()
	Game.register_saver(self)
	Bus.settings_changed.connect(_apply_settings)
	_apply_settings()


# ══════════════════════════════════════════════════════════════════════════
#  CÉU / LUZ / ÁGUA
# ══════════════════════════════════════════════════════════════════════════
func _build_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.55, 0.72, 0.92)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.74, 0.92)
	environment.ambient_light_energy = 0.9
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.72, 0.83, 0.95)
	environment.fog_density = 0.0035
	environment.fog_sky_affect = 0.35
	environment.glow_enabled = true
	environment.glow_intensity = 0.45
	environment.glow_strength = 0.9
	environment.glow_bloom = 0.08
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.12
	env_node = WorldEnvironment.new()
	env_node.environment = environment
	env_node.name = "WorldEnvironment"
	add_child(env_node)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.light_angular_distance = 1.2
	add_child(sun)


func _build_sky_dome() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 400.0
	sphere.height = 800.0
	sphere.radial_segments = 40
	sphere.rings = 24
	sky_dome = MeshInstance3D.new()
	sky_dome.name = "SkyDome"
	sky_dome.mesh = sphere
	sky_dome.material_override = mats.sky
	sky_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sky_dome.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	sky_dome.render_priority = -100
	add_child(sky_dome)


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400, 1400)
	plane.subdivide_width = 40
	plane.subdivide_depth = 40
	water = MeshInstance3D.new()
	water.name = "Water"
	water.mesh = plane
	water.material_override = mats.water
	water.position = Vector3(0, Terrain.SEA_LEVEL, 0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(water)


## O céu e a luz seguem a hora do jogo.
func update_time(hour: float, daylight: float, phase: String) -> void:
	var dir := Game.sun_direction()
	sun.rotation = Vector3(0, 0, 0)
	# `dir` é a direção para onde a luz VIAJA (já vem negada em Game.sun_direction()).
	# O nó tem de ficar do lado OPOSTO, senão o sol nasce debaixo do terreno e
	# ilumina tudo por baixo — foi isso que deixou o chão às escuras.
	sun.look_at_from_position(-dir * 200.0, Vector3.ZERO, Vector3.UP)
	sun.light_color = Game.sun_color()
	var night := 1.0 - daylight
	sun.light_energy = lerpf(1.35, 0.22, night)
	sun.visible = true

	var dusk := 0.0
	if phase == "dusk" or phase == "dawn":
		dusk = clampf(1.0 - absf(daylight - 0.45) * 3.0, 0.0, 1.0)
	mats.apply_time(dir, daylight, dusk)

	environment.ambient_light_energy = lerpf(0.85, 0.30, night)
	environment.fog_light_color = Color(0.72, 0.83, 0.95).lerp(Color(0.07, 0.09, 0.18), night)
	environment.fog_light_color = environment.fog_light_color.lerp(Color(1.0, 0.62, 0.42), dusk * 0.5)
	environment.fog_density = lerpf(0.0032, 0.0062, night)
	environment.background_color = environment.fog_light_color
	environment.ambient_light_color = environment.fog_light_color.lightened(0.1)


# ══════════════════════════════════════════════════════════════════════════
#  CHUNKS
# ══════════════════════════════════════════════════════════════════════════
func set_target(p: Vector3) -> void:
	_target = p


func radius() -> int:
	return clampi(int(view_distance / Chunk.SIZE), 1, 6)


func _process(_delta: float) -> void:
	var c := Vector2i(int(floor(_target.x / Chunk.SIZE)), int(floor(_target.z / Chunk.SIZE)))
	var r := radius()
	if sky_dome:
		var cam := get_viewport().get_camera_3d()
		if cam:
			# o domo acompanha a câmara sem rodar: assim VERTEX continua a ser a direção
			sky_dome.global_position = cam.global_position
	if water:
		# a água segue o jogador em passos de 10 m para o shader não "nadar"
		water.position.x = snappedf(_target.x, 10.0)
		water.position.z = snappedf(_target.z, 10.0)
	if c == _last_center:
		return
	_last_center = c
	_update_chunks(c, r)


func _update_chunks(c: Vector2i, r: int) -> void:
	var deadline := Time.get_ticks_msec() + int(build_budget_ms)
	var wanted := {}
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var key := Vector2i(c.x + dx, c.y + dz)
			var d := maxi(absi(dx), absi(dz))
			wanted[key] = 0 if d <= 1 else (1 if d <= 2 else 2)
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
	order.sort_custom(func(a, b): return wanted[a] < wanted[b])
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
		ch.terrain = terrain
		ch.species = species
		ch.mats = mats
		ch.grass_quality = grass_quality
		add_child(ch)
	else:
		ch = _pool.pop_back()
	ch.name = "Chunk_%d_%d" % [key.x, key.y]
	ch.cx = key.x
	ch.cz = key.y
	ch.lod = lod
	ch.grass_quality = grass_quality
	return ch


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


func ground_height(x: float, z: float) -> float:
	return terrain.height(x, z)


func is_in_water(p: Vector3) -> bool:
	return terrain.height(p.x, p.z) < Terrain.SEA_LEVEL and p.y < Terrain.SEA_LEVEL + 0.6


func _apply_settings() -> void:
	view_distance = float(Game.settings["view_distance"])
	grass_quality = int(Game.settings["grass_quality"])
	shadows_enabled = int(Game.settings["shadows"]) > 0
	if sun:
		sun.shadow_enabled = shadows_enabled
		sun.directional_shadow_max_distance = [60.0, 120.0, 200.0][clampi(int(Game.settings["shadows"]), 0, 2)]
	if environment:
		environment.glow_enabled = int(Game.settings["film_grain"]) >= 0
	for ch in chunks.values():
		(ch as Chunk).grass_quality = grass_quality
	_last_center = Vector2i(999999, 999999)


func save_data() -> Dictionary:
	return {"seed": Game.world_seed}


func load_data(_d: Dictionary) -> void:
	for key in chunks.keys():
		(chunks[key] as Chunk).release()
	chunks.clear()
	_last_center = Vector2i(999999, 999999)
