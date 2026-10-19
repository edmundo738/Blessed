extends Node
## Captura GPU do laboratório depois da unificação visual.
##
## O laboratório é a estação de prova: se aqui as árvores, a água e o terreno
## não forem os do jogo, a imagem não prova nada. Uso: `-- labshot`.

var main: Node


func setup(m: Node) -> void:
	main = m


func _ready() -> void:
	for i in 20:
		await get_tree().process_frame
	Game.started = true
	# Esconde TUDO o que é do mundo grande (não só o nó World): estruturas,
	# aldeia, FX e criaturas vivem em ramos irmãos e apareciam por cima do
	# laboratório na primeira tentativa.
	for child in main.get_children():
		if child is Node3D:
			(child as Node3D).visible = false
		elif child is CanvasLayer:
			(child as CanvasLayer).visible = false
	if main.get("debug_view") != null:
		var dv: Node = main.get("debug_view")
		var line := dv.get("hud_line") as Label
		if line != null:
			line.visible = false
	if main.get("player") != null and main.get("player") is Player:
		(main.get("player") as Player).enabled = false

	var packed: PackedScene = load("res://scenes/lab.tscn")
	var scene := packed.instantiate() as LabScene
	add_child(scene)
	for i in 40:
		await get_tree().process_frame
	# O LabDev é a HUD do testador, não gameplay; sai da fotografia.
	var dev := scene.get_node_or_null("LabDev") as CanvasLayer
	if dev != null:
		dev.visible = false
	scene.set_station_labels_visible(false)
	Game.paused = true
	scene.player.call("_set_view_mode", true)

	var cam := Camera3D.new()
	cam.name = "LabShowcaseCamera"
	add_child(cam)
	cam.fov = 55.0
	cam.near = 0.1
	cam.far = 700.0
	# Câmara a partir do próprio spawn, acima e atrás: o prado, o corpo e as
	# estações próximas. A vista aberta anterior caía dentro de uma encosta.
	var p := scene.player.global_position
	var cam_pos := p + Vector3(8.0, 6.0, 11.0)
	var target := p + Vector3(-2.0, 1.0, -4.0)
	cam.global_position = cam_pos
	cam.look_at(target, Vector3.UP)
	cam.current = true
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "res://docs/shots/12_lab_gpu.png"
	var err := img.save_png(path)
	print("LABSHOT %s -> %s" % [path, str(err)])
	get_tree().quit(0 if err == OK else 1)
