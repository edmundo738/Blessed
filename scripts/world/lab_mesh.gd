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
			colors.append(_color_at(lab, p.x, p.y, h))
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
	arrays[Mesh.ARRAY_INDEX] = idx
	return {"arrays": arrays, "faces": faces, "verts": verts.size()}


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
	# humidade escurece o solo: o campo ve-se sem legenda
	c = c.lerp(c * 0.72, float(s["moisture"]) * 0.35)
	return c


static func build_water(lab: LabWorld) -> Dictionary:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	var half := LabWorld.CELL * 0.5
	var base := 0
	for j in LabWorld.N:
		for i in LabWorld.N:
			var p := lab.grid_pos(i, j)
			var s := lab.sample(p.x, p.y)
			if int(s["water_kind"]) == 0:
				continue
			var wl: float = s["water_level"]
			var kind := int(s["water_kind"])
			var c := Color(0.15, 0.45, 0.75, 0.82)
			if kind == 2:
				c = Color(0.25, 0.65, 0.85, 0.82)
			elif kind == 3:
				c = Color(0.20, 0.55, 0.70, 0.82)
			var corners := [
				Vector3(p.x - half, wl, p.y - half), Vector3(p.x + half, wl, p.y - half),
				Vector3(p.x - half, wl, p.y + half), Vector3(p.x + half, wl, p.y + half)]
			for v in corners:
				verts.append(v)
				normals.append(Vector3.UP)
				colors.append(c)
			# Mesma convencao do terreno: cantos 0=(-,-) 1=(+,-) 2=(-,+)
			# 3=(+,+); frente (de cima) = [0,1,3 / 0,3,2]. A ordem anterior
			# so era visivel por baixo.
			idx.append_array([base, base + 1, base + 3, base, base + 3, base + 2])
			base += 4
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	return {"arrays": arrays, "quads": base / 4}
