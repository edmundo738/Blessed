class_name Animal
extends CharacterBody3D
## Animal — caça diurna, agora com corpo 3D e uma cabeça que decide.
##
## O animal existia para dar carne ao ciclo de sobrevivência, mas era um
## billboard de 24×18 pixels: não virava com o declive, não mexia as pernas e
## não dizia ao jogador se estava a pastar, alerta ou em fuga. Este ficheiro
## mantém o contrato (grupo `animals`, `hurt()`, drop de carne) e melhora o
## resto:
##
##   • corpo low-poly articulado (tronco, pescoço, cabeça, orelhas, hastes,
##     quatro pernas e cauda) — a silhueta lê-se a 30 m;
##   • estados GRAZE → WANDER → ALERT → FLEE com transições pelo que o bicho
##     vê, não por um temporizador de sorte;
##   • marcha com passada, cabeça que baixa a pastar e se levanta a olhar;
##   • coesão de bando e separação: os animais não andam uns dentro dos outros;
##   • som de passo pelo material do chão e fuga para longe da água funda.
##
## O comportamento continua barato: cinco animais no máximo, um `_think` por
## frame e nenhuma procura em toda a árvore (a lista do bando é atualizada a
## cada 0,5 s).

enum State { GRAZE, WANDER, ALERT, FLEE }

const FLEE_DIST := 9.5
const ALERT_DIST := 15.0
const CALM_DIST := 19.0
const PANIC_TIME := 4.0

var species := "grazer"
var speed := 1.6
var flee_speed := 4.4
var health := 6.0
var meat := 2
var world: Node3D
var player: Node3D
var inv: Node
var alive := true

var _body_root: Node3D
var _neck: Node3D
var _head: Node3D
var _tail: Node3D
var _legs: Array[Node3D] = []
var _ears: Array[Node3D] = []
var _mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _wish := Vector3.ZERO
var _wander_t := 0.0
var _panic_t := 0.0
var _bob_t := 0.0
var _step_t := 0.0
var _hurt_t := 0.0
var _state: State = State.GRAZE
var _state_t := 0.0
var _think_t := 0.0
var _grazing := true
var _player_dist := 999.0
var _last_strike_from := Vector3.ZERO
var _herd: Array[Node3D] = []
var _herd_t := 0.0
var _drink_t := 0.0

const FUR := Color("#8a5a32")
const FUR_DARK := Color("#6b451f")
const BELLY := Color("#c9b08a")
const INK := Color("#2b1d12")
const ANTLER := Color("#b8a67f")


func _ready() -> void:
	_rng.seed = randi()
	collision_layer = 2
	collision_mask = 1
	add_to_group("animals")
	_build()
	_pick_direction()
	_state = State.GRAZE
	_state_t = _rng.randf_range(1.0, 3.0)


func _build() -> void:
	_body_root = Node3D.new()
	_body_root.name = "GrazerBody"
	add_child(_body_root)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/toon_character.gdshader")
	_mat.set_shader_parameter("shadow_tint", Color(0.46, 0.50, 0.80))
	_mat.set_shader_parameter("bands", 3.0)
	_mat.set_shader_parameter("rim_strength", 0.20)

	# Tronco: uma massa comprida e baixa, com barriga clara por baixo. A
	# barriga é uma segunda malha, não uma cor de face: lê-se de lado.
	_add_part(_body_root, MeshKit.blob(_rng, 0.52, 2, 0.09,
		Vector3(1.35, 0.62, 0.60), FUR), Vector3(0, 0.82, 0))
	_add_part(_body_root, MeshKit.blob(_rng, 0.40, 1, 0.05,
		Vector3(1.10, 0.32, 0.52), BELLY), Vector3(0, 0.70, 0.03))
	# Peito mais estreito, para a frente não ser um cilindro cortado.
	_add_part(_body_root, MeshKit.blob(_rng, 0.30, 1, 0.08,
		Vector3(0.95, 0.95, 0.85), FUR), Vector3(0, 0.88, 0.38))

	# Pescoço articulado: o pivô fica na base do tronco e a malha aponta para
	# cima/frente. É este osso que faz a cabeça baixar a pastar.
	_neck = Node3D.new()
	_neck.name = "Neck"
	_neck.position = Vector3(0, 0.92, 0.36)
	_body_root.add_child(_neck)
	_add_between(_neck, Vector3(0, 0, 0), Vector3(0, 0.30, 0.16), 0.15, 0.10,
		FUR)

	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, 0.30, 0.16)
	_neck.add_child(_head)
	_add_part(_head, MeshKit.blob(_rng, 0.20, 2, 0.08,
		Vector3(0.86, 0.92, 1.15), FUR), Vector3(0, 0.03, 0.10))
	_add_part(_head, MeshKit.blob(_rng, 0.12, 1, 0.08,
		Vector3(0.72, 0.62, 1.25), FUR_DARK), Vector3(0, -0.01, 0.28))
	# Focinho escuro e olhos laterais (é assim que um herbívoro vê).
	_add_part(_head, MeshKit.blob(_rng, 0.055, 1, 0.04,
		Vector3(1.20, 0.52, 0.55), INK), Vector3(0, -0.01, 0.39))
	for side in [-1.0, 1.0]:
		_add_part(_head, MeshKit.blob(_rng, 0.027, 1, 0.0,
			Vector3(1.0, 0.9, 0.6), INK), Vector3(0.145 * float(side), 0.08, 0.17))
		# Orelhas: cones deitados para fora, sensíveis ao estado ALERT.
		var ear := Node3D.new()
		ear.position = Vector3(0.12 * float(side), 0.16, 0.05)
		ear.rotation_degrees = Vector3(-18, 0, 38 * float(side))
		_head.add_child(ear)
		_add_part(ear, MeshKit.cone(0.075, 0.24, 6, FUR_DARK),
			Vector3.ZERO, Vector3(0, 0, 0))
		_ears.append(ear)
	# Hastes de veado: duas hastes com uma forquilha. Não são decoração —
	# dizem "macho adulto" e dão escala à cabeça quando o bicho está longe.
	for side in [-1.0, 1.0]:
		var base := Vector3(0.075 * float(side), 0.17, 0.06)
		var mid := base + Vector3(0.09 * float(side), 0.20, 0.02)
		var tip := mid + Vector3(0.06 * float(side), 0.14, -0.02)
		_add_between(_head, base, mid, 0.025, 0.017, ANTLER)
		_add_between(_head, mid, tip, 0.018, 0.008, ANTLER)
		_add_between(_head, mid, mid + Vector3(0.13 * float(side), 0.09, 0.05),
			0.014, 0.006, ANTLER)

	# Quatro pernas. O pivô é a anca/ombro; a malha desce e a rotação X é a
	# passada. Guardar a ordem [frente_e, frente_d, trás_e, trás_d] permite
	# diagonais opostas na marcha.
	var hips := [
		Vector3(-0.18, 0.72, 0.30), Vector3(0.18, 0.72, 0.30),
		Vector3(-0.18, 0.72, -0.28), Vector3(0.18, 0.72, -0.28),
	]
	for i in hips.size():
		var leg := Node3D.new()
		leg.position = hips[i]
		_body_root.add_child(leg)
		_add_part(leg, MeshKit.tapered(_rng, 0.68, 0.070, 0.040, 6, 2, 0.0,
			false, FUR_DARK), Vector3.ZERO, Vector3(PI, 0, 0))
		_add_part(leg, MeshKit.box(Vector3(0.085, 0.075, 0.13), INK),
			Vector3(0, -0.69, 0.025))
		_legs.append(leg)

	_tail = Node3D.new()
	_tail.position = Vector3(0, 0.90, -0.35)
	_tail.rotation_degrees = Vector3(24, 0, 0)
	_body_root.add_child(_tail)
	_add_part(_tail, MeshKit.blob(_rng, 0.10, 1, 0.16,
		Vector3(0.55, 1.5, 0.55), FUR_DARK), Vector3(0, -0.10, -0.03))

	# Colisão vertical acompanha a nova altura.
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.05
	col.shape = cap
	col.position = Vector3(0, 0.55, 0)
	add_child(col)


func _add_part(parent: Node3D, mesh: ArrayMesh, off: Vector3,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.position = off
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


## Cilindro entre dois pontos locais (pescoço, hastes). A malha do MeshKit
## cresce em +Y; a base é rodada para a direção do osso.
func _add_between(parent: Node3D, a: Vector3, b: Vector3, r0: float, r1: float,
		tint: Color) -> MeshInstance3D:
	var delta := b - a
	var length := delta.length()
	var mesh := MeshKit.tapered(_rng, maxf(length, 0.01), r0, r1, 6, 2, 0.0,
		false, tint)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	var basis := Basis(Quaternion(Vector3.UP, delta.normalized()))
	mi.transform = Transform3D(basis, a)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# ── percepção / decisão ────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not alive or Game.paused:
		return
	_bob_t += delta
	_hurt_t = maxf(0.0, _hurt_t - delta)
	_panic_t = maxf(0.0, _panic_t - delta)
	_state_t += delta
	_think(delta)
	_move(delta)
	_animate(delta)


func _think(delta: float) -> void:
	var flat := Vector3.ZERO
	var dist := 999.0
	if is_instance_valid(player):
		flat = (player as Node3D).global_position - global_position
		flat.y = 0.0
		dist = flat.length()
	_player_dist = dist

	# A ameaça é o jogador a aproximar-se; um golpe é uma ameaça instantânea.
	if _panic_t > 0.0 or dist < FLEE_DIST:
		_enter(State.FLEE)
	elif dist < ALERT_DIST:
		if _state != State.FLEE:
			_enter(State.ALERT)
	elif _state == State.ALERT and dist > CALM_DIST:
		_enter(State.GRAZE)
	elif _state == State.FLEE and dist > CALM_DIST and _panic_t <= 0.0:
		_enter(State.ALERT)

	match _state:
		State.GRAZE:
			_wish = Vector3.ZERO
			if _state_t > 2.6 + _rng.randf() * 2.0:
				_enter(State.WANDER)
		State.WANDER:
			_wander_t -= delta
			if _wander_t <= 0.0:
				_pick_direction()
			if _state_t > 4.0:
				_enter(State.GRAZE)
		State.ALERT:
			_wish = Vector3.ZERO
			if dist < 5.5:
				_enter(State.FLEE)
		State.FLEE:
			if dist < 45.0 and dist > 0.01:
				_wish = -flat.normalized()
			elif _panic_t > 0.0 and _last_strike_from != Vector3.ZERO:
				var away := global_position - _last_strike_from
				away.y = 0.0
				_wish = away.normalized()
			else:
				_wish = Vector3.ZERO

	# Não entra em água funda: evita o bicho a nadar em círculos no rio.
	var ahead := global_position + _wish * 2.2
	if world != null and world.has_method("is_in_water"):
		if bool(world.call("is_in_water", ahead + Vector3(0, 0.4, 0))):
			var side := Vector3(-_wish.z, 0.0, _wish.x)
			_wish = (side if _rng.randf() > 0.5 else -side).normalized()
			_state_t = 0.0

	# Bando: coesão fraca + separação. Atualizado a 2 Hz, não por frame.
	_herd_t -= delta
	if _herd_t <= 0.0:
		_herd_t = 0.5
		_herd.clear()
		for other in get_tree().get_nodes_in_group("animals"):
			var on := other as Node3D
			if on == null or on == self or not is_instance_valid(on):
				continue
			if not bool(on.get("alive")):
				continue
			if on.global_position.distance_to(global_position) < 11.0:
				_herd.append(on)
	if _state != State.FLEE and not _herd.is_empty():
		var centre := Vector3.ZERO
		var push := Vector3.ZERO
		for other in _herd:
			var d := other.global_position - global_position
			d.y = 0.0
			centre += other.global_position
			if d.length() < 2.2 and d.length_squared() > 0.001:
				push -= d.normalized() * (2.2 - d.length()) * 0.55
		centre /= float(_herd.size())
		var to_centre := centre - global_position
		to_centre.y = 0.0
		_wish = (_wish + to_centre.normalized() * 0.20 + push * 0.35).normalized() \
			if (_wish + to_centre.normalized() * 0.20 + push * 0.35).length_squared() > 0.001 \
			else _wish


func _enter(next: State) -> void:
	if _state == next:
		return
	_state = next
	_state_t = 0.0
	if next == State.FLEE:
		_panic_t = maxf(_panic_t, PANIC_TIME)
		Sfx.play_at("growl", global_position, -18.0, _rng.randf_range(1.25, 1.55))
	elif next == State.ALERT:
		Sfx.play_at("pick", global_position, -24.0, 1.65)
	elif next == State.GRAZE:
		_pick_direction()
		_wish = Vector3.ZERO


func _pick_direction() -> void:
	var a := _rng.randf() * TAU
	_wish = Vector3(cos(a), 0.0, sin(a))
	_wander_t = _rng.randf_range(2.5, 6.0)


# ── movimento / chão ───────────────────────────────────────────────────────
func _move(delta: float) -> void:
	velocity.y = maxf(velocity.y - 18.0 * delta, -32.0)
	var wanted := _wish * (flee_speed if _state == State.FLEE else speed)
	velocity.x = move_toward(velocity.x, wanted.x, 11.0 * delta)
	velocity.z = move_toward(velocity.z, wanted.z, 11.0 * delta)

	var target_y := global_position.y
	if world != null:
		if world.has_method("is_in_water") and bool(world.call("is_in_water", global_position)):
			var surface := float(world.call("water_surface_height",
				global_position.x, global_position.z))
			target_y = surface - 0.55
			velocity.y = 0.0
		elif world.has_method("ground_height"):
			target_y = float(world.call("ground_height",
				global_position.x, global_position.z))
		global_position.y = lerpf(global_position.y, target_y, 1.0 - exp(-12.0 * delta))

	move_and_slide()

	var flat_vel := Vector3(velocity.x, 0.0, velocity.z)
	if flat_vel.length_squared() > 0.04:
		rotation.y = lerp_angle(rotation.y, atan2(flat_vel.x, flat_vel.z),
			1.0 - exp(-9.0 * delta))

	# Passos pelo material do chão.
	var spd := flat_vel.length()
	if spd > 0.6:
		_step_t -= delta * spd
		if _step_t <= 0.0:
			_step_t = 2.2
			var mat := "grass"
			if world != null and world.has_method("footstep_material_at"):
				mat = str(world.call("footstep_material_at",
					global_position.x, global_position.z))
			Sfx.play_at("step_" + mat, global_position, -20.0,
				_rng.randf_range(1.05, 1.30))


# ── animação ───────────────────────────────────────────────────────────────
func _animate(delta: float) -> void:
	var spd := Vector2(velocity.x, velocity.z).length()
	var moving := spd > 0.35
	if moving:
		_bob_t += delta * (1.2 + spd * 0.35)
	var gait := clampf(spd / flee_speed, 0.0, 1.4)
	var swing := sin(_bob_t * (5.2 + spd * 1.8)) * 0.58 * gait
	# Diagonais opostas: frente-esquerda anda com trás-direita.
	var signs := [1.0, -1.0, -1.0, 1.0]
	for i in _legs.size():
		_legs[i].rotation.x = swing * float(signs[i])

	# Tronco: respiração, balanço da passada e inclinação da fuga.
	var lean := -0.10 if _state == State.FLEE else 0.0
	_body_root.rotation.x = lerpf(_body_root.rotation.x, lean,
		1.0 - exp(-6.0 * delta))
	_body_root.position.y = sin(_bob_t * 2.4) * 0.015 + absf(swing) * 0.035
	_tail.rotation.z = sin(_bob_t * 2.0) * 0.22
	_tail.rotation.x = 0.42 + sin(_bob_t * 1.3) * 0.12

	# Cabeça: pastar, olhar para o jogador, ou fugir em frente.
	var head_pitch := 0.0
	var neck_pitch := 0.0
	match _state:
		State.GRAZE:
			head_pitch = 0.92 + sin(_bob_t * 2.6) * 0.08
			neck_pitch = 0.38
		State.WANDER:
			head_pitch = 0.10
			neck_pitch = 0.02
		State.ALERT:
			head_pitch = -0.10
			neck_pitch = -0.10
		State.FLEE:
			head_pitch = -0.22
			neck_pitch = -0.18
	_head.rotation.x = lerpf(_head.rotation.x, head_pitch, 1.0 - exp(-7.0 * delta))
	_neck.rotation.x = lerpf(_neck.rotation.x, neck_pitch, 1.0 - exp(-7.0 * delta))

	# Em ALERT a cabeça segue o jogador (yaw local), sem rodar o corpo todo.
	var look_yaw := 0.0
	if _state == State.ALERT and is_instance_valid(player):
		var to_p := (player as Node3D).global_position - global_position
		var local := Basis(Vector3.UP, -rotation.y) * to_p
		look_yaw = clampf(atan2(local.x, local.z), -0.7, 0.7)
	_head.rotation.y = lerpf(_head.rotation.y, look_yaw, 1.0 - exp(-6.0 * delta))
	for ear in _ears:
		ear.rotation.z += sin(_bob_t * 11.0 + float(ear.get_index())) * 0.0009 \
			* (2.5 if _state == State.ALERT else 1.0)

	if _hurt_t > 0.0:
		# Um solavanco de dor, curto e local.
		_body_root.rotation.z = sin(_hurt_t * 50.0) * 0.08 * (_hurt_t / 0.25)
	else:
		_body_root.rotation.z = lerpf(_body_root.rotation.z, 0.0,
			1.0 - exp(-10.0 * delta))


# ── dano / morte ───────────────────────────────────────────────────────────
func aim_point() -> Vector3:
	return global_position + Vector3(0, 0.95, 0)


## Um golpe. Qualquer ferramenta serve para caçar (as mãos também, mais devagar).
func hurt(amount: float) -> void:
	if not alive:
		return
	health -= amount
	_hurt_t = 0.25
	_panic_t = PANIC_TIME
	_last_strike_from = (player as Node3D).global_position if is_instance_valid(player) \
		else global_position
	_enter(State.FLEE)
	Sfx.play_at("pick", global_position, -8.0, _rng.randf_range(0.8, 0.95))
	if health > 0.0:
		# Foge na direção oposta ao golpe, para o jogador ter de correr atrás.
		var away := global_position - _last_strike_from
		away.y = 0.0
		if away.length_squared() > 0.01:
			_wish = away.normalized()
		return
	alive = false
	_die()


func _die() -> void:
	Sfx.play_at("body_fall", global_position, -5.0, 0.85)
	if world != null and world.has_method("ground_height"):
		var g: float = world.call("ground_height", global_position.x, global_position.z)
		global_position.y = g
	DroppedItem.spawn(world, "meat_raw", meat, global_position + Vector3(0, 0.3, 0),
		inv, player)
	Game.bump("animal_hunted")
	set_physics_process(false)
	# O corpo afunda e desaparece: o jogador vê a consequência, não um pop.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_body_root, "scale", Vector3(1.0, 0.08, 1.0), 0.55)
	tween.tween_property(_body_root, "rotation:x", 0.9, 0.55)
	tween.tween_property(_body_root, "position:y", -0.55, 0.55)
	tween.finished.connect(queue_free)
