extends Node
## Game — o relógio do mundo, o registo de comandos, a memória e o save.
##
## Duas cadeias vivem aqui:
##
##   Canónica:  Percepção → Interpretação → Intenção → Decisão →
##              Manifestação → Consequência → Memória
##   Técnica:   CONTRACT → OWNER → INPUT → DECISION → ACTION → OBSERVABLE RESULT
##
## A cadeia técnica é literal: cada ação do jogo é uma `CommandContract` com um
## dono (o sistema que sabe fazê-la), um contrato (o que garante), uma decisão
## (pré-condições) e um resultado observável. `request()` é a única porta:
## ninguém executa nada pelas costas, por isso tudo fica testável e gravável.

const SAVE_PATH := "user://save_0.json"
const DAY_SECONDS := 600.0        # duração real de um dia inteiro (10 min)
const DAWN := Vector2(5.0, 8.0)
const DAY_END := Vector2(18.0, 20.5)

# ── estado do mundo ──────────────────────────────────────────────────────────
var world_seed: int = 20260109
var day: int = 1
var hour: float = 6.6
var phase: String = "dawn"
var paused: bool = false
var started: bool = false

# ── perfil ───────────────────────────────────────────────────────────────────
var profile := {"name": "", "body": "f", "soul": "curious"}

# ── memória (factos + contadores + relações) ─────────────────────────────────
var facts: Dictionary = {}
var counters: Dictionary = {}
var relationships: Dictionary = {}
var objectives_done: Array = []
var objective_current: String = "wood"

# ── definições ───────────────────────────────────────────────────────────────
var settings := {
	"sensitivity": 0.35,
	"fov": 78.0,
	"invert_y": false,
	"volume": 0.7,
	"view_distance": 160.0,
	"grass_quality": 1,        # 0 baixo, 1 médio, 2 alto
	"shadows": 1,              # 0 desligado, 1 normal, 2 alto
	"head_bob": 1.0,
	"film_grain": 0.5,
	"subtitles": true,
	"horror": 1.0,             # 0 suave … 2 implacável
}

var _commands: Dictionary = {}
var _savers: Array = []


# ══════════════════════════════════════════════════════════════════════════
#  CONTRACT
# ══════════════════════════════════════════════════════════════════════════
class CommandContract extends RefCounted:
	## Um comando do jogo. `id` é o nome que a UI e os NPC usam.
	var id: String = ""
	var description_key: String = ""     # o que promete (CONTRACT)
	var owner: Node = null               # quem sabe fazer (OWNER)
	var can: Callable = Callable()       # INPUT + DECISION: (args) -> bool
	var run: Callable = Callable()       # ACTION: (args) -> Dictionary (RESULT)


func register_command(id: String, owner: Node, can: Callable, run: Callable, desc: String = "") -> void:
	var c := CommandContract.new()
	c.id = id
	c.owner = owner
	c.can = can
	c.run = run
	c.description_key = desc
	_commands[id] = c


func has_command(id: String) -> bool:
	return _commands.has(id)


## A única porta de entrada para agir no mundo.
func request(id: String, args: Dictionary = {}) -> Dictionary:
	Bus.intent_requested.emit(id, args)
	if not _commands.has(id):
		var miss := {"ok": false, "reason": "no_such_command"}
		Bus.command_resolved.emit(id, false, miss)
		return miss
	var c: CommandContract = _commands[id]
	if c.can.is_valid() and not c.can.call(args):
		var denied := {"ok": false, "reason": "denied"}
		Bus.command_resolved.emit(id, false, denied)
		return denied
	var result: Dictionary = {}
	if c.run.is_valid():
		result = c.run.call(args)
	result["ok"] = not bool(result.get("failed", false))
	Bus.command_resolved.emit(id, bool(result["ok"]), result)
	return result


# ══════════════════════════════════════════════════════════════════════════
#  ARRANQUE
# ══════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	_build_input_map()
	_load_prefs()
	Sfx.set_volume_db(linear_to_db(clampf(float(settings["volume"]), 0.001, 1.0)))
	Bus.ui_message.connect(_on_ui_message)


func _build_input_map() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT],
		"crouch": [KEY_CTRL],
		"jump": [KEY_SPACE],
		"interact": [KEY_F],
		"use": [],            # rato esquerdo, ver abaixo
		"bag": [KEY_TAB],
		"journal": [KEY_J],
		"map": [KEY_M],
		"build": [KEY_B],
		"pause": [KEY_ESCAPE],
		"lean_left": [KEY_Q],
		"lean_right": [KEY_E],
		"drop": [KEY_G],
		"save": [KEY_F5],
		"locale": [KEY_F2],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for kc in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = kc
			if not InputMap.action_has_event(action, ev):
				InputMap.action_add_event(action, ev)
	# botões do rato
	if not InputMap.has_action("use"):
		InputMap.add_action("use")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	if not InputMap.action_has_event("use", mb):
		InputMap.action_add_event("use", mb)
	# barra rápida 1..9
	for i in 9:
		var a := "hotbar_%d" % (i + 1)
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		var kev := InputEventKey.new()
		kev.physical_keycode = KEY_1 + i
		if not InputMap.action_has_event(a, kev):
			InputMap.action_add_event(a, kev)


# ══════════════════════════════════════════════════════════════════════════
#  TEMPO / FASES DO DIA
# ══════════════════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	if paused or not started:
		return
	hour += delta * (24.0 / DAY_SECONDS)
	if hour >= 24.0:
		hour -= 24.0
		day += 1
		Bus.toast.emit("msg.dawn", 5.0)
		Bus.subtitle_requested.emit("msg.dawn", 4.0)
	var p := current_phase()
	if p != phase:
		phase = p
		Bus.phase_changed.emit(phase)
		if phase == "dusk":
			Bus.toast.emit("msg.night_falls", 5.0)
	Bus.time_advanced.emit(hour, day)


func current_phase() -> String:
	if hour >= DAWN.x and hour < DAWN.y:
		return "dawn"
	if hour >= DAWN.y and hour < DAY_END.x:
		return "day"
	if hour >= DAY_END.x and hour < DAY_END.y:
		return "dusk"
	return "night"


## 0.0 = breu total, 1.0 = meio-dia. Usado pelo céu, pelo medo e pela relva.
func daylight() -> float:
	var h := hour
	if h < DAWN.x or h >= DAY_END.y:
		return 0.0
	if h < DAWN.y:
		return smooth(DAWN.x, DAWN.y, h)
	if h > DAY_END.x:
		return 1.0 - smooth(DAY_END.x, DAY_END.y, h)
	# meio do dia: curva suave com pico às 13h
	return clampf(1.0 - absf(h - 13.0) / 9.0, 0.35, 1.0)


func is_night() -> bool:
	return phase == "night"


## Cor do sol/luz ambiente em função da hora (para o céu e a luz direcional).
func sun_color() -> Color:
	var d := daylight()
	var warm := Color(1.0, 0.62, 0.42)     # nascer/pôr
	var noon := Color(1.0, 0.96, 0.88)
	var night_c := Color(0.35, 0.45, 0.75)
	var c: Color = noon.lerp(warm, 1.0 - clampf(d * 1.4, 0.0, 1.0))
	return c.lerp(night_c, 1.0 - d)


func sun_direction() -> Vector3:
	# O sol nasce a este (+X) e põe-se a oeste (-X).
	var t := clampf((hour - 5.5) / 13.0, -0.2, 1.2)
	var ang := PI * t
	var dir := Vector3(cos(ang), sin(ang) * 0.9 + 0.12, 0.28).normalized()
	return -dir  # direção "para onde aponta" a luz


func smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func clock_string() -> String:
	var h := int(hour) % 24
	var m := int(fmod(hour * 60.0, 60.0))
	return "%02d:%02d" % [h, m]


# ══════════════════════════════════════════════════════════════════════════
#  MEMÓRIA
# ══════════════════════════════════════════════════════════════════════════
func remember(fact_id: String, value: Variant, subject: String = "world") -> void:
	facts[fact_id] = value
	Bus.fact_recorded.emit(fact_id, subject, value)


func recall(fact_id: String, default: Variant = null) -> Variant:
	return facts.get(fact_id, default)


## Contadores: a moeda dos objetivos e da memória dos NPC.
func bump(key: String, amount: int = 1) -> void:
	counters[key] = int(counters.get(key, 0)) + amount
	_check_objectives()


func count(key: String) -> int:
	return int(counters.get(key, 0))


func befriend(npc_id: String, delta: int = 1) -> void:
	relationships[npc_id] = int(relationships.get(npc_id, 0)) + delta
	Bus.relationship_changed.emit(npc_id, delta, int(relationships[npc_id]))


func trust(npc_id: String) -> int:
	return int(relationships.get(npc_id, 0))


func _check_objectives() -> void:
	if objective_current.is_empty():
		return
	var spec := Db.recipe("")  # placeholder para não capturar
	for o in Db.OBJECTIVES:
		if str(o["id"]) != objective_current:
			continue
		if count(str(o["track"])) >= int(o["target"]):
			objectives_done.append(objective_current)
			Bus.objective_done.emit(objective_current)
			objective_current = str(o["next"])
			if not objective_current.is_empty():
				Bus.objective_added.emit(objective_current)
		break


# ══════════════════════════════════════════════════════════════════════════
#  DEFINIÇÕES
# ══════════════════════════════════════════════════════════════════════════
func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	apply_settings()


func apply_settings() -> void:
	Sfx.set_volume_db(linear_to_db(clampf(float(settings["volume"]), 0.001, 1.0)))
	_save_prefs()
	Bus.settings_changed.emit()


func _load_prefs() -> void:
	var path := "user://prefs.json"
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for k in (parsed as Dictionary):
		if settings.has(k):
			settings[k] = (parsed as Dictionary)[k]


func _save_prefs() -> void:
	var f := FileAccess.open("user://prefs.json", FileAccess.WRITE)
	if not f:
		return
	var d := settings.duplicate()
	d["locale"] = Loc.code
	f.store_string(JSON.stringify(d, "\t"))
	f.close()


func _on_ui_message(_key: String, _seconds: float) -> void:
	pass


# ══════════════════════════════════════════════════════════════════════════
#  SAVE / LOAD
# ══════════════════════════════════════════════════════════════════════════
## Cada sistema que tem estado regista-se aqui.
func register_saver(node: Node) -> void:
	if not _savers.has(node):
		_savers.append(node)


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	var data := {
		"version": 1,
		"seed": world_seed,
		"profile": profile,
		"day": day,
		"hour": hour,
		"facts": facts,
		"counters": counters,
		"relationships": relationships,
		"objectives_done": objectives_done,
		"objective_current": objective_current,
		"systems": {},
	}
	for n in _savers:
		if is_instance_valid(n) and n.has_method("save_data"):
			data["systems"][n.name] = n.call("save_data")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not f:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	Bus.say("msg.saved", 2.0)
	return true


func load_game() -> bool:
	if not has_save():
		Bus.say("menu.no_save", 3.0)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	world_seed = int(d.get("seed", world_seed))
	profile = d.get("profile", profile)
	day = int(d.get("day", 1))
	hour = float(d.get("hour", 6.6))
	facts = d.get("facts", {})
	counters = d.get("counters", {})
	relationships = d.get("relationships", {})
	objectives_done = d.get("objectives_done", [])
	objective_current = str(d.get("objective_current", ""))
	var systems: Dictionary = d.get("systems", {})
	for n in _savers:
		if is_instance_valid(n) and n.has_method("load_data") and systems.has(n.name):
			n.call("load_data", systems[n.name])
	phase = current_phase()
	Bus.say("menu.loaded", 2.0)
	return true


func new_game(seed_value: int = 0) -> void:
	world_seed = seed_value if seed_value != 0 else randi()
	day = 1
	hour = 6.6
	phase = current_phase()
	facts.clear()
	counters.clear()
	relationships.clear()
	objectives_done.clear()
	objective_current = "wood"
	started = true
	Bus.objective_added.emit(objective_current)
