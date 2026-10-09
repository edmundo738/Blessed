class_name Npc
extends CharacterBody3D
## Npc — um habitante do mundo, construído como LEGO.
##
## Poucas peças boas + regras de combinação + contexto real + memória +
## personalidade. A cadeia canónica está aqui, literalmente, em sete passos:
##
##   1 Percepção      → o que os sentidos apanham (distâncias, luz, hora, gestos)
##   2 Interpretação  → que situação é esta, para ESTA pessoa
##   3 Intenção       → o que ela quer
##   4 Decisão        → o que consegue fazer agora
##   5 Manifestação   → fá-lo (move-se, fala, oferece)
##   6 Consequência   → o mundo muda (relação, factos, objetivos)
##   7 Memória        → fica guardado e pesa nas próximas interpretações
##
## Nada de árvores de comportamento gigantes: são 6 intenções e 4 disposições,
## e a variedade nasce da combinação com memória e contexto.

enum Intent { IDLE, GREET, WARN, CHAT, FLEE, FOLLOW, SLEEP }

var id := "elder"
var display_key := "npc.elder.name"

## Peças de personalidade (0..1). Mudam tudo sem mudar código.
var personality := {"warmth": 0.65, "curiosity": 0.4, "fear": 0.35, "talkative": 0.7}

var memory: Array = []          # [{what, value, day, weight}]
var mood := 0.55
var intent: int = Intent.IDLE
var last_action := ""
var home := Vector3.ZERO
var wander_target := Vector3.ZERO
var wander_t := 0.0
var greet_cooldown := 0.0
var talk_cooldown := 0.0
var brain_t := 0.0
var alive := true

var player: Node3D
var world: Node3D
var structures: Structures

var _mesh: MeshInstance3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = hash(id)
	_build_body()
	Game.register_saver(self)


func _build_body() -> void:
	var body := MeshInstance3D.new()
	body.mesh = _make_mesh()
	body.position = Vector3(0, 0.85, 0)
	add_child(body)
	_mesh = body
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.7
	col.shape = cap
	col.position = Vector3(0, 0.85, 0)
	add_child(col)


func _make_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) ^ 0x1234
	var skin := Color(0.94, 0.80, 0.70)
	var cloth := Color(0.32, 0.40, 0.62)
	var hair := Color(0.85, 0.85, 0.90)
	# corpo
	var torso := MeshKit.box(Vector3(0.52, 0.78, 0.30), cloth)
	_append(st, torso, Vector3(0, 0.18, 0))
	# cabeça
	var head := MeshKit.blob(rng, 0.21, 1, 0.06, Vector3(0.92, 1.05, 0.92), Color.WHITE)
	_append(st, head, Vector3(0, 0.80, 0), Color(skin))
	# cabelo
	var cap := MeshKit.blob(rng, 0.225, 1, 0.10, Vector3(1.0, 0.85, 1.0), Color.WHITE)
	_append(st, cap, Vector3(0, 0.86, -0.01), Color(hair))
	# braços
	for s in [-1.0, 1.0]:
		var arm := MeshKit.box(Vector3(0.14, 0.62, 0.16), cloth.darkened(0.08))
		_append(st, arm, Vector3(s * 0.33, 0.16, 0))
	# saia/pernas
	var legs := MeshKit.box(Vector3(0.44, 0.62, 0.28), cloth.lightened(0.12))
	_append(st, legs, Vector3(0, -0.52, 0))
	return st.commit()


func _append(st: SurfaceTool, mesh: ArrayMesh, off: Vector3, tint: Color = Color.WHITE) -> void:
	var arr := mesh.surface_get_arrays(0)
	var verts: Array = arr[Mesh.ARRAY_VERTEX]
	var norms: Variant = arr[Mesh.ARRAY_NORMAL]
	var cols: Variant = arr[Mesh.ARRAY_COLOR]
	var idx: Variant = arr[Mesh.ARRAY_INDEX]
	var order: Array = (idx as Array) if (idx != null and not (idx as Array).is_empty()) else verts
	for k in order.size():
		var vi := int(order[k])
		var c: Color = (cols as Array)[vi] if cols != null else Color.WHITE
		st.set_color(c * tint)
		if norms != null:
			st.set_normal((norms as Array)[vi])
		st.add_vertex((verts[vi] as Vector3) + off)


# ══════════════════════════════════════════════════════════════════════════
#  A CADEIA
# ══════════════════════════════════════════════════════════════════════════
func _physics_process(delta: float) -> void:
	if not alive or Game.paused or not Game.started or player == null:
		return
	velocity.y -= 18.0 * delta
	brain_t -= delta
	if brain_t <= 0.0:
		brain_t = 0.35
		_tick()
	move_and_slide()
	_animate(delta)


func _tick() -> void:
	# 1 ── PERCEPÇÃO ────────────────────────────────────────────────────────
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	var percepts := {
		"dist": dist,
		"visible": dist < 26.0,
		"night": Game.is_night(),
		"player_hurt": _player_health() < 55.0,
		"player_near_fire": _near_light(player.global_position, 6.0),
		"i_near_fire": _near_light(global_position, 6.0),
		"blessing_high": _player_blessing() > 60.0,
		"recent_gift": recall("gift") != null,
	}

	# 2 ── INTERPRETAÇÃO ───────────────────────────────────────────────────
	var situ := _interpret(percepts)

	# 3 ── INTENÇÃO ────────────────────────────────────────────────────────
	intent = _choose_intent(situ)

	# 4/5 ── DECISÃO + MANIFESTAÇÃO ────────────────────────────────────────
	_act(situ)

	# 6 ── CONSEQUÊNCIA ────────────────────────────────────────────────────
	_consequences(situ)

	# 7 ── MEMÓRIA ─────────────────────────────────────────────────────────
	_remember(situ)


func _interpret(p: Dictionary) -> Dictionary:
	var trust := float(Game.trust(id))
	var quiet_bonus := 0.12 if str(Game.profile.get("soul", "")) == "quiet" else 0.0
	var situ := "calm"
	if p["night"] and not p["i_near_fire"]:
		situ = "afraid_dark"
	elif p["dist"] < 3.4 and greet_cooldown <= 0.0:
		situ = "encounter"
	elif p["player_hurt"] and p["dist"] < 12.0:
		situ = "concern"
	elif p["night"] and not p["player_near_fire"] and p["dist"] < 20.0:
		situ = "worry"
	elif p["blessing_high"] and p["dist"] < 14.0 and trust < 2:
		situ = "curious_blessing"
	elif p["dist"] > 30.0:
		situ = "alone"

	var valence: float = 0.5 + float(personality["warmth"]) * 0.2 + quiet_bonus
	if situ == "afraid_dark":
		valence -= personality["fear"] * 0.5
	if situ == "encounter":
		valence += trust * 0.06
	if situ == "concern":
		valence -= 0.1
	return {"situ": situ, "valence": clampf(valence, 0.0, 1.0), "trust": trust}


func _choose_intent(s: Dictionary) -> int:
	match str(s["situ"]):
		"afraid_dark":
			return Intent.FLEE
		"encounter":
			return Intent.GREET if s["trust"] < 6 else Intent.CHAT
		"worry":
			return Intent.WARN
		"concern":
			return Intent.CHAT
		"curious_blessing":
			return Intent.CHAT
		"alone":
			return Intent.SLEEP if Game.is_night() else Intent.IDLE
	return Intent.IDLE


func _act(s: Dictionary) -> void:
	match intent:
		Intent.FLEE:
			var away := (global_position - player.global_position).normalized()
			var target := _nearest_light()
			if target != Vector3.INF:
				away = (target - global_position).normalized()
			_move_toward(global_position + away * 4.0, 2.4)
			last_action = "flee"
		Intent.GREET:
			_face_player()
			greet_cooldown = 45.0
			var key := "npc.%s.greet_first" % id if Game.trust(id) <= 0 else "npc.%s.greet" % id
			if Game.is_night():
				key = "npc.%s.night" % id
			_say(key, 5.0)
			last_action = "greet"
		Intent.WARN:
			_face_player()
			_say("npc.%s.night" % id, 5.0)
			greet_cooldown = 30.0
			last_action = "warn"
		Intent.CHAT:
			_face_player()
			last_action = "chat"
		Intent.SLEEP:
			_move_toward(home, 1.0)
			last_action = "sleep"
		_:
			_wander()
			last_action = "idle"
	greet_cooldown = maxf(0.0, greet_cooldown - 0.35)
	talk_cooldown = maxf(0.0, talk_cooldown - 0.35)


## Fala para o ar (legendas + áudio de voz sintético).
func _say(key: String, seconds: float) -> void:
	Bus.subtitle_requested.emit(key, seconds)
	Sfx.play_at("ui_open", global_position + Vector3(0, 1.4, 0), -14.0, 1.35)


func _consequences(s: Dictionary) -> void:
	if last_action == "greet" and Game.trust(id) <= 0:
		Game.befriend(id, 1)
		Game.bump("npc_talked")
	if last_action == "warn":
		Game.bump("npc_warned")
	mood = clampf(mood * 0.9 + s["valence"] * 0.1, 0.0, 1.0)


func _remember(s: Dictionary) -> void:
	var situ := str(s["situ"])
	if situ in ["encounter", "concern", "curious_blessing", "afraid_dark"]:
		memory.append({"what": situ, "value": s["valence"], "day": Game.day, "weight": 1.0})
	# a memória é curta: ficam as últimas 24 e as mais pesadas
	if memory.size() > 24:
		memory = memory.slice(memory.size() - 24)


func recall(what: String) -> Variant:
	for i in range(memory.size() - 1, -1, -1):
		if str((memory[i] as Dictionary)["what"]) == what:
			return (memory[i] as Dictionary)["value"]
	return null


# ── movimento simples ─────────────────────────────────────────────────────
func _move_toward(target: Vector3, speed: float) -> void:
	var flat := target - global_position
	flat.y = 0.0
	if flat.length() < 0.4:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var d := flat.normalized()
	velocity.x = move_toward(velocity.x, d.x * speed, 12.0 * 0.35)
	velocity.z = move_toward(velocity.z, d.z * speed, 12.0 * 0.35)
	if world != null and world.has_method("ground_height"):
		var g: float = world.call("ground_height", global_position.x + d.x, global_position.z + d.z)
		if g > global_position.y + 0.4:
			velocity.y = 5.0


func _wander() -> void:
	wander_t -= 0.35
	if wander_t <= 0.0 or wander_target.distance_to(global_position) < 1.2:
		wander_t = randf_range(3.0, 8.0)
		var a := randf() * TAU
		var r := randf_range(2.0, 9.0)
		wander_target = home + Vector3(cos(a) * r, 0, sin(a) * r)
	_move_toward(wander_target, 1.2)


func _face_player() -> void:
	var d := player.global_position - global_position
	if d.length_squared() < 0.01:
		return
	rotation.y = atan2(d.x, d.z)


func _animate(delta: float) -> void:
	# respiração + olhar: barato, mas é o que faz parecer vivo
	var t := float(Time.get_ticks_msec()) * 0.001
	if _mesh:
		_mesh.position.y = 0.85 + sin(t * 1.6) * 0.012
		_mesh.rotation.z = sin(t * 0.7) * 0.02


# ── sentidos ──────────────────────────────────────────────────────────────
func _player_health() -> float:
	var s := player.get_node_or_null("Survival")
	return s.health if s != null else 100.0


func _player_blessing() -> float:
	var s := player.get_node_or_null("Survival")
	return s.blessing if s != null else 0.0


func _near_light(p: Vector3, radius: float) -> bool:
	if structures == null:
		return false
	for lp in structures.lit_positions():
		if (lp as Vector3).distance_to(p) < radius:
			return true
	return not Game.is_night()


func _nearest_light() -> Vector3:
	var best := Vector3.INF
	var bd := 1e18
	if structures == null:
		return best
	for lp in structures.lit_positions():
		var d: float = (lp as Vector3).distance_to(global_position)
		if d < bd:
			bd = d
			best = lp
	return best


# ══════════════════════════════════════════════════════════════════════════
#  DIÁLOGO
# ══════════════════════════════════════════════════════════════════════════
func interaction_target() -> Dictionary:
	return {"kind": "npc", "id": id}


func talk_to() -> void:
	_face_player()
	talk_cooldown = 2.0
	Game.bump("npc_talked")
	Game.befriend(id, 1)
	Bus.dialogue_started.emit(id)
	if Game.trust(id) <= 1:
		Bus.subtitle_requested.emit("npc.%s.greet_first" % id, 5.0)
	else:
		Bus.subtitle_requested.emit("npc.%s.greet" % id, 4.0)
	memory.append({"what": "talked", "value": 1.0, "day": Game.day, "weight": 1.0})


## Tópicos disponíveis agora (a UI mostra-os).
func topics() -> Array:
	var out := []
	out.append({"id": "night", "key": "npc.%s.topic_night" % id})
	out.append({"id": "world", "key": "npc.%s.topic_world" % id})
	if Game.trust(id) >= 2:
		out.append({"id": "blessed", "key": "npc.%s.topic_blessed" % id})
	out.append({"id": "bye", "key": "npc.%s.topic_bye" % id})
	return out


func answer(topic_id: String) -> String:
	memory.append({"what": "topic_" + topic_id, "value": 1.0, "day": Game.day, "weight": 0.6})
	Game.befriend(id, 1)
	return "npc.%s.a_%s" % [id, topic_id]


func display_name() -> String:
	return Loc.t(display_key)


func save_data() -> Dictionary:
	return {"pos": [global_position.x, global_position.y, global_position.z],
		"mood": mood, "mem": memory.slice(-12)}


func load_data(d: Dictionary) -> void:
	var p: Array = d.get("pos", [0, 0, 0])
	global_position = Vector3(p[0], p[1], p[2])
	home = global_position
	mood = float(d.get("mood", 0.55))
	memory = d.get("mem", [])
