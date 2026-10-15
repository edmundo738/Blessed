class_name Hud
extends CanvasLayer
## Hud — tudo o que vês enquanto jogas.
##
## Construído em código (sem .tscn, sem fontes externas) para o projeto não ter
## imports. A hierarquia é fixa: crosshair, barras, barra rápida, prompt,
## legendas, avisos e o véu de medo por cima de tudo.

var root: Control
var bars: Dictionary = {}
var hotbar_slots: Array = []
var prompt_label: Label
var prompt_bar: ProgressBar
var hotbar_item_label: Label
var subtitle: Label
var toast_label: Label
var clock_label: Label
var objective_label: Label
var fps_label: Label
var build_label: Label
var identity_name: Label
var identity_bonus: Label
var camera_mode_label: Label
var needs_panel: PanelContainer
var needs_button: Button
var needs_expanded := false
var fear_rect: ColorRect
var hurt_rect: ColorRect
var crosshair: Control
var interaction: Node
var inv: Inventory
var survival: Node
var player: Node

var _toast_t := 0.0
var _sub_t := 0.0
var _fps_acc := 0.0
var _fps_n := 0


const BAR_ORDER := [
	["health", Color(0.90, 0.28, 0.32)],
	["stamina", Color(0.95, 0.82, 0.35)],
	["hunger", Color(0.90, 0.58, 0.28)],
	["thirst", Color(0.36, 0.72, 0.95)],
	["energy", Color(0.66, 0.58, 0.92)],
	["warmth", Color(0.98, 0.66, 0.34)],
	["sanity", Color(0.55, 0.86, 0.72)],
	["blessing", Color(0.98, 0.92, 0.62)],
]


func set_build(stamp: String) -> void:
	if build_label != null:
		build_label.text = "build %s" % stamp


func _ready() -> void:
	layer = 10
	_build()
	Bus.stat_changed.connect(_on_stat)
	Bus.ui_message.connect(_on_toast)
	Bus.toast.connect(_on_toast)
	Bus.subtitle_requested.connect(_on_subtitle)
	Bus.focus_changed.connect(_on_focus)
	Bus.time_advanced.connect(_on_time)
	Bus.fear_changed.connect(_on_fear)
	Bus.player_damaged.connect(_on_hurt)
	Bus.objective_added.connect(_on_objective)
	Bus.objective_done.connect(_on_objective_done)


func _build() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_vignette()
	crosshair = _crosshair()
	_bars()
	_hotbar()
	_prompt()
	_top()
	_subtitle_ui()
	_toast_ui()


# ── peças ─────────────────────────────────────────────────────────────────
func _vignette() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float fear : hint_range(0.0, 1.0) = 0.0;
uniform float grain : hint_range(0.0, 1.0) = 0.4;
uniform float hurt : hint_range(0.0, 1.0) = 0.0;
uniform float time_s = 0.0;
float rnd(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	vec2 c = uv - 0.5;
	float d = length(c) * 1.42;
	float vig = smoothstep(0.55, 1.25, d);
	vec3 col = vec3(0.0);
	float a = vig * (0.28 + fear * 0.62) + hurt * 0.55 * (1.0 - d);
	// pulsa com o medo
	a *= 1.0 + fear * 0.12 * sin(time_s * (2.0 + fear * 4.0));
	float g = (rnd(uv * 512.0 + time_s) - 0.5) * grain * 0.06;
	col = vec3(0.02, 0.0, 0.03) * (fear * 1.2) + vec3(0.5, 0.0, 0.05) * hurt * 0.6;
	COLOR = vec4(col + g, clamp(a + g, 0.0, 1.0));
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	fear_rect = ColorRect.new()
	fear_rect.material = mat
	fear_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fear_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fear_rect)

	hurt_rect = ColorRect.new()
	hurt_rect.color = Color(0.6, 0.0, 0.05, 0.0)
	hurt_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hurt_rect)


func _crosshair() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(c)
	for i in 4:
		var l := ColorRect.new()
		l.color = Color(1, 1, 1, 0.55)
		match i:
			0: l.size = Vector2(2, 8); l.position = Vector2(-1, -14)
			1: l.size = Vector2(2, 8); l.position = Vector2(-1, 6)
			2: l.size = Vector2(8, 2); l.position = Vector2(-14, -1)
			3: l.size = Vector2(8, 2); l.position = Vector2(6, -1)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(l)
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.85)
	dot.size = Vector2(2, 2)
	dot.position = Vector2(-1, -1)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(dot)
	return c


func _bars() -> void:
	var primary := VBoxContainer.new()
	primary.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	primary.offset_left = 22
	primary.offset_top = -70
	primary.offset_right = 290
	primary.offset_bottom = -18
	primary.add_theme_constant_override("separation", 4)
	primary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(primary)
	for id in ["health", "stamina"]:
		_add_status_bar(primary, id, _bar_color(id), 184.0, 12.0)

	needs_button = Button.new()
	needs_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	needs_button.offset_left = 22
	needs_button.offset_top = -106
	needs_button.offset_right = 52
	needs_button.offset_bottom = -76
	needs_button.custom_minimum_size = Vector2(30, 30)
	needs_button.tooltip_text = Loc.t("hud.needs")
	needs_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	needs_button.add_theme_color_override("font_color", Color(0.91, 0.93, 0.87, 0.92))
	needs_button.focus_mode = Control.FOCUS_NONE
	var needs_icon := ItemIcon.new()
	needs_icon.item_id = "needs"
	needs_icon.position = Vector2(4, 4)
	needs_icon.size = Vector2(22, 22)
	needs_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	needs_button.add_child(needs_icon)
	needs_button.pressed.connect(func():
		needs_expanded = not needs_expanded
		_refresh_needs_panel())
	root.add_child(needs_button)

	needs_panel = PanelContainer.new()
	needs_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	needs_panel.offset_left = 22
	needs_panel.offset_top = -274
	needs_panel.offset_right = 290
	needs_panel.offset_bottom = -110
	needs_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.04, 0.055, 0.78)
	style.border_color = Color(0.68, 0.7, 0.62, 0.32)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	needs_panel.add_theme_stylebox_override("panel", style)
	root.add_child(needs_panel)
	var needs_stack := VBoxContainer.new()
	needs_stack.add_theme_constant_override("separation", 3)
	needs_panel.add_child(needs_stack)
	for id in ["hunger", "thirst", "energy", "warmth", "sanity", "blessing"]:
		_add_status_bar(needs_stack, id, _bar_color(id), 164.0, 9.0)
	needs_panel.visible = false
	_refresh_needs_panel()


func _bar_color(id: String) -> Color:
	for entry in BAR_ORDER:
		if str(entry[0]) == id:
			return entry[1]
	return Color.WHITE


func _add_status_bar(parent: Control, id: String, col: Color,
		fill_width: float, height: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var icon := ItemIcon.new()
	icon.item_id = id
	icon.custom_minimum_size = Vector2(20, 20)
	icon.size = Vector2(20, 20)
	icon.tooltip_text = Loc.t("hud." + id)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.02, 0.028, 0.58)
	bg.custom_minimum_size = Vector2(fill_width + 2.0, height)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bg)
	var fill := ColorRect.new()
	fill.color = col
	fill.position = Vector2(1, 1)
	fill.size = Vector2(fill_width, maxf(height - 2.0, 1.0))
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(fill)
	var value_label := Label.new()
	value_label.text = "100"
	value_label.custom_minimum_size = Vector2(28, 0)
	value_label.add_theme_font_size_override("font_size", 9)
	value_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.62))
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(value_label)
	bars[id] = {"fill": fill, "label": icon, "value_label": value_label,
		"color": col, "value": 1.0, "width": fill_width}


func _refresh_needs_panel() -> void:
	if needs_panel == null or needs_button == null:
		return
	var critical := false
	for id in ["hunger", "thirst", "energy", "warmth", "sanity"]:
		if float((bars.get(id, {}) as Dictionary).get("value", 1.0)) < 0.28:
			critical = true
	needs_panel.visible = needs_expanded or critical
	needs_button.text = ""
	needs_button.tooltip_text = Loc.t("hud.needs") + ("  !" if critical else "")
	if critical:
		needs_button.modulate = Color(1.0, 0.74, 0.5, 1.0)
	else:
		needs_button.modulate = Color.WHITE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("status_panel") and Game.started and not Game.paused:
		needs_expanded = not needs_expanded
		_refresh_needs_panel()
		get_viewport().set_input_as_handled()



func _hotbar() -> void:
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hb.offset_left = -220
	hb.offset_top = -60
	hb.offset_right = 220
	hb.offset_bottom = -12
	hb.add_theme_constant_override("separation", 5)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hb)
	for i in 9:
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(43, 47)
		slot.toggle_mode = true
		slot.focus_mode = Control.FOCUS_NONE
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.035, 0.055, 0.06, 0.84)
		normal.border_color = Color(0.53, 0.57, 0.52, 0.68)
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(5)
		normal.content_margin_left = 2
		normal.content_margin_right = 2
		normal.content_margin_top = 2
		normal.content_margin_bottom = 2
		slot.add_theme_stylebox_override("normal", normal)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color(0.12, 0.15, 0.12, 0.95)
		slot.add_theme_stylebox_override("hover", hover)
		var selected := normal.duplicate() as StyleBoxFlat
		selected.bg_color = Color(0.19, 0.15, 0.075, 0.96)
		selected.border_color = Color(0.96, 0.78, 0.38, 1.0)
		selected.set_border_width_all(2)
		slot.add_theme_stylebox_override("pressed", selected)
		hb.add_child(slot)
		var num := Label.new()
		num.text = str(i + 1)
		num.position = Vector2(4, 1)
		num.add_theme_font_size_override("font_size", 8)
		num.add_theme_color_override("font_color", Color(0.92, 0.9, 0.8, 0.76))
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(num)
		var icon := ItemIcon.new()
		icon.position = Vector2(6, 5)
		icon.size = Vector2(31, 31)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		var qty := Label.new()
		qty.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		qty.offset_left = -22
		qty.offset_top = -17
		qty.offset_right = -2
		qty.offset_bottom = -1
		qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty.add_theme_font_size_override("font_size", 10)
		qty.add_theme_color_override("font_color", Color.WHITE)
		qty.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
		qty.add_theme_constant_override("shadow_offset_x", 1)
		qty.add_theme_constant_override("shadow_offset_y", 1)
		qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(qty)
		slot.pressed.connect(func():
			if inv != null:
				inv.select(i))
		hotbar_slots.append({"bg": slot, "icon": icon, "qty": qty})
	hotbar_item_label = Label.new()
	hotbar_item_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar_item_label.offset_left = -160
	hotbar_item_label.offset_top = -83
	hotbar_item_label.offset_right = 160
	hotbar_item_label.offset_bottom = -62
	hotbar_item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hotbar_item_label.add_theme_font_size_override("font_size", 12)
	hotbar_item_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.78, 0.92))
	hotbar_item_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.92))
	hotbar_item_label.add_theme_constant_override("shadow_offset_y", 2)
	hotbar_item_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hotbar_item_label)


func _prompt() -> void:
	var plate := PanelContainer.new()
	plate.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	plate.offset_top = -148
	plate.offset_bottom = -112
	plate.offset_left = -220
	plate.offset_right = 220
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate_style := StyleBoxFlat.new()
	plate_style.bg_color = Color(0.025, 0.035, 0.04, 0.78)
	plate_style.border_color = Color(0.78, 0.68, 0.44, 0.65)
	plate_style.set_border_width_all(1)
	plate_style.set_corner_radius_all(6)
	plate_style.content_margin_left = 12
	plate_style.content_margin_right = 12
	plate_style.content_margin_top = 3
	plate_style.content_margin_bottom = 3
	plate.add_theme_stylebox_override("panel", plate_style)
	root.add_child(plate)
	prompt_label = Label.new()
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 13)
	prompt_label.add_theme_color_override("font_color", Color(0.98, 0.95, 0.87, 0.98))
	prompt_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	prompt_label.add_theme_constant_override("shadow_offset_y", 2)
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(prompt_label)

	prompt_bar = ProgressBar.new()
	prompt_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_bar.offset_left = -70
	prompt_bar.offset_right = 70
	prompt_bar.offset_top = -108
	prompt_bar.offset_bottom = -102
	prompt_bar.show_percentage = false
	prompt_bar.value = 0
	prompt_bar.visible = false
	prompt_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(prompt_bar)


func _top() -> void:
	clock_label = Label.new()
	clock_label.position = Vector2(22, 18)
	clock_label.add_theme_font_size_override("font_size", 18)
	clock_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	clock_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(clock_label)

	var identity_panel := PanelContainer.new()
	identity_panel.position = Vector2(18, 48)
	identity_panel.custom_minimum_size = Vector2(270, 78)
	identity_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.055, 0.075, 0.76)
	panel_style.border_color = Color(0.72, 0.66, 0.48, 0.48)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(5)
	panel_style.content_margin_left = 10
	panel_style.content_margin_right = 10
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	identity_panel.add_theme_stylebox_override("panel", panel_style)
	root.add_child(identity_panel)
	var identity_stack := VBoxContainer.new()
	identity_stack.add_theme_constant_override("separation", 1)
	identity_panel.add_child(identity_stack)
	identity_name = Label.new()
	identity_name.add_theme_font_size_override("font_size", 13)
	identity_name.add_theme_color_override("font_color", Color(1.0, 0.93, 0.72))
	identity_stack.add_child(identity_name)
	identity_bonus = Label.new()
	identity_bonus.custom_minimum_size = Vector2(240, 30)
	identity_bonus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity_bonus.add_theme_font_size_override("font_size", 10)
	identity_bonus.add_theme_color_override("font_color", Color(0.86, 0.91, 0.87, 0.92))
	identity_stack.add_child(identity_bonus)
	# O nome e o traço continuam disponíveis no diário; o HUD de jogo reserva
	# espaço para informação de sobrevivência e para a cena.
	identity_panel.visible = false
	camera_mode_label = Label.new()
	camera_mode_label.position = Vector2(22, 132)
	camera_mode_label.add_theme_font_size_override("font_size", 10)
	camera_mode_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	camera_mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camera_mode_label.visible = false
	root.add_child(camera_mode_label)
	_refresh_identity()

	objective_label = Label.new()
	objective_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	objective_label.offset_left = -420
	objective_label.offset_right = -22
	objective_label.offset_top = 18
	objective_label.offset_bottom = 54
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	objective_label.add_theme_font_size_override("font_size", 14)
	objective_label.add_theme_color_override("font_color", Color(1, 0.95, 0.7, 0.9))
	objective_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(objective_label)

	fps_label = Label.new()
	fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	fps_label.offset_left = -140
	fps_label.offset_right = -22
	fps_label.offset_top = 56
	fps_label.offset_bottom = 76
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.add_theme_font_size_override("font_size", 11)
	fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.visible = OS.is_debug_build()
	root.add_child(fps_label)

	build_label = Label.new()
	build_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	build_label.offset_left = -220
	build_label.offset_right = -22
	build_label.offset_top = 78
	build_label.offset_bottom = 96
	build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	build_label.add_theme_font_size_override("font_size", 10)
	build_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	build_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_label.visible = OS.is_debug_build()
	root.add_child(build_label)


func _subtitle_ui() -> void:
	subtitle = Label.new()
	subtitle.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	subtitle.offset_left = -440
	subtitle.offset_right = 440
	subtitle.offset_top = -190
	subtitle.offset_bottom = -140
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	subtitle.add_theme_constant_override("shadow_offset_y", 2)
	subtitle.visible = false
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(subtitle)


func _toast_ui() -> void:
	toast_label = Label.new()
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.offset_left = -360
	toast_label.offset_right = 360
	toast_label.offset_top = 120
	toast_label.offset_bottom = 160
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 16)
	toast_label.add_theme_color_override("font_color", Color(1, 0.93, 0.68, 0.95))
	toast_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	toast_label.visible = false
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_label)


# ── reações ───────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_fps_acc += delta
	_fps_n += 1
	if _fps_acc > 0.5:
		fps_label.text = "%s %d" % [Loc.t("ui.fps"), int(_fps_n / _fps_acc)]
		_fps_acc = 0.0
		_fps_n = 0
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			toast_label.visible = false
	if _sub_t > 0.0:
		_sub_t -= delta
		if _sub_t <= 0.0:
			subtitle.visible = false
	if hurt_rect.color.a > 0.0:
		hurt_rect.color.a = maxf(0.0, hurt_rect.color.a - delta * 1.2)
	if fear_rect and fear_rect.material is ShaderMaterial:
		(fear_rect.material as ShaderMaterial).set_shader_parameter("time_s",
			float(Time.get_ticks_msec()) * 0.001)
	_refresh_hotbar()
	_refresh_identity()
	_refresh_needs_panel()
	if interaction != null:
		_refresh_prompt()
	# suaviza as barras
	for id in bars:
		var b: Dictionary = bars[id]
		var f: ColorRect = b["fill"]
		var target := float(b["width"]) * clampf(float(b["value"]), 0.0, 1.0)
		f.size.x = lerpf(f.size.x, target, 1.0 - exp(-9.0 * delta))


func _refresh_identity() -> void:
	if identity_name == null:
		return
	var profile: Dictionary = Game.profile
	var player_name := str(profile.get("name", "")).strip_edges()
	if player_name.is_empty():
		player_name = Loc.t("app.title")
	var soul := str(profile.get("soul", "curious"))
	var label := Loc.t("prologo.soul_" + soul)
	var detail := Loc.t("prologo.soul_" + soul + "_desc")
	var name_text := player_name + "  ·  " + label
	var bonus_text := Loc.t("hud.bonus") + "  " + detail
	if identity_name.text != name_text:
		identity_name.text = name_text
	if identity_bonus.text != bonus_text:
		identity_bonus.text = bonus_text
	if camera_mode_label != null and player != null:
		var third := bool(player.get("third_person"))
		var mode := Loc.t("hud.view_third") if third else Loc.t("hud.view_first")
		camera_mode_label.text = Loc.t("hud.view_toggle", [mode])


func _refresh_hotbar() -> void:
	if inv == null:
		return
	for i in 9:
		var s: Dictionary = inv.slots[i]
		var slot: Dictionary = hotbar_slots[i]
		var icon: ItemIcon = slot["icon"]
		var qty: Label = slot["qty"]
		var bg: Button = slot["bg"]
		if s.is_empty():
			icon.set_item("")
			qty.text = ""
			bg.tooltip_text = Loc.t("hud.empty_slot")
		else:
			var id := str(s["id"])
			icon.set_item(id)
			qty.text = str(int(s["qty"])) if int(s["qty"]) > 1 else ""
			bg.tooltip_text = Db.item_name(id)
		bg.button_pressed = i == inv.hotbar_index
	var selected := inv.hotbar_id()
	hotbar_item_label.text = Db.item_name(selected) if selected != "" else Loc.t("hud.empty_slot")


func _on_stat(id: String, value: float, max_value: float) -> void:
	if not bars.has(id):
		return
	var bar: Dictionary = bars[id]
	bar["value"] = value / maxf(max_value, 0.001)
	(bar["value_label"] as Label).text = str(roundi(value))
	_refresh_needs_panel()


func _on_toast(key: String, seconds: float) -> void:
	if not bool(Game.settings["subtitles"]) and key.begins_with("story."):
		return
	toast_label.text = Loc.t(key)
	toast_label.visible = true
	_toast_t = seconds


func _on_subtitle(key: String, seconds: float) -> void:
	if not bool(Game.settings["subtitles"]):
		return
	subtitle.text = Loc.t(key)
	subtitle.visible = true
	_sub_t = seconds


func _on_focus(_who: Node, _key: String) -> void:
	_refresh_prompt()


func _refresh_prompt() -> void:
	if prompt_label == null:
		return
	if interaction == null or interaction.focus.is_empty():
		prompt_label.text = ""
		prompt_label.get_parent().visible = false
		crosshair.modulate = Color(1, 1, 1, 0.76)
		return
	prompt_label.get_parent().visible = true
	crosshair.modulate = Color(1.0, 0.84, 0.52, 0.96)
	var f: Dictionary = interaction.focus
	var key: String = str(interaction.call("prompt_key"))
	var action := Loc.t(key)
	var target := ""
	var kind := str(f.get("kind", ""))
	var hold_action := false
	if kind == "harvest":
		var node: Dictionary = f["ref"]
		var resource_id := str(node.get("kind", ""))
		var spec: Dictionary = Db.HARVEST.get(resource_id, {})
		var want := str(spec.get("tool", ""))
		if resource_id.begins_with("tree"):
			target = Loc.t("hud.target_tree")
		elif resource_id == "rock":
			target = Loc.t("hud.target_rock")
		elif resource_id == "bush":
			target = Loc.t("hud.target_bush")
		else:
			var yields: Dictionary = spec.get("yields", {})
			var yield_ids := yields.keys()
			target = Db.item_name(str(yield_ids[0])) if not yield_ids.is_empty() else action
		hold_action = resource_id.begins_with("tree") or resource_id == "rock"
		if hold_action and want != "" and inv != null and inv.hotbar_id() != want:
			action += "  ·  " + Loc.t("hud.needs_tool", [Db.item_name(want)])
		var max_hp := maxf(float(node.get("max_hp", node.get("hp", 1))), 1.0)
		var hp := maxf(float(node.get("hp", max_hp)), 0.0)
		prompt_bar.value = (1.0 - hp / max_hp) * 100.0
		prompt_bar.visible = hold_action and hp < max_hp
	else:
		match kind:
			"structure": target = Db.item_name(str(f["ref"].get("id", "")))
			"water": target = Loc.t("hud.target_water")
			"npc": target = Loc.t("hud.target_person")
			"felled_tree": target = Loc.t("hud.target_log")
		prompt_bar.visible = false
	var binding := Loc.t("hud.hold_interact") if hold_action else "[F]"
	prompt_label.text = "%s   %s · %s" % [binding, target, action] if target != "" else "%s   %s" % [binding, action]


func _on_time(hour: float, day: int) -> void:
	clock_label.text = "%s   %s" % [Loc.t("hud.day", [str(day)]), Game.clock_string()]


func _on_fear(level: float) -> void:
	if fear_rect.material is ShaderMaterial:
		(fear_rect.material as ShaderMaterial).set_shader_parameter("fear", level)


func _on_hurt(_amount: float, _cause: String) -> void:
	hurt_rect.color = Color(0.65, 0.02, 0.06, 0.5)


func _on_objective(id: String) -> void:
	objective_label.text = "▸ " + Loc.t("obj." + id)


func _on_objective_done(id: String) -> void:
	toast_label.text = "✓ " + Loc.t("obj." + id)
	toast_label.visible = true
	_toast_t = 3.0
	Sfx.play("ui_open", -10.0, 1.2)


func refresh_locale() -> void:
	for entry in BAR_ORDER:
		var id: String = entry[0]
		if bars.has(id):
			((bars[id] as Dictionary)["label"] as Control).tooltip_text = Loc.t("hud." + id)
	_refresh_identity()
	_refresh_needs_panel()
	_refresh_hotbar()
	_refresh_prompt()
