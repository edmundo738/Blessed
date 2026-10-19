class_name LabMesh
extends RefCounted
## LabMesh — do dado ao poligono.
##
## Le a grelha do LabWorld e produz, por pedaco (chunk de 50 m):
##   - ArrayMesh suave (normais por gradiente, cor por bioma/campo)
##   - faces para ConcavePolygonShape3D (colisao que acompanha a mesh)
## Cavar reconstrói so os pedacos tocados — nunca a ilha inteira.
## A agua e uma so malha de celulas (nivel por celula), reconstruida ao cavar.

const CHUNK_CELLS := 10  # 10 celulas de 5 m = 50 m por pedaco
const BIOME_COLORS := {
	0: Color(0.05, 0.20, 0.45),  # oceano (leito)
	1: Color(0.85, 0.76, 0.55),  # praia
	2: Color(0.38, 0.58, 0.28),  # prado
	3: Color(0.18, 0.42, 0.22),  # floresta
	4: Color(0.85, 0.58, 0.68),  # bosque sakura
	5: Color(0.48, 0.46, 0.48),  # rocha
	6: Color(0.35, 0.48, 0.30),  # pantano
	7: Color(0.80, 0.66, 0.38),  # seco
}


static func chunk_count() -> int:
	return (LabWorld.N - 1) / CHUNK_CELLS


## Auditoria de winding (regressao do bug "so se ve por baixo"): conta os
## triangulos cuja winding contradiz a normal do vertice. Na convencao do
## Godot (frontal = horario), o produto cruzado geometrico de uma face
## correta aponta para o lado OPOSTO ao da normal de shading; dot > 0 (ou
## triangulo degenerado) = face virada ao contrario. Tem de dar 0.
static func winding_mismatch(arrays: Array) -> int:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if verts.is_empty() or normals.size() != verts.size() or idx.size() < 3:
		return 0
	var bad := 0
	var t := 0
	while t + 2 < idx.size():
		var ia: int = idx[t]
		var ib: int = idx[t + 1]
		var ic: int = idx[t + 2]
		var geo := (verts[ib] - verts[ia]).cross(verts[ic] - verts[ia])
		var vn := normals[ia] + normals[ib] + normals[ic]
		if geo.length_squared() < 1e-12 or geo.dot(vn) > 0.0:
			bad += 1
		t += 3
	return bad


static func build_chunk(lab: LabWorld, ci: int, cj: int) -> Dictionary:
	var seg := CHUNK_CELLS
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	var i0 := ci * CHUNK_CELLS
	var j0 := cj * CHUNK_CELLS
	for j in seg + 1:
		for i in seg + 1:
			var gi: int = i0 + i
			var gj: int = j0 + j
			var p := lab.grid_pos(gi, gj)
			var h := lab.height(p.x, p.y)
			verts.append(Vector3(p.x, h, p.y))
			var e := 2.0
			var n := Vector3(lab.height(p.x - e, p.y) - lab.height(p.x + e, p.y),
					2.0 * e,
					lab.height(p.x, p.y - e) - lab.height(p.x, p.y + e)).normalized()
			normals.append(n)
			# COLOR.a = neve no shader do mundo. O laboratório não tem neve,
			# por isso o alfa fica a zero em vez de transformar a ilha inteira
			# num campo branco quando o material partilhado entra.
			var c := _color_at(lab, p.x, p.y, h)
			colors.append(Color(c.r, c.g, c.b, 0.0))
			var w := _weights_at(lab, p.x, p.y, h)
			uvs.append(Vector2(w.x, w.y))
			uv2s.append(Vector2(w.z, w.w))
	for j in seg:
		for i in seg:
			var a := j * (seg + 1) + i
			var b := a + 1
			var c := a + seg + 1
			var d := c + 1
			# CONVENCAO DO REPO (chunk.gd, KNOWN_ISSUES #9): no Godot a face
			# frontal e a de winding HORARIA vista de frente. Com b=+x,
			# c=+z, d=diagonal, a ordem certa vista de cima e [a,b,d / a,d,c].
			# A ordem anterior [a,c,b] estava espelhada: o rasterizador
			# deitava fora a face de cima (backface culling) e o terreno so
			# se via por baixo, apesar das normais apontarem para cima.
			idx.append_array([a, b, d, a, d, c])
			faces.append_array([verts[a], verts[b], verts[d], verts[a], verts[d], verts[c]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = idx
	return {"arrays": arrays, "faces": faces, "verts": verts.size()}


## Pesos das quatro classes do shader do mundo: (relva, terra, areia, estratos).
## O laboratório tem materiais explícitos, por isso a conversão é direta e não
## uma segunda opinião inventada: areia é areia, rocha é estrato, terra exposta
## é terra, e a relva só existe onde a humidade e o declive a deixam nascer.
static func _weights_at(lab: LabWorld, x: float, z: float, _h: float) -> Vector4:
	var s := lab.sample(x, z)
	if int(s["water_kind"]) != 0:
		return Vector4(0.0, 0.0, 1.0, 0.0)
	var mat := int(s["material"])
	var dug := float(s["depth_dug"])
	var slope := float(s["slope"])
	if mat == LabWorld.M_SAND:
		return Vector4(0.0, 0.0, 1.0, 0.0)
	if mat == LabWorld.M_ROCK or slope > 0.55 or dug > 0.24:
		return Vector4(0.0, 0.0, 0.0, 1.0)
	if dug > 0.10:
		return Vector4(0.0, 1.0, 0.0, 0.0)
	var moisture := clampf(float(s["moisture"]), 0.0, 1.0)
	var grass := clampf((moisture - 0.18) * 1.55, 0.0, 1.0)
	# Bosque/prado segura mais relva que a savana seca.
	match int(s["biome"]):
		LabWorld.B_MEADOW, LabWorld.B_FOREST, LabWorld.B_GROVE, LabWorld.B_MARSH:
			grass = maxf(grass, 0.72)
		LabWorld.B_DRY:
			grass *= 0.55
		LabWorld.B_BEACH, LabWorld.B_ROCK:
			grass = 0.0
	var dirt := 1.0 - grass
	return Vector4(grass, dirt, 0.0, 0.0)


static func _color_at(lab: LabWorld, x: float, z: float, h: float) -> Color:
	var b := lab.biome_at(x, z)
	var c: Color = BIOME_COLORS.get(b, Color.MAGENTA)
	var s := lab.sample(x, z)
	if h < 0.0:
		# leito: areia rasa -> fundo escuro
		return Color(0.76, 0.68, 0.48).lerp(Color(0.10, 0.25, 0.38), clampf(-h / 14.0, 0.0, 1.0))
	var sl: float = s["slope"]
	if sl > 0.45:
		c = c.lerp(BIOME_COLORS[5], clampf((sl - 0.45) / 0.5, 0.0, 0.75))
	# CAMADAS EXPOSTAS: onde ja se escavou, a parede do buraco le-se por
	# estratos (a mesma profundidade que decide o material/ferramenta):
	# topsoil escuro -> subsolo ocre -> rocha cinzenta.
	var dug := lab.depth_dug(x, z)
	if dug > 0.12:
		var layer := Color(0.40, 0.30, 0.19)
		if dug > LabWorld.LAYER_ROCK:
			layer = Color(0.44, 0.44, 0.47)
		elif dug > LabWorld.LAYER_TOP:
			layer = Color(0.56, 0.43, 0.27)
		c = c.lerp(layer, clampf((dug - 0.12) / 0.5, 0.0, 0.9))
	# humidade escurece o solo: o campo ve-se sem legenda
	c = c.lerp(c * 0.72, float(s["moisture"]) * 0.35)
	return c


## Agua: malha sobre OS MESMOS pontos de grelha do terreno, com os
## triangulos RECORTADOS pelo campo assinado (nivel - altura), como o
## mundo principal faz em chunk.gd (_add_clipped_water_triangle).
## A versao anterior emitia um quadrado plano por celula: na costa, o
## quadrado ou cobria terra seca ou deixava triangulos orfaos serrilhados.
## Com o recorte, a linha de costa nasce onde nivel == altura ao longo da
## aresta — terra e agua partilham a mesma amostragem e soldam.
static func build_water(lab: LabWorld) -> Dictionary:
	var n := LabWorld.N
	var pts: Array[Dictionary] = []
	pts.resize(n * n)
	for j in n:
		for i in n:
			var p := lab.grid_pos(i, j)
			var s := lab.sample(p.x, p.y)
			var h: float = s["height"]
			var wl: float = s["water_level"]
			var kind := int(s["water_kind"])
			var c := Color(0.15, 0.45, 0.75, 0.82)
			if kind == 2:
				c = Color(0.25, 0.65, 0.85, 0.82)
			elif kind == 3:
				c = Color(0.20, 0.55, 0.70, 0.82)
			var signed := -1.0
			var level := h - 1.0
			var depth := 0.0
			if wl > -50000.0:
				signed = wl - h
				level = wl
				depth = maxf(wl - h, 0.0)
			# UV2 = (profundidade, salinidade). COLOR = (velocidade, turvação,
			# corrente x, corrente z em 0..1). É o mesmo contrato do mundo
			# grande: um shader, três águas.
			var salt := 1.0 if kind == 1 else 0.0
			var speed := 0.42 if kind == 2 else (0.05 if kind == 3 else 0.55)
			var turb := 0.30 if kind == 2 else (0.22 if kind == 1 else 0.40)
			var uv2 := Vector2(depth, salt)
			var run := Color(speed, turb, 0.5, 0.5)
			pts[j * n + i] = {"xz": p, "level": level, "signed": signed,
				"col": run, "uv2": uv2}
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := a + n + 1
			_clip_water_tri(pts, [a, b, d], verts, normals, colors, uv2s, idx)
			_clip_water_tri(pts, [a, d, c], verts, normals, colors, uv2s, idx)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = idx
	return {"arrays": arrays, "quads": idx.size() / 6}


static func _water_vert(pts: Array, k: int) -> Dictionary:
	var p: Dictionary = pts[k]
	var xz: Vector2 = p["xz"]
	return {"pos": Vector3(xz.x, float(p["level"]), xz.y),
			"signed": float(p["signed"]), "col": p["col"], "uv2": p["uv2"]}


## Recorta um triangulo pelo semiplano molhado (signed > 0), interpolando
## posicao/nivel/cor nas arestas que cruzam a costa. Preserva a winding
## de entrada (a,b,d / a,d,c — frontal de cima, convencao do repo).
static func _clip_water_tri(pts: Array, tri: Array, verts: PackedVector3Array,
		normals: PackedVector3Array, colors: PackedColorArray,
		uv2s: PackedVector2Array, idx: PackedInt32Array) -> void:
	var poly: Array[Dictionary] = []
	for k in tri:
		poly.append(_water_vert(pts, int(k)))
	var clipped: Array[Dictionary] = []
	for t in 3:
		var cur: Dictionary = poly[t]
		var nxt: Dictionary = poly[(t + 1) % 3]
		var cur_in := float(cur["signed"]) > 0.0
		var nxt_in := float(nxt["signed"]) > 0.0
		if cur_in:
			clipped.append(cur)
		if cur_in != nxt_in:
			var sa := float(cur["signed"])
			var sb := float(nxt["signed"])
			var f := sa / (sa - sb)
			clipped.append({
				"pos": (cur["pos"] as Vector3).lerp(nxt["pos"], f),
				"signed": 0.0,
				"col": (cur["col"] as Color).lerp(nxt["col"], f),
				"uv2": (cur["uv2"] as Vector2).lerp(nxt["uv2"], f),
			})
	if clipped.size() < 3:
		return
	var base := verts.size()
	for v in clipped:
		verts.append(v["pos"])
		normals.append(Vector3.UP)
		colors.append(v["col"])
		uv2s.append(v["uv2"])
	for t in range(1, clipped.size() - 1):
		idx.append_array([base, base + t, base + t + 1])
