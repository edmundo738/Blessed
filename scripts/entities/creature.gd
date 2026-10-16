class_name Creature
extends CharacterBody3D
## Creature — o que vive na noite.
##
## Não é um inimigo genérico: é uma regra do mundo. Nasce onde não há luz,
## aproxima-se devagar, recua da chama e desaparece com o sol. O jogador aprende
## isto em duas noites sem nunca ler um tutorial.

var speed := 2.6
var damage := 14.0
var health := 30.0
var boldness := 0.5
var fear_of_light := 9.0
var target: Node3D
var world: Node3D
var structures: Structures
var survival: Node
var alive := true
var touch_t := 0.0
var growl_t := 0.0
var _body: Sprite3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = randi()
	_build()
	add_to_group("creatures")


func _build() -> void:
	# A criatura também é 2D: uma silhueta pixel art suspensa no cenário 3D.
	_body = Sprite3D.new()
	_body.name = "NightWandererSprite"
	_body.texture = _make_texture()
	_body.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_body.pixel_size = 0.045
	_body.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.position = Vector3(0, 1.05, 0)
	add_child(_body)

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 2.0
	col.shape = cap
	col.position = Vector3(0, 1.0, 0)
	add_child(col)


func _make_texture() -> Texture2D:
	const W := 32
	const H := 48
	var image := Image.create(W, H, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var ink := Color("#171827")
	var shade := Color("#30263d")
	var edge := Color("#554060")
	var eye := Color("#ffd78a")
	# Cabeça estreita, ombros largos e braços alongados para ler bem à distância.
	image.fill_rect(Rect2i(11, 4, 10, 2), edge)
	image.fill_rect(Rect2i(8, 6, 16, 9), ink)
	image.fill_rect(Rect2i(10, 7, 12, 8), shade)
	image.fill_rect(Rect2i(5, 15, 22, 17), ink)
	image.fill_rect(Rect2i(8, 16, 16, 15), shade)
	image.fill_rect(Rect2i(2, 17, 6, 20), ink)
	image.fill_rect(Rect2i(24, 17, 6, 20), ink)
	image.fill_rect(Rect2i(4, 34, 5, 8), shade)
	image.fill_rect(Rect2i(23, 34, 5, 8), shade)
	image.fill_rect(Rect2i(9, 29, 6, 15), ink)
	image.fill_rect(Rect2i(17, 29, 6, 15), ink)
	image.fill_rect(Rect2i(8, 43, 8, 3), edge)
	image.fill_rect(Rect2i(16, 43, 8, 3), edge)
	# Olhos dourados pequenos: um ponto de luz que se distingue no escuro.
	image.fill_rect(Rect2i(11, 10, 3, 2), eye)
	image.fill_rect(Rect2i(19, 10, 3, 2), eye)
	image.fill_rect(Rect2i(14, 19, 4, 8), Color("#8b3e57"))
	return ImageTexture.create_from_image(image)


func _physics_process(delta: float) -> void:
	if not alive or target == null or Game.paused:
		return
	velocity.y -= 16.0 * delta
	var to := target.global_position - global_position
	var flat := Vector3(to.x, 0, to.z)
	var dist := flat.length()

	# a luz repele: perto de uma chama, recua
	var light_push := Vector3.ZERO
	if structures != null:
		for lp in structures.lit_positions():
			var d: float = (lp as Vector3).distance_to(global_position)
			if d < fear_of_light:
				light_push += (global_position - lp).normalized() * (1.0 - d / fear_of_light)
	var day := Game.daylight()
	if day > 0.25:
		# o sol mata: foge e desaparece
		_fade_out(delta * 1.6)
		if not alive:
			return
		light_push += -flat.normalized() * 2.0

	var wish := flat.normalized() * speed * (0.55 + boldness)
	if light_push.length_squared() > 0.001:
		wish = light_push.normalized() * speed * 1.2
	velocity.x = move_toward(velocity.x, wish.x, 9.0 * delta)
	velocity.z = move_toward(velocity.z, wish.z, 9.0 * delta)

	if world != null and world.has_method("ground_height"):
		var g: float = world.call("ground_height", global_position.x, global_position.z)
		global_position.y = lerpf(global_position.y, g, 1.0 - exp(-12.0 * delta))

	move_and_slide()

	# olha para o jogador
	if flat.length_squared() > 0.01:
		rotation.y = atan2(flat.x, flat.z)
	_body.rotation.z = sin(float(Time.get_ticks_msec()) * 0.004) * 0.08

	# contacto
	touch_t = maxf(0.0, touch_t - delta)
	if day <= 0.25 and dist < 1.5 and touch_t <= 0.0:
		touch_t = 1.4
		if survival != null and survival.has_method("damage"):
			survival.call("damage", damage, "creature")
		Sfx.play_at("scream", global_position, -6.0, randf_range(0.9, 1.15))

	# som de presença
	growl_t -= delta
	if growl_t <= 0.0 and dist < 22.0:
		growl_t = randf_range(2.5, 6.0)
		Sfx.play_at("growl", global_position, -10.0 + clampf(dist, 0.0, 20.0) * 0.3,
			randf_range(0.8, 1.1))

	# alimenta o medo do jogador
	if day <= 0.25 and survival != null and dist < 26.0:
		survival.creature_threat = maxf(survival.creature_threat,
			clampf(1.0 - dist / 26.0, 0.0, 1.0))


func hurt(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		alive = false
		queue_free()


func _fade_out(rate: float) -> void:
	_body.modulate.a = maxf(0.0, _body.modulate.a - rate * 0.75)
	if _body.modulate.a <= 0.01:
		alive = false
		queue_free()
