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
##   "BSH1" u32 versao (2)
##   3xf32 cam_pos | 9xf32 cam_basis (colunas x,y,z) | f32 fov | f32 aspect
##   f32 near | f32 far | 3xf32 sun_dir | 3xf32 sun_color | 3xf32 sky_top
##   3xf32 sky_bot | f32 exposure
##   u32 n_meshes
##   por malha: nome 32B | material 32B | u32 cull (0=back,1=off)
##              u32 n_params
##                por parâmetro: nome 32B | u8 tipo (0=f,1=v2,2=v3,3=v4,4=bool,5=textura)
##                               4xf32 valor | texto do caminho (64B, só tipo 5)
##              12xf32 transform (basis.x, basis.y, basis.z, origin)
##              u32 n_verts | n_verts x 13xf32 (pos, normal, cor, uv, uv2)
##              u32 n_idx | n_idx x u32
##
## A versão 2 existe por causa da relva: sem o NÍVEL de cada vértice (UV2.x) e
## sem os parâmetros reais do material, o rasterizador só podia adivinhar. Agora
## ele lê os valores que o jogo usa — deixou de haver tabela copiada à mão em
## tools/render_shot.py a divergir do GDScript.

const CHUNK: int = 4000  # caracteres por linha de base64

var main: Node
var _args: Array = []
var _eye := Vector3()
var _radius: float = 70.0


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
	Game.started = true
	var player: Node3D = main.get("player")
	var eye := Vector3(0, 0, 0)
	if player != null:
		eye = player.global_position + Vector3(0, 1.62, 0)
	print("SHOT_EYE: (%.1f, %.1f, %.1f) jogador=%s" % [eye.x, eye.y, eye.z,
		"sim" if player != null else "NAO ENCONTRADO"])
	# --tp x,z: leva o JOGADOR (não só a câmara) para um sítio. O mundo só
	# constrói chunks à volta do jogador; sem isto uma vista para longe
	# fotografava o vazio.
	var tp := _opt("--tp", "")
	if tp != "" and player != null:
		var tps := tp.split(",")
		if tps.size() == 2:
			var tx := float(tps[0])
			var tz := float(tps[1])
			var ty: float = main.world.ground_height(tx, tz) + 1.0
			player.teleport(Vector3(tx, ty, tz))
			main.world.set_target(Vector3(tx, ty, tz))
			for _i in 90:
				await get_tree().process_frame
			eye = Vector3(tx, ty + 0.62, tz)
			print("SHOT_TP: (%.1f, %.1f, %.1f)" % [tx, ty, tz])
	var vp := _opt("--view", "")
	if vp != "":
		var ps := vp.split(",")
		if ps.size() == 3:
			eye = Vector3(float(ps[0]), float(ps[1]), float(ps[2]))

	var yaw := deg_to_rad(float(_opt("--yaw", "-35")))
	var pitch := deg_to_rad(float(_opt("--pitch", "-8")))
	# --third: mostra o corpo 3D do jogador. A vista é sintética (a câmara do
	# jogador é a primeira pessoa), por isso o enquadramento tem de vir de fora:
	# atrás e acima dos ombros, a olhar para a bacia.
	if _args.has("--third") and player != null:
		player.call("_set_view_mode", true)
		for _i in 3:
			await get_tree().process_frame
		if not _args.has("--view"):
			var base := player.global_position
			var target := base + Vector3(0, 1.05, 0)
			eye = base + Vector3(0.8, 2.15, 3.6)
			var d := target - eye
			yaw = atan2(-d.x, -d.z)
			pitch = atan2(d.y, Vector2(d.x, d.z).length())
			print("SHOT_THIRD: body=%s eye=(%.2f, %.2f, %.2f)" % [
				"sim" if player.get("body") != null else "nao",
				eye.x, eye.y, eye.z])
	var lk := _opt("--look", "")
	if lk != "":
		var lps := lk.split(",")
		if lps.size() == 3:
			var d := Vector3(float(lps[0]), float(lps[1]), float(lps[2])) - eye
			yaw = atan2(-d.x, -d.z)
			pitch = atan2(d.y, Vector2(d.x, d.z).length())
	var radius := float(_opt("--radius", "70"))

	# --fell: abate a árvore mais próxima e deixa-a cair antes de fotografar.
	# Sem isto o agente nunca via o estado "árvore caída" — que é justamente o
	# que o jogador descrevia como "cor esquisita, plana, como se a luz já não
	# a afetasse": o tronco estava a levar o material das FOLHAS.
	if _args.has("--fell") and player != null:
		var world_node: Node = main.get("world")
		var best: Dictionary = {}
		var best_d := 1e9
		for c in (world_node.get("chunks") as Dictionary).values():
			for n in (c as Chunk).harvest_nodes:
				if not str(n.get("kind", "")).begins_with("tree"):
					continue
				var d: float = (n["pos"] as Vector3).distance_to(player.global_position)
				if d < best_d and bool(n.get("alive", true)):
					best_d = d
					best = n
		if best.is_empty():
			print("SHOT_FELL: nenhuma árvore perto")
		else:
			var it: Node = main.get("interaction")
			it.focus = {"kind": "harvest", "ref": best, "pos": best["pos"]}
			print("SHOT_FELL: %s a %.1f m" % [str(best.get("species", "?")), best_d])
			for i in 40:
				it.call("_hold_work", 0.6, 1.0)
				if not bool(best.get("alive", true)):
					break
			# a queda é conduzida por tempo explícito (1,05 s). Em headless os
			# frames são curtos, por isso espera-se pelo ESTADO, não por N frames.
			for i in 400:
				await get_tree().process_frame
				var prontos := get_tree().get_nodes_in_group("fellable_logs")
				if not prontos.is_empty() and bool(prontos[0].get("settled")):
					break
			var ft_nos := get_tree().get_nodes_in_group("fellable_logs")
			if not ft_nos.is_empty():
				print("SHOT_FELL_STATE: settled=%s rot_z=%.2f y=%.2f" % [
					str(ft_nos[0].get("settled")), (ft_nos[0] as Node3D).rotation.z,
					(ft_nos[0] as Node3D).global_position.y])
			# a árvore caída é o alvo desta imagem: olhar para ela
			var logs := get_tree().get_nodes_in_group("fellable_logs")
			if not logs.is_empty():
				var ft := logs[0] as Node3D
				var alvo := ft.global_position + Vector3(0, 0.6, 0)
				eye = alvo + Vector3(0, 4.0, 6.0)
				var d2 := alvo - eye
				yaw = atan2(-d2.x, -d2.z)
				pitch = atan2(d2.y, Vector2(d2.x, d2.z).length())
				print("SHOT_FELL_POS: %.1f, %.1f, %.1f" % [ft.global_position.x,
					ft.global_position.y, ft.global_position.z])

	# --fire: olhar para a fogueira ACESA mais próxima (a da aldeia serve). É o
	# objeto central do primeiro dia, por isso tem de haver uma forma barata de
	# olhar para ele sem andar pelo mundo à mão.
	if _args.has("--fire"):
		var st: Node = main.get("structures")
		var alvo_fogo := Vector3.ZERO
		var d_fogo := 1e9
		if st != null:
			for e in (st.get("list") as Array):
				if not bool((e as Dictionary).get("lit", false)):
					continue
				var p3: Vector3 = (e as Dictionary)["pos"]
				var eu: Vector3 = (player as Node3D).global_position if player != null else Vector3.ZERO
				var d3: float = p3.distance_to(eu)
				if d3 < d_fogo:
					d_fogo = d3
					alvo_fogo = p3
		if d_fogo > 1e8:
			print("SHOT_FIRE: nenhuma fogueira acesa")
		else:
			var alvo := alvo_fogo + Vector3(0, 0.45, 0)
			if _args.has("--player") and player != null:
				# Põe o jogador em frente da fogueira e deixa a câmara DELE
				# enquadrar: é assim que o jogador a vê, com as mãos à frente.
				var wn: Node = main.get("world")
				var pp := alvo_fogo + Vector3(1.7, 0.0, 1.9)
				pp.y = float(wn.ground_height(pp.x, pp.z)) + 0.1
				# Usar o teleporte do PRÓPRIO jogador: escrever-lhe o
				# global_position à mão não pegava (ele guarda yaw/pitch em
				# `target_yaw`/`target_pitch` e o controlador reescreve a
				# rotação no frame seguinte).
				player.call("teleport", pp)
				player.call("look_at_point", alvo_fogo + Vector3(0, 0.45, 0))
				player.set("pitch", -0.20)
				player.set("target_pitch", -0.20)
				player.set("yaw", player.get("target_yaw"))
				# a câmara do jogador é actualizada no _process dele: dar-lhe um
				# par de frames para chegar à posição nova antes de fotografar
				await get_tree().process_frame
				await get_tree().process_frame
			eye = alvo + Vector3(1.7, 1.15, 1.9)
			var d4 := alvo - eye
			yaw = atan2(-d4.x, -d4.z)
			pitch = atan2(d4.y, Vector2(d4.x, d4.z).length())
			print("SHOT_FIRE: %.1f, %.1f, %.1f" % [alvo_fogo.x, alvo_fogo.y, alvo_fogo.z])

	var fwd := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var right := fwd.cross(Vector3.UP).normalized()
	if right.length_squared() < 1e-6:
		right = Vector3.RIGHT
	var up := right.cross(fwd).normalized()
	var fov := 75.0
	# --player: a vista EXATA da 1.ª pessoa — a câmara do jogador, com a direção
	# e o balanço reais. Era o que faltava para julgar as mãos: elas estão
	# penduradas nessa câmara, não na câmara sintética do shot, e com o yaw
	# sintético (-35°) apareciam rodadas para o lado errado do ecrã.
	if _args.has("--player") and player != null:
		var cam := player.get("camera") as Camera3D
		if cam != null:
			var cb := cam.global_transform.basis
			right = cb.x.normalized()
			up = cb.y.normalized()
			fwd = -cb.z.normalized()
			eye = cam.global_position
			fov = cam.fov
			print("SHOT_PLAYER: eye=(%.2f, %.2f, %.2f) fov=%.1f" % [eye.x, eye.y, eye.z, fov])

	var buf := StreamPeerBuffer.new()
	buf.put_data("BSH1".to_utf8_buffer())
	buf.put_32(2)
	buf.put_float(eye.x); buf.put_float(eye.y); buf.put_float(eye.z)
	# basis da câmara: colunas = right, up, -fwd (Godot olha por -Z)
	buf.put_float(right.x); buf.put_float(right.y); buf.put_float(right.z)
	buf.put_float(up.x); buf.put_float(up.y); buf.put_float(up.z)
	buf.put_float(-fwd.x); buf.put_float(-fwd.y); buf.put_float(-fwd.z)
	buf.put_float(fov)                       # fov
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
	_eye = eye
	_radius = radius
	var items: Array = []
	_walk(main, eye, radius, items)

	var pos_marker := buf.get_position()
	buf.put_32(0)  # n_meshes, preenchido no fim
	var written := 0
	var skipped := 0
	for it in items:
		var ok := false
		if it is MultiMeshInstance3D:
			ok = _write_multimesh(buf, it as MultiMeshInstance3D)
		else:
			ok = _write_mesh(buf, it as MeshInstance3D)
		if ok:
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
	if node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		# MultiMesh nao tem AABB fiavel: inclui o no e filtra por instancia
		# la no dump, pela distancia ao olho.
		if mmi.multimesh != null and mmi.visible:
			out.append(mmi)
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			return
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


## Escreve os parâmetros do material que o rasterizador precisa de conhecer.
## São lidos do próprio ShaderMaterial (a lista de uniforms vem do shader), por
## isso não há uma segunda tabela de valores a manter em dois sítios.
func _write_material_params(buf: StreamPeerBuffer, mat: Material) -> void:
	var entries: Array = []
	# StandardMaterial3D: sem isto o rasterizador só sabia a cor de vértice, e as
	# mãos (esfera/cápsula com material_override de cor lisa) saíam BRANCAS no
	# render — foi assim que uma mão castanha pareceu um cilindro branco partido.
	var std := mat as StandardMaterial3D
	if std != null:
		var ac := std.albedo_color
		entries.append({"name": "__std_albedo", "kind": 3,
			"v": [ac.r, ac.g, ac.b, ac.a], "path": ""})
		entries.append({"name": "__std_vcol", "kind": 4,
			"v": [1.0 if std.vertex_color_use_as_albedo else 0.0, 0.0, 0.0, 0.0], "path": ""})
		entries.append({"name": "__std_rough", "kind": 0,
			"v": [std.roughness, 0.0, 0.0, 0.0], "path": ""})
		entries.append({"name": "__std_cull", "kind": 0,
			"v": [float(std.cull_mode), 0.0, 0.0, 0.0], "path": ""})
		if std.emission_enabled:
			var ec := std.emission
			var en: float = std.emission_energy
			entries.append({"name": "__std_emit", "kind": 3,
				"v": [ec.r * en, ec.g * en, ec.b * en, 1.0], "path": ""})
	var shader_material := mat as ShaderMaterial
	if shader_material != null and shader_material.shader != null:
		for uniform in shader_material.shader.get_shader_uniform_list(true):
			var name := str(uniform["name"])
			var value: Variant = shader_material.get_shader_parameter(name)
			if value == null:
				continue
			var type := int(uniform["type"])
			var kind := -1
			var packed := [0.0, 0.0, 0.0, 0.0]
			var text := ""
			match type:
				TYPE_FLOAT, TYPE_INT:
					kind = 0
					packed[0] = float(value)
				TYPE_BOOL:
					kind = 4
					packed[0] = 1.0 if bool(value) else 0.0
				TYPE_VECTOR2:
					kind = 1
					var v2: Vector2 = value
					packed[0] = v2.x; packed[1] = v2.y
				TYPE_VECTOR3:
					kind = 2
					var v3: Vector3 = value
					packed[0] = v3.x; packed[1] = v3.y; packed[2] = v3.z
				TYPE_COLOR:
					kind = 3
					var col: Color = value
					packed[0] = col.r; packed[1] = col.g; packed[2] = col.b; packed[3] = col.a
				TYPE_OBJECT:
					if value is Texture2D:
						kind = 5
						text = Materials.texture_paths.get(
							(value as Texture2D).get_instance_id(), "")
			if kind < 0:
				continue
			entries.append({"name": name, "kind": kind, "v": packed, "path": text})
	buf.put_32(entries.size())
	for entry in entries:
		_put_fixed(buf, str(entry["name"]), 32)
		buf.put_u8(int(entry["kind"]))
		var packed: Array = entry["v"]
		for i in 4:
			buf.put_float(float(packed[i]))
		if int(entry["kind"]) == 5:
			_put_fixed(buf, str(entry["path"]), 64)


## Expande um MultiMesh (relva/arvores) e junta as instancias proximas numa
## unica malha, com a tinta da instancia como cor de vertice. Limitado para o
## dump nao crescer sem limite.
func _write_multimesh(buf: StreamPeerBuffer, mi: MultiMeshInstance3D) -> bool:
	var mm: MultiMesh = mi.multimesh
	if mm == null or mm.mesh == null or mm.instance_count == 0:
		return false
	# O servidor "dummy" do headless não guarda os buffers do MultiMesh: as
	# transmissões lêem-se da cópia que os construtores deixam nos metadados
	# (scripts/core/shot_meta.gd). Sem isto não havia cartas de relva no dump.
	var espelho := ShotMeta.has(mi)
	var inst_count := ShotMeta.count(mi) if espelho else mm.instance_count
	var arr: Array = mm.mesh.surface_get_arrays(0)
	var lv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ln := PackedVector3Array()
	if arr[Mesh.ARRAY_NORMAL] is PackedVector3Array:
		ln = arr[Mesh.ARRAY_NORMAL]
	var uvs := PackedVector2Array()
	if arr[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
		uvs = arr[Mesh.ARRAY_TEX_UV]
	var uv2s := PackedVector2Array()
	if arr[Mesh.ARRAY_TEX_UV2] is PackedVector2Array:
		uv2s = arr[Mesh.ARRAY_TEX_UV2]
	var vcols := PackedColorArray()
	if arr[Mesh.ARRAY_COLOR] is PackedColorArray:
		vcols = arr[Mesh.ARRAY_COLOR]
	var lidx := PackedInt32Array()
	if arr[Mesh.ARRAY_INDEX] is PackedInt32Array:
		lidx = arr[Mesh.ARRAY_INDEX]
	if lv.size() == 0:
		return false
	var gt := mi.global_transform
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var _inst_uv2 := PackedVector2Array()
	# Orçamento de vértices por MultiMesh. As instâncias são ordenadas pela
	# distância ao olho e corta-se pelo MAIS LONGE: numa malha de relva com 2500
	# tufos, ficar com os primeiros por ordem de grelha dava uma cunha de cartas
	# (metade da imagem vazia) — que foi exactamente o que se viu no dump v2.
	var maxv := 24000
	var used := 0
	var near: Array = []
	for i in inst_count:
		var it := gt * (ShotMeta.transform_at(mi, i) if espelho else mm.get_instance_transform(i))
		var d := it.origin.distance_to(_eye)
		if d <= _radius + 8.0:
			near.append({"i": i, "d": d})
	near.sort_custom(func(x, y): return float(x["d"]) < float(y["d"]))
	var keep: Array = []
	var budget := 0
	for entry in near:
		if budget + lv.size() > maxv:
			break
		budget += lv.size()
		keep.append(int(entry["i"]))
	if keep.is_empty():
		return false
	for i in keep:
		var it := gt * (ShotMeta.transform_at(mi, i) if espelho else mm.get_instance_transform(i))
		var tint := ShotMeta.custom_at(mi, i) if espelho else mm.get_instance_custom_data(i)
		var inst_col := ShotMeta.color_at(mi, i) if espelho \
			else (mm.get_instance_color(i) if mm.use_colors else Color.WHITE)
		var base := used
		for v in lv.size():
			var vc := (vcols[v] if vcols.size() == lv.size() else Color.WHITE) * inst_col
			verts.append(it * lv[v])
			norms.append((it.basis * (ln[v] if ln.size() == lv.size() else Vector3.UP)).normalized())
			# COLOR é a cor de vértice (como no motor); o custom por instância
			# (seca/variação) vai no UV2, que estes cartões não usam — o
			# rasterizador precisa dos dois para avaliar o mesmo que o shader.
			cols.append(Color(vc.r, vc.g, vc.b, 1.0))
			_inst_uv2.append(Vector2(tint.g, tint.r))
		if lidx.size() > 0:
			for q in lidx.size():
				idx.append(base + int(lidx[q]))
		else:
			for q in lv.size():
				idx.append(base + q)
		used += lv.size()

	var mat_name := "toon_foliage.gdshader"
	if mi.material_override is ShaderMaterial:
		var override_shader: Shader = (mi.material_override as ShaderMaterial).shader
		if override_shader != null:
			mat_name = override_shader.resource_path.get_file()
	_put_fixed(buf, mi.name, 32)
	_put_fixed(buf, mat_name, 32)
	buf.put_32(0)
	_write_material_params(buf, mi.material_override)
	var b := gt.basis
	buf.put_float(b.x.x); buf.put_float(b.x.y); buf.put_float(b.x.z)
	buf.put_float(b.y.x); buf.put_float(b.y.y); buf.put_float(b.y.z)
	buf.put_float(b.z.x); buf.put_float(b.z.y); buf.put_float(b.z.z)
	buf.put_float(0.0); buf.put_float(0.0); buf.put_float(0.0)
	buf.put_32(verts.size())
	for v in verts.size():
		buf.put_float(verts[v].x); buf.put_float(verts[v].y); buf.put_float(verts[v].z)
		buf.put_float(norms[v].x); buf.put_float(norms[v].y); buf.put_float(norms[v].z)
		buf.put_float(cols[v].r); buf.put_float(cols[v].g); buf.put_float(cols[v].b)
		buf.put_float(uvs[v].x if uvs.size() == verts.size() else 0.0)
		buf.put_float(uvs[v].y if uvs.size() == verts.size() else 0.0)
		buf.put_float(_inst_uv2[v].x if _inst_uv2.size() == verts.size() else 0.0)
		buf.put_float(_inst_uv2[v].y if _inst_uv2.size() == verts.size() else 0.0)
	buf.put_32(idx.size())
	for q in idx.size():
		buf.put_32(int(idx[q]))
	return true


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
	elif mat is StandardMaterial3D and (mat as StandardMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED:
		cull = 1

	var t := mi.global_transform
	var b := t.basis
	_put_fixed(buf, mi.name, 32)
	_put_fixed(buf, mat_name, 32)
	buf.put_32(cull)
	_write_material_params(buf, mat)
	buf.put_float(b.x.x); buf.put_float(b.x.y); buf.put_float(b.x.z)
	buf.put_float(b.y.x); buf.put_float(b.y.y); buf.put_float(b.y.z)
	buf.put_float(b.z.x); buf.put_float(b.z.y); buf.put_float(b.z.z)
	buf.put_float(t.origin.x); buf.put_float(t.origin.y); buf.put_float(t.origin.z)

	# só a superfície 0 chega para diagnóstico; o resto é registado no log
	var arr: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms := PackedVector3Array()
	if arr[Mesh.ARRAY_NORMAL] is PackedVector3Array:
		norms = arr[Mesh.ARRAY_NORMAL]
	var cols := PackedColorArray()
	if arr[Mesh.ARRAY_COLOR] is PackedColorArray:
		cols = arr[Mesh.ARRAY_COLOR]
	var idx := PackedInt32Array()
	if arr[Mesh.ARRAY_INDEX] is PackedInt32Array:
		idx = arr[Mesh.ARRAY_INDEX]
	var uvs := PackedVector2Array()
	if arr[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
		uvs = arr[Mesh.ARRAY_TEX_UV]
	var uv2s := PackedVector2Array()
	if arr[Mesh.ARRAY_TEX_UV2] is PackedVector2Array:
		uv2s = arr[Mesh.ARRAY_TEX_UV2]
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
		buf.put_float(uvs[i].x if uvs.size() == verts.size() else 0.0)
		buf.put_float(uvs[i].y if uvs.size() == verts.size() else 0.0)
		buf.put_float(uv2s[i].x if uv2s.size() == verts.size() else 0.0)
		buf.put_float(uv2s[i].y if uv2s.size() == verts.size() else 0.0)

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
