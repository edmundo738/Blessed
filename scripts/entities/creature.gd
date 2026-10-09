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
var _body: MeshInstance3D
var _eyes: MeshInstance3D
var _mat: StandardMaterial3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = randi()
	_build()
	add_to_group("creatures")


func _build() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(0.035, 0.03, 0.055)
	_body = MeshInstance3D.new()
	_body.mesh = MeshKit.blob(_rng, 0.85, 1, 0.42, Vector3(0.95, 1.5, 0.95), Color.WHITE)
	_body.material_override = _mat
	_body.position = Vector3(0, 1.05, 0)
	add_child(_body)

	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color(1.0, 0.85, 0.55)
	_eyes = MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [-1.0, 1.0]:
		var m := MeshKit.blob(_rng, 0.055, 0, 0.0, Vector3(1.4, 0.8, 0.6), Color.WHITE)
		var arr := m.surface_get_arrays(0)
		var verts: Array = arr[Mesh.ARRAY_VERTEX]
		for v in verts:
			st.set_color(Color.WHITE)
			st.add_vertex((v as Vector3) + Vector3(s * 0.16, 0.1, -0.7))
	_eyes.mesh = st.commit()
	_eyes.material_override = eye_mat
	_eyes.position = Vector3(0, 1.65, 0)
	add_child(_eyes)

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 2.0
	col.shape = cap
	col.position = Vector3(0, 1.0, 0)
	add_child(col)


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
	_eyes.visible = day < 0.5

	# contacto
	touch_t = maxf(0.0, touch_t - delta)
	if dist < 1.5 and touch_t <= 0.0:
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
	if survival != null and dist < 26.0:
		survival.creature_threat = maxf(survival.creature_threat,
			clampf(1.0 - dist / 26.0, 0.0, 1.0))


func hurt(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		alive = false
		queue_free()


func _fade_out(rate: float) -> void:
	var c: Color = _mat.albedo_color
	c.a = maxf(0.0, c.a - rate * 0.02)
	_mat.albedo_color = c
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if c.a <= 0.01:
		alive = false
		queue_free()
