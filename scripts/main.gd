extends Node
## Main — monta o mundo e liga os sistemas.
##
## Ordem de montagem importa: o mundo primeiro (dá alturas), depois as
## estruturas, depois o jogador, depois o que depende dele. Nenhum sistema
## conhece outro: comunicam pelo Bus e por referências explícitas passadas aqui.

var world: World
var structures: Structures
var fx: Node3D
var npc_root: Node3D
var village: Village
var player: Player
var survival: Survival
var inv: Inventory
var interaction: Interaction
var night: NightDirector
var creature_root: Node3D
var hud: Hud
var menus: Menus
var prologo: Prologo

var _cinema_t := 0.0


func _ready() -> void:
	randomize()
	_build_world()
	_build_player()
	_build_systems()
	_build_ui()
	_starter_kit()
	# o mundo à volta do spawn começa logo a existir
	world.set_target(player.global_position)
	world._update_chunks(Vector2i(int(floor(player.global_position.x / Chunk.SIZE)),
		int(floor(player.global_position.z / Chunk.SIZE))), world.radius())
	print("BLESSED pronto. seed=", Game.world_seed)
	var all_args := OS.get_cmdline_args() + OS.get_cmdline_user_args()

	# sondas de desenvolvimento: `-- selftest`, `-- diag`, …
	# (fora do .pck; servem para medir o jogo a sério, não para jogar)
	for arg in all_args:
		var s_arg := str(arg)
		if s_arg in ["selftest", "diag"]:
			_start_probe(s_arg)
			break


## Arranca uma sonda de desenvolvimento (tests/<nome>.gd).
func _start_probe(which: String) -> void:
	var path := "res://tests/%s.gd" % which
	if not ResourceLoader.exists(path):
		print("SELFTEST_FAIL: %s em falta" % path)
		get_tree().quit(1)
		return
	var st: Node = load(path).new()
	st.call("setup", self)
	add_child(st)


func _build_world() -> void:
	world = World.new()
	add_child(world)

	structures = Structures.new()
	structures.species = world.species
	structures.mats = world.mats
	add_child(structures)
	structures.setup(world.species, world.mats)

	fx = Node3D.new()
	fx.set_script(load("res://scripts/world/fx.gd"))
	add_child(fx)

	npc_root = Node3D.new()
	npc_root.name = "Npcs"
	add_child(npc_root)

	village = Village.new()
	village.world = world
	village.structures = structures
	village.npc_root = npc_root
	village.species = world.species
	village.mats = world.mats
	add_child(village)
	village.build()


## Onde se nasce.
##
## A aldeia é a referência visual do mundo, por isso nasce-se a ~20-32 m do
## centro: perto o bastante para ver as cabanas, longe o bastante para não
## ficar dentro do anel das fogueiras (o NightDirector não gera criaturas a
## menos de 10 m de uma luz, e nascer encostado a uma tornava a primeira noite
## impossível de avaliar). Antes o spawn saía à volta da ORIGEM, a ~96 m das
## casas — não se via rigorosamente nada.
func _pick_spawn() -> Vector3:
	var ter: Terrain = world.terrain
	var vc: Vector2 = ter.village_center()
	var lit: Array = structures.lit_positions()
	var fallback := ter.find_spawn(vc, 24.0)
	for rr in [20.0, 26.0, 32.0]:
		var ring: float = float(rr)
		for i in 32:
			var a := float(i) / 32.0 * TAU
			var x: float = vc.x + cos(a) * ring
			var z: float = vc.y + sin(a) * ring
			if ter.slope(x, z) >= 0.35 or ter.is_water(x, z):
				continue
			var near_fire := false
			for lp in lit:
				if (lp as Vector3).distance_to(Vector3(x, 0, z)) < 14.0:
					near_fire = true
					break
			if near_fire:
				continue
			return Vector3(x, ter.height(x, z), z)
	return fallback


func _build_player() -> void:
	player = Player.new()
	world.add_child(player)
	player.global_position = _pick_spawn() + Vector3(0, 1.0, 0)

	survival = Survival.new()
	player.add_child(survival)


func _build_systems() -> void:
	inv = Inventory.new()
	add_child(inv)

	interaction = Interaction.new()
	interaction.player = player
	interaction.world = world
	interaction.survival = survival
	interaction.inv = inv
	interaction.structures = structures
	interaction.fx = fx
	interaction.npc_root = npc_root
	add_child(interaction)

	creature_root = Node3D.new()
	creature_root.name = "Creatures"
	add_child(creature_root)

	night = NightDirector.new()
	night.player = player
	night.world = world
	night.structures = structures
	night.survival = survival
	night.root = creature_root
	add_child(night)


func _build_ui() -> void:
	hud = Hud.new()
	hud.inv = inv
	hud.interaction = interaction
	hud.survival = survival
	hud.player = player
	add_child(hud)

	menus = Menus.new()
	menus.inv = inv
	menus.interaction = interaction
	menus.survival = survival
	menus.player = player
	add_child(menus)

	prologo = Prologo.new()
	add_child(prologo)

	Bus.time_advanced.connect(_on_time)
	Bus.locale_changed.connect(_on_locale)
	_on_time(Game.hour, Game.day)


func _starter_kit() -> void:
	inv.add("torch", 1)
	inv.add("berry", 3)


# ══════════════════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	if not Game.started:
		_cinema(delta)
		return
	world.set_target(player.global_position)
	_apply_player_state()
	_sense_light()
	_hotbar_input()


func _apply_player_state() -> void:
	player.speed_multiplier = survival.speed_multiplier()
	player.stamina_drain_multiplier = 1.0 if survival.energy > 25.0 else 1.5


func _sense_light() -> void:
	var l := Game.daylight()
	# tocha na mão
	if inv.hotbar_id() == "torch":
		l = maxf(l, 0.55)
	# fogueiras acesas
	for p in structures.lit_positions():
		var d: float = (p as Vector3).distance_to(player.global_position)
		if d < 12.0:
			l = maxf(l, clampf(1.0 - d / 12.0, 0.0, 1.0) * 0.95)
	survival.light_level = clampf(l, 0.0, 1.0)
	survival.near_fire = not structures.lit_positions().is_empty() \
		and _min_light_distance() < 7.0
	survival.sheltered = structures.has_shelter(player.global_position, 5.0)
	survival.companion_near = _companion_near()


func _min_light_distance() -> float:
	var best := 1e18
	for p in structures.lit_positions():
		best = minf(best, (p as Vector3).distance_to(player.global_position))
	return best


func _companion_near() -> bool:
	for c in npc_root.get_children():
		if c is Node3D and (c as Node3D).global_position.distance_to(player.global_position) < 9.0:
			return true
	return false


func _hotbar_input() -> void:
	for i in 9:
		if Input.is_action_just_pressed("hotbar_%d" % (i + 1)):
			inv.select(i)


func _unhandled_input(event: InputEvent) -> void:
	if not Game.started:
		return
	if event.is_action_pressed("save"):
		Game.save_game()
	elif event.is_action_pressed("drop"):
		var id := inv.hotbar_id()
		if id != "":
			inv.remove(id, 1)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			inv.next_slot(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			inv.next_slot(1)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if survival.blessing >= 35.0:
			survival.flare_blessing()
			_push_back_creatures()


func _push_back_creatures() -> void:
	for c in get_tree().get_nodes_in_group("creatures"):
		if is_instance_valid(c):
			(c as Creature).hurt(18.0)


func _on_time(hour: float, day: int) -> void:
	if world != null:
		world.update_time(hour, Game.daylight(), Game.current_phase())


func _on_locale(_code: String) -> void:
	if hud:
		hud.refresh_locale()


# ══════════════════════════════════════════════════════════════════════════
#  Câmar cinematográfica do prólogo: uma volta lenta sobre o vale.
# ══════════════════════════════════════════════════════════════════════════
func _cinema(delta: float) -> void:
	_cinema_t += delta
	var c := world.terrain.village_center()
	var a := _cinema_t * 0.07
	var r := 26.0 + sin(_cinema_t * 0.11) * 6.0
	var p := Vector3(c.x + cos(a) * r, 0, c.y + sin(a) * r)
	p.y = world.ground_height(p.x, p.z) + 4.5 + sin(_cinema_t * 0.2) * 1.2
	player.global_position = p
	player.target_yaw = atan2(-(c.x - p.x), -(c.y - p.z))
	player.target_pitch = -0.12
	player.yaw = lerpf(player.yaw, player.target_yaw, 1.0 - exp(-1.5 * delta))
	player.pitch = lerpf(player.pitch, player.target_pitch, 1.0 - exp(-1.5 * delta))
	player.rotation.y = player.yaw
	player.cam_pivot.rotation.x = player.pitch
	world.set_target(p)
	world.update_time(Game.hour, Game.daylight(), Game.current_phase())
