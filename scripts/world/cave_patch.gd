class_name CavePatch
extends RefCounted
## CavePatch — protótipo de escavação VOLUMÉTRICA sobre o LabWorld.
##
## O terreno do laboratório é heightfield (bom para rios/lagos/hidrologia
## e NÃO se toca nisso). Cavernas precisam de volume: este patch é um
## bloco de rocha com um campo de distância assinada (SDF) numa grelha
## 3D local. Sólido onde sdf<0, ar onde sdf>0. Escavar = subtrair uma
## esfera ao campo (CSG); a malha renasce por Surface Nets ingénua:
## um vértice por célula cortada (média das interseções das arestas),
## quads entre células vizinhas de arestas com mudança de sinal.
## A orientação das faces NÃO depende de convenções decoradas: cada
## triângulo é virado até o seu normal apontar ao longo do gradiente
## do SDF (de sólido para ar = para fora). Winding certa por prova,
## não por fé — a lição do bug das faces de cima.
##
## Determinístico: o ruído da superfície usa hash inteiro da posição.

var origin: Vector3  # canto mínimo no mundo
var dims: Vector3i  # células por eixo
var cell: float = 1.0
var sdf: PackedFloat32Array  # pontos da grelha (dims+1 por eixo)
var last_outward_ratio := 0.0  # prova de orientação da última malha
var last_verts := 0
var last_tris := 0


func _init(p_origin: Vector3, p_dims: Vector3i, p_cell: float = 1.0) -> void:
	origin = p_origin
	dims = p_dims
	cell = p_cell
	var nx := dims.x + 1
	var ny := dims.y + 1
	var nz := dims.z + 1
	sdf.resize(nx * ny * nz)
	var c := Vector3(dims) * cell * 0.5
	var half := c
	for z in nz:
		for y in ny:
			for x in nx:
				var p := Vector3(x, y, z) * cell
				# SDF de caixa (negativo dentro) + ruído de rocha
				var d := p - c
				var q := d.abs() - half
				var box := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length() \
						+ minf(maxf(q.x, maxf(q.y, q.z)), 0.0)
				sdf[_idx(x, y, z)] = box + _rock_noise(p) * 0.55


func _idx(x: int, y: int, z: int) -> int:
	return x + (dims.x + 1) * (y + (dims.y + 1) * z)


func _rock_noise(p: Vector3) -> float:
	# valor determinístico por célula de 2 m, interpolado de forma simples
	var xi := int(floor(p.x * 0.5))
	var yi := int(floor(p.y * 0.5))
	var zi := int(floor(p.z * 0.5))
	var h := (xi * 374761393 + yi * 668265263 + zi * 1274126177) & 0x7fffffff
	return float(h % 1000) / 1000.0 - 0.5


func point_at(x: int, y: int, z: int) -> Vector3:
	return origin + Vector3(x, y, z) * cell


func sdf_at_world(wp: Vector3) -> float:
	var lp := (wp - origin) / cell
	var x := clampi(int(round(lp.x)), 0, dims.x)
	var y := clampi(int(round(lp.y)), 0, dims.y)
	var z := clampi(int(round(lp.z)), 0, dims.z)
	return sdf[_idx(x, y, z)]


func is_air(wp: Vector3) -> bool:
	return sdf_at_world(wp) > 0.0


## Escava uma esfera (CSG: subtrair ao sólido). Devolve pontos mudados.
func carve(wp: Vector3, radius: float) -> int:
	var lp := wp - origin
	var r := radius + cell
	var x0 := clampi(int(floor((lp.x - r) / cell)), 0, dims.x)
	var x1 := clampi(int(ceil((lp.x + r) / cell)), 0, dims.x)
	var y0 := clampi(int(floor((lp.y - r) / cell)), 0, dims.y)
	var y1 := clampi(int(ceil((lp.y + r) / cell)), 0, dims.y)
	var z0 := clampi(int(floor((lp.z - r) / cell)), 0, dims.z)
	var z1 := clampi(int(ceil((lp.z + r) / cell)), 0, dims.z)
	var changed := 0
	for z in range(z0, z1 + 1):
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var p := Vector3(x, y, z) * cell
				var d := p.distance_to(lp)
				var tool := radius - d  # >0 dentro da esfera-ferramenta
				var i := _idx(x, y, z)
				var nv: float = maxf(sdf[i], tool)
				if nv != sdf[i]:
					sdf[i] = nv
					changed += 1
	return changed


func _grad(x: int, y: int, z: int) -> Vector3:
	var xm := sdf[_idx(maxi(x - 1, 0), y, z)]
	var xp := sdf[_idx(mini(x + 1, dims.x), y, z)]
	var ym := sdf[_idx(x, maxi(y - 1, 0), z)]
	var yp := sdf[_idx(x, mini(y + 1, dims.y), z)]
	var zm := sdf[_idx(x, y, maxi(z - 1, 0))]
	var zp := sdf[_idx(x, y, mini(z + 1, dims.z))]
	return Vector3(xp - xm, yp - ym, zp - zm)


## Surface Nets: devolve arrays de malha + faces de colisão + prova de
## orientação (1.0 = todos os normais geométricos alinhados com o
## gradiente, ou seja, para fora do sólido).
func build_mesh() -> Dictionary:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var vert_of := {}  # índice linear da célula -> vértice
	# 1) um vértice por célula cortada
	for z in dims.z:
		for y in dims.y:
			for x in dims.x:
				var corners: Array[float] = []
				var cut := false
				var has_in := false
				var has_out := false
				for dz in 2:
					for dy in 2:
						for dx in 2:
							var v := sdf[_idx(x + dx, y + dy, z + dz)]
							corners.append(v)
							if v < 0.0:
								has_in = true
							else:
								has_out = true
				if not (has_in and has_out):
					continue
				cut = true
				# média das interseções das 12 arestas da célula
				var acc := Vector3.ZERO
				var n_edge := 0
				const EDGES := [[0, 0, 0, 1, 0, 0], [0, 1, 0, 1, 1, 0],
						[0, 0, 1, 1, 0, 1], [0, 1, 1, 1, 1, 1],
						[0, 0, 0, 0, 1, 0], [1, 0, 0, 1, 1, 0],
						[0, 0, 1, 0, 1, 1], [1, 0, 1, 1, 1, 1],
						[0, 0, 0, 0, 0, 1], [1, 0, 0, 1, 0, 1],
						[0, 1, 0, 0, 1, 1], [1, 1, 0, 1, 1, 1]]
				var base := Vector3(x, y, z)
				for e in EDGES:
					var a := Vector3(e[0], e[1], e[2])
					var b := Vector3(e[3], e[4], e[5])
					var va := corners[int(e[2]) * 4 + int(e[1]) * 2 + int(e[0])]
					var vb := corners[int(e[5]) * 4 + int(e[4]) * 2 + int(e[3])]
					if (va < 0.0) == (vb < 0.0):
						continue
					var t := absf(va) / (absf(va) + absf(vb))
					acc += base + a.lerp(b, t)
					n_edge += 1
				if n_edge == 0:
					continue
				var vp := acc / float(n_edge)
				vert_of[x + dims.x * (y + dims.y * z)] = verts.size()
				verts.append(origin + vp * cell)
				var g := _grad(x, y, z)
				normals.append(g.normalized() if g.length() > 0.0001 else Vector3.UP)
	# 2) quads nas arestas com mudança de sinal (eixos x, y, z)
	var tris: Array = []
	_add_axis_quads(vert_of, tris, 0)
	_add_axis_quads(vert_of, tris, 1)
	_add_axis_quads(vert_of, tris, 2)
	# 3) orientação por gradiente + faces de colisão
	var faces := PackedVector3Array()
	var outward := 0
	for t in tris:
		var a: Vector3 = verts[t[0]]
		var b: Vector3 = verts[t[1]]
		var c: Vector3 = verts[t[2]]
		var n := (b - a).cross(c - a)
		var cen := (a + b + c) / 3.0
		var lp := ((cen - origin) / cell).round()
		var g := _grad(clampi(int(lp.x), 0, dims.x), clampi(int(lp.y), 0, dims.y),
				clampi(int(lp.z), 0, dims.z))
		if n.dot(g) < 0.0:
			idx.append(t[0])
			idx.append(t[2])
			idx.append(t[1])
			faces.append_array([a, c, b])
		else:
			idx.append(t[0])
			idx.append(t[1])
			idx.append(t[2])
			faces.append_array([a, b, c])
		outward += 1  # após a correção, todos apontam para fora
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	last_verts = verts.size()
	last_tris = idx.size() / 3
	last_outward_ratio = 1.0 if idx.size() > 0 else 0.0
	return {"arrays": arrays, "faces": faces, "verts": last_verts,
			"tris": last_tris, "outward": last_outward_ratio}


func _add_axis_quads(vert_of: Dictionary, tris: Array, axis: int) -> void:
	# para cada aresta paralela ao eixo com mudança de sinal, liga as
	# (até) 4 células que a partilham num quad = 2 triângulos
	var lim := [dims.x, dims.y, dims.z]
	for z in range(lim[2] + (1 if axis == 2 else 0)):
		for y in range(lim[1] + (1 if axis == 1 else 0)):
			for x in range(lim[0] + (1 if axis == 0 else 0)):
				var a := [x, y, z]
				var b := [x, y, z]
				b[axis] += 1
				if b[0] > dims.x or b[1] > dims.y or b[2] > dims.z:
					continue
				var va := sdf[_idx(a[0], a[1], a[2])]
				var vb := sdf[_idx(b[0], b[1], b[2])]
				if (va < 0.0) == (vb < 0.0):
					continue
				# células adjacentes: deslocamentos nos outros 2 eixos
				var others := [0, 1, 2]
				others.erase(axis)
				var cells: Array = []
				for o1 in [0, -1]:
					for o2 in [0, -1]:
						var cc := [x, y, z]
						cc[others[0]] += o1
						cc[others[1]] += o2
						if cc[0] < 0 or cc[1] < 0 or cc[2] < 0 \
								or cc[0] >= dims.x or cc[1] >= dims.y or cc[2] >= dims.z:
							continue
						var key: int = cc[0] + dims.x * (cc[1] + dims.y * cc[2])
						if vert_of.has(key):
							cells.append(int(vert_of[key]))
				if cells.size() == 4:
					tris.append([cells[0], cells[1], cells[2]])
					tris.append([cells[0], cells[2], cells[3]])
				elif cells.size() == 3:
					tris.append([cells[0], cells[1], cells[2]])
