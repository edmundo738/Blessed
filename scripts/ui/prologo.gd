class_name Prologo
extends CanvasLayer
## Prologo — a entrada no mundo.
##
## Oito frases, um nome, um corpo e uma marca da vida anterior. É a única parte
## do jogo que não é procedural: é a promessa narrativa, e é curta de propósito.

const LINES := ["story.p1", "story.p2", "story.p3", "story.p4",
	"story.p5", "story.p6", "story.p7", "story.p8"]

var finished := false
var phase := "story"
var line_i := 0

var root: Control
var label: Label
var skip: Label
var creator: Control
var name_edit: LineEdit
var body_group: Array = []
var soul_group: Array = []
var soul_desc: Label
var appearance_preview: TextureRect
var chosen_body := "f"
var chosen_soul := "curious"
var chosen_appearance := {"skin": 0, "cloth": 0, "hair": 0}
var _fade := 0.0
var _target_alpha := 1.0


func _ready() -> void:
	layer = 30
	_build()
	# sem isto o ecra fica preto com a pelicula a 86% e nenhuma frase
	label.text = Loc.t(LINES[0])
	_target_alpha = 1.0
	_fade = 5.2
	Sfx.play("blessing", -10.0)


func _build() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.016, 0.03, 0.86)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	label = Label.new()
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.offset_left = -480
	label.offset_right = 480
	label.offset_top = -60
	label.offset_bottom = 60
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(1, 0.97, 0.9, 0.0))
	root.add_child(label)

	skip = Label.new()
	skip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	skip.offset_top = -52
	skip.offset_bottom = -22
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skip.add_theme_font_size_override("font_size", 12)
	skip.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	skip.text = Loc.t("prologo.skip")
	root.add_child(skip)

	creator = Control.new()
	creator.set_anchors_preset(Control.PRESET_FULL_RECT)
	creator.visible = false
	root.add_child(creator)
	_build_creator()


func _refresh_appearance_preview() -> void:
	if appearance_preview == null:
		return
	for p in get_tree().get_nodes_in_group("player"):
		var avatar: Node = p.get_node_or_null("Avatar2D")
		if avatar != null and avatar.has_method("preview_texture"):
			appearance_preview.texture = avatar.call("preview_texture")
			return


func _build_creator() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.offset_left = -320
	v.offset_right = 320
	v.offset_top = -300
	v.offset_bottom = 300
	v.add_theme_constant_override("separation", 10)
	creator.add_child(v)

	var t := Label.new()
	t.text = Loc.t("app.title")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", Color(1, 0.93, 0.72))
	v.add_child(t)

	var st := Label.new()
	st.text = Loc.t("app.subtitle")
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.add_theme_font_size_override("font_size", 13)
	st.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	v.add_child(st)
	v.add_child(HSeparator.new())

	var nl := Label.new()
	nl.text = Loc.t("prologo.name_prompt")
	v.add_child(nl)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = Loc.t("prologo.name_placeholder")
	name_edit.max_length = 18
	v.add_child(name_edit)

	var bl := Label.new()
	bl.text = Loc.t("prologo.body")
	v.add_child(bl)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	v.add_child(brow)
	for opt in [["f", "prologo.body_f"], ["m", "prologo.body_m"]]:
		var b := Button.new()
		b.text = Loc.t(str(opt[1]))
		b.toggle_mode = true
		b.button_pressed = str(opt[0]) == chosen_body
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_pick_body.bind(str(opt[0])))
		brow.add_child(b)
		body_group.append(b)

	var sl := Label.new()
	sl.text = Loc.t("prologo.soul")
	v.add_child(sl)
	for opt in ["curious", "brave", "hands", "quiet"]:
		var b := Button.new()
		b.text = Loc.t("prologo.soul_" + opt)
		b.toggle_mode = true
		b.button_pressed = opt == chosen_soul
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_pick_soul.bind(opt))
		v.add_child(b)
		soul_group.append(b)

	var appearance_title := Label.new()
	appearance_title.text = Loc.t("prologo.appearance")
	v.add_child(appearance_title)
	var appearance_row := HBoxContainer.new()
	appearance_row.add_theme_constant_override("separation", 6)
	v.add_child(appearance_row)
	for palette_key in ["skin", "cloth", "hair"]:
		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var category: String = "prologo.appearance_" + palette_key
		option.add_item(Loc.t(category) + " · " + Loc.t("prologo.palette_1"))
		option.add_item(Loc.t(category) + " · " + Loc.t("prologo.palette_2"))
		option.add_item(Loc.t(category) + " · " + Loc.t("prologo.palette_3"))
		if palette_key == "cloth":
			option.add_item(Loc.t(category) + " · " + Loc.t("prologo.palette_4"))
		option.select(int(chosen_appearance[palette_key]))
		option.item_selected.connect(_pick_appearance.bind(palette_key))
		appearance_row.add_child(option)

	soul_desc = Label.new()
	soul_desc.text = Loc.t("prologo.soul_" + chosen_soul + "_desc")
	soul_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	soul_desc.add_theme_font_size_override("font_size", 12)
	soul_desc.add_theme_color_override("font_color", Color(1, 0.95, 0.7, 0.8))
	v.add_child(soul_desc)

	var go := Button.new()
	go.text = Loc.t("prologo.confirm")
	go.pressed.connect(finish)
	v.add_child(go)

	appearance_preview = TextureRect.new()
	appearance_preview.set_anchors_preset(Control.PRESET_CENTER)
	appearance_preview.offset_left = 344
	appearance_preview.offset_right = 464
	appearance_preview.offset_top = -60
	appearance_preview.offset_bottom = 120
	appearance_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	appearance_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	appearance_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	appearance_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	creator.add_child(appearance_preview)
	_refresh_appearance_preview()


func _pick_body(which: String) -> void:
	chosen_body = which
	for i in body_group.size():
		(body_group[i] as Button).button_pressed = (["f", "m"][i] == which)
	Sfx.play("ui_click", -12.0)


func _pick_appearance(index: int, palette_key: String) -> void:
	chosen_appearance[palette_key] = index
	Game.profile["appearance"] = chosen_appearance.duplicate(true)
	for p in get_tree().get_nodes_in_group("player"):
		var avatar: Node = p.get_node_or_null("Avatar2D")
		if avatar != null and avatar.has_method("refresh_appearance"):
			avatar.call("refresh_appearance")
	_refresh_appearance_preview()
	Sfx.play("ui_click", -16.0)


func _pick_soul(which: String) -> void:
	chosen_soul = which
	for i in soul_group.size():
		(soul_group[i] as Button).button_pressed = (["curious", "brave", "hands", "quiet"][i] == which)
	soul_desc.text = Loc.t("prologo.soul_" + which + "_desc")
	Sfx.play("ui_click", -12.0)


func _unhandled_input(event: InputEvent) -> void:
	if finished:
		return
	if phase != "story":
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			finish()
		elif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_advance()
	elif event is InputEventMouseButton and event.pressed:
		_advance()


func _process(delta: float) -> void:
	if finished:
		return
	var a: float = label.get_theme_color("font_color").a
	a = move_toward(a, _target_alpha, delta * 1.6)
	label.add_theme_color_override("font_color", Color(1, 0.97, 0.9, a))
	_fade -= delta
	if _fade <= 0.0 and phase == "story":
		_target_alpha = 0.0
		_fade = 999.0
		await get_tree().create_timer(1.4).timeout
		if phase == "story":
			_advance()


func _advance() -> void:
	line_i += 1
	if line_i >= LINES.size():
		phase = "create"
		label.visible = false
		skip.visible = false
		creator.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		name_edit.grab_focus()
		return
	label.text = Loc.t(LINES[line_i])
	_target_alpha = 1.0
	_fade = 5.2
	Sfx.play("ui_click", -20.0, 0.8)


func finish() -> void:
	if finished:
		return
	finished = true
	var n := name_edit.text.strip_edges()
	Game.profile = {
		"name": n if n != "" else ("Ana" if chosen_body == "f" else "Rui"),
		"body": chosen_body,
		"soul": chosen_soul,
		"appearance": chosen_appearance.duplicate(true),
	}
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()
	Game.started = true
	for p in get_tree().get_nodes_in_group("player"):
		var avatar: Node = p.get_node_or_null("Avatar2D")
		if avatar != null and avatar.has_method("refresh_appearance"):
			avatar.call("refresh_appearance")
