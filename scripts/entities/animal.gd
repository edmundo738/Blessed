class_name Animal
extends CharacterBody3D
## Animal — caça diurna.
##
## Existe por um motivo concreto: as receitas de carne (`meat_raw`,
## `meat_cooked`, o guisado) não tinham **nenhuma** fonte no mundo. Sem caça, o
## ciclo de sobrevivência fechava no peixe e metade da comida era conteúdo
## inalcançável.
##
## Comportamento (regras curtas, como o resto do projeto):
##   • pasta em bando, muda de direção sozinho, não entra em água funda
##   • foge do jogador quando ele se aproxima (e foge mais depressa quando
##     leva um golpe)
##   • dá carne quando morre — a carne cai no chão e apanha-se como tudo o resto

const FLEE_DIST := 9.5
const PANIC_DIST := 15.0
const PANIC_TIME := 4.0

var species := "grazer"
var speed := 1.6
var flee_speed := 4.0
var health := 6.0
var meat := 2
var world: Node3D
var player: Node3D
var inv: Node
var alive := true

var _body: Sprite3D
var _rng := RandomNumberGenerator.new()
var _wish := Vector3.ZERO
var _wander_t := 0.0
var _panic_t := 0.0
var _bob_t := 0.0
var _step_t := 0.0
var _hurt_t := 0.0


func _ready() -> void:
	_rng.seed = randi()
	_build()
	add_to_group("animals")
	_pick_direction()


func _build() -> void:
	_body = Sprite3D.new()
	_body.name = "GrazerSprite"
	_body.texture = _make_texture()
	_body.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# achata o sprite: visto de fora lê-se como um bicho pequeno e não como
	# um cartaz de pé (o erro clássico do billboard)
	_body.pixel_size = 0.032
	_body.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.position = Vector3(0, 0.42, 0)
	add_child(_body)

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 0.85
	col.shape = cap
	col.position = Vector3(0, 0.42, 0)
	add_child(col)


## Silhueta pixel art de um quadrúpede pequeno (o jogo é todo desenhado por
## código; não há sprites de animais no kit).
func _make_texture() -> Texture2D:
	const W := 24
	const H := 18
	var image := Image.create(W, H, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var fur := Color("b98a55")
	var fur_dark := Color("8f6537")
	var belly := Color("e6d3b4")
	var ink := Color("33241a")
	var eye := Color("1a1410")
	# corpo
	for x in range(5, 20):
		var t := float(x - 5) / 15.0
		var top := int(round(6.0 - sin(t * PI) * 1.6))
		var bottom := int(round(10.0 + sin(t * PI) * 1.2))
		for y in range(top, bottom + 1):
			image.set_pixel(x, y, fur if y < bottom - 1 else belly)
	# patas
	for x in [7, 9, 16, 18]:
		for y in range(11, 15):
			image.set_pixel(x, y, fur_dark)
		image.set_pixel(x, 15, ink)
	# cabeça + orelhas + olho + focinho
	for x in range(18, 23):
		for y in range(5, 10):
			image.set_pixel(x, y, fur)
	image.set_pixel(20, 4, fur_dark)
	image.set_pixel(22, 4, fur_dark)
	image.set_pixel(21, 7, eye)
	image.set_pixel(22, 9, ink)
	# cauda
	image.set_pixel(4, 6, fur_dark)
	image.set_pixel(3, 5, fur_dark)
	return ImageTexture.create_from_image(image)


func _physics_process(delta: float) -> void:
	if not alive or Game.paused:
		return
	_bob_t += delta
	_hurt_t = maxf(0.0, _hurt_t - delta)
	velocity.y = maxf(velocity.y - 18.0 * delta, -32.0)

	var to_player := Vector3.INF
	if is_instance_valid(player):
		to_player = (player as Node3D).global_position - global_position
	var flat_player := Vector3(to_player.x, 0.0, to_player.z)
	var player_dist := flat_player.length()

	# fugir é a melhor defesa: o bicho não luta
	_wander_t -= delta
	_panic_t = maxf(0.0, _panic_t - delta)
	if player_dist < FLEE_DIST or _panic_t > 0.0:
		if player_dist > 0.01:
			_wish = -flat_player.normalized()
		_panic_t = maxf(_panic_t, PANIC_TIME * 0.6)
		_wander_t = _rng.randf_range(1.5, 3.0)
	elif _wander_t <= 0.0:
		_pick_direction()

	# não entra em água funda: evita o bicho a nadar em círculos no rio
	var ahead := global_position + _wish * 1.8
	if world != null and world.has_method("is_in_water"):
		if bool(world.call("is_in_water", ahead + Vector3(0, 0.4, 0))):
			_pick_direction()

	var moving_fast := _panic_t > 0.0 or player_dist < FLEE_DIST
	var wanted := _wish * (flee_speed if moving_fast else speed)
	velocity.x = move_toward(velocity.x, wanted.x, 11.0 * delta)
	velocity.z = move_toward(velocity.z, wanted.z, 11.0 * delta)

	# chão (ou linha de água, se por acidente cair dentro dela)
	var target_y := global_position.y
	if world != null:
		if world.has_method("is_in_water") and bool(world.call("is_in_water", global_position)):
			var surface := float(world.call("water_surface_height",
				global_position.x, global_position.z))
			target_y = surface - 0.25
			velocity.y = 0.0
		elif world.has_method("ground_height"):
			target_y = float(world.call("ground_height", global_position.x, global_position.z))
		global_position.y = lerpf(global_position.y, target_y, 1.0 - exp(-12.0 * delta))

	move_and_slide()

	# olha para onde vai
	var flat_vel := Vector3(velocity.x, 0.0, velocity.z)
	if flat_vel.length_squared() > 0.04:
		rotation.y = atan2(flat_vel.x, flat_vel.z)
	# passo: som + balanço, para se ouvir que há bicho por perto
	var spd := flat_vel.length()
	_body.position.y = 0.42 + sin(_bob_t * (7.0 if moving_fast else 3.5)) * 0.03
	if spd > 0.6:
		_step_t -= delta * spd
		if _step_t <= 0.0:
			_step_t = 2.2
			Sfx.play_at("step_grass", global_position, -20.0, _rng.randf_range(1.1, 1.35))
	if _hurt_t > 0.0 and is_instance_valid(_body):
		_body.modulate = Color(1.0, 0.65, 0.65)
	elif is_instance_valid(_body):
		_body.modulate = Color.WHITE


func _pick_direction() -> void:
	var a := _rng.randf() * TAU
	_wish = Vector3(cos(a), 0.0, sin(a))
	_wander_t = _rng.randf_range(2.5, 6.0)


## Um golpe. Qualquer ferramenta serve para caçar (as mãos também, mais devagar).
func hurt(amount: float) -> void:
	if not alive:
		return
	health -= amount
	_hurt_t = 0.25
	_panic_t = PANIC_TIME
	if health > 0.0:
		Sfx.play_at("pick", global_position, -8.0, _rng.randf_range(0.8, 0.95))
		# foge na direção oposta ao golpe, para o jogador ter de correr atrás
		if is_instance_valid(player):
			var away := global_position - (player as Node3D).global_position
			away.y = 0.0
			if away.length_squared() > 0.01:
				_wish = away.normalized()
		return
	alive = false
	_die()


func _die() -> void:
	Sfx.play_at("pick", global_position, -4.0, 0.7)
	if world != null and world.has_method("ground_height"):
		var g: float = world.call("ground_height", global_position.x, global_position.z)
		global_position.y = g
	DroppedItem.spawn(world, "meat_raw", meat, global_position, inv, player)
	Game.bump("animal_hunted")
	set_physics_process(false)
	# pequena queda: o corpo desaparece com um afundamento no chão
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3(1.0, 0.15, 1.0), 0.45)
	if is_instance_valid(_body):
		tween.tween_property(_body, "modulate:a", 0.0, 0.45)
	tween.finished.connect(queue_free)
