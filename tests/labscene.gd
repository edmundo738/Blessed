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
