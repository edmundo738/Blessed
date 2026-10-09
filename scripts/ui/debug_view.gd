extends Node
## DebugView — isolar um problema de renderização sem ter de adivinhar.
##
## O agente que escreve este código não consegue ver o ecrã (corre sem GPU).
## Esta cena existe para que QUEM JOGA faça a pesquisa binária em segundos:
## cada tecla desliga uma camada. Aquilo que mudar é a camada culpada.
##
##   F1  cena de diagnóstico (materiais básicos, geometria conhecida)
##   F3  água
##   F6  céu / domo
##   F7  sombras
##   F8  meio-dia
##   F9  materiais do jogo ↔ StandardMaterial3D  ← a tecla importante
##
## F9 responde à única pergunta que importa primeiro:
##   • se com F9 o mundo fica CORRECTO, o problema está nos SHADERS;
##   • se com F9 continua errado, o problema está na GEOMETRIA ou no motor.

var main: Node
var rig: Node3D
var rig_origin: Vector3
var in_rig := false
var basic := false
var saved: Array = []
var hud_line: Label


func setup(p_main: Node) -> void:
	main = p_main


func _ready() -> void:
	hud_line = Label.new()
	hud_line.name = "DebugLine"
	hud_line.position = Vector2(12, 12)
	hud_line.add_theme_font_size_override("font_size", 13)
	hud_line.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	hud_line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hud_line.add_theme_constant_override("outline_size", 4)
	main.get_tree().root.add_child(hud_line)
	_paint()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_F1:
			_toggle_rig()
		KEY_F3:
			main.world.water.visible = not main.world.water.visible
		KEY_F6:
			main.world.sky_dome.visible = not main.world.sky_dome.visible
		KEY_F7:
			main.world.sun.shadow_enabled = not main.world.sun.shadow_enabled
		KEY_F8:
			Game.hour = 12.5
			Game.phase = Game.current_phase()
		KEY_F9:
			_toggle_basic()
		_:
			return
	_paint()
	get_viewport().set_input_as_handled()


func _paint() -> void:
	var w: Node = main.world
	hud_line.text = "F9 materiais: %s   F1 diagnóstico: %s   F3 água: %s   F6 céu: %s   F7 sombras: %s   F8 meio-dia" % [
		"BÁSICOS" if basic else "do jogo",
		"ON" if in_rig else "off",
		"on" if w.water.visible else "OFF",
		"on" if w.sky_dome.visible else "OFF",
		"on" if w.sun.shadow_enabled else "OFF",
	]


# ══════════════════════════════════════════════════════════════════════════
#  F9 — materiais do jogo ↔ materiais básicos
# ══════════════════════════════════════════════════════════════════════════
func _toggle_basic() -> void:
	if not basic:
		saved.clear()
		_walk(main, func(n: Node) -> void:
			if n is MeshInstance3D:
				var mi := n as MeshInstance3D
				saved.append([mi, mi.material_override])
				mi.material_override = _plain(Color(0.55, 0.75, 0.45))
			elif n is MultiMeshInstance3D:
				var mm := n as MultiMeshInstance3D
				saved.append([mm, mm.material_override])
				mm.material_override = _plain(Color(0.35, 0.65, 0.35))
		)
		basic = true
	else:
		for e in saved:
			var g: GeometryInstance3D = e[0]
			if not is_instance_valid(g):
				continue
			g.material_override = e[1]
		saved.clear()
		basic = false


func _plain(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


func _walk(n: Node, f: Callable) -> void:
	f.call(n)
	for c in n.get_children():
		_walk(c, f)


# ══════════════════════════════════════════════════════════════════════════
#  F1 — cena de diagnóstico
# ══════════════════════════════════════════════════════════════════════════
## Geometria conhecida com materiais básicos. Se isto se vê bem e o mundo não,
## o problema está no mundo; se isto também se vê mal, está no motor/ecrã.
func _toggle_rig() -> void:
	if in_rig:
		main.player.global_position = rig_origin
		in_rig = false
		return
	rig_origin = main.player.global_position
	if rig == null:
		_build_rig()
	main.player.global_position = rig_origin + Vector3(0, 6000, 0)
	in_rig = true


func _build_rig() -> void:
	rig = Node3D.new()
	rig.name = "DiagRig"
	var o := rig_origin + Vector3(0, 6000, 0)
	rig.global_position = o
	main.add_child(rig)

	# chão às damas — referência de escala e de profundidade
	for i in 10:
		for j in 10:
			var dark := (i + j) % 2 == 0
			_box(Vector3(4, 0.4, 4),
				Color(0.85, 0.85, 0.88) if dark else Color(0.25, 0.27, 0.32),
				o + Vector3((i - 5) * 4.0, -0.2, (j - 5) * 4.0), 0.0)

	# cubo com uma cor por face — diz-te imediatamente se alguma face falta
	var faces := [
		[Vector3(1, 0, 0), Color(0.95, 0.20, 0.20)],
		[Vector3(-1, 0, 0), Color(0.20, 0.95, 0.20)],
		[Vector3(0, 1, 0), Color(0.20, 0.40, 0.95)],
		[Vector3(0, -1, 0), Color(0.95, 0.85, 0.15)],
		[Vector3(0, 0, 1), Color(0.95, 0.45, 0.95)],
		[Vector3(0, 0, -1), Color(0.20, 0.90, 0.90)],
	]
	var cube := Node3D.new()
	cube.position = Vector3(-8, 1.6, -4)
	rig.add_child(cube)
	for f in faces:
		var n: Vector3 = f[0]
		var q := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(3, 3)
		q.mesh = pm
		var m := _plain(f[1])
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		q.material_override = m
		q.position = n * 1.5
		var up := Vector3(0, 0, 1) if absf(n.y) > 0.5 else Vector3.UP
		q.look_at_from_position(n * 1.5, Vector3.ZERO, up)
		cube.add_child(q)
	_label(cube, "cubo · 6 cores")

	# esfera com cull_back ao lado de uma com cull_disabled — testa o "raio X"
	var s1 := _sphere(1.5, Color(0.9, 0.6, 0.2), BaseMaterial3D.CULL_BACK)
	s1.position = Vector3(0, 1.6, -4)
	rig.add_child(s1)
	_label(s1, "cull_back")
	var s2 := _sphere(1.5, Color(0.9, 0.6, 0.2), BaseMaterial3D.CULL_DISABLED)
	s2.position = Vector3(4, 1.6, -4)
	rig.add_child(s2)
	_label(s2, "cull_disabled")

	# uma cabana real, com o material real do jogo
	var hut := MeshInstance3D.new()
	hut.mesh = MeshKit.box(Vector3(4.0, 2.8, 4.0), Color(0.55, 0.40, 0.28))
	hut.material_override = main.world.mats.structure
	hut.position = Vector3(9, 1.4, -4)
	rig.add_child(hut)
	_label(hut, "casa · material do jogo")

	# uma árvore real, com o material real
	var oak = main.world.species.trees["oak"]
	var tree := MeshInstance3D.new()
	tree.mesh = oak.lods[0]
	tree.material_override = main.world.mats.foliage
	tree.position = Vector3(14, 0.0, -4)
	rig.add_child(tree)
	_label(tree, "carvalho · material do jogo")

	# um bocado de terreno real, com o material real
	var patch := MeshInstance3D.new()
	patch.mesh = MeshKit.box(Vector3(6, 0.6, 6), Color(0.44, 0.62, 0.38))
	patch.material_override = main.world.mats.terrain
	patch.position = Vector3(-14, 0.3, -4)
	rig.add_child(patch)
	_label(patch, "terreno · material do jogo")


func _box(size: Vector3, c: Color, at: Vector3, rot: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _plain(c)
	mi.global_position = at
	mi.rotation.y = rot
	rig.add_child(mi)


func _sphere(r: float, c: Color, cull: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	var m := _plain(c)
	m.cull_mode = cull
	mi.material_override = m
	return mi


func _label(target: Node3D, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = 0.012
	l.font_size = 42
	l.modulate = Color(1, 1, 1)
	l.outline_size = 8
	l.position = Vector3(0, 3.6, 0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	target.add_child(l)
