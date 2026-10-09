class_name Menus
extends CanvasLayer
## Menus — pausa, definições, mochila, bancada, diário, diálogo e morte.
##
## Um só sítio para "o jogo pára e fala contigo". Tudo construído em código,
## com o tema por omissão do Godot (sem fontes para importar).

var inv: Inventory
var interaction: Node
var survival: Node
var player: Node

var panel_root: Control
var current := ""
var dialogue_npc: Node = null
var death_cause := ""

var _panel: Panel
var _content: VBoxContainer
var _title: Label


func _ready() -> void:
	layer = 20
	panel_root = Control.new()
	panel_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_root.visible = false
	add_child(panel_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_root.add_child(dim)

	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -300
	_panel.offset_right = 300
	_panel.offset_top = -230
	_panel.offset_bottom = 230
	panel_root.add_child(_panel)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 22
	v.offset_right = -22
	v.offset_top = 16
	v.offset_bottom = -16
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)

	var sep := HSeparator.new()
	v.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)

	Bus.dialogue_started.connect(_on_dialogue_started)
	Bus.player_died.connect(_on_player_died)
	Bus.locale_changed.connect(func(_c): if current != "": _rebuild())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if current == "":
			open("pause")
		else:
			close()
	elif current == "" and event.is_action_pressed("bag"):
		open("bag")
	elif current == "bag" and event.is_action_pressed("bag"):
		close()
	elif current == "" and event.is_action_pressed("journal"):
		open("journal")
	elif current == "journal" and event.is_action_pressed("journal"):
		close()
	elif current == "" and event.is_action_pressed("map"):
		open("map")
	elif current == "map" and event.is_action_pressed("map"):
		close()
	elif current == "dialogue" and event.is_action_pressed("pause"):
		close()


# ══════════════════════════════════════════════════════════════════════════
func open(which: String) -> void:
	current = which
	panel_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.paused = true
	Bus.game_paused.emit(true)
	Sfx.play("ui_open", -10.0)
	_rebuild()


func close() -> void:
	if current == "dialogue" and dialogue_npc != null:
		Bus.dialogue_ended.emit(str(dialogue_npc.id))
	current = ""
	dialogue_npc = null
	panel_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Game.paused = false
	Bus.game_paused.emit(false)
	Sfx.play("ui_click", -14.0)


func _clear() -> void:
	for c in _content.get_children():
		c.queue_free()


func _rebuild() -> void:
	_clear()
	match current:
		"pause": _build_pause()
		"settings": _build_settings()
		"bag": _build_bag()
		"craft": _build_craft()
		"journal": _build_journal()
		"map": _build_map()
		"dialogue": _build_dialogue()
		"death": _build_death()


# ── pausa ─────────────────────────────────────────────────────────────────
func _build_pause() -> void:
	_title.text = Loc.t("menu.paused")
	_button(Loc.t("menu.resume"), close)
	_button(Loc.t("tab.inventory"), func(): open("bag"))
	_button(Loc.t("tab.crafting"), func(): open("craft"))
	_button(Loc.t("tab.journal"), func(): open("journal"))
	_button(Loc.t("menu.save"), func(): Game.save_game())
	if Game.has_save():
		_button(Loc.t("menu.load"), func():
			Game.load_game()
			close())
	_button(Loc.t("menu.settings"), func(): open("settings"))
	_button(Loc.t("menu.quit"), func(): get_tree().quit())
	_label("")
	_label(Loc.t("ui.help.move"), 11, Color(1, 1, 1, 0.45))
	_label(Loc.t("ui.help.use"), 11, Color(1, 1, 1, 0.45))
	_label(Loc.t("ui.help.bag"), 11, Color(1, 1, 1, 0.45))


# ── definições ────────────────────────────────────────────────────────────
func _build_settings() -> void:
	_title.text = Loc.t("menu.settings")
	_slider("settings.sensitivity", "sensitivity", 0.05, 1.5, 0.05)
	_slider("settings.fov", "fov", 60.0, 105.0, 1.0)
	_slider("settings.volume", "volume", 0.0, 1.0, 0.05)
	_slider("settings.view_distance", "view_distance", 60.0, 300.0, 10.0)
	_option("settings.grass_quality", "grass_quality",
		["settings.low", "settings.medium", "settings.high"])
	_option("settings.shadows", "shadows",
		["settings.off", "settings.medium", "settings.high"])
	_slider("settings.head_bob", "head_bob", 0.0, 1.5, 0.1)
	_slider("settings.film_grain", "film_grain", 0.0, 1.0, 0.1)
	_slider("settings.horror", "horror", 0.0, 2.0, 0.1)
	_toggle("settings.invert_y", "invert_y")
	_toggle("settings.subtitles", "subtitles")
	_button("%s: %s" % [Loc.t("settings.locale"), Loc.native_name()], func():
		Loc.cycle_locale())
	_button(Loc.t("settings.back"), func(): open("pause"))


func _slider(label_key: String, setting: String, lo: float, hi: float, step: float) -> void:
	var row := HBoxContainer.new()
	_content.add_child(row)
	var lbl := Label.new()
	lbl.text = Loc.t(label_key)
	lbl.custom_minimum_size = Vector2(190, 0)
	row.add_child(lbl)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = float(Game.settings[setting])
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(200, 0)
	var val := Label.new()
	val.text = "%.2f" % sl.value
	val.custom_minimum_size = Vector2(52, 0)
	row.add_child(sl)
	row.add_child(val)
	sl.value_changed.connect(func(v: float):
		val.text = "%.2f" % v
		Game.set_setting(setting, v))


func _toggle(label_key: String, setting: String) -> void:
	var row := HBoxContainer.new()
	_content.add_child(row)
	var lbl := Label.new()
	lbl.text = Loc.t(label_key)
	lbl.custom_minimum_size = Vector2(190, 0)
	row.add_child(lbl)
	var cb := CheckBox.new()
	cb.button_pressed = bool(Game.settings[setting])
	row.add_child(cb)
	cb.toggled.connect(func(v: bool): Game.set_setting(setting, v))


func _option(label_key: String, setting: String, options: Array) -> void:
	var row := HBoxContainer.new()
	_content.add_child(row)
	var lbl := Label.new()
	lbl.text = Loc.t(label_key)
	lbl.custom_minimum_size = Vector2(190, 0)
	row.add_child(lbl)
	var ob := OptionButton.new()
	for o in options:
		ob.add_item(Loc.t(str(o)))
	ob.selected = clampi(int(Game.settings[setting]), 0, options.size() - 1)
	row.add_child(ob)
	ob.item_selected.connect(func(i: int): Game.set_setting(setting, i))


# ── mochila ───────────────────────────────────────────────────────────────
func _build_bag() -> void:
	_title.text = Loc.t("tab.inventory")
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_content.add_child(grid)
	for i in inv.SLOTS:
		var s: Dictionary = inv.slots[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(88, 52)
		if s.is_empty():
			b.text = "·"
			b.disabled = true
		else:
			var id := str(s["id"])
			b.text = "%s\nx%d" % [Db.item_name(id), int(s["qty"])]
			b.pressed.connect(_use_item.bind(id))
		grid.add_child(b)
	_label("")
	_button(Loc.t("tab.crafting"), func(): open("craft"))
	_button(Loc.t("settings.back"), func(): open("pause"))


func _use_item(id: String) -> void:
	var def := Db.item(id)
	match str(def.get("kind", "")):
		"food":
			if inv.remove(id, 1):
				survival.eat(float(def.get("food", 0)), float(def.get("drink", 0)),
					float(def.get("risk", 0)))
		"tool":
			if id == "water":
				if inv.remove("water", 1):
					inv.add("bottle", 1)
					survival.drink(float(def.get("drink_amount", 50.0)))
			elif id == "torch":
				Bus.say("prompt.light", 2.0)
		"structure":
			Bus.say("prompt.place", 2.0)
	_rebuild()


# ── bancada ───────────────────────────────────────────────────────────────
func _build_craft() -> void:
	_title.text = Loc.t("tab.crafting")
	var stations: Array = interaction.nearby_stations() if interaction != null else []
	if stations.is_empty():
		_label("— " + Loc.t("item.campfire") + " —", 12, Color(1, 1, 1, 0.5))
	for r in Db.recipes_for(stations):
		var row := HBoxContainer.new()
		_content.add_child(row)
		var lbl := Label.new()
		var needs_txt := []
		for k in r["needs"]:
			needs_txt.append("%d %s" % [int(r["needs"][k]), Db.item_name(str(k))])
		lbl.text = "%s x%d   (%s)" % [Db.item_name(str(r["result"])), int(r.get("qty", 1)),
			", ".join(needs_txt)]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ok := inv.can_craft(r)
		lbl.add_theme_color_override("font_color",
			Color(1, 1, 1, 0.9) if ok else Color(1, 1, 1, 0.35))
		row.add_child(lbl)
		var b := Button.new()
		b.text = "+"
		b.custom_minimum_size = Vector2(46, 0)
		b.disabled = not ok
		b.pressed.connect(_craft.bind(str(r["id"])))
		row.add_child(b)
	_label("")
	_button(Loc.t("settings.back"), func(): open("pause"))


func _craft(id: String) -> void:
	Game.request("craft", {"recipe": id})
	_rebuild()


# ── diário ────────────────────────────────────────────────────────────────
func _build_journal() -> void:
	_title.text = Loc.t("tab.journal")
	_label(Loc.t("app.subtitle"), 13, Color(1, 0.95, 0.7, 0.9))
	_label("")
	if not Game.objective_current.is_empty():
		_label("▸ " + Loc.t("obj." + Game.objective_current), 16, Color(1, 0.95, 0.7, 1.0))
	for o in Game.objectives_done:
		_label("✓ " + Loc.t("obj." + str(o)), 13, Color(0.7, 0.9, 0.7, 0.8))
	_label("")
	_label("%s  ·  %s" % [Loc.t("hud.day", [str(Game.day)]), Game.clock_string()], 12)
	if not str(Game.profile.get("name", "")).is_empty():
		_label("%s  ·  %s  ·  %s" % [Game.profile["name"],
			Loc.t("prologo.body_" + str(Game.profile.get("body", "f"))),
			Loc.t("prologo.soul_" + str(Game.profile.get("soul", "curious")))], 12)
	_label("")
	_button(Loc.t("settings.back"), func(): open("pause"))


func _build_map() -> void:
	_title.text = Loc.t("tab.map")
	_label("·", 12)
	_label(Loc.t("obj.explore"), 13, Color(1, 0.95, 0.7, 0.8))
	_label("")
	_button(Loc.t("settings.back"), func(): open("pause"))


# ── diálogo ───────────────────────────────────────────────────────────────
func _build_dialogue() -> void:
	if dialogue_npc == null:
		close()
		return
	_title.text = dialogue_npc.display_name()
	for t in dialogue_npc.topics():
		var key := str(t["key"])
		var b := Button.new()
		b.text = Loc.t(key)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_ask.bind(str(t["id"])))
		_content.add_child(b)
	_label("")
	_button("— " + Loc.t("npc.elder.a_bye") + " —", close)


func _ask(topic: String) -> void:
	if dialogue_npc == null:
		return
	var answer_key: String = dialogue_npc.answer(topic)
	_clear()
	_title.text = dialogue_npc.display_name()
	_label(Loc.t(answer_key), 16, Color(1, 1, 1, 0.95))
	_label("")
	_button("…", func(): _rebuild())
	Bus.subtitle_requested.emit(answer_key, 6.0)


func _on_dialogue_started(npc_id: String) -> void:
	for c in get_tree().get_nodes_in_group("npcs"):
		if "id" in c and str(c.id) == npc_id:
			dialogue_npc = c
			open("dialogue")
			return


# ── morte ─────────────────────────────────────────────────────────────────
func _on_player_died(cause: String) -> void:
	death_cause = cause
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	open("death")


func _build_death() -> void:
	_title.text = Loc.t("death.title")
	_label(Loc.t("death." + death_cause) if Loc.has_key("death." + death_cause) else "",
		16, Color(1, 0.6, 0.6, 0.95))
	_label("")
	_button(Loc.t("death.respawn"), func():
		survival.respawn()
		if player != null and player.has_method("teleport"):
			var w := player.get_parent()
			player.teleport(Vector3(0, 20, 0))
		close())


# ── widgets ───────────────────────────────────────────────────────────────
func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		Sfx.play("ui_click", -12.0)
		cb.call())
	_content.add_child(b)
	return b


func _label(text: String, size: int = 14, col: Color = Color(1, 1, 1, 0.85)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	_content.add_child(l)
	return l
