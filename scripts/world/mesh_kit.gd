class_name MeshKit
extends RefCounted
## MeshKit — toda a geometria do jogo é feita aqui, em código.
##
## Nada de .obj/.glb/.png: o mundo inteiro é gerado. Vantagens concretas:
##   • o projeto não tem **nenhum** import → corre no editor e num .pck de script
##   • cada árvore/rocha pode variar por semente sem custo de memória
##   • LOD é só "menos subdivisões", não outro ficheiro
##
## Convenção: todas as malhas devolvem ArrayMesh com VERTEX + NORMAL + COLOR.
## A cor de vértice leva a tinta local (sombra na base, brilho no topo) e o
## shader multiplica-a pela cor da instância.

const UP := Vector3.UP


# ══════════════════════════════════════════════════════════════════════════
#  PRIMITIVAS
# ══════════════════════════════════════════════════════════════════════════
## Triângulo com a winding corrigida para o lado de `hint`.
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, hint: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(hint) < 0.0:
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
	else:
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)


## Icosfera subdividida — a bolha de folhagem do estilo anime.
static func blob(rng: RandomNumberGenerator, radius: float, subdiv: int = 2,
		jitter: float = 0.18, scale_v: Vector3 = Vector3.ONE,
		tint: Color = Color(1, 1, 1)) -> ArrayMesh:
	var verts: Array[Vector3] = []
	var faces: Array = []
	_icosa(verts, faces)
	for s in subdiv:
		_subdivide(verts, faces)
	# projeta na esfera e aplica jitter
	for i in verts.size():
		var v := verts[i].normalized()
		if jitter > 0.0:
			var n := rng.randf_range(-jitter, jitter)
			v *= 1.0 + n
		verts[i] = v * radius * scale_v

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var a: Vector3 = verts[f[0]]
		var b: Vector3 = verts[f[1]]
		var c: Vector3 = verts[f[2]]
		for v in [a, b, c]:
			# tinta: mais escuro em baixo (falso AO) — dá volume sem textura
			var k := clampf(0.62 + 0.38 * (v.y / maxf(radius, 0.001) + 1.0) * 0.5, 0.55, 1.0)
			st.set_color(Color(tint.r * k, tint.g * k, tint.b * k))
		tri(st, a, b, c, (a + b + c) / 3.0)
	st.generate_normals()
	return st.commit()


static func _icosa(verts: Array[Vector3], faces: Array) -> void:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var raw := [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	for v in raw:
		verts.append(v.normalized())
	var idx := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]
	for f in idx:
		faces.append([f[0], f[1], f[2]])


static func _subdivide(verts: Array[Vector3], faces: Array) -> void:
	var cache := {}
	var out: Array = []
	for f in faces:
		var a: int = f[0]
		var b: int = f[1]
		var c: int = f[2]
		var ab := _mid(a, b, verts, cache)
		var bc := _mid(b, c, verts, cache)
		var ca := _mid(c, a, verts, cache)
		out.append([a, ab, ca])
		out.append([b, bc, ab])
		out.append([c, ca, bc])
		out.append([ab, bc, ca])
	faces.clear()
	for f in out:
		faces.append(f)


static func _mid(a: int, b: int, verts: Array[Vector3], cache: Dictionary) -> int:
	var k := mini(a, b) * 100000 + maxi(a, b)
	if cache.has(k):
		return cache[k]
	verts.append(((verts[a] + verts[b]) * 0.5).normalized())
	cache[k] = verts.size() - 1
	return verts.size() - 1


## Cilindro afunilado e ligeiramente curvo — troncos e ramos.
static func tapered(rng: RandomNumberGenerator, height: float, r_bottom: float,
		r_top: float, segments: int = 7, rings: int = 4, bend: float = 0.12,
		cap: bool = true, tint: Color = Color(1, 1, 1)) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring_v: Array = []
	for r in rings + 1:
		var t := float(r) / float(rings)
		var rad := lerpf(r_bottom, r_top, t)
		var y := height * t
		var off := Vector2(sin(t * 2.1) * bend, cos(t * 1.7) * bend * 0.6) * height * 0.06
		var ring := []
		for i in segments:
			var a := float(i) / float(segments) * TAU + rng.randf() * 0.25
			var rr := rad * (1.0 + rng.randf_range(-0.09, 0.09))
			ring.append(Vector3(cos(a) * rr + off.x, y, sin(a) * rr + off.y))
		ring_v.append(ring)
	for r in rings:
		var a: Array = ring_v[r]
		var b: Array = ring_v[r + 1]
		for i in segments:
			var j := (i + 1) % segments
			var p0: Vector3 = a[i]
			var p1: Vector3 = a[j]
			var p2: Vector3 = b[j]
			var p3: Vector3 = b[i]
			for v in [p0, p1, p2, p3]:
				var k := clampf(0.72 + 0.28 * (v.y / maxf(height, 0.001)), 0.6, 1.0)
				st.set_color(Color(tint.r * k, tint.g * k, tint.b * k))
			tri(st, p0, p1, p2, p0 * Vector3(1, 0, 1))
			tri(st, p0, p2, p3, p0 * Vector3(1, 0, 1))
	if cap:
		var top: Array = ring_v[rings]
		var c := Vector3(0, height, 0)
		st.set_color(Color(tint.r, tint.g, tint.b))
		for i in segments:
			var j := (i + 1) % segments
			tri(st, c, top[i], top[j], UP)
	st.generate_normals()
	return st.commit()


## Rocha: bolha achatada e muito irregular.
static func rock(rng: RandomNumberGenerator, size: float) -> ArrayMesh:
	return blob(rng, size, 1, 0.34, Vector3(1.25, 0.72, 1.05), Color(0.92, 0.92, 0.98))


## Tufo de relva: lâminas em quads, com tinta da base para a ponta.
static func grass_tuft(rng: RandomNumberGenerator, blades: int, h: float,
		w: float, tint: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in blades:
		var a := rng.randf() * TAU
		var lean := rng.randf_range(0.15, 0.5)
		var bh := h * rng.randf_range(0.6, 1.15)
		var bw := w * rng.randf_range(0.7, 1.3)
		var dir := Vector2(cos(a), sin(a))
		var perp := Vector2(-dir.y, dir.x)
		var base := Vector3(dir.x * rng.randf_range(0, 0.06), 0.0, dir.y * rng.randf_range(0, 0.06))
		var tip := base + Vector3(dir.x * lean * bh, bh, dir.y * lean * bh)
		var mid := (base + tip) * 0.5 + Vector3(dir.x * lean * bh * 0.25, 0, dir.y * lean * bh * 0.25)
		var p0 := base + Vector3(perp.x * bw, 0, perp.y * bw)
		var p1 := base - Vector3(perp.x * bw, 0, perp.y * bw)
		var m0 := mid + Vector3(perp.x * bw * 0.5, 0, perp.y * bw * 0.5)
		var m1 := mid - Vector3(perp.x * bw * 0.5, 0, perp.y * bw * 0.5)
		_stripe(st, p0, p1, m0, m1, tint, 0.0)
		_stripe(st, m0, m1, tip, tip, tint, 0.55)
	st.generate_normals()
	return st.commit()


static func _stripe(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		tint: Color, shade: float) -> void:
	var dark := Color(tint.r * (0.55 + shade * 0.2), tint.g * (0.6 + shade * 0.2), tint.b * (0.55 + shade * 0.2))
	var lite := Color(tint.r, tint.g, tint.b).lightened(shade * 0.35)
	st.set_color(dark); st.set_color(dark)
	st.set_color(lite); st.set_color(lite)
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.set_color(dark); st.set_color(lite); st.set_color(lite)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)


## Caixa (paredes, chãos, estacas).
static func box(size: Vector3, tint: Color = Color(1, 1, 1), hollow_bottom: bool = false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := size * 0.5
	var v := [
		Vector3(-s.x, -s.y, -s.z), Vector3(s.x, -s.y, -s.z), Vector3(s.x, s.y, -s.z), Vector3(-s.x, s.y, -s.z),
		Vector3(-s.x, -s.y, s.z), Vector3(s.x, -s.y, s.z), Vector3(s.x, s.y, s.z), Vector3(-s.x, s.y, s.z),
	]
	var faces := [
		[0, 1, 2, 3, Vector3(0, 0, -1)], [5, 4, 7, 6, Vector3(0, 0, 1)],
		[4, 0, 3, 7, Vector3(-1, 0, 0)], [1, 5, 6, 2, Vector3(1, 0, 0)],
		[3, 2, 6, 7, Vector3(0, 1, 0)], [4, 5, 1, 0, Vector3(0, -1, 0)],
	]
	var fi := 0
	for f in faces:
		if hollow_bottom and fi == 5:
			fi += 1
			continue
		fi += 1
		var a: Vector3 = v[f[0]]
		var b: Vector3 = v[f[1]]
		var c: Vector3 = v[f[2]]
		var d: Vector3 = v[f[3]]
		var n: Vector3 = f[4]
		for p in [a, b, c, d]:
			var k := 0.78 + 0.22 * clampf(n.dot(Vector3(0.4, 0.8, 0.3)), 0.0, 1.0)
			st.set_color(Color(tint.r * k, tint.g * k, tint.b * k))
		tri(st, a, b, c, n)
		tri(st, a, c, d, n)
	st.generate_normals()
	return st.commit()


## Cone (pinheiros, telhados).
static func cone(radius: float, height: float, segments: int = 8,
		tint: Color = Color(1, 1, 1)) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0, height, 0)
	for i in segments:
		var a0 := float(i) / float(segments) * TAU
		var a1 := float(i + 1) / float(segments) * TAU
		var p0 := Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		st.set_color(tint.darkened(0.22)); st.set_color(tint.darkened(0.22)); st.set_color(tint)
		tri(st, p0, p1, tip, (p0 + p1) * 0.5)
	st.set_color(tint.darkened(0.35))
	var c := Vector3.ZERO
	for i in segments:
		var a0 := float(i) / float(segments) * TAU
		var a1 := float(i + 1) / float(segments) * TAU
		st.set_color(tint.darkened(0.35))
		tri(st, c, Vector3(cos(a1) * radius, 0, sin(a1) * radius),
			Vector3(cos(a0) * radius, 0, sin(a0) * radius), -UP)
	st.generate_normals()
	return st.commit()
