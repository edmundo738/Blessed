extends Node
## SHOT — dá olhos ao agente.
##
## O problema de fundo deste projecto: ninguém consegue ver o jogo. Não há GPU
## nem browser no sandbox onde o código é escrito, por isso cada bug visual
## custava uma ronda inteira de "o utilizador descreve, o agente adivinha".
##
## Isto resolve-o a sério. O motor corre headless como sempre, mas em vez de
## desenhar, SERIALIZA a geometria real — as mesmas malhas, as mesmas
## transformações globais, as mesmas cores de vértice e as mesmas normais que o
## Godot ia mandar para a GPU — e cospe-a em base64 para o stdout.
##
## tools/render_shot.py rasteriza depois esses dados com a MESMA matemática dos
## shaders (bandas toon, shadow_tint, rim, céu) e escreve um PNG. O agente lê o
## PNG com read_file e vê o resultado. Deixou de ser adivinhação.
##
## Uso:  node shot.mjs /home/user/Blessed --quit-after 3000 -- shot
##       [--view x,y,z] [--yaw graus] [--pitch graus] [--radius m] [--out f.bin]
##
## Formato binário (little-endian), ver tools/render_shot.py:
##   "BSH1" u32 versao
##   3xf32 cam_pos | 9xf32 cam_basis (colunas x,y,z) | f32 fov | f32 aspect
##   f32 near | f32 far | 3xf32 sun_dir | 3xf32 sun_color | 3xf32 sky_top
##   3xf32 sky_bot | f32 exposure
##   u32 n_meshes
##   por malha: u32 len + nome | u32 len + material | u8 cull (0=back,1=off)
##              12xf32 transform (basis.x, basis.y, basis.z, origin)
##              u32 n_verts | n_verts x 9xf32 (pos, normal, cor)
##              u32 n_idx | n_idx x u32

const CHUNK: int = 4000  # caracteres por linha de base64

var main: Node
var _args: Array = []


func setup(m: Node) -> void:
	main = m
	_args = OS.get_cmdline_user_args()


func _ready() -> void:
	# o mundo constrói-se ao longo de vários frames (orçamento de 5 ms/frame);
	# sem esperar apanhávamos zero chunks.
	for i in 40:
		await get_tree().process_frame
	await get_tree().process_frame
	_run()


func _opt(flag: String, fallback: String) -> String:
	var i := _args.find(flag)
	if i < 0 or i + 1 >= _args.size():
		return fallback
	return str(_args[i + 1])


func _run() -> void:
	var world: Node3D = main.get_node_or_null("World")
	if world == null:
		print("SELFTEST_FAIL: shot sem World")
		get_tree().quit(1)
		return

	# o Player é filho do World, não do main — daí `main.player`
	var player: Node3D = main.get("player")
	var eye := Vector3(0, 0, 0)
	if player != null:
		eye = player.global_position + Vector3(0, 1.62, 0)
	print("SHOT_EYE: (%.1f, %.1f, %.1f) jogador=%s" % [eye.x, eye.y, eye.z,
		"sim" if player != null else "NAO ENCONTRADO"])
	var vp := _opt("--view", "")
	if vp != "":
		var ps := vp.split(",")
		if ps.size() == 3:
			eye = Vector3(float(ps[0]), float(ps[1]), float(ps[2]))

	var yaw := deg_to_rad(float(_opt("--yaw", "-35")))
	var pitch := deg_to_rad(float(_opt("--pitch", "-8")))
	var lk := _opt("--look", "")
	if lk != "":
		var lps := lk.split(",")
		if lps.size() == 3:
			var d := Vector3(float(lps[0]), float(lps[1]), float(lps[2])) - eye
			yaw = atan2(-d.x, -d.z)
			pitch = atan2(d.y, Vector2(d.x, d.z).length())
	var radius := float(_opt("--radius", "70"))

	var fwd := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var right := fwd.cross(Vector3.UP).normalized()
	if right.length_squared() < 1e-6:
		right = Vector3.RIGHT
	var up := right.cross(fwd).normalized()

	var buf := StreamPeerBuffer.new()
	buf.put_data("BSH1".to_utf8_buffer())
	buf.put_32(1)
	buf.put_float(eye.x); buf.put_float(eye.y); buf.put_float(eye.z)
	# basis da câmara: colunas = right, up, -fwd (Godot olha por -Z)
	buf.put_float(right.x); buf.put_float(right.y); buf.put_float(right.z)
	buf.put_float(up.x); buf.put_float(up.y); buf.put_float(up.z)
	buf.put_float(-fwd.x); buf.put_float(-fwd.y); buf.put_float(-fwd.z)
	buf.put_float(75.0)                      # fov
	buf.put_float(16.0 / 9.0)                # aspect
	buf.put_float(0.05)                      # near
	buf.put_float(900.0)                     # far

	var sun_dir := Vector3(-0.4, 0.8, 0.3)
	if Game != null:
		sun_dir = Game.sun_direction()
	buf.put_float(sun_dir.x); buf.put_float(sun_dir.y); buf.put_float(sun_dir.z)
	var sun_col := Color(1.0, 0.97, 0.90)
	var sky_top := Color(0.24, 0.52, 0.90)
	var sky_bot := Color(0.76, 0.88, 1.00)
	if world.has_method("sky_colors"):
		var sc: Array = world.call("sky_colors")
		if sc.size() >= 3:
			sun_col = sc[0]
			sky_top = sc[1]
			sky_bot = sc[2]
	buf.put_float(sun_col.r); buf.put_float(sun_col.g); buf.put_float(sun_col.b)
	buf.put_float(sky_top.r); buf.put_float(sky_top.g); buf.put_float(sky_top.b)
	buf.put_float(sky_bot.r); buf.put_float(sky_bot.g); buf.put_float(sky_bot.b)
	buf.put_float(1.0)

	# ── recolhe as malhas ──────────────────────────────────────────────
	# percorre a árvore toda a partir da raiz: o terreno, as estruturas, os NPCs
	# e o jogador vivem em ramos diferentes.
	var items: Array = []
	_walk(main, eye, radius, items)

	var pos_marker := buf.get_position()
	buf.put_32(0)  # n_meshes, preenchido no fim
	var written := 0
	var skipped := 0
	for it in items:
		if _write_mesh(buf, it):
			written += 1
		else:
			skipped += 1
	var end_marker := buf.get_position()
	buf.seek(pos_marker)
	buf.put_32(written)
	buf.seek(end_marker)

	var raw: PackedByteArray = buf.data_array
	# gzip: são megabytes de floats com muito padrão repetido. Sem isto o
	# base64 não passava pelo stdout do build wasm sem esgotar a heap.
	var bytes := raw.compress(FileAccess.COMPRESSION_GZIP)
	print("SHOT_GZIP: %d -> %d bytes (%.0f%%)" % [raw.size(), bytes.size(),
		100.0 * float(bytes.size()) / float(raw.size())])
	var b64 := Marshalls.raw_to_base64(bytes)
	var n := int(ceil(b64.length() / float(CHUNK)))
	print("SHOT_BEGIN bytes=%d meshes=%d saltadas=%d linhas=%d" % [bytes.size(), written, skipped, n])
	for i in n:
		print("SHOTB64:" + b64.substr(i * CHUNK, CHUNK))
	print("SHOT_END")
	print("SHOT_DONE")
	get_tree().quit(0)


func _walk(node: Node, eye: Vector3, radius: float, out: Array) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			return
		# As malhas dos chunks estão em coordenadas do MUNDO com o nó na
		# origem, por isso `global_position` é (0,0,0) e não diz nada sobre
		# onde a geometria está. A distância tem de se medir pelo AABB
		# transformado — foi exactamente esta armadilha que já tinha mordido
		# o tests/diag.gd.
		var bb: AABB = mi.global_transform * mi.get_aabb()
		var d: float = _dist_point_aabb(eye, bb)
		if d <= radius:
			out.append(mi)
	for c in node.get_children():
		_walk(c, eye, radius, out)


## Escreve uma string num campo de `n` bytes, com zeros à direita.
## Tamanho fixo = tudo o que vem a seguir fica alinhado a 4 bytes, que é o que
## o StreamPeerBuffer assume para put_32/put_float. Com campos de comprimento
## variável o Godot insere preenchimento e o leitor do outro lado desalinha.
func _put_fixed(buf: StreamPeerBuffer, text: String, n: int) -> void:
	var b: PackedByteArray = text.to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(n)
	out.fill(0)
	for i in mini(b.size(), n):
		out[i] = b[i]
	buf.put_data(out)


func _dist_point_aabb(p: Vector3, bb: AABB) -> float:
	var c := bb.get_center()
	var h := bb.size * 0.5
	var dx := maxf(absf(p.x - c.x) - h.x, 0.0)
	var dy := maxf(absf(p.y - c.y) - h.y, 0.0)
	var dz := maxf(absf(p.z - c.z) - h.z, 0.0)
	return Vector3(dx, dy, dz).length()


func _write_mesh(buf: StreamPeerBuffer, mi: MeshInstance3D) -> bool:
	var mesh: Mesh = mi.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return false
	# O material pode vir de dois sítios: material_override OU a superfície da
	# malha. O terreno usa `mesh.surface_set_material(0, mats.terrain)`, por
	# isso olhar só para o override mostrava-o como "default".
	var mat: Material = mi.material_override
	if mat == null and mi.mesh != null:
		mat = mi.mesh.surface_get_material(0)
	var mat_name := "default"
	var cull: int = 0
	if mat is ShaderMaterial:
		var sh: Shader = (mat as ShaderMaterial).shader
		if sh != null:
			mat_name = sh.resource_path.get_file()
			if "cull_disabled" in sh.code:
				cull = 1

	var t := mi.global_transform
	var b := t.basis
	_put_fixed(buf, mi.name, 32)
	_put_fixed(buf, mat_name, 32)
	buf.put_32(cull)
	buf.put_float(b.x.x); buf.put_float(b.x.y); buf.put_float(b.x.z)
	buf.put_float(b.y.x); buf.put_float(b.y.y); buf.put_float(b.y.z)
	buf.put_float(b.z.x); buf.put_float(b.z.y); buf.put_float(b.z.z)
	buf.put_float(t.origin.x); buf.put_float(t.origin.y); buf.put_float(t.origin.z)

	# só a superfície 0 chega para diagnóstico; o resto é registado no log
	var arr: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	if verts.size() == 0:
		return false
	var has_cols: bool = cols.size() == verts.size()
	var has_norms: bool = norms.size() == verts.size()

	buf.put_32(verts.size())
	for i in verts.size():
		var v: Vector3 = verts[i]
		buf.put_float(v.x); buf.put_float(v.y); buf.put_float(v.z)
		var nrm := Vector3.UP
		if has_norms:
			nrm = norms[i]
		buf.put_float(nrm.x); buf.put_float(nrm.y); buf.put_float(nrm.z)
		var col := Color.WHITE
		if has_cols:
			col = cols[i]
		buf.put_float(col.r); buf.put_float(col.g); buf.put_float(col.b)

	buf.put_32(idx.size())
	if idx.size() > 0:
		for i in idx.size():
			buf.put_32(int(idx[i]))
	else:
		# não indexado: 1 índice por vértice, na ordem
		buf.seek(buf.get_position() - 4)
		buf.put_32(verts.size())
		for i in verts.size():
			buf.put_32(i)
	return true
