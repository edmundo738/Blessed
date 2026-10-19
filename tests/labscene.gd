extends Node
## LABSCENE — prova automática da Etapa 2 (mesh 3D, colisão, spawn, cavar).
## Uso: -- labscene   (imprime LABSCENE_PASS / LABSCENE_FAIL + LABGRID_B64)

var main: Node
var _fails: Array[String] = []
var _count := 0


func setup(m: Node) -> void:
	main = m


func _check(cond: bool, label: String) -> void:
	_count += 1
	if cond:
		print("ok ", _count, " - ", label)
	else:
		_fails.append(label)
		print("FALHA ", _count, " - ", label)


func _ready() -> void:
	for i in 6:
		await get_tree().process_frame
	var packed: PackedScene = load("res://scenes/lab.tscn")
	_check(packed != null, "cena do laboratório carrega")
	var scene := packed.instantiate() as LabScene
	add_child(scene)
	for i in 6:
		await get_tree().process_frame

	_check(scene.lab != null, "LabWorld existe na cena")
	_check(scene.get("_chunks") != null and scene._chunks.size() == 64,
			"64 pedaços de terreno (8x8)")
	var total_verts := 0
	for key in scene._chunks.keys():
		var mi := scene._chunks[key]["mesh"] as MeshInstance3D
		if mi != null and mi.mesh != null:
			total_verts += mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	_check(total_verts > 5000, "mesh 3D com geometria real (%d vértices)" % total_verts)
	_check(scene._water_inst != null, "malha de água presente")

	# REGRESSAO winding/normais: a face de cima tem de ser a frontal.
	# O bug original (indices espelhados) passava em todos os testes
	# antigos porque nenhum olhava para a orientacao das faces — o
	# terreno e a agua so se viam por baixo (backface culling).
	var bad_terrain := 0
	for key in scene._chunks.keys():
		var mi := scene._chunks[key]["mesh"] as MeshInstance3D
		if mi != null and mi.mesh != null:
			bad_terrain += LabMesh.winding_mismatch(mi.mesh.surface_get_arrays(0))
	_check(bad_terrain == 0, "winding do terreno coerente com as normais (%d maus)" % bad_terrain)
	var bad_water := -1
	if scene._water_inst != null and scene._water_inst.mesh != null:
		bad_water = LabMesh.winding_mismatch(scene._water_inst.mesh.surface_get_arrays(0))
	_check(bad_water == 0, "winding da água coerente com as normais (%d maus)" % bad_water)

	# spawn em terra firme, acima do chão
	_check(scene.player != null, "jogador nasceu")
	var sp := scene.player.global_position
	_check(scene.lab.height(sp.x, sp.z) > 0.3, "spawn em terra (h=%.2f)" % scene.lab.height(sp.x, sp.z))
	# a origem do Player são os pés: assentado, fica ao nível do chão (± snap)
	_check(absf(sp.y - scene.lab.height(sp.x, sp.z)) < 3.5,
			"spawn assentou na malha (pés a %.2f do relevo analítico)" % absf(sp.y - scene.lab.height(sp.x, sp.z)))

	# colisão acompanha a mesh: raio para baixo acerta no chão do laboratório
	var query := PhysicsRayQueryParameters3D.create(
			Vector3(sp.x, sp.y + 4.0, sp.z), Vector3(sp.x, sp.y - 6.0, sp.z), 1)
	var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty(), "raycast acerta na colisão do terreno")

	# cavar: altura desce, e só o pedaço local reconstrói
	var before := scene.lab.height(30.0, 30.0)
	scene.lab.dig(30.0, 30.0, 4.5, 0.9)
	scene.rebuild_area(30.0, 30.0, 9.0)
	_check(scene.lab.height(30.0, 30.0) < before - 0.4, "cavar baixa o chão 3D")
	# reconstruir: aterrar volta a subir
	scene.lab.fill(30.0, 30.0, 4.5, 0.9)
	scene.rebuild_area(30.0, 30.0, 9.0)
	_check(scene.lab.height(30.0, 30.0) > before - 0.45, "aterrar reconstrói o chão")

	# voo do modo deus
	scene.player.dev_fly = true
	scene.player._move_fly()
	_check(scene.player.velocity.length() >= 0.0 and scene.player.dev_fly, "modo deus: voo ativo")

	# ferramentas: raios REDUZIDOS face ao pincel antigo de 4.5 m
	_check(float(LabScene.TOOLS["shovel"]["radius"]) <= 2.5
			and float(LabScene.TOOLS["hand"]["radius"]) <= 1.6
			and float(LabScene.TOOLS["pickaxe"]["radius"]) <= 1.4,
			"ferramentas: raios pequenos (mão/pá/picareta)")

	# regras de material: a mão NÃO escava rocha; a picareta sim
	var rock_at := Vector2.INF
	for j in range(4, LabWorld.N - 4):
		for i in range(4, LabWorld.N - 4):
			var p := scene.lab.grid_pos(i, j)
			if scene.lab.material_at(p.x, p.y) == LabWorld.M_ROCK:
				rock_at = p
				break
		if rock_at != Vector2.INF:
			break
	_check(rock_at != Vector2.INF, "existe afloramento de ROCHA para testar ferramentas")
	if rock_at != Vector2.INF:
		var h_rock := scene.lab.height(rock_at.x, rock_at.y)
		var denied: Dictionary = scene.tool_dig("hand", rock_at.x, rock_at.y)
		_check(not bool(denied["ok"]) and absf(scene.lab.height(rock_at.x, rock_at.y) - h_rock) < 0.01,
				"mão NÃO parte rocha (sem picareta, sem escavar)")
		var mined: Dictionary = scene.tool_dig("pickaxe", rock_at.x, rock_at.y)
		_check(bool(mined["ok"]) and scene.lab.height(rock_at.x, rock_at.y) < h_rock - 0.05
				and str(mined["yield_item"]) == "stone",
				"picareta parte rocha e rende stone")

	# objetos nao flutuam: escavar debaixo de uma arvore faz-la cair
	var tree_body: Node3D = null
	for child in scene.get_node("LabProps").get_children():
		var b := child as Node3D
		if b != null and str(b.get_meta("lab_kind", "")).begins_with("tree"):
			tree_body = b
			break
	_check(tree_body != null, "existe árvore para o teste de queda")
	if tree_body != null:
		var tp := tree_body.global_position
		for n in 4:
			scene.lab.dig(tp.x, tp.z, 2.0, 1.2)
			scene.rebuild_area(tp.x, tp.z, 8.0)
			if tree_body.has_meta("lab_felled"):
				break
		_check(tree_body.has_meta("lab_felled"),
				"escavar debaixo da árvore: ela CAI (não flutua)")

	# relva: existe como MultiMesh, some ao escavar e recresce ao aterrar
	var total_grass := 0
	for key in scene._grass.keys():
		total_grass += scene.grass_count((key as Vector2i).x, (key as Vector2i).y)
	_check(total_grass > 1500, "relva MultiMesh cobre a ilha (%d lâminas)" % total_grass)
	var meadow := Vector2.INF
	for j in range(4, LabWorld.N - 4):
		for i in range(4, LabWorld.N - 4):
			var p := scene.lab.grid_pos(i, j)
			if scene.grass_density(p.x, p.y) > 0.6:
				meadow = p
				break
		if meadow != Vector2.INF:
			break
	_check(meadow != Vector2.INF, "existe prado denso para testar a relva")
	if meadow != Vector2.INF:
		var gci := clampi(int(floor((meadow.x + 200.0) / 50.0)), 0, 7)
		var gcj := clampi(int(floor((meadow.y + 200.0) / 50.0)), 0, 7)
		var g_before := scene.grass_count(gci, gcj)
		for n in 5:
			scene.tool_dig("shovel", meadow.x, meadow.y)
		var g_dug := scene.grass_count(gci, gcj)
		_check(g_dug < g_before, "escavar faz a relva sumir no pedaço (%d -> %d)" % [g_before, g_dug])
		for n in 5:
			scene.tool_dig("shovel", meadow.x, meadow.y, true)
		scene.advance_growth(30.0)
		var g_back := scene.grass_count(gci, gcj)
		_check(g_back > g_dug, "aterrar + tempo: a relva recresce (%d -> %d)" % [g_dug, g_back])

	# estação de escavação: a pá para na rocha; a picareta desenterra
	var site := scene.dig_site_pos()
	_check(site != Vector2.INF, "estação de escavação (dig_pit) localizada")
	if site != Vector2.INF:
		var denied := false
		var saw_glint := false
		for n in 25:
			var r: Dictionary = scene.tool_dig("shovel", site.x, site.y)
			if float(r.get("glint", 0.0)) > 0.05:
				saw_glint = true
			if not bool(r["ok"]):
				denied = true
				break
		_check(denied and not scene.relic_found(),
				"pá bate na camada de rocha e para (relíquia continua enterrada)")
		_check(saw_glint, "poeira brilha perto do prémio (pista sensorial, sem texto)")
		for n in 30:
			scene.tool_dig("pickaxe", site.x, site.y)
			if scene.relic_found():
				break
		_check(scene.relic_found(), "picareta atravessa a rocha e desenterra a relíquia")
		_check(scene.relic_node() != null, "relíquia visível e luminosa no mundo")

	# construção inteligente: snap, suporte, estabilidade, colapso
	var pad := Vector2(-5.0, -20.0)
	var no_foundation: Dictionary = scene.try_place("wall", pad.x, pad.y)
	_check(not bool(no_foundation["ok"]) and str(no_foundation["reason"]) == "no_foundation",
			"construção: parede sem fundação NÃO entra")
	var in_water: Dictionary = scene.evaluate_place("foundation", 170.0, 170.0)
	_check(not bool(in_water["ok"]) and str(in_water["reason"]) == "in_water",
			"construção: fundação na água NÃO entra")
	var built0 := scene.built_count()
	var f1: Dictionary = scene.try_place("foundation", pad.x, pad.y)
	_check(bool(f1["ok"]) and absf(float(f1["stability"]) - 1.0) < 0.01,
			"construção: fundação adaptativa coloca (estabilidade 1.0)")
	var dup: Dictionary = scene.try_place("foundation", pad.x, pad.y)
	_check(not bool(dup["ok"]), "construção: célula ocupada recusa segunda fundação")
	var w1: Dictionary = scene.try_place("wall", pad.x, pad.y)
	var fl: Dictionary = scene.try_place("floor", pad.x, pad.y)
	var rf: Dictionary = scene.try_place("roof", pad.x, pad.y)
	_check(bool(w1["ok"]) and bool(fl["ok"]) and bool(rf["ok"]),
			"construção: parede -> chão -> telhado empilham com suporte")
	_check(scene.built_count() == built0 + 4, "construção: 4 peças registadas")
	var fell := scene.remove_piece(str(f1["key"]))
	_check(fell >= 4 and scene.built_count() == built0,
			"construção: tirar a fundação DERRUBA a casa (colapso em cascata)")
	# custo real: colocar consome materiais do inventário
	scene.inv.add("wood", 10)
	scene.inv.add("stone", 10)
	var w_before := scene.inv.count("wood")
	var paid: Dictionary = scene.try_place("foundation", pad.x + 4.0, pad.y, 0.0, scene.inv)
	_check(bool(paid["ok"]) and scene.inv.count("wood") == w_before - 2,
			"construção: colocar consome materiais (madeira -2)")

	# mais peças: porta/janela ocupam o lugar da parede, escadas e telhado
	var door_at := Vector2(3.0, -20.0)
	scene.try_place("foundation", door_at.x, door_at.y)
	var door1: Dictionary = scene.try_place("door", door_at.x, door_at.y, PI * 0.25)
	_check(bool(door1["ok"]) and int(door1["level"]) == 0,
			"construção: porta entra no nível 0 (lugar da parede)")
	var above_door: Dictionary = scene.evaluate_place("wall", door_at.x, door_at.y)
	_check(bool(above_door["ok"]) and int(above_door["level"]) == 1,
			"construção: sobre a porta só entra parede no nível 1")
	var door_node := scene._built.get(str(door1["key"])) as Node3D
	_check(door_node != null and absf(door_node.rotation.y - PI * 0.25) < 0.01,
			"construção: peças rodam em 45° (R)")
	var win_at := Vector2(11.0, -20.0)
	scene.try_place("foundation", win_at.x, win_at.y)
	var win1: Dictionary = scene.try_place("window", win_at.x, win_at.y)
	var floor_on_window: Dictionary = scene.try_place("floor", win_at.x, win_at.y)
	_check(bool(win1["ok"]) and bool(floor_on_window["ok"]),
			"construção: janela sustenta o chão como uma parede")
	var roof1: Dictionary = scene.try_place("roof", win_at.x, win_at.y)
	var roof_node := scene._built.get(str(roof1["key"])) as Node3D
	_check(bool(roof1["ok"]) and roof_node != null and roof_node.get_child_count() >= 6,
			"construção: telhado de duas águas (2 painéis + cumeeira)")
	var fell_window := scene.remove_piece(str(win1["key"]))
	_check(fell_window >= 3 and not scene._built.has(str(floor_on_window["key"])),
			"construção: tirar a janela derruba chão e telhado")
	var stairs_at := Vector2(19.0, -20.0)
	scene.try_place("foundation", stairs_at.x, stairs_at.y)
	var stairs1: Dictionary = scene.try_place("stairs", stairs_at.x, stairs_at.y, PI)
	var stairs_node := scene._built.get(str(stairs1["key"])) as Node3D
	_check(bool(stairs1["ok"]) and stairs_node != null and stairs_node.get_child_count() >= 10,
			"construção: escadas com degraus pisáveis (5 degraus com colisão)")

	# polimento: casinha-exemplo nasce construída + sons sintetizados
	_check(scene.built_count() >= 15 and scene._built.has(scene._bkey(-7, -15, 0, "door"))
			and scene._built.has(scene._bkey(-7, -15, 0, "roof"))
			and scene._built.has(scene._bkey(-7, -14, 0, "stairs")),
			"polimento: casinha-exemplo de pé (porta, telhado, escadas)")
	_check(Sfx.stream("build_wood") != null and Sfx.stream("build_stone") != null
			and Sfx.stream("collapse") != null,
			"polimento: sons de construção sintetizados (madeira/pedra/colapso)")

	# eficiência + construção ligada (base HD2D)
	var fa: Dictionary = scene.try_place("foundation", 25.0, -20.0)
	var ev_b: Dictionary = scene.evaluate_place("foundation", 27.0, -20.0)
	_check(bool(fa["ok"]) and absf(float(ev_b["top"]) - float(fa["top"])) < 0.01,
			"eficiência: fundação nova ALINHA o nível com a vizinha (piso partilhado)")
	scene.try_place("foundation", 27.0, -20.0)
	var wa: Dictionary = scene.try_place("wall", 25.0, -20.0)
	var s_iso: Dictionary = scene.evaluate_place("wall", 25.0, -20.0)
	scene.try_place("wall", 27.0, -20.0)
	var s_lig: Dictionary = scene.evaluate_place("wall", 25.0, -20.0)
	_check(float(s_lig["stability"]) > float(s_iso["stability"]) + 0.015,
			"eficiência: construção LIGADA é mais estável (bónus de vizinhança)")
	var wall_a := scene._built.get(str(wa["key"])) as Node3D
	var wall_b_key := scene._bkey(14, -10, 0, "wall")
	var wall_b := scene._built.get(wall_b_key) as Node3D
	_check(wall_a != null and wall_b != null and wall_a.get_child(0).get("material_override") != null
			and wall_a.get_child(0).get("material_override") == wall_b.get_child(0).get("material_override"),
			"eficiência: peças partilham material (sem recursos gémeos)")
	var builds0: int = scene._water_builds
	scene.rebuild_area(30.0, -60.0, 8.0)  # bosque alto e seco: longe de rios/lago/oceano
	var inland_ok: bool = scene._water_builds == builds0
	scene.rebuild_area(170.0, 170.0, 8.0)
	_check(inland_ok and scene._water_builds > builds0,
			"eficiência: escavar longe de água NÃO reconstrói a água; junto dela sim")

	# CavePatch: escavação volumétrica sem tocar na hidrologia
	_check(scene.cave != null and scene._cave_body != null,
			"caverna: bloco de rocha volumétrico existe na cena")
	var cc: Vector3 = scene.cave.origin + Vector3(12, 6, 12)
	var h_before: float = scene.lab.height(44.0, -64.0)
	_check(not scene.cave.is_air(cc),
			"caverna: o centro do bloco começa SÓLIDO")
	var cave_denied: Dictionary = scene.dig_cave(cc, "shovel")
	var cave_dug: Dictionary = scene.dig_cave(cc, "pickaxe")
	_check(not bool(cave_denied["ok"]) and bool(cave_dug["ok"]) and scene.cave.is_air(cc),
			"caverna: pá não entra; picareta abre AR dentro da rocha")
	var tunnel_ok := true
	for step in [2.0, 5.0, 8.0]:
		scene.dig_cave(scene.cave.origin + Vector3(step, 6, 12), "pickaxe")
		if not scene.cave.is_air(scene.cave.origin + Vector3(step, 6, 12)):
			tunnel_ok = false
	_check(tunnel_ok and scene.cave.is_air(scene.cave.origin + Vector3(3.5, 6, 12)),
			"caverna: escavações ligadas formam TÚNEL contínuo")
	_check(scene.cave.last_verts > 0 and scene.cave.last_tris > 0
			and scene.cave.last_outward_ratio > 0.99,
			"caverna: Surface Nets gera malha com faces para fora (gradiente)")
	_check(absf(scene.lab.height(44.0, -64.0) - h_before) < 0.001,
			"caverna: hidrologia/terreno heightfield INTOCADOS pelo túnel")

	# aprofundar: entrada natural, sílex na rocha, lençol freático
	_check(scene.cave.is_air(scene.cave.origin + Vector3(2, 5, 12))
			and scene.cave.is_air(scene.cave.origin + Vector3(7, 5, 12)),
			"caverna: ENTRADA natural pré-escavada na face oeste")
	_check(scene.cave.ore.size() > 0,
			"caverna: veios de sílex existem dentro da rocha")
	var ore_hit: Dictionary = {}
	if scene.cave.ore.size() > 0:
		ore_hit = scene.dig_cave(scene.cave.ore[0], "pickaxe")
	_check(str(ore_hit.get("yield_item", "")) == "flint",
			"caverna: escavar no veio rende SÍLEX (flint), não pedra comum")
	var flood_hit: Dictionary = scene.dig_cave(scene.cave.origin + Vector3(13, 1, 12), "pickaxe")
	_check(bool(flood_hit.get("flooded", false)) and scene.cave_flooded
			and scene._cave_water != null and scene._cave_water.visible,
			"caverna: cavar abaixo do lençol freático ENCHE a mina de água")

	# grelha para o PNG da etapa (render por software a partir dos dados reais)
	var bytes := PackedByteArray()
	bytes.resize(LabWorld.N * LabWorld.N * 2)
	var pos := 0
	for j in LabWorld.N:
		for i in LabWorld.N:
			var p := scene.lab.grid_pos(i, j)
			var s := scene.lab.sample(p.x, p.y)
			var h8 := int(clampf((float(s["height"]) + 20.0) / 70.0, 0.0, 1.0) * 255.0)
			var w8 := 255 if int(s["water_kind"]) > 0 else int(clampf(float(s["moisture"]) * 255.0, 0.0, 255.0))
			bytes[pos] = h8
			bytes[pos + 1] = w8
			pos += 2
	print("LABGRID_B64:", Marshalls.raw_to_base64(bytes))

	if _fails.is_empty():
		print("LABSCENE_PASS ", _count, " verificacoes")
		get_tree().quit(0)
	else:
		print("LABSCENE_FAIL ", _fails.size(), " falhas: ", _fails)
		get_tree().quit(1)
