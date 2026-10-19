class_name CavePatch
extends RefCounted
## CavePatch — escavação VOLUMÉTRICA sobre o LabWorld (protótipo).
##
## O terreno é heightfield (rios/lagos/hidrologia NÃO se toca). Este
## patch é um monte de rocha com campo de distância assinada (SDF) em
## grelha 3D: sólido onde sdf<0, ar onde sdf>0. Escavar = subtrair
## esfera com blend suave (smax polinomial) — os túneis nascem com
## cantos arredondados em vez de buracos dentados. A malha renasce por
## Surface Nets ingénua e cada triângulo é virado até alinhar com o
## gradiente do SDF: faces para fora POR CONSTRUÇÃO (lição do winding).
##
## Dentro da rocha há VEIOS DE SÍLEX determinísticos (hash da posição):
## brilham ocre na malha e rendem `flint` ao escavar; escavado o veio,
## o brilho some. Determinístico por construção (sem RNG de sessão).

var origin: Vector3  # canto mínimo no mundo
var dims: Vector3i  # células por eixo
var cell: float = 1.0
var sdf: PackedFloat32Array  # pontos da grelha (dims+1 por eixo)
var ore: Array[Vector3] = []  # veios de sílex ainda por escavar (mundo)
var last_outward_ratio := 0.0
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
	var rr := Vector3(maxf(c.x, 1.0), maxf(c.y, 1.0), maxf(c.z, 1.0))
	for z in nz:
		for y in ny:
			for x in nx:
				var p := Vector3(x, y, z) * cell
				# monte arredondado (elipsoide), não uma caixa: a rocha
				# lê-se como outeiro na encosta, com ruído de superfície
				var k := (p - c) / rr
				var ell := (k.length() - 1.0) * minf(rr.x, minf(rr.y, rr.z))
				sdf[_idx(x, y, z)] = ell + _rock_noise(p) * 0.55
				# veio de sílex: bem dentro da rocha, determinístico
				if ell < -2.2 and _vein_hash(x, y, z) > 0.86:
					ore.append(origin + p)


func _idx(x: int, y: int, z: int) -> int:
	return x + (dims.x + 1) * (y + (dims.y + 1) * z)


func _rock_noise(p: Vector3) -> float:
	var xi := int(floor(p.x * 0.5))
	var yi := int(floor(p.y * 0.5))
	var zi := int(floor(p.z * 0.5))
	var h := (xi * 374761393 + yi * 668265263 + zi * 1274126177) & 0x7fffffff
	return float(h % 1000) / 1000.0 - 0.5


func _vein_hash(x: int, y: int, z: int) -> float:
	var h := (x * 911 + y * 541 + z * 733) & 0x7fffffff
	h = (h ^ (h >> 13)) * 1274126177 & 0x7fffffff
	return float(h % 1000) / 1000.0


func sdf_at_world(wp: Vector3) -> float:
	var lp := (wp - origin) / cell
	var x := clampi(int(round(lp.x)), 0, dims.x)
	var y := clampi(int(round(lp.y)), 0, dims.y)
	var z := clampi(int(round(lp.z)), 0, dims.z)
	return sdf[_idx(x, y, z)]


func is_air(wp: Vector3) -> bool:
	return sdf_at_world(wp) > 0.0


## Há sílex por escavar perto deste ponto?
func ore_near(wp: Vector3, r: float) -> bool:
	for o in ore:
		if o.distance_to(wp) <= r:
			return true
	return false


## Retira o sílex num raio (foi escavado). Devolve true se havia.
func consume_ore(wp: Vector3, r: float) -> bool:
	var found := false
	for i in range(ore.size() - 1, -1, -1):
		if ore[i].distance_to(wp) <= r:
			ore.remove_at(i)
			found = true
	return found


func _smax(a: float, b: float, k: float) -> float:
	# máximo suave polinomial: mistura a e b numa banda k (cantos moles)
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(a, b, h) + k * h * (1.0 - h)


## Escava esfera com blend suave (túneis arredondados). smooth<=0 = corte seco.
func carve(wp: Vector3, radius: float, smooth: float = 0.7) -> int:
	var lp := wp - origin
	var r := radius + cell + smooth
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
				var tool := radius - p.distance_to(lp)
				var i := _idx(x, y, z)
				var nv: float = _smax(sdf[i], tool, smooth) if smooth > 0.0 else maxf(sdf[i], tool)
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


## Surface Nets: arrays + faces de colisão + cores (rocha / brilho de
## sílex) + prova de orientação (1.0 = normais para fora do sólido).
func build_mesh() -> Dictionary:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	var vert_of := {}
	for z in dims.z:
		for y in dims.y:
			for x in dims.x:
				var corners: Array[float] = []
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
				var wp := origin + vp * cell
				vert_of[x + dims.x * (y + dims.y * z)] = verts.size()
				verts.append(wp)
				var g := _grad(x, y, z)
				normals.append(g.normalized() if g.length() > 0.0001 else Vector3.UP)
				# cor: brilho ocre onde há sílex por baixo; rocha no resto
				if ore_near(wp, 1.7):
					colors.append(Color(0.92, 0.66, 0.28))
				else:
					var sh := 0.36 + (_rock_noise(vp * cell) + 0.5) * 0.14
					colors.append(Color(sh, sh * 0.94, sh * 0.86))
	var tris: Array = []
	_add_axis_quads(vert_of, tris, 0)
	_add_axis_quads(vert_of, tris, 1)
	_add_axis_quads(vert_of, tris, 2)
	var faces := PackedVector3Array()
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
			idx.append_array([t[0], t[2], t[1]])
			faces.append_array([a, c, b])
		else:
			idx.append_array([t[0], t[1], t[2]])
			faces.append_array([a, b, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	last_verts = verts.size()
	last_tris = idx.size() / 3
	last_outward_ratio = 1.0 if idx.size() > 0 else 0.0
	return {"arrays": arrays, "faces": faces, "verts": last_verts,
			"tris": last_tris, "outward": last_outward_ratio}


func _add_axis_quads(vert_of: Dictionary, tris: Array, axis: int) -> void:
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
