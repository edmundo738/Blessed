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
var subtitle: Label
var toast_label: Label
var clock_label: Label
var objective_label: Label
var fps_label: Label
var build_label: Label
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
	var panel := VBoxContainer.new()
	panel.position = Vector2(22, -150)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 22
	panel.offset_top = -196
	panel.offset_right = 250
	panel.offset_bottom = -24
	panel.add_theme_constant_override("separation", 3)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	for entry in BAR_ORDER:
		var id: String = entry[0]
		var col: Color = entry[1]
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(row)
		var lbl := Label.new()
		lbl.text = Loc.t("hud." + id).substr(0, 3).to_upper()
		lbl.custom_minimum_size = Vector2(38, 0)
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lbl)
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.38)
		bg.custom_minimum_size = Vector2(150, 9)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bg)
		var fill := ColorRect.new()
		fill.color = col
		fill.position = Vector2(1, 1)
		fill.size = Vector2(148, 7)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(fill)
		bars[id] = {"fill": fill, "label": lbl, "color": col, "value": 1.0}


func _hotbar() -> void:
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hb.offset_left = -9 * 44 * 0.5
	hb.offset_top = -74
	hb.offset_right = 9 * 44 * 0.5
	hb.offset_bottom = -22
	hb.add_theme_constant_override("separation", 4)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hb)
	for i in 9:
		var slot := ColorRect.new()
		slot.color = Color(0, 0, 0, 0.35)
		slot.custom_minimum_size = Vector2(40, 40)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(slot)
		var lbl := Label.new()
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(lbl)
		var num := Label.new()
		num.text = str(i + 1)
		num.position = Vector2(2, 1)
		num.add_theme_font_size_override("font_size", 9)
		num.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(num)
		hotbar_slots.append({"bg": slot, "label": lbl})


func _prompt() -> void:
	prompt_label = Label.new()
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.offset_top = -128
	prompt_label.offset_bottom = -100
	prompt_label.offset_left = -220
	prompt_label.offset_right = 220
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 16)
	prompt_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	prompt_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	prompt_label.add_theme_constant_override("shadow_offset_y", 2)
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(prompt_label)

	prompt_bar = ProgressBar.new()
	prompt_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_bar.offset_left = -70
	prompt_bar.offset_right = 70
	prompt_bar.offset_top = -98
	prompt_bar.offset_bottom = -92
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
	if interaction != null:
		prompt_bar.value = clampf(interaction.progress, 0.0, 1.0) * 100.0
		prompt_bar.visible = interaction.progress > 0.005
	# suaviza as barras
	for id in bars:
		var b: Dictionary = bars[id]
		var f: ColorRect = b["fill"]
		var target := 148.0 * clampf(float(b["value"]), 0.0, 1.0)
		f.size.x = lerpf(f.size.x, target, 1.0 - exp(-9.0 * delta))


func _refresh_hotbar() -> void:
	if inv == null:
		return
	for i in 9:
		var s: Dictionary = inv.slots[i]
		var slot: Dictionary = hotbar_slots[i]
		var lbl: Label = slot["label"]
		var bg: ColorRect = slot["bg"]
		if s.is_empty():
			lbl.text = ""
		else:
			var id := str(s["id"])
			lbl.text = "%s\n%d" % [Db.item_name(id).substr(0, 10), int(s["qty"])]
		bg.color = Color(1, 1, 1, 0.14) if i == inv.hotbar_index else Color(0, 0, 0, 0.35)


func _on_stat(id: String, value: float, max_value: float) -> void:
	if not bars.has(id):
		return
	(bars[id] as Dictionary)["value"] = value / maxf(max_value, 0.001)


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


func _on_focus(_who: Node, key: String) -> void:
	prompt_label.text = "" if key == "" else "[E] " + Loc.t(key)


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
			((bars[id] as Dictionary)["label"] as Label).text = Loc.t("hud." + id).substr(0, 3).to_upper()
