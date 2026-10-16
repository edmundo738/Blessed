class_name PixelAvatar
extends Node3D
## 2.5D character renderer: pixel art sprites in the 3D world.
## Palette and silhouette are profile-driven so later outfits/heritage can be data assets.

var sprite: AnimatedSprite3D
var _last_animation := ""
var appearance_override: Dictionary = {}
## O modo Camp to Me é uma substituição reversível só para o jogador.
## NPCs continuam a usar os perfis próprios do Blessed.
var use_camp_sprite := false


func _ready() -> void:
	_build_sprite_frames()
	position.y = 0.88


func refresh_appearance() -> void:
	_build_sprite_frames()
	_last_animation = ""


func preview_texture() -> Texture2D:
	if sprite == null or sprite.sprite_frames == null:
		return null
	return sprite.sprite_frames.get_frame_texture("front_idle", 0)


func _build_sprite_frames() -> void:
	if sprite == null:
		sprite = AnimatedSprite3D.new()
		sprite.name = "PixelSprite"
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.pixel_size = 0.036
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.position.y = 0.0
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sprite)
	if use_camp_sprite:
		_build_camp_sprite_frames()
		return

	var frames := SpriteFrames.new()
	frames.clear_all()
	for direction in ["front", "back", "side"]:
		for gait in ["idle", "walk"]:
			var anim: String = direction + "_" + gait
			frames.add_animation(anim)
			frames.set_animation_speed(anim, 8.0 if gait == "walk" else 2.0)
			frames.set_animation_loop(anim, true)
			var count := 4 if gait == "walk" else 1
			for frame in count:
				frames.add_frame(anim, _make_frame(direction, frame))
	sprite.sprite_frames = frames
	sprite.animation = "back_idle"


func _build_camp_sprite_frames() -> void:
	# Usamos apenas os ciclos frente/costas que o projeto de origem aprovou.
	# Os ciclos de caminhada/laterais estão marcados como experimentais nesse
	# projeto, por isso não são promovidos silenciosamente para produção.
	const DIRECTIONS := {"front": "front", "back": "back"}
	const FRAME_COUNT := 12
	const FRAME_SECONDS := 0.27
	var frames := SpriteFrames.new()
	frames.clear_all()
	for direction in DIRECTIONS:
		var animation: String = str(direction) + "_idle"
		frames.add_animation(animation)
		frames.set_animation_speed(animation, 1.0 / FRAME_SECONDS)
		frames.set_animation_loop(animation, true)
		for index in range(1, FRAME_COUNT + 1):
			var path := "res://content/characters/camp_to_me/%s/frame_%03d.png" % [
				DIRECTIONS[direction], index]
			var texture := load(path) as Texture2D
			if texture == null:
				push_error("Missing Camp to Me player frame: " + path)
				continue
			frames.add_frame(animation, texture)
	sprite.sprite_frames = frames
	sprite.pixel_size = 1.72 / 544.0
	sprite.animation = "back_idle"
	sprite.speed_scale = 1.0


func _make_frame(direction: String, frame: int) -> Texture2D:
	const W := 32
	const H := 48
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Palette slots are intentionally centralized for future costume/heritage assets.
	var profile: Dictionary = appearance_override if not appearance_override.is_empty() else Game.profile
	var appearance: Dictionary = profile.get("appearance", {})
	var body := str(profile.get("body", "f"))
	var skin := _palette_color(appearance.get("skin", 0), [
		Color("#f1c7a2"), Color("#d89b72"), Color("#8e5b43")])
	var cloth := _palette_color(appearance.get("cloth", 0), [
		Color("#527c78"), Color("#8a536d"), Color("#9b7644"), Color("#52678d")])
	var hair := _palette_color(appearance.get("hair", 0), [
		Color("#302b3c"), Color("#754a38"), Color("#d0a65e"), Color("#52604b")])
	var outline := Color("#28283a")
	var shade := cloth.darkened(0.28)
	var light := cloth.lightened(0.24)
	var hair_light := hair.lightened(0.18)
	var leg_shift: int = [0, 2, 0, -2][frame % 4] if direction == "side" else [0, 1, 0, -1][frame % 4]
	var arm_shift: int = [0, 1, 0, -1][frame % 4]

	# Soft pixel-art ground shadow is omitted: the 3D world supplies contact shadow.
	# Boots and legs, outlined in a deep ink tone.
	_rect(img, 9 + leg_shift, 37, 6, 8, outline)
	_rect(img, 18 - leg_shift, 37, 6, 8, outline)
	_rect(img, 10 + leg_shift, 38, 4, 6, Color("#51465a"))
	_rect(img, 19 - leg_shift, 38, 4, 6, Color("#51465a"))
	_rect(img, 8 + leg_shift, 44, 7, 3, outline)
	_rect(img, 18 - leg_shift, 44, 8, 3, outline)
	_rect(img, 9 + leg_shift, 44, 5, 1, Color("#b08a61"))
	_rect(img, 19 - leg_shift, 44, 5, 1, Color("#b08a61"))

	# Tunic silhouette and shaded folds.
	_rect(img, 8, 20, 17, 19, outline)
	_rect(img, 9, 21, 15, 16, cloth)
	_rect(img, 10, 22, 4, 12, light)
	_rect(img, 15, 24, 2, 11, shade)
	_rect(img, 19, 22, 4, 13, shade)
	_rect(img, 10, 35, 13, 2, Color("#d0ae71"))
	_rect(img, 15, 35, 2, 2, outline)

	# Arms sit outside the torso so the silhouette reads at small scale.
	_rect(img, 5, 22 + arm_shift, 5, 14, outline)
	_rect(img, 6, 23 + arm_shift, 3, 11, cloth)
	_rect(img, 23, 22 - arm_shift, 5, 14, outline)
	_rect(img, 24, 23 - arm_shift, 3, 11, shade)
	_rect(img, 6, 34 + arm_shift, 4, 4, outline)
	_rect(img, 24, 34 - arm_shift, 4, 4, skin)

	# Neck and head, with a distinctive layered fringe.
	_rect(img, 13, 17, 7, 5, outline)
	_rect(img, 14, 18, 5, 4, skin)
	_rect(img, 10, 5, 14, 15, outline)
	_rect(img, 11, 6, 12, 13, skin)
	_rect(img, 10, 5, 14, 5, outline)
	_rect(img, 11, 6, 12, 3, hair)
	_rect(img, 10, 8, 4, 8, hair)
	_rect(img, 20, 8, 4, 7, hair)
	if body == "f":
		_rect(img, 10, 12, 2, 6, hair)
		_rect(img, 22, 12, 2, 6, hair)
	_rect(img, 13, 8, 5, 2, hair_light)
	_rect(img, 16, 10, 3, 2, hair)
	_rect(img, 12, 13, 2, 2, outline)
	_rect(img, 20, 13, 2, 2, outline)

	if direction == "back":
		# Back view: a longer hair shape and a stitched collar, no face marks.
		_rect(img, 10, 8, 14, 10, hair)
		_rect(img, 11, 16, 12, 3, hair_light)
		_rect(img, 12, 21, 9, 2, shade)
	elif direction == "side":
		# Profile: nose, one eye, ear, and asymmetrical hair contour.
		_rect(img, 21, 11, 3, 3, skin)
		_rect(img, 20, 12, 2, 2, outline)
		_rect(img, 11, 11, 3, 2, hair)
	else:
		# Front: warm eyes, small nose and scarf accent.
		_rect(img, 13, 12, 2, 2, Color("#493843"))
		_rect(img, 19, 12, 2, 2, Color("#493843"))
		_rect(img, 16, 14, 2, 2, skin.darkened(0.12))
		_rect(img, 13, 18, 7, 2, light)

	# Identity mark is a small blessing charm, reserved across future outfits.
	_rect(img, 15, 27, 3, 4, Color("#f2d888"))
	_rect(img, 16, 28, 1, 2, Color("#fff1bd"))
	return ImageTexture.create_from_image(img)


func _rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h), color)


func _palette_color(index: Variant, palette: Array[Color]) -> Color:
	return palette[posmod(int(index), palette.size())]


func update_pose(world_velocity: Vector3, facing: float, camera_position: Vector3) -> void:
	if sprite == null:
		return
	var local_camera := Basis(Vector3.UP, -facing) * (camera_position - global_position)
	if use_camp_sprite:
		# A arte tem vistas de frente e costas. Mantemos a silhueta consistente
		# sem espelhar a face nem inventar uma vista lateral inexistente.
		var camp_animation := "back_idle" if local_camera.z >= 0.0 else "front_idle"
		if sprite.animation != camp_animation:
			sprite.play(camp_animation)
		return
	var direction := "back"
	if local_camera.z < -0.55:
		direction = "front"
	elif absf(local_camera.x) > absf(local_camera.z) * 0.72:
		direction = "side"
	var moving := Vector2(world_velocity.x, world_velocity.z).length() > 0.35
	var anim := direction + ("_walk" if moving else "_idle")
	if anim != _last_animation:
		_last_animation = anim
		sprite.play(anim)
