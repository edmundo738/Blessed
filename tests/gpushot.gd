extends Node
## Captura GPU real (Forward+) para provar modelos e composição sem adivinhar.
##
## O rasterizador por software continua a ser a ferramenta de auditoria de
## geometria, mas não desenha texturas nem o segundo material de uma árvore.
## Esta sonda corre o jogo no renderer real, coloca o corpo 3D em cena com um
## animal e guarda o viewport num PNG. Uso: `-- gpushot`.

var main: Node


func setup(m: Node) -> void:
	main = m


func _ready() -> void:
	for i in 90:
		await get_tree().process_frame
	if main == null:
		get_tree().quit(1)
		return
	Game.started = true
	if main.get("prologo") != null:
		(main.get("prologo") as CanvasLayer).visible = false
	if main.get("hud") != null:
		(main.get("hud") as CanvasLayer).visible = false
	if main.get("debug_view") != null:
		var dv: Node = main.get("debug_view")
		var line := dv.get("hud_line") as Label
		if line != null:
			line.visible = false
	Game.hour = 9.2
	var player: Player = main.get("player")
	var world: World = main.get("world")
	var spot := Vector3(112.0, 0.0, 12.0)
	spot.y = world.ground_height(spot.x, spot.z) + 0.15
	player.teleport(spot)
	# Frente para -Z (a convenção do controlador). Sem isto a câmara de
	# apresentação podia apanhar as costas e o rosto nunca era validado.
	player.yaw = 0.0
	player.target_yaw = 0.0
	player.pitch = 0.0
	player.target_pitch = 0.0
	player.rotation.y = 0.0
	world.set_target(spot)
	for i in 110:
		await get_tree().process_frame
	# Câmara externa: corpo visível, mãos escondidas.
	player.call("_set_view_mode", true)
	for i in 8:
		await get_tree().process_frame

	# Um veado ao lado: a nova malha 3D e a postura de pastar no mesmo plano
	# do jogador. Fica em pausa depois de colocado para a pose não fugir.
	var deer := Animal.new()
	deer.world = world
	deer.player = player
	deer.inv = main.get("inv")
	world.add_child(deer)
	deer.global_position = spot + Vector3(-3.4, 0.0, -2.2)
	deer.rotation.y = deg_to_rad(25.0)
	deer.set_physics_process(false)
	Game.paused = true

	# Câmara de apresentação à frente e ao lado: vê a cara do corpo, a capa e
	# o animal, não as costas de ambos.
	var cam := Camera3D.new()
	cam.name = "ShowcaseCamera"
	main.add_child(cam)
	cam.fov = 58.0
	cam.near = 0.05
	cam.far = 500.0
	cam.global_position = spot + Vector3(2.10, 1.62, -4.35)
	cam.look_at(spot + Vector3(0.15, 1.02, -0.15), Vector3.UP)
	cam.current = true
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "res://docs/shots/11_corpo_3d_gpu.png"
	var err := img.save_png(path)
	print("GPUSHOT %s -> %s" % [path, str(err)])

	# ── segunda foto: as mãos em 1.ª pessoa com o machado ────────────────
	# A câmara de apresentação sai; volta a câmara do jogador. O corpo
	# esconde-se e as mãos aparecem, que é a vista onde o jogo é jogado.
	cam.current = false
	player.call("_set_view_mode", false)
	player.camera.current = true
	player.call("look_at_point", spot + Vector3(0.0, 1.20, -4.0))
	player.set("pitch", -0.10)
	player.set("target_pitch", -0.10)
	player.hands.call("set_item", "axe")
	player.hands.call("swing", 0.34)
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img2 := get_viewport().get_texture().get_image()
	var path2 := "res://docs/shots/13_maos_gpu.png"
	var err2 := img2.save_png(path2)
	print("GPUSHOT %s -> %s" % [path2, str(err2)])
	get_tree().quit(0 if err == OK and err2 == OK else 1)
