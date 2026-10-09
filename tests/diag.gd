extends Node
## Sonda de diagnóstico — mede o que o ecrã mostra, sem olhar para o ecrã.
##
## Corre o jogo a sério e imprime NÚMEROS sobre:
##   A. controlos  → direção pedida por cada tecla vs. direção esperada
##   B. geometria  → winding, normais, cores de vértice, AABB
##   C. materiais  → shader, cull, transparência, prioridade
##   D. luz/câmara → o que ilumina a cena
##
## Uso:  godot --headless --path . --quit-after 3000 -- diag

var main: Node
var out: Array = []


func say(fmt: String, args: Array = []) -> void:
	var line := fmt % args if not args.is_empty() else fmt
	out.append(line)
	print(line)


func setup(p_main: Node) -> void:
	main = p_main


func _ready() -> void:
	Game.started = true
	Game.profile = {"name": "Diag", "body": "f", "soul": "hands"}
	await get_tree().process_frame
	await get_tree().process_frame
	say("══ DIAGNÓSTICO BLESSED ══")
	say("Godot %s · renderer=%s · semente=%d",
		[str(Engine.get_version_info()["string"]),
		RenderingServer.get_current_rendering_method(), Game.world_seed])
	say("relógio: hora=%.2f fase=%s daylight=%.3f  ← se daylight for baixo o mundo é escuro",
		[Game.hour, Game.current_phase(), Game.daylight()])
	_controls()
	_geometry()
	_materials()
	_scene_light()
	say("══ FIM ══")
	print("DIAG_DONE")
	var f := FileAccess.open("user://diag.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out) + "\n")
		f.close()
	get_tree().quit(0)


# ══════════════════════════════════════════════════════════════════════════
#  A. CONTROLOS
# ══════════════════════════════════════════════════════════════════════════
func _controls() -> void:
	say("")
	say("── A. CONTROLOS ──")
	var player: Node = main.player
	player.yaw = 0.0
	player.target_yaw = 0.0
	player.rotation.y = 0.0
	var cam_fwd: Vector3 = -player.camera.global_transform.basis.z
	var cam_right: Vector3 = player.camera.global_transform.basis.x
	say("câmara: forward=%s  right=%s  (Godot: -Z é a frente)",
		[_v(cam_fwd), _v(cam_right)])

	var cases := [
		["move_forward", "W", cam_fwd],
		["move_back", "S", -cam_fwd],
		["move_left", "A", -cam_right],
		["move_right", "D", cam_right],
	]
	say("")
	say("%-14s %-4s %-22s %-22s %s", ["acção", "tecla", "esperado (mundo)", "calculado (mundo)", "veredicto"])
	for c in cases:
		for x in cases:
			Input.action_release(str(x[0]))
		Input.action_press(str(c[0]))
		var wish: Vector3 = player.call("_wish_direction")
		# a mesma conversão que _move_land faz
		var world_dir: Vector3 = (player.transform.basis * wish).normalized() if wish.length_squared() > 0.0001 else Vector3.ZERO
		var want: Vector3 = (c[2] as Vector3)
		var agree := world_dir.dot(want) > 0.7
		say("%-14s %-4s %-22s %-22s %s",
			[str(c[0]), str(c[1]), _v(want), _v(world_dir),
			"OK" if agree else "INVERTIDO/ERRADO (dot=%.2f)" % world_dir.dot(want)])
		Input.action_release(str(c[0]))

	# diagonais
	for x in cases:
		Input.action_release(str(x[0]))
	Input.action_press("move_forward")
	Input.action_press("move_right")
	var wd: Vector3 = player.call("_wish_direction")
	var wdir: Vector3 = (player.transform.basis * wd).normalized()
	say("%-14s %-4s %-22s %-22s %s", ["W+D", "WD", _v((cam_fwd + cam_right).normalized()), _v(wdir),
		"OK" if wdir.dot((cam_fwd + cam_right).normalized()) > 0.7 else "ERRADO"])
	for x in cases:
		Input.action_release(str(x[0]))

	# inclinação da câmara não deve inclinar o movimento
	player.camera.rotation.x = -0.6
	var cam_fwd_tilted: Vector3 = -player.camera.global_transform.basis.z
	Input.action_press("move_forward")
	var wt: Vector3 = player.call("_wish_direction")
	var wt_dir: Vector3 = (player.transform.basis * wt).normalized()
	say("câmara inclinada 34°: desejado horizontal=%s  real=%s  (y=%.3f) %s",
		[_v(Vector3(cam_fwd_tilted.x, 0, cam_fwd_tilted.z).normalized()), _v(wt_dir), wt_dir.y,
		"OK" if absf(wt_dir.y) < 0.01 else "O MOVIMENTO INCLINA"])
	Input.action_release("move_forward")
	player.camera.rotation.x = 0.0


# ══════════════════════════════════════════════════════════════════════════
#  B. GEOMETRIA
# ══════════════════════════════════════════════════════════════════════════
func _geometry() -> void:
	say("")
	say("── B. GEOMETRIA ──")

	# terreno: primeiro chunk com geometria
	var terrain_mesh: Mesh = null
	var chunk_node: Node3D = null
	for c in main.world.get_children():
		if not (c is Node3D):
			continue
		for mi in c.get_children():
			if mi is MeshInstance3D and (mi as MeshInstance3D).mesh != null \
					and (mi as MeshInstance3D).mesh.get_surface_count() > 0:
				terrain_mesh = (mi as MeshInstance3D).mesh
				chunk_node = c
				break
		if terrain_mesh:
			break
	if terrain_mesh:
		var lod_i: int = clampi(int(chunk_node.get("lod")), 0, Chunk.RES.size() - 1)
		var gres: int = Chunk.RES[lod_i]
		var gtris: int = gres * gres * 2
		# a geometria do chunk está em coordenadas do MUNDO (o nó fica na origem),
		# por isso o centro sai do AABB da malha, não da posição do nó.
		var ab: AABB = terrain_mesh.get_aabb()
		var centre := Vector3(ab.position.x + ab.size.x * 0.5, 0.0, ab.position.z + ab.size.z * 0.5)
		say("[terreno] chunk=%s lod=%d grelha=%dx%d  triângulos de chão=%d  o resto é saia  centro=%s",
			[chunk_node.name, lod_i, gres + 1, gres + 1, gtris, _v(centre)])
		_report_mesh("terreno", terrain_mesh, Vector3.UP, true, gtris, centre)
		_probe_skirt(terrain_mesh, gtris, centre)
	else:
		say("[terreno] NENHUMA MESH ENCONTRADA — o chão não existe!")

	# estruturas (casas)
	say("")
	var shown := 0
	for s in main.structures.get_children():
		if not (s is Node3D) or shown >= 3:
			continue
		for mi in s.get_children():
			if mi is MeshInstance3D and (mi as MeshInstance3D).mesh != null:
				_report_mesh("estrutura:" + str(mi.name), (mi as MeshInstance3D).mesh, Vector3.ZERO, false)
				shown += 1
				break
		if shown >= 3:
			break
	if shown == 0:
		say("[estruturas] NENHUMA MESH — as casas não existem!")

	# aldeia: o largo e as cabanas
	say("")
	var vstat := 0
	for c in main.village.get_children():
		if not (c is Node3D):
			continue
		for mi in c.get_children():
			if mi is MeshInstance3D and (mi as MeshInstance3D).mesh != null:
				var m2: Mesh = (mi as MeshInstance3D).mesh
				var sc: Vector3 = (mi as MeshInstance3D).global_transform.basis.get_scale()
				say("[aldeia] %-28s tamanho real = %s  escala=%s  cor média=%s",
					[c.name, _v(m2.get_aabb().size * sc.x), _v(sc), _avg_color(m2)])
				vstat += 1
	if vstat == 0:
		say("[aldeia] SEM GEOMETRIA — não há casas nenhumas!")

	# estruturas colocadas (fogueiras, etc.)
	say("")
	for e in main.structures.list:
		var ent: Dictionary = e
		var node: Node3D = ent.get("node")
		if node == null or not is_instance_valid(node):
			continue
		for mi in node.get_children():
			if mi is MeshInstance3D and (mi as MeshInstance3D).mesh != null:
				say("[estrutura] %-12s pos=%s  tamanho=%s",
					[str(ent["id"]), _v(ent["pos"]), _v((mi as MeshInstance3D).mesh.get_aabb().size)])
				break

	# vegetação (MultiMesh)
	say("")
	var mm_count := 0
	var mm_sample: MultiMesh = null
	for c in main.world.get_children():
		for mi in c.get_children():
			if mi is MultiMeshInstance3D:
				mm_count += 1
				if mm_sample == null and (mi as MultiMeshInstance3D).multimesh != null:
					mm_sample = (mi as MultiMeshInstance3D).multimesh
	say("[vegetação] MultiMeshInstance3D no mundo: %d", [mm_count])
	var seen := {}
	for c in main.world.get_children():
		for mi in c.get_children():
			if mi is MultiMeshInstance3D and (mi as MultiMeshInstance3D).multimesh != null:
				var mm: MultiMesh = (mi as MultiMeshInstance3D).multimesh
				if mm.mesh == null or seen.has(mm.mesh.get_instance_id()):
					continue
				seen[mm.mesh.get_instance_id()] = true
				var inst := 0
				if mm.instance_count > 0:
					inst = 1
					var first: Transform3D = mm.get_instance_transform(0)
					say("[vegetação]   escala da 1ª instância = %s  custom=%s",
						[_v(first.basis.get_scale()), str(mm.use_custom_data)])
				say("[vegetação] %-22s inst=%3d tris=%5d  cor=%s",
					[str(mi.name), mm.instance_count,
					mm.mesh.get_faces().size() / 9 if mm.mesh.get_faces() != null else 0,
					_avg_color(mm.mesh)])
	if mm_sample:
		say("[vegetação] instâncias=%d  mesh base: %s", [mm_sample.instance_count,
			str(mm_sample.mesh.resource_path if mm_sample.mesh else "-")])
		if mm_sample.mesh:
			_report_mesh("vegetação(base)", mm_sample.mesh, Vector3.ZERO, false)


func _report_mesh(tag: String, mesh: Mesh, expect_normal: Vector3, is_terrain: bool, ground_tris: int = -1, chunk_centre: Vector3 = Vector3.ZERO) -> void:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: Array = arrays[Mesh.ARRAY_COLOR]
	var idx: Array = arrays[Mesh.ARRAY_INDEX]
	var tris := idx.size() / 3 if not idx.is_empty() else verts.size() / 3

	say("[%s] vértices=%d  triângulos=%d  indexado=%s  AABB=%s",
		[tag, verts.size(), tris, str(not idx.is_empty()), str(mesh.get_aabb())])
	say("[%s]   NORMAL array: %s   COLOR array: %s",
		[tag, "sim" if not norms.is_empty() else "NÃO — o shader vai ler lixo",
		"sim" if not colors.is_empty() else "NÃO — ALBEDO=COLOR fica preto!"])
	if not colors.is_empty():
		var sum := Color(0, 0, 0)
		for c in colors:
			sum += c as Color
		sum /= float(colors.size())
		say("[%s]   cor de vértice média = (%.2f, %.2f, %.2f)  ← se ~0 o objeto é preto",
			[tag, sum.r, sum.g, sum.b])

	# winding: normal geométrica vs. direção esperada
	var up_ok := 0
	var up_bad := 0
	var skirt_ok := 0
	var skirt_bad := 0
	var outward_ok := 0
	var outward_bad := 0
	var center := mesh.get_aabb().get_center()
	var step: int = maxi(1, tris / 400)
	var checked := 0
	for t in range(0, tris, step):
		var i0: int
		var i1: int
		var i2: int
		if idx.is_empty():
			i0 = t * 3; i1 = t * 3 + 1; i2 = t * 3 + 2
		else:
			i0 = idx[t * 3]; i1 = idx[t * 3 + 1]; i2 = idx[t * 3 + 2]
		if i2 >= verts.size():
			continue
		var a: Vector3 = verts[i0]
		var b: Vector3 = verts[i1]
		var c2: Vector3 = verts[i2]
		var gn := (b - a).cross(c2 - a)
		if gn.length_squared() < 1e-12:
			continue
		gn = gn.normalized()
		checked += 1
		if is_terrain:
			if ground_tris >= 0 and t >= ground_tris:
				# saia: parede vertical, tem de apontar para FORA do chunk
				var mid := (a + b + c2) / 3.0
				var away := Vector3(mid.x - chunk_centre.x, 0.0, mid.z - chunk_centre.z)
				if away.length_squared() > 1e-8:
					if gn.dot(away.normalized()) > 0.0:
						skirt_ok += 1
					else:
						skirt_bad += 1
				continue
			if gn.y > 0.0:
				up_ok += 1
			else:
				up_bad += 1
		else:
			var mid := (a + b + c2) / 3.0
			var away := mid - center
			if away.length_squared() < 1e-8:
				continue
			if gn.dot(away.normalized()) > 0.0:
				outward_ok += 1
			else:
				outward_bad += 1

	if is_terrain:
		say("[%s]   winding do CHÃO (normal para CIMA): %d ok / %d ao contrário  %s",
			[tag, up_ok, up_bad, "OK" if up_bad == 0 else "FACES INVERTIDAS"])
		say("[%s]   winding da SAIA (normal para FORA do chunk): %d ok / %d ao contrário  %s",
			[tag, skirt_ok, skirt_bad, "OK" if skirt_bad == 0 else "FACES INVERTIDAS"])
	else:
		var total := outward_ok + outward_bad
		var pct := 100.0 * float(outward_ok) / float(maxi(total, 1))
		say("[%s]   winding (normal aponta para FORA do centro): %d ok / %d ao contrário (%.0f%% para fora) %s",
			[tag, outward_ok, outward_bad, pct,
			"OK" if pct > 85.0 else ("INVERTIDO" if pct < 15.0 else "MISTO")])

	# normal de vértice vs. normal geométrica (detecta normais trocadas)
	if not norms.is_empty() and not idx.is_empty() and tris > 0:
		var agree := 0
		var disagree := 0
		for t in range(0, tris, step):
			var i0: int = idx[t * 3]
			var i1: int = idx[t * 3 + 1]
			var i2: int = idx[t * 3 + 2]
			if i2 >= verts.size() or i2 >= norms.size():
				continue
			var a: Vector3 = verts[i0]
			var b: Vector3 = verts[i1]
			var c2: Vector3 = verts[i2]
			var gn := (b - a).cross(c2 - a)
			if gn.length_squared() < 1e-12:
				continue
			gn = gn.normalized()
			var vn := ((norms[i0] as Vector3) + (norms[i1] as Vector3) + (norms[i2] as Vector3)).normalized()
			if gn.dot(vn) > 0.0:
				agree += 1
			else:
				disagree += 1
		say("[%s]   normais de vértice concordam com a geometria: %d sim / %d não %s",
			[tag, agree, disagree,
			"OK" if agree >= disagree else "NORMAIS AO CONTRÁRIO"])


# ══════════════════════════════════════════════════════════════════════════
#  C. MATERIAIS
# ══════════════════════════════════════════════════════════════════════════
func _materials() -> void:
	say("")
	say("── C. MATERIAIS ──")
	var mats: Object = main.world.mats
	for k in ["terrain", "foliage", "grass", "structure", "water", "sky"]:
		var m: ShaderMaterial = mats.get(k)
		if m == null:
			say("  %-10s NULO — nada vai ser desenhado com este material", [k])
			continue
		var sh: Shader = m.shader
		var code := sh.get_code() if sh else ""
		var rm := ""
		for line in code.split("\n"):
			if "render_mode" in line:
				rm = line.strip_edges()
				break
		say("  %-10s shader=%-28s render_priority=%d", [k,
			str(sh.resource_path if sh else "NENHUM").get_file(), m.render_priority])
		say("  %-10s   %s", ["", rm if not rm.is_empty() else "render_mode: (nada — cull_back por omissão)"])
		if "ALBEDO = COLOR" in code:
			say("  %-10s   ⚠ usa COLOR (cor de vértice) como ALBEDO — exige ARRAY_COLOR na mesh", [""])
		if "DIFFUSE_LIGHT" in code and "void light()" in code:
			say("  %-10s   ⚠ tem light() próprio: sem luz a atingir o fragmento fica PRETO", [""])


# ══════════════════════════════════════════════════════════════════════════
#  D. LUZ / CÂMARA / AMBIENTE
# ══════════════════════════════════════════════════════════════════════════
func _scene_light() -> void:
	say("")
	say("── D. LUZ / CÂMARA ──")
	var w: Node = main.world
	var travel: Vector3 = -w.sun.global_transform.basis.z
	say("  sol: energy=%.2f visible=%s shadow=%s", [w.sun.light_energy, str(w.sun.visible), str(w.sun.shadow_enabled)])
	say("  sol: Game.sun_direction()=%s   (deve ser a direção para onde a luz VIAJA)", [_v(Game.sun_direction())])
	say("  sol: posição do nó=%s   direção em que brilha=%s", [_v(w.sun.global_position), _v(travel)])
	say("  sol: %s  ← de dia a luz tem de vir de CIMA (y negativo)",
		["OK, vem de cima" if travel.y < 0.0 else "INVERTIDO: a luz vem de BAIXO, o sol está debaixo do chão"])
	say("  ambiente: bg=%s  ambient_source=%d cor=%s energia=%.2f",
		[_c(w.environment.background_color), w.environment.ambient_light_source,
		_c(w.environment.ambient_light_color), w.environment.ambient_light_energy])
	say("  tonemap=%d  fog=%s densidade=%.4f  glow=%s",
		[w.environment.tonemap_mode, str(w.environment.fog_enabled),
		w.environment.fog_density, str(w.environment.glow_enabled)])
	var cam: Camera3D = main.player.camera
	say("  câmara: fov=%.1f near=%.3f far=%.1f  posição=%s",
		[cam.fov, cam.near, cam.far, _v(cam.global_position)])
	var sky: MeshInstance3D = w.sky_dome
	var sky_r := float(sky.mesh.get_aabb().size.x) * 0.5
	say("  domo do céu: raio=%.0f  prioridade do nó=%d  posição=%s  (câmara dentro? %s)",
		[sky_r, int(sky.render_priority), _v(sky.global_position),
		str(sky.global_position.distance_to(cam.global_position) < sky_r)])
	_probe_meshes()
	say("")
	say("  cor de vértice por espécie (o shader faz ALBEDO = COLOR × tinta):")
	for k in main.world.species.trees:
		var sp = main.world.species.trees[k]
		say("    árvore %-8s cor média=%s  tinta da espécie=%s", [str(k), _avg_color(sp.mesh), _c(sp.tint)])
	for k in main.world.species.rocks:
		var sp = main.world.species.rocks[k]
		say("    rocha  %-8s cor média=%s  tinta=%s", [str(k), _avg_color(sp.mesh), _c(sp.tint)])
	say("  spawn do jogador: %s  altura do terreno aí: %.2f",
		[_v(main.player.global_position), main.world.terrain.height(
			main.player.global_position.x, main.player.global_position.z)])


func _probe_skirt(mesh: Mesh, ground_tris: int, centre: Vector3) -> void:
	## A saia emite 4 arestas por k, 2 triângulos cada: norte, sul, oeste, este.
	say("")
	say("  SAIA aresta a aresta (a ordem de emissão é norte, sul, oeste, este):")
	var arr: Array = mesh.surface_get_arrays(0)
	var verts: Array = arr[Mesh.ARRAY_VERTEX]
	var idx: Array = arr[Mesh.ARRAY_INDEX]
	var names := ["norte", "sul", "oeste", "este"]
	var counts := {"norte": [0, 0], "sul": [0, 0], "oeste": [0, 0], "este": [0, 0]}
	var skirt_tris := (idx.size() / 3) - ground_tris
	for r in skirt_tris:
		var t := ground_tris + r
		var edge: String = names[(r / 2) % 4]
		var a: Vector3 = verts[idx[t * 3]]
		var b: Vector3 = verts[idx[t * 3 + 1]]
		var c: Vector3 = verts[idx[t * 3 + 2]]
		var gn := (b - a).cross(c - a)
		if gn.length_squared() < 1e-12:
			continue
		gn = gn.normalized()
		var mid := (a + b + c) / 3.0
		var away := Vector3(mid.x - centre.x, 0.0, mid.z - centre.z).normalized()
		var pair: Array = counts[edge]
		if gn.dot(away) > 0.0:
			pair[0] = int(pair[0]) + 1
		else:
			pair[1] = int(pair[1]) + 1
		counts[edge] = pair
	say("    (k=0: r=0..7 são norte×2, sul×2, oeste×2, este×2)")
	for rr in range(0, 8):
		var r2: int = int(rr)
		var t2: int = ground_tris + r2
		var av: Vector3 = verts[idx[t2 * 3]]
		var bv: Vector3 = verts[idx[t2 * 3 + 1]]
		var cv: Vector3 = verts[idx[t2 * 3 + 2]]
		say("      r=%d %-6s idx=(%d,%d,%d)  %s %s %s",
			[r2, names[int(r2 / 2)], int(idx[t2 * 3]), int(idx[t2 * 3 + 1]), int(idx[t2 * 3 + 2]),
			_v(av), _v(bv), _v(cv)])
	say("    vértices da saia (últimos 12): total=%d", [verts.size()])
	for q in range(verts.size() - 12, verts.size()):
		say("      v[%d] = %s", [int(q), _v(verts[int(q)])])
	say("    (amostra: 1º triângulo de cada aresta — r=0,2,4,6)")
	for rr in [0, 2, 4, 6]:
		var r: int = int(rr)
		var t: int = ground_tris + r
		var a: Vector3 = verts[idx[t * 3]]
		var b: Vector3 = verts[idx[t * 3 + 1]]
		var c: Vector3 = verts[idx[t * 3 + 2]]
		var gn := (b - a).cross(c - a).normalized()
		var mid := (a + b + c) / 3.0
		var away := Vector3(mid.x - centre.x, 0.0, mid.z - centre.z).normalized()
		say("      %-6s a=%s b=%s c=%s", [names[int(r / 2)], _v(a), _v(b), _v(c)])
		say("      %-6s normal=%s  para-fora=%s  dot=%+.3f  centro=%s",
			["", _v(gn), _v(away), gn.dot(away), _v(centre)])

	for e in names:
		var p2: Array = counts[e]
		say("    %-6s  para fora=%3d   para dentro=%3d   %s",
			[e, int(p2[0]), int(p2[1]), "OK" if int(p2[1]) == 0 else "INVERTIDA"])


func _probe_meshes() -> void:
	say("")
	say("  MICRO-SONDA: de onde vem a cor preta?")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var green := Color(0.30, 0.72, 0.34)
	var brown := Color(0.42, 0.29, 0.21)
	var blob: ArrayMesh = MeshKit.blob(rng, 1.0, 1, 0.18, Vector3.ONE, green)
	say("    blob(verde) sozinho        → %s", [_avg_color(blob)])
	var barr: Array = blob.surface_get_arrays(0)
	var bverts: Array = barr[Mesh.ARRAY_VERTEX]
	var bidx: Array = barr[Mesh.ARRAY_INDEX]
	var bcols: Array = barr[Mesh.ARRAY_COLOR]
	say("    blob: vértices=%d  índices=%d  cores=%d  (índices vazios => _offset usa `verts` como `order`)",
		[bverts.size(), bidx.size(), bcols.size()])
	if not bidx.is_empty():
		say("    blob: order[0]=%s (tipo %s) → int()=%d", [str(bidx[0]), bidx[0].get_type(), int(bidx[0])])
	else:
		say("    blob: SEM ÍNDICES → `order` passa a ser o array de VÉRTICES, e `int(order[k])` recebe um Vector3")
		say("    blob: int(Vector3) devolve = %s   ← isto é o índice usado para ler a cor", [str(int(bverts[0]))])
	var off: ArrayMesh = main.world.species.call("_offset", blob, Vector3(0, 2, 0))
	say("    blob depois de _offset()   → %s", [_avg_color(off)])
	var trunk: ArrayMesh = MeshKit.tapered(rng, 2.2, 0.3, 0.16, 5, 3, 0.1, true, brown)
	say("    tronco(castanho) sozinho   → %s", [_avg_color(trunk)])
	var merged: ArrayMesh = main.world.species.call("_merge", [trunk, off])
	say("    _merge(tronco + copa)      → %s", [_avg_color(merged)])
	for k in main.world.species.trees:
		var sp = main.world.species.trees[k]
		for li in sp.lods.size():
			say("    %-8s LOD%d                    → %s", [str(k), li, _avg_color(sp.lods[li])])


func _avg_color(mesh: Mesh) -> String:
	if mesh == null or mesh.get_surface_count() == 0:
		return "sem mesh"
	var arr: Array = mesh.surface_get_arrays(0)
	var cols: Array = arr[Mesh.ARRAY_COLOR]
	if cols.is_empty():
		return "SEM ARRAY_COLOR"
	var sum := Color(0, 0, 0)
	var lo := Color(1, 1, 1)
	var hi := Color(0, 0, 0)
	for c in cols:
		var cc: Color = c
		sum += cc
		lo = Color(minf(lo.r, cc.r), minf(lo.g, cc.g), minf(lo.b, cc.b))
		hi = Color(maxf(hi.r, cc.r), maxf(hi.g, cc.g), maxf(hi.b, cc.b))
	sum /= float(cols.size())
	return "média(%.2f,%.2f,%.2f) min(%.2f,%.2f,%.2f) max(%.2f,%.2f,%.2f)" % [
		sum.r, sum.g, sum.b, lo.r, lo.g, lo.b, hi.r, hi.g, hi.b]


func _v(v: Vector3) -> String:
	return "(%6.2f,%6.2f,%6.2f)" % [v.x, v.y, v.z]


func _c(c: Color) -> String:
	return "(%.2f,%.2f,%.2f)" % [c.r, c.g, c.b]
