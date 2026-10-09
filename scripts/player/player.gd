class_name Player
extends CharacterBody3D
## Player — controlo em 1ª pessoa com "peso".
##
## O que faz parecer AAA não é a velocidade, é o conjunto:
##   • aceleração e atrito (não é teletransporte de velocidade)
##   • tempo de coyote + buffer de salto (o jogo perdoa, o jogador não nota)
##   • head bob ligado à velocidade real, com roll e FOV
##   • inclinação (lean) com mola, não instantânea
##   • aterragem com mergulho da câmara e som próprio
##   • passos sincronizados com o ciclo do bob e com o material do chão
##   • natação com flutuação em vez de "voar baixo"

const EYE := 1.62
const CROUCH_EYE := 1.05
const RADIUS := 0.34
const HEIGHT := 1.78

const WALK := 3.6
const SPRINT := 6.4
const CROUCH_SPEED := 1.7
const SWIM := 3.0
const ACCEL_GROUND := 14.0
const ACCEL_AIR := 3.2
const FRICTION := 11.0
const JUMP_VELOCITY := 5.1
const GRAVITY := 17.5
const COYOTE := 0.14
const JUMP_BUFFER := 0.14

var camera: Camera3D
var cam_pivot: Node3D
var lean_node: Node3D
var hands: Node3D
var collider: CollisionShape3D

var yaw := 0.0
var pitch := 0.0
var target_yaw := 0.0
var target_pitch := 0.0
var lean := 0.0
var target_lean := 0.0

var bob_t := 0.0
var bob_amp := 0.0
var step_phase := 0.0
var coyote := 0.0
var jump_buffer := 0.0
var crouching := false
var sprinting := false
var swimming := false
var was_grounded := true
var stamina := 100.0
var surface := "grass"
var enabled := true

## chamado pelo Survival
var speed_multiplier := 1.0
var stamina_drain_multiplier := 1.0

signal stepped(surface: String)
signal landed(force: float)
signal jumped()


func _ready() -> void:
	name = "Player"
	_build_tree()
	Game.register_saver(self)


func _build_tree() -> void:
	collider = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	collider.shape = cap
	collider.position = Vector3(0, HEIGHT * 0.5, 0)
	add_child(collider)

	cam_pivot = Node3D.new()
	cam_pivot.name = "CamPivot"
	cam_pivot.position = Vector3(0, EYE, 0)
	add_child(cam_pivot)

	lean_node = Node3D.new()
	lean_node.name = "Lean"
	cam_pivot.add_child(lean_node)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = float(Game.settings["fov"])
	camera.near = 0.05
	camera.far = 900.0
	camera.current = true
	lean_node.add_child(camera)

	hands = Node3D.new()
	hands.name = "Hands"
	camera.add_child(hands)
	var hands_script: GDScript = load("res://scripts/player/hands.gd")
	hands.set_script(hands_script)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := float(Game.settings["sensitivity"]) * 0.0022
		target_yaw -= event.relative.x * sens
		var inv := -1.0 if bool(Game.settings["invert_y"]) else 1.0
		target_pitch -= event.relative.y * sens * inv
		target_pitch = clampf(target_pitch, -1.45, 1.45)


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_smooth_look(delta)
	_swim_check()
	var wish := _wish_direction()
	if swimming:
		_move_swim(delta, wish)
	else:
		_move_land(delta, wish)
	_head_bob(delta)
	move_and_slide()
	_surface_probe()


# ── câmara ────────────────────────────────────────────────────────────────
func _smooth_look(delta: float) -> void:
	# suavização curta: tira o "digital" do rato sem parecer atraso
	var k := 1.0 - exp(-38.0 * delta)
	yaw = lerpf(yaw, target_yaw, k)
	pitch = lerpf(pitch, target_pitch, k)
	rotation.y = yaw
	cam_pivot.rotation.x = pitch

	var want := 0.0
	if Input.is_action_pressed("lean_left"):
		want += 1.0
	if Input.is_action_pressed("lean_right"):
		want -= 1.0
	target_lean = want
	lean = lerpf(lean, target_lean, 1.0 - exp(-9.0 * delta))
	lean_node.rotation.z = lean * 0.14
	lean_node.position.x = lean * 0.13


# ── direção pedida ────────────────────────────────────────────────────────
## Direção pedida, em espaço LOCAL do jogador.
##
## Convenção Godot: a câmara e o jogador olham para **-Z**. Por isso
## "para a frente" é z NEGATIVO. Antes isto estava trocado nos dois eixos:
## usava +Z como frente (W andava para trás) e get_axis("move_right",
## "move_left") devolve +1 quando se carrega em A (A andava para a direita).
## tests/diag.gd mede isto tecla a tecla — ver "A. CONTROLOS".
func _wish_direction() -> Vector3:
	# get_axis(negativo, positivo) = força(positivo) - força(negativo).
	# A ordem dos argumentos importa: trocá-la inverte o eixo.
	var lr := Input.get_axis("move_left", "move_right")    # D → +1, A → -1
	var fb := Input.get_axis("move_back", "move_forward")  # W → +1, S → -1
	var v := Vector3(lr, 0.0, -fb)
	return v.normalized() if v.length_squared() > 0.0001 else Vector3.ZERO


func _move_land(delta: float, wish: Vector3) -> void:
	# gravidade
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
		coyote = maxf(0.0, coyote - delta)
	else:
		coyote = COYOTE

	# agachar
	var want_crouch := Input.is_action_pressed("crouch")
	if want_crouch != crouching:
		crouching = want_crouch
		var h := CROUCH_EYE if crouching else EYE
		collider.shape.height = HEIGHT * (0.62 if crouching else 1.0)
		collider.position.y = collider.shape.height * 0.5
		_animate_eye(h)

	# sprint só com fôlego e a andar para a frente
	var has_stamina := stamina > 2.0
	sprinting = Input.is_action_pressed("sprint") and not crouching \
		and wish.z < -0.2 and has_stamina and is_on_floor()  # frente é -Z
	var target_speed := WALK
	if sprinting:
		target_speed = SPRINT
	elif crouching:
		target_speed = CROUCH_SPEED
	target_speed *= speed_multiplier

	var dir_world := (transform.basis * Vector3(wish.x, 0, wish.z)).normalized() \
		if wish.length_squared() > 0.0001 else Vector3.ZERO
	var accel := ACCEL_GROUND if is_on_floor() else ACCEL_AIR
	var flat := Vector3(velocity.x, 0, velocity.z)
	var target_vel := dir_world * target_speed
	flat = flat.move_toward(target_vel, accel * delta * (1.0 if is_on_floor() else 0.55))
	if wish.length_squared() < 0.0001 and is_on_floor():
		flat = flat.move_toward(Vector3.ZERO, FRICTION * delta)
	velocity.x = flat.x
	velocity.z = flat.z

	# fôlego
	if sprinting:
		stamina = maxf(0.0, stamina - 14.0 * delta * stamina_drain_multiplier)
	else:
		stamina = minf(100.0, stamina + (9.0 if is_on_floor() else 4.0) * delta)
	Bus.stat_changed.emit("stamina", stamina, 100.0)

	# saltar com buffer + coyote
	if Input.is_action_just_pressed("jump"):
		jump_buffer = JUMP_BUFFER
	jump_buffer = maxf(0.0, jump_buffer - delta)
	if jump_buffer > 0.0 and (is_on_floor() or coyote > 0.0):
		velocity.y = JUMP_VELOCITY * (0.72 if crouching else 1.0)
		jump_buffer = 0.0
		coyote = 0.0
		jumped.emit()
		Sfx.play("step_grass", -14.0, 1.4)

	# aterragem
	if is_on_floor() and not was_grounded:
		var force := clampf(absf(velocity.y) / 12.0, 0.0, 1.0)
		landed.emit(force)
		if force > 0.12:
			Sfx.play_at("step_" + surface, global_position, -8.0, 0.8)
	was_grounded = is_on_floor()

	# FOV respira com a velocidade
	var spd := Vector3(velocity.x, 0, velocity.z).length()
	var want_fov := float(Game.settings["fov"]) + (spd / SPRINT) * 7.0
	camera.fov = lerpf(camera.fov, want_fov, 1.0 - exp(-6.0 * delta))


func _move_swim(delta: float, wish: Vector3) -> void:
	var dir_world := (transform.basis * Vector3(wish.x, 0, wish.z)).normalized() \
		if wish.length_squared() > 0.0001 else Vector3.ZERO
	var flat := Vector3(velocity.x, 0, velocity.z).move_toward(dir_world * SWIM, 9.0 * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	# flutuação: sobe devagar, afunda devagar, salto = braçada
	var up := 0.0
	if Input.is_action_pressed("jump"):
		up = 2.6
	elif Input.is_action_pressed("crouch"):
		up = -2.4
	var target_y := up - 0.5
	velocity.y = lerpf(velocity.y, target_y, 1.0 - exp(-5.0 * delta))
	stamina = minf(100.0, stamina + 3.0 * delta)
	Bus.stat_changed.emit("stamina", stamina, 100.0)
	camera.fov = lerpf(camera.fov, float(Game.settings["fov"]) + 3.0, 1.0 - exp(-4.0 * delta))


func _swim_check() -> void:
	var was := swimming
	swimming = get_parent() != null and get_parent().has_method("is_in_water") \
		and get_parent().call("is_in_water", global_position)
	if swimming and not was:
		Sfx.play("splash", -6.0, 1.0)
		velocity.y *= 0.3
	elif was and not swimming:
		Sfx.play("splash", -10.0, 1.3)


# ── head bob / passos ─────────────────────────────────────────────────────
func _head_bob(delta: float) -> void:
	var spd := Vector3(velocity.x, 0, velocity.z).length()
	var grounded := is_on_floor() and not swimming
	var strength := clampf(spd / SPRINT, 0.0, 1.3) * float(Game.settings["head_bob"])
	bob_amp = lerpf(bob_amp, strength if grounded else 0.0, 1.0 - exp(-8.0 * delta))
	if bob_amp > 0.001:
		bob_t += delta * (7.4 + spd * 0.75)
	else:
		bob_t = lerpf(bob_t, roundf(bob_t / PI) * PI, 1.0 - exp(-6.0 * delta))
	var amp := 0.055 * bob_amp
	var base := CROUCH_EYE if crouching else EYE
	var swim_dip := -0.25 if swimming else 0.0
	camera.position = Vector3(
		cos(bob_t) * amp * 0.8,
		sin(bob_t * 2.0) * amp + swim_dip,
		sin(bob_t) * amp * 0.35)
	lean_node.rotation.z += sin(bob_t) * 0.012 * bob_amp

	# passos no ponto certo do ciclo
	if grounded and bob_amp > 0.12:
		step_phase += delta * (2.0 + spd * 0.42)
		if step_phase >= 1.0:
			step_phase = 0.0
			stepped.emit(surface)
			Sfx.play_at("step_" + surface, global_position,
				-13.0 - (4.0 if sprinting else 0.0), randf_range(0.92, 1.1))


func _animate_eye(h: float) -> void:
	var tw := create_tween()
	tw.tween_property(cam_pivot, "position:y", h, 0.16)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _surface_probe() -> void:
	# o chão por baixo decide o som do passo
	var w := get_parent()
	if w == null or not w.has_method("ground_height"):
		surface = "grass"
		return
	var h: float = w.call("ground_height", global_position.x, global_position.z)
	if h < Terrain.SEA_LEVEL + 0.35:
		surface = "water" if global_position.y < Terrain.SEA_LEVEL + 0.6 else "stone"
	elif global_position.y < h + 0.3:
		surface = "grass"
	if w.has_method("path_distance_at"):
		pass


## Teletransporte suave (spawn, respawn, viagem rápida).
func teleport(p: Vector3) -> void:
	global_position = p
	velocity = Vector3.ZERO
	target_pitch = 0.0
	pitch = 0.0


func look_at_point(p: Vector3) -> void:
	var d := p - global_position - Vector3(0, EYE, 0)
	target_yaw = atan2(-d.x, -d.z)
	target_pitch = atan2(d.y, Vector2(d.x, d.z).length())


func save_data() -> Dictionary:
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"yaw": yaw, "pitch": pitch, "stamina": stamina,
	}


func load_data(d: Dictionary) -> void:
	var p: Array = d.get("pos", [0, 0, 0])
	teleport(Vector3(p[0], p[1], p[2]))
	yaw = float(d.get("yaw", 0.0))
	target_yaw = yaw
	pitch = float(d.get("pitch", 0.0))
	target_pitch = pitch
	stamina = float(d.get("stamina", 100.0))
