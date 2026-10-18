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


func setup(p_scene: LabScene) -> void:
	scene = p_scene


func _ready() -> void:
	layer = 20
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_status = Label.new()
	_status.position = Vector2(12, 10)
	_status.add_theme_font_size_override("font_size", 15)
	_status.text = "LAB DEV — LMB cavar · RMB aterrar/reconstruir · F voar · F1 painel · E partir"
	add_child(_status)
	_build_panel()
	_update_status()


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
	if scene != null and scene.player != null and scene.player.dev_fly:
		_status.text = "LAB DEV [VOAR] — LMB cavar · RMB aterrar · F andar · F1 painel"
	else:
		_status.text = "LAB DEV — LMB cavar · RMB aterrar/reconstruir · F voar · F1 painel · E partir"


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
	if event is InputEventMouseButton and event.pressed and _panel.visible == false:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_dig_timer -= delta
	if _panel.visible or scene == null or scene.player == null:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var digging := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var filling := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if (digging or filling) and _dig_timer <= 0.0:
		_dig_timer = 0.16
		_apply_tool(filling)


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
	# Se o raio acerta primeiro numa árvore/pedra, o clique é partir — cavar
	# através de uma árvore para o chão atrás dela seria mentira física.
	if collider != null and (collider as Node).has_meta("lab_kind"):
		_strike_prop()
		return
	var at: Vector3 = hit.get("position", Vector3.ZERO)
	var before := scene.lab.height(at.x, at.z)
	if fill:
		scene.lab.fill(at.x, at.z, 4.5, 0.9)
	else:
		var soil: float = scene.lab.dig(at.x, at.z, 4.5, 0.9)
		if soil > 12.0:
			DroppedItem.spawn(scene, "soil", 1, at + Vector3(0, 1.0, 0), scene.inv, scene.player)
	scene.rebuild_area(at.x, at.z, 9.0)
	_dust(at, fill)
	print("LABDIG ", "fill" if fill else "dig", " em ", at, " altura ", before, " -> ", scene.lab.height(at.x, at.z))


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


func _dust(at: Vector3, fill: bool) -> void:
	var p := CPUParticles3D.new()
	p.amount = 26
	p.one_shot = true
	p.explosiveness = 0.92
	p.lifetime = 0.65
	p.direction = Vector3(0, 1, 0)
	p.spread = 42.0
	p.initial_velocity_min = 1.6
	p.initial_velocity_max = 3.8
	p.gravity = Vector3(0, -5.5, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.14
	p.color = Color(0.55, 0.42, 0.28) if not fill else Color(0.62, 0.52, 0.36)
	scene.add_child(p)
	p.global_position = at + Vector3(0, 0.25, 0)
	p.emitting = true
	var t := get_tree().create_timer(1.2)
	t.timeout.connect(p.queue_free)
