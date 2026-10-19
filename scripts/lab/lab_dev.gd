class_name LabDev
extends CanvasLayer
## LabDev — modo deus/desenvolvedor do laboratório.
##
## Ferramenta de teste, não gameplay: voar, cavar/aterrar com o rato,
## partir árvores e pedras, dar/spawnar TODOS os itens do Db e repor o
## mundo. É deliberadamente textual — quem está aqui é o testador.
## No jogo normal nada disto existe.

var scene: LabScene
var _panel: PanelContainer
var _inv_label: Label
var _status: Label
var _fly_btn: Button
var _labels_on := false
var _dig_timer := 0.0
var tool := "hand"
var _tool_slots: Dictionary = {}
var _mat_label: Label
var _aim_timer := 0.0
var _denial_timer := 0.0
var _relic_seen := false
var build_mode := false
var build_piece := "foundation"
var build_rot := 0.0
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _ghost_timer := 0.0


func setup(p_scene: LabScene) -> void:
	scene = p_scene


func _ready() -> void:
	layer = 20
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_status = Label.new()
	_status.position = Vector2(10, 8)
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	add_child(_status)
	# mira: um ponto discreto no centro — o material le-se do chao, a mira
	# so diz onde a ferramenta vai bater.
	var cross := Label.new()
	cross.text = "·"
	cross.add_theme_font_size_override("font_size", 22)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-2, -14)
	add_child(cross)
	_build_toolbar()
	_build_panel()
	_update_status()
	_update_tool_ui()


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 44)
	_panel.custom_minimum_size = Vector2(340, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)
	var title := Label.new()
	title.text = "MODO DEUS — LABORATÓRIO"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)
	_fly_btn = _add_button(vbox, "Voar: desligado", _toggle_fly)
	_add_button(vbox, "Dar TODOS os itens (inventário)", _give_all)
	_add_button(vbox, "Spawnar TODOS os itens (à volta)", _spawn_all)
	_add_button(vbox, "Repor mundo (destruir→reconstruir)", func() -> void: scene.reset_world())
	_add_button(vbox, "Renascer em terra firme", func() -> void: scene.respawn_player())
	_add_button(vbox, "Nomes das estações: mostrar/esconder", _toggle_labels)
	_inv_label = Label.new()
	_inv_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inv_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_inv_label)
	_panel.visible = false
	add_child(_panel)


## Barra de ferramentas compacta (fundo-centro): 3 slots + material sob a
## mira. Pequena de proposito — o laboratorio le-se no mundo, nao no HUD.
func _build_toolbar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.position = Vector2(-170, -58)
	bar.custom_minimum_size = Vector2(340, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.10, 0.62)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	bar.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	bar.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	for i in LabScene.TOOL_ORDER.size():
		var t := LabScene.TOOL_ORDER[i]
		var b := Button.new()
		b.text = "%d %s" % [i + 1, str(LabScene.TOOLS[t]["label"])]
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func() -> void: _set_tool(t))
		row.add_child(b)
		_tool_slots[t] = b
	_mat_label = Label.new()
	_mat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mat_label.add_theme_font_size_override("font_size", 11)
	_mat_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_mat_label.text = "—"
	v.add_child(_mat_label)
	add_child(bar)


func _set_tool(t: String) -> void:
	tool = t
	_update_tool_ui()


func _cycle_tool(dir: int) -> void:
	var i := LabScene.TOOL_ORDER.find(tool)
	i = posmod(i + dir, LabScene.TOOL_ORDER.size())
	_set_tool(LabScene.TOOL_ORDER[i])


func _update_tool_ui() -> void:
	for t in _tool_slots.keys():
		var b := _tool_slots[t] as Button
		b.modulate = Color(1.25, 1.15, 0.75) if t == tool else Color(0.75, 0.75, 0.8)


func _add_button(parent: Container, text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


func _toggle_labels() -> void:
	_labels_on = not _labels_on
	scene.set_station_labels_visible(_labels_on)


func _toggle_fly() -> void:
	if scene.player == null:
		return
	scene.player.dev_fly = not scene.player.dev_fly
	_fly_btn.text = "Voar: LIGADO (Espaço/Ctrl = sobe/desce)" if scene.player.dev_fly else "Voar: desligado"
	_update_status()


func _give_all() -> void:
	for id in Db.ITEMS.keys():
		scene.inv.add(str(id), 5)
	_refresh_inv()


func _spawn_all() -> void:
	var center := scene.player.global_position
	var ids := Db.ITEMS.keys()
	for n in ids.size():
		var a := float(n) / float(maxi(ids.size(), 1)) * TAU
		var r := 3.0 + float(n % 3) * 1.6
		var at := center + Vector3(cos(a) * r, 1.0, sin(a) * r)
		at.y = scene.lab.height(at.x, at.z) + 0.8
		DroppedItem.spawn(scene, str(ids[n]), 1, at, scene.inv, scene.player)


func _refresh_inv() -> void:
	if _inv_label == null or scene.inv == null:
		return
	var parts: Array[String] = []
	for id in Db.ITEMS.keys():
		var c: int = scene.inv.count(str(id))
		if c > 0:
			parts.append("%s×%d" % [id, c])
	_inv_label.text = "Inventário: " + (", ".join(parts) if not parts.is_empty() else "(vazio)")


func _update_status() -> void:
	var fly := scene != null and scene.player != null and scene.player.dev_fly
	_status.text = "LAB DEV%s%s · LMB escavar/colocar · RMB aterrar/remover · roda escolhe · B construir · F voar · F1 painel" % [" [VOAR]" if fly else "", " [CONSTRUIR]" if build_mode else ""]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				_panel.visible = not _panel.visible
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _panel.visible else Input.MOUSE_MODE_CAPTURED
				if _panel.visible:
					_refresh_inv()
			KEY_F:
				_toggle_fly()
			KEY_E:
				_strike_prop()
			KEY_1:
				if build_mode:
					_set_build_piece(0)
				else:
					_set_tool("hand")
			KEY_2:
				if build_mode:
					_set_build_piece(1)
				else:
					_set_tool("shovel")
			KEY_3:
				if build_mode:
					_set_build_piece(2)
				else:
					_set_tool("pickaxe")
			KEY_4:
				if build_mode:
					_set_build_piece(3)
			KEY_5:
				if build_mode:
					_set_build_piece(4)
			KEY_6:
				if build_mode:
					_set_build_piece(5)
			KEY_7:
				if build_mode:
					_set_build_piece(6)
			KEY_8:
				if build_mode:
					_set_build_piece(7)
			KEY_B:
				_toggle_build_mode()
			KEY_R:
				if build_mode:
					build_rot += PI * 0.25  # 45°: paredes/escadas/telhado em diagonal também entram
	if event is InputEventMouseButton and event.pressed and _panel.visible == false:
		if build_mode and event.button_index == MOUSE_BUTTON_LEFT:
			_place_ghost()
		elif build_mode and event.button_index == MOUSE_BUTTON_RIGHT:
			_remove_aimed()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if build_mode:
				_cycle_build_piece(1)
			else:
				_cycle_tool(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if build_mode:
				_cycle_build_piece(-1)
			else:
				_cycle_tool(-1)
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_dig_timer -= delta
	_aim_timer -= delta
	if _denial_timer > 0.0:
		_denial_timer -= delta
		if _denial_timer <= 0.0:
			_update_tool_ui()
	if _panel.visible or scene == null or scene.player == null:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if _aim_timer <= 0.0:
		_aim_timer = 0.12
		_update_aim_label()
	if build_mode:
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_timer = 0.05
			_update_ghost()
		return
	var digging := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var filling := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if (digging or filling) and _dig_timer <= 0.0:
		_dig_timer = float(LabScene.TOOLS[tool]["interval"])
		_apply_tool(filling)


## ── construção: preview fantasma que pinta a estabilidade ─────────────
## Verde = firme, amarelo = estica, vermelho = nao entra (sem suporte,
## agua, declive ou material). A cor ENSINA — nao ha texto de tutorial.
func _toggle_build_mode() -> void:
	build_mode = not build_mode
	if _ghost != null:
		_ghost.visible = build_mode
	_update_status()
	_update_aim_label()


func _set_build_piece(i: int) -> void:
	build_piece = LabScene.BUILD_ORDER[clampi(i, 0, LabScene.BUILD_ORDER.size() - 1)]


func _cycle_build_piece(dir: int) -> void:
	var i := LabScene.BUILD_ORDER.find(build_piece)
	_set_build_piece(posmod(i + dir, LabScene.BUILD_ORDER.size()))


func _ensure_ghost() -> void:
	if _ghost != null or scene == null:
		return
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.albedo_color = Color(0.4, 1.0, 0.5, 0.45)
	_ghost_mat.no_depth_test = false
	_ghost = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	_ghost.mesh = bm
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	scene.add_child(_ghost)


func _update_ghost() -> void:
	_ensure_ghost()
	if _ghost == null:
		return
	var hit := _ray_hit(36.0)
	if hit.is_empty():
		_ghost.visible = false
		return
	var at: Vector3 = hit.get("position", Vector3.ZERO)
	var ev := scene.evaluate_place(build_piece, at.x, at.z)
	var cx := float(int(ev["gx"])) * LabScene.BUILD_CELL
	var cz := float(int(ev["gz"])) * LabScene.BUILD_CELL
	var top := float(ev["top"])
	var size: Vector3 = LabScene.BUILD_PIECES[build_piece]["size"]
	var y := top
	match build_piece:
		"foundation":
			y = top - 0.15
		"wall", "door", "window":
			y = top + float(int(ev.get("level", 0))) * 2.4 + 1.2
		"pillar", "stairs":
			y = top + 1.2
		"floor":
			y = top + 2.48
		"roof":
			y = top + 3.9
	_ghost.position = Vector3(cx, y, cz)
	_ghost.scale = size
	_ghost.rotation = Vector3(0,
		build_rot if build_piece in ["wall", "door", "window", "stairs", "roof"] else 0.0, 0.0)
	var afford := scene.inv == null or scene.inv.has_all(LabScene.BUILD_PIECES[build_piece]["cost"])
	if not bool(ev["ok"]) or not afford:
		_ghost_mat.albedo_color = Color(1.0, 0.30, 0.22, 0.45)
	elif float(ev["stability"]) >= 0.8:
		_ghost_mat.albedo_color = Color(0.35, 1.0, 0.45, 0.45)
	elif float(ev["stability"]) >= 0.62:
		_ghost_mat.albedo_color = Color(1.0, 0.85, 0.30, 0.45)
	else:
		_ghost_mat.albedo_color = Color(1.0, 0.55, 0.20, 0.45)
	_ghost.visible = true


func _place_ghost() -> void:
	_update_ghost()
	if _ghost == null or not _ghost.visible:
		return
	var hit := _ray_hit(36.0)
	if hit.is_empty():
		return
	var at: Vector3 = hit.get("position", Vector3.ZERO)
	var res: Dictionary = scene.try_place(build_piece, at.x, at.z, build_rot, scene.inv)
	if bool(res.get("ok", false)):
		_refresh_inv()
	else:
		_denial(at, LabWorld.M_ROCK)
	_update_ghost()


func _remove_aimed() -> void:
	var hit := _ray_hit(36.0)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider == null or not (collider as Node).has_meta("lab_piece_key"):
		return
	var key := str((collider as Node).get_meta("lab_piece_key"))
	var piece := key.split(":")[3]
	var removed := scene.remove_piece(key)
	if removed > 0:
		var cost: Dictionary = LabScene.BUILD_PIECES[piece]["cost"]
		for id in cost.keys():
			scene.inv.add(str(id), maxi(1, int(cost[id]) / 2))
		_refresh_inv()


## Material sob a mira (leitura dev): nome + dureza + se a ferramenta
## atual entra. No jogo isto sera efeito (som/poeira/recuo), nao texto.
func _update_aim_label() -> void:
	if _mat_label == null:
		return
	if build_mode:
		var hit := _ray_hit(36.0)
		if hit.is_empty():
			_mat_label.text = "CONSTRUIR — %s" % str(LabScene.BUILD_PIECES[build_piece]["label"])
			return
		var at: Vector3 = hit.get("position", Vector3.ZERO)
		var ev := scene.evaluate_place(build_piece, at.x, at.z)
		var cost: Dictionary = LabScene.BUILD_PIECES[build_piece]["cost"]
		var afford := scene.inv != null and scene.inv.has_all(cost)
		_mat_label.text = "%s · %s · %s" % [
			str(LabScene.BUILD_PIECES[build_piece]["label"]),
			("estabilidade %d%%" % int(float(ev["stability"]) * 100.0)) if bool(ev["ok"]) else str(ev["reason"]),
			"materiais ok" if afford else "FALTA material"]
		return
	var hit := _ray_hit(36.0)
	if hit.is_empty():
		_mat_label.text = "—"
		return
	var at: Vector3 = hit.get("position", Vector3.ZERO)
	var mat := scene.lab.material_at(at.x, at.z)
	var ok := LabScene.tool_can(tool, mat, scene.lab.depth_dug(at.x, at.z))
	_mat_label.text = "%s · dureza %d · %s" % [
		LabWorld.material_name(mat), scene.lab.material_hardness(at.x, at.z),
		"a %s entra" % str(LabScene.TOOLS[tool]["label"]) if ok else "a %s NÃO entra" % str(LabScene.TOOLS[tool]["label"])]


func _ray_hit(max_dist: float) -> Dictionary:
	var cam := scene.player.camera
	if cam == null:
		return {}
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * max_dist
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [scene.player.get_rid()]
	var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
	return hit


func _apply_tool(fill: bool) -> void:
	var hit := _ray_hit(36.0)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	# Rocha volumétrica (CavePatch): a picareta abre túnel; outra
	# ferramenta nega pelo efeito. Aterrar na caverna ainda não existe.
	if collider != null and (collider as Node).has_meta("lab_cave"):
		var cat: Vector3 = hit.get("position", Vector3.ZERO)
		if fill:
			_denial(cat, LabWorld.M_ROCK)
			return
		var cres: Dictionary = scene.dig_cave(cat, tool)
		if not bool(cres.get("ok", false)):
			_denial(cat, LabWorld.M_ROCK)
			return
		_dust(cat, false, LabWorld.M_ROCK)
		DroppedItem.spawn(scene, "stone", 1, cat + Vector3(0, 0.8, 0), scene.inv, scene.player)
		print("LABCAVEDIG ", tool, " em ", cat)
		return
	# Se o raio acerta primeiro numa árvore/pedra, o clique é partir — cavar
	# através de uma árvore para o chão atrás dela seria mentira física.
	if collider != null and (collider as Node).has_meta("lab_kind"):
		_strike_prop()
		return
	var at: Vector3 = hit.get("position", Vector3.ZERO)
	var before := scene.lab.height(at.x, at.z)
	var res: Dictionary = scene.tool_dig(tool, at.x, at.z, fill)
	if not bool(res.get("ok", false)):
		_denial(at, int(res.get("material", LabWorld.M_DIRT)))
		return
	var removed := float(res.get("removed", 0.0))
	if not fill and removed > 3.0:
		DroppedItem.spawn(scene, str(res.get("yield_item", "soil")), 1,
				at + Vector3(0, 1.0, 0), scene.inv, scene.player)
	_dust(at, fill, int(res.get("material", LabWorld.M_DIRT)))
	var glint := float(res.get("glint", 0.0))
	if glint > 0.05:
		_glint_dust(at, glint)
	if bool(res.get("relic", false)) and not _relic_seen:
		_relic_seen = true
		_flash_gold()
	print("LABDIG ", tool, " ", "fill" if fill else "dig", " em ", at,
			" altura ", before, " -> ", scene.lab.height(at.x, at.z),
			" material ", res.get("material"))


## Brilho na poeira: a pista sensorial da estacao de escavacao. A
## intensidade vem do LabScene (perto + fundo = mais ouro). Nenhum texto
## diz "esta aqui" — quem joga aprende a ler a poeira.
func _glint_dust(at: Vector3, intensity: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = int(6.0 + intensity * 22.0)
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 0.8
	p.direction = Vector3(0, 1, 0)
	p.spread = 38.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 3.0 + intensity * 2.0
	p.gravity = Vector3(0, -2.2, 0)
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.10 + intensity * 0.08
	p.color = Color(1.0, 0.80, 0.30, 0.9)
	scene.add_child(p)
	p.global_position = at + Vector3(0, 0.3, 0)
	p.emitting = true
	var t := get_tree().create_timer(1.2)
	t.timeout.connect(p.queue_free)


## Flash dourado de 200 ms ao desenterrar: dopamina visual, zero texto.
func _flash_gold() -> void:
	var rect := ColorRect.new()
	rect.color = Color(1.0, 0.82, 0.35, 0.28)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	var tween := create_tween()
	tween.tween_property(rect, "color:a", 0.0, 0.45)
	tween.tween_callback(rect.queue_free)


## Ferramenta errada = EFEITO, nao sermão: slot pisca vermelho, poeira
## cinzenta seca (nada cedeu) e um "tink" visual na barra. A leitura
## textual vive só na etiqueta dev da mira.
func _denial(at: Vector3, mat: int) -> void:
	_denial_timer = 0.45
	var b := _tool_slots.get(tool) as Button
	if b != null:
		b.modulate = Color(1.6, 0.45, 0.4)
	_dust(at, false, mat, true)
	print("LABDENY ", tool, " em ", LabWorld.material_name(mat))


func _strike_prop() -> void:
	var hit := _ray_hit(8.0)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider == null or not (collider as Node).has_meta("lab_kind"):
		return
	var body := collider as Node3D
	var kind := str(body.get_meta("lab_kind"))
	var hp := int(body.get_meta("lab_hp", int(Db.HARVEST.get(kind, {}).get("hp", 3))))
	hp -= 2
	body.set_meta("lab_hp", hp)
	_dust(body.global_position + Vector3(0, 1.2, 0), false)
	if hp > 0:
		return
	var yields: Dictionary = Db.HARVEST.get(kind, {}).get("yields", {})
	for id in yields.keys():
		DroppedItem.spawn(scene, str(id), int(yields[id]), body.global_position + Vector3(0, 0.8, 0), scene.inv, scene.player)
	body.queue_free()
	print("LABHARVEST ", kind, " -> ", yields)


func _dust(at: Vector3, fill: bool, mat: int = LabWorld.M_DIRT, denied: bool = false) -> void:
	var p := CPUParticles3D.new()
	p.amount = 10 if denied else 26
	p.one_shot = true
	p.explosiveness = 0.92
	p.lifetime = 0.4 if denied else 0.65
	p.direction = Vector3(0, 1, 0)
	p.spread = 42.0
	p.initial_velocity_min = 1.6
	p.initial_velocity_max = 3.8
	p.gravity = Vector3(0, -5.5, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.14
	# a poeira DENUNCIA o material: areia palida, terra castanha, rocha cinzenta
	if denied:
		p.color = Color(0.62, 0.62, 0.64)
	elif fill:
		p.color = Color(0.62, 0.52, 0.36)
	else:
		p.color = [Color(0.85, 0.74, 0.50), Color(0.52, 0.39, 0.24),
				Color(0.58, 0.58, 0.62)][clampi(mat, 0, 2)]
	scene.add_child(p)
	p.global_position = at + Vector3(0, 0.25, 0)
	p.emitting = true
	var t := get_tree().create_timer(1.2)
	t.timeout.connect(p.queue_free)
