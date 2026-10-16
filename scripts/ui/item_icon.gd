class_name ItemIcon
extends Control
## Ícones vetoriais pequenos, desenhados com primitivas do Godot para evitar
## depender de emojis ou fontes externas (que falham entre plataformas).

var item_id := ""

const INK := Color("202a2b")
const WOOD := Color("a97542")
const LEAF := Color("76ad55")
const METAL := Color("c8d5d2")
const RED := Color("d94e4d")
const BLUE := Color("60b6d2")
const GOLD := Color("f3c966")


func set_item(id: String) -> void:
	if item_id == id:
		return
	item_id = id
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	if s <= 1.0:
		return
	var center := size * 0.5
	var k := s / 40.0
	match item_id:
		"needs":
			for i in 3:
				var yy := (-9.0 + float(i) * 9.0) * k
				draw_circle(center + Vector2(-9, yy / k) * k, 2.0 * k, GOLD)
				draw_line(center + Vector2(-3, yy), center + Vector2(10, yy), Color("e8e4d5"), 2.4 * k, true)
		"health":
			draw_circle(center + Vector2(-5, -5) * k, 6.0 * k, Color("ee6a70"))
			draw_circle(center + Vector2(5, -5) * k, 6.0 * k, Color("ee6a70"))
			_poly(center + Vector2(0, 1) * k, [Vector2(-11, -3), Vector2(11, -3), Vector2(0, 13)], Color("ee6a70"))
		"stamina":
			_poly(center, [Vector2(2, -15), Vector2(-9, 2), Vector2(-1, 2), Vector2(-4, 14), Vector2(10, -4), Vector2(2, -4)], GOLD)
		"hunger":
			_stroke(center + Vector2(-9, -13) * k, center + Vector2(-9, 12) * k, METAL, 2.4 * k)
			_stroke(center + Vector2(-14, -11) * k, center + Vector2(-14, -3) * k, METAL, 1.5 * k)
			_stroke(center + Vector2(-9, -11) * k, center + Vector2(-9, -3) * k, METAL, 1.5 * k)
			_stroke(center + Vector2(-4, -11) * k, center + Vector2(-4, -3) * k, METAL, 1.5 * k)
			_stroke(center + Vector2(9, -13) * k, center + Vector2(9, 12) * k, GOLD, 2.4 * k)
		"thirst":
			_poly(center, [Vector2(0, -16), Vector2(11, -1), Vector2(9, 9), Vector2(0, 14), Vector2(-9, 9), Vector2(-11, -1)], BLUE)
		"energy":
			draw_circle(center, 12.0 * k, Color("d7d5f2"))
			draw_circle(center + Vector2(6, -5) * k, 10.0 * k, Color("29313b"))
		"warmth":
			draw_circle(center, 7.0 * k, Color("f09c59"))
			for i in 8:
				var a := float(i) * TAU / 8.0
				_stroke(center + Vector2(cos(a), sin(a)) * 10.0 * k, center + Vector2(cos(a), sin(a)) * 15.0 * k, GOLD, 1.8 * k)
		"sanity":
			draw_arc(center, 11.0 * k, PI, TAU, 18, Color("b9dce7"), 2.0 * k, true)
			draw_arc(center, 11.0 * k, 0.0, PI, 18, Color("b9dce7"), 2.0 * k, true)
			draw_circle(center, 4.0 * k, Color("b9dce7"))
			draw_circle(center, 1.5 * k, INK)
		"blessing":
			var star := PackedVector2Array()
			for i in 10:
				var a := -PI * 0.5 + float(i) * PI / 5.0
				var r := (14.0 if i % 2 == 0 else 6.0) * k
				star.append(center + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(star, GOLD)
		"axe":
			_stroke(center + Vector2(7, 13) * k, center + Vector2(-8, -13) * k, WOOD, 5.0 * k)
			_poly(center + Vector2(-9, -12) * k, [Vector2(-1, -8), Vector2(11, -7), Vector2(10, 1), Vector2(1, 6), Vector2(-3, 2)], METAL)
		"pickaxe":
			_stroke(center + Vector2(8, 13) * k, center + Vector2(-7, -11) * k, WOOD, 5.0 * k)
			_stroke(center + Vector2(-14, -10) * k, center + Vector2(12, -14) * k, METAL, 5.0 * k)
			_stroke(center + Vector2(-14, -10) * k, center + Vector2(-18, -14) * k, METAL, 3.0 * k)
		# Ferramentas de madeira: MESMA forma, cabeça em madeira — o ícone diz
		# logo "isto é o degrau fraco" sem precisar de texto.
		"wood_axe":
			_stroke(center + Vector2(7, 13) * k, center + Vector2(-8, -13) * k, Color("8a6136"), 5.0 * k)
			_poly(center + Vector2(-9, -12) * k, [Vector2(-1, -8), Vector2(11, -7), Vector2(10, 1), Vector2(1, 6), Vector2(-3, 2)], Color("bd8b53"))
			_stroke(center + Vector2(2, -9) * k, center + Vector2(7, 2) * k, Color("6d4a29"), 1.6 * k)
		"wood_pickaxe":
			_stroke(center + Vector2(8, 13) * k, center + Vector2(-7, -11) * k, Color("8a6136"), 5.0 * k)
			_stroke(center + Vector2(-14, -10) * k, center + Vector2(12, -14) * k, Color("bd8b53"), 5.0 * k)
			_stroke(center + Vector2(-14, -10) * k, center + Vector2(-18, -14) * k, Color("bd8b53"), 3.0 * k)
			_stroke(center + Vector2(-9, -12) * k, center + Vector2(-4, -11) * k, Color("6d4a29"), 2.0 * k)
		"rod":
			_stroke(center + Vector2(-8, 14) * k, center + Vector2(8, -16) * k, WOOD, 3.0 * k)
			_stroke(center + Vector2(8, -16) * k, center + Vector2(16, -5) * k, INK, 1.4 * k)
			draw_arc(center + Vector2(16, -4) * k, 4.0 * k, 0.0, TAU, 20, METAL, 1.8 * k, true)
		"torch", "campfire":
			if item_id == "campfire":
				_stroke(center + Vector2(-14, 12) * k, center + Vector2(14, 12) * k, WOOD, 5.0 * k)
				_stroke(center + Vector2(-11, 15) * k, center + Vector2(11, 15) * k, INK, 1.0 * k)
				_stroke(center + Vector2(-11, 12) * k, center + Vector2(11, 12) * k, WOOD, 5.0 * k)
			else:
				_stroke(center + Vector2(8, 15) * k, center + Vector2(-5, -8) * k, WOOD, 5.0 * k)
			_poly(center + Vector2(-5, -10) * k, [Vector2(0, 10), Vector2(-6, 2), Vector2(-4, -3), Vector2(-1, -10), Vector2(3, -3), Vector2(7, 1), Vector2(5, 8)], GOLD)
			draw_circle(center + Vector2(0, -7) * k, 4.0 * k, Color("ff8a45"))
		"wood", "stick":
			_stroke(center + Vector2(-13, 8) * k, center + Vector2(13, -8) * k, WOOD, 6.0 * k)
			_stroke(center + Vector2(-12, 11) * k, center + Vector2(14, -5) * k, Color("d29a60"), 2.0 * k)
		"stone", "flint":
			_poly(center, [Vector2(-15, 5), Vector2(-10, -9), Vector2(-1, -14), Vector2(13, -8), Vector2(15, 5), Vector2(5, 13), Vector2(-8, 12)], Color("9da7a4") if item_id == "stone" else Color("87949e"))
		"fiber":
			for i in 3:
				_stroke(center + Vector2(-9 + i * 7, 12) * k, center + Vector2(-12 + i * 8, -10) * k, LEAF.lightened(float(i) * 0.08), 3.0 * k)
		"leaf":
			_poly(center, [Vector2(-14, 5), Vector2(-12, -3), Vector2(-5, -12), Vector2(5, -14), Vector2(13, -8), Vector2(14, 0), Vector2(7, 9), Vector2(-2, 13)], LEAF)
			_stroke(center + Vector2(-10, 9) * k, center + Vector2(9, -9) * k, Color("d9d69b"), 1.6 * k)
		"mushroom":
			draw_rect(Rect2(center + Vector2(-3, -2) * k, Vector2(6, 15) * k), Color("f2e8d4"))
			_poly(center + Vector2(0, -3) * k, [Vector2(-13, 2), Vector2(-10, -5), Vector2(-5, -10), Vector2(4, -10), Vector2(10, -5), Vector2(13, 2), Vector2(9, 5), Vector2(-9, 5)], Color("d96d56"))
		"meat_raw", "meat_cooked", "fish_raw", "fish_cooked", "stew":
			var cooked := item_id.ends_with("cooked") or item_id == "stew"
			draw_circle(center, 11.0 * k, Color("b95d49") if cooked else Color("d98078"))
			draw_circle(center + Vector2(-2, -3) * k, 4.0 * k, Color("f5d2a7"))
			if item_id.begins_with("fish"):
				_poly(center + Vector2(8, 0) * k, [Vector2(0, 0), Vector2(9, -7), Vector2(9, 7)], BLUE)
		"bottle", "water":
			_poly(center, [Vector2(-6, -14), Vector2(6, -14), Vector2(6, -8), Vector2(11, -4), Vector2(10, 13), Vector2(-10, 13), Vector2(-11, -4), Vector2(-6, -8)], Color("9ed8d0"))
			draw_rect(Rect2(center + Vector2(-7, 1) * k, Vector2(14, 10) * k), BLUE if item_id == "water" else Color("c5e6d7"))
			_stroke(center + Vector2(-5, -10) * k, center + Vector2(5, -10) * k, INK, 2.0 * k)
		"workbench":
			# tampo + quatro pernas + ferramentas em cima
			draw_rect(Rect2(center + Vector2(-15, -8) * k, Vector2(30, 7) * k), INK)
			draw_rect(Rect2(center + Vector2(-14, -7) * k, Vector2(28, 5) * k), WOOD)
			for dx in [-12.0, 8.0]:
				draw_rect(Rect2(center + Vector2(dx, -2) * k, Vector2(6, 16) * k), INK)
				draw_rect(Rect2(center + Vector2(dx + 1, -1) * k, Vector2(4, 14) * k), Color("8a5f38"))
			_stroke(center + Vector2(-10, -12) * k, center + Vector2(-3, -12) * k, METAL, 2.2 * k)
			_stroke(center + Vector2(2, -13) * k, center + Vector2(9, -10) * k, METAL, 2.2 * k)
		"wall", "floor", "pillar", "bed":
			if item_id == "wall":
				draw_rect(Rect2(center + Vector2(-13, -11) * k, Vector2(26, 22) * k), WOOD)
				for y in [-5, 3]: _stroke(center + Vector2(-11, y) * k, center + Vector2(11, y) * k, Color("d49b62"), 1.5 * k)
			elif item_id == "floor":
				for y in [-9, -3, 3, 9]: _stroke(center + Vector2(-13, y) * k, center + Vector2(13, y) * k, WOOD, 4.0 * k)
			elif item_id == "pillar":
				draw_rect(Rect2(center + Vector2(-6, -14) * k, Vector2(12, 28) * k), WOOD)
				_stroke(center + Vector2(-8, -12) * k, center + Vector2(8, -12) * k, GOLD, 2.0 * k)
			else:
				draw_rect(Rect2(center + Vector2(-13, 2) * k, Vector2(26, 9) * k), WOOD)
				_stroke(center + Vector2(-9, 0) * k, center + Vector2(-9, 14) * k, INK, 2.0 * k)
				_stroke(center + Vector2(9, 0) * k, center + Vector2(9, 14) * k, INK, 2.0 * k)
		_:
			draw_circle(center, 13.0 * k, Color("647a74"))
			draw_string(ThemeDB.fallback_font, center + Vector2(-4, 5) * k, item_id.substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * k), Color.WHITE)


func _stroke(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	draw_line(a, b, INK, width + 2.0, true)
	draw_line(a, b, color, width, true)


func _poly(origin: Vector2, points: Array, color: Color) -> void:
	var pts := PackedVector2Array()
	for p in points:
		pts.append(origin + p * (minf(size.x, size.y) / 40.0))
	draw_colored_polygon(pts, INK)
	var inner := PackedVector2Array()
	for p in points:
		inner.append(origin + p * (minf(size.x, size.y) / 40.0) * 0.86)
	draw_colored_polygon(inner, color)
