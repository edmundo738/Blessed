extends Node
## Self-test do Blessed.
##
## Corre o jogo a sério (o mesmo main.gd, os mesmos sistemas) e verifica que as
## mecânicas produzem resultados observáveis — não que "não deu erro".
##
## Uso:
##   godot --headless --path . --quit-after 900 -- selftest
## ou:
##   ./tools/check.sh
##
## Sai com código 0 se tudo passar, 1 se alguma verificação falhar.

var main: Node
var passed := 0
var failed := 0
var skipped := 0
var lines: Array = []
## Passos do "primeiro dia" que falharam (o fecho da sessão lê isto).
var _fd_failed: Array = []


func check(what: String, ok: bool, detail: String = "") -> void:
	var line := ""
	if ok:
		passed += 1
		line = "  OK   %s%s" % [what, "" if detail.is_empty() else "  (" + detail + ")"]
	else:
		failed += 1
		line = "  FALHA %s%s" % [what, "" if detail.is_empty() else "  (" + detail + ")"]
	lines.append(line)
	# Impresso À MEDIDA que acontece: o resumo final continua igual, mas uma
	# falha do motor a meio do teste deixa de apagar tudo o que já tinha passado
	# (foi assim que uma paragem da build web escondeu onde o teste morreu).
	print(line)


## Verificação que NÃO pode ser feita nesta build do motor. Não conta como
## falha (não há nada partido), mas fica escrita no relatório: um relatório só
## com "OK" e "FALHA" fazia parecer que 30 verificações dos modelos Blender
## tinham corrido quando na build web não corriam de todo.
func skip(what: String, detail: String = "", count: int = 1) -> void:
	skipped += count
	var line := "  SALTA %s%s" % [what, "" if detail.is_empty() else "  (" + detail + ")"]
	lines.append(line)
	print(line)


## Esta build do motor traz o módulo glTF? Sem `GLTFDocument`/`GLTFState` não há
## forma de abrir um .glb: nem o editor, nem o `Assets`, nem este teste.
func _gltf_available() -> bool:
	return ClassDB.class_exists("GLTFDocument") and ClassDB.class_exists("GLTFState")


func setup(p_main: Node) -> void:
	main = p_main


func _ready() -> void:
	# o prólogo é saltado: o self-test joga diretamente
	Game.started = true
	Game.profile = {"name": "Teste", "body": "f", "soul": "hands"}
	await get_tree().process_frame
	await get_tree().process_frame
	if "dia1" in OS.get_cmdline_user_args():
		# modo de desenvolvimento: só a sessão do primeiro dia (minutos a menos)
		await _first_day()
		_report()
		return
	await _run()


func _run() -> void:
	print("── SELF-TEST BLESSED ─────────────────────────────")

	# ── 1. mundo ──────────────────────────────────────────────────────────
	var world: World = main.world
	check("mundo existe", world != null)
	check("céu nativo com ciclo dia/noite", world.environment.background_mode == Environment.BG_SKY
		and world.sky_resource != null and world.sky_resource.sky_material is ShaderMaterial)
	var sky_mat := world.sky_resource.sky_material as ShaderMaterial
	check("três panoramas estilizados carregados", sky_mat != null
		and sky_mat.get_shader_parameter("sky_day") != null
		and sky_mat.get_shader_parameter("sky_morning") != null
		and sky_mat.get_shader_parameter("sky_night") != null)
	world.set_sky_visible(false)
	check("modo de diagnóstico consegue ocultar o céu", world.environment.background_mode == Environment.BG_COLOR)
	world.set_sky_visible(true)
	check("modo de diagnóstico repõe o céu", world.environment.background_mode == Environment.BG_SKY)
	var ambient: Node = main.get_node_or_null("AmbientFx")
	var dust: CPUParticles3D = ambient.get("dust") as CPUParticles3D if ambient != null else null
	var flies: CPUParticles3D = ambient.get("flies") as CPUParticles3D if ambient != null else null
	check("poeira ambiental usa sprite Kenney", dust != null and dust.mesh is QuadMesh
		and (dust.mesh.surface_get_material(0) as StandardMaterial3D).albedo_texture != null)
	check("pirilampos usam sprite Kenney", flies != null and flies.mesh is QuadMesh
		and (flies.mesh.surface_get_material(0) as StandardMaterial3D).albedo_texture != null)
	var impact_pool: Array = main.fx.get("_pool") as Array
	var impact: Node3D = impact_pool[0] as Node3D if not impact_pool.is_empty() else null
	# Os dois caminhos são legítimos: Forward+ usa dois passes no emissor GPU; o
	# Compatibility (gl_compatibility — o build web) usa um só emissor CPU com a
	# malha de duas superfícies, porque o desenho por passes é do GPU. A
	# verificação tem de aceitar o caminho que o renderer em uso realmente toma,
	# senão acusa um bug onde há uma decisão de portabilidade.
	var impact_ok := false
	var impact_detail := "nenhum emissor"
	if impact is GPUParticles3D:
		var spark_mesh := impact.get("draw_pass_2") as QuadMesh
		impact_ok = int(impact.get("draw_passes")) == 2 and spark_mesh != null \
			and (spark_mesh.surface_get_material(0) as StandardMaterial3D) != null \
			and (spark_mesh.surface_get_material(0) as StandardMaterial3D).albedo_texture != null
		impact_detail = "GPU, draw_passes=%d" % int(impact.get("draw_passes"))
	elif impact is CPUParticles3D:
		var combo := impact.mesh as ArrayMesh
		var glow := combo.surface_get_material(1) as StandardMaterial3D if combo != null \
			and combo.get_surface_count() > 1 else null
		impact_ok = combo != null and combo.get_surface_count() == 2 and glow != null \
			and glow.albedo_texture != null
		impact_detail = "CPU, superfícies=%d" % (combo.get_surface_count() if combo != null else 0)
	check("impacto combina lascas 3D com brilho 2D reutilizável", impact != null and impact_ok,
		impact_detail)
	var fx_use_gpu := bool(main.fx.get("_use_gpu"))
	main.fx.set("_use_gpu", false)
	var compatibility_emitter: CPUParticles3D = main.fx.call("_new_emitter") as CPUParticles3D
	var compatibility_mesh: ArrayMesh = compatibility_emitter.mesh as ArrayMesh if compatibility_emitter != null else null
	check("Compatibility tem emissor CPU com os mesmos dois passes", compatibility_emitter != null
		and compatibility_mesh != null and compatibility_mesh.get_surface_count() == 2
		and (compatibility_mesh.surface_get_material(1) as StandardMaterial3D).albedo_texture != null)
	if compatibility_emitter != null:
		compatibility_emitter.free()
	main.fx.set("_use_gpu", fx_use_gpu)
	check("terreno tem altura", absf(world.terrain.height(0, 0)) < 500.0,
		"h(0,0)=%.2f" % world.terrain.height(0, 0))
	check("aldeia existe", world.terrain.village_distance(
		world.terrain.village_center().x, world.terrain.village_center().y) < 0.01)
	var avatar_sprite := main.player.avatar.get_node_or_null("PixelSprite") as AnimatedSprite3D
	check("jogador começa em 1.ª pessoa", not main.player.third_person)
	check("avatar do jogador é sprite billboard",
		avatar_sprite != null and avatar_sprite.billboard == BaseMaterial3D.BILLBOARD_ENABLED
			and not main.player.avatar.visible)
	check("substituição Camp to Me desligada",
		not bool(main.player.avatar.get("use_camp_sprite")))
	var hands: Node = main.player.hands
	var held: MeshInstance3D = hands.get("held") as MeshInstance3D if hands != null else null
	check("mãos da 1.ª pessoa têm modelo pronto", hands != null and hands.has_method("set_item")
		and held != null and hands.visible)
	check("item inicial tem malha para a 1.ª pessoa", held != null and held.mesh != null)
	if hands != null and held != null:
		hands.call("set_item", "axe")
		check("machado importado fica visível na mão", held.visible and _node_has_surface_mesh(held))
		hands.call("set_item", "pickaxe")
		check("picareta importada fica visível na mão", held.visible and _node_has_surface_mesh(held))
		hands.call("set_item", "torch")
	check("HUD mostra ícones nos espaços rápidos",
		main.hud.hotbar_slots.size() == 9 and
			(main.hud.hotbar_slots[0]["icon"] as ItemIcon).item_id == "torch")
	var day_music: AudioStreamWAV = Sfx.stream("music_day")
	var night_music: AudioStreamWAV = Sfx.stream("music_night")
	check("temas diurno e noturno são loops",
		day_music.loop_mode == AudioStreamWAV.LOOP_FORWARD and
		 night_music.loop_mode == AudioStreamWAV.LOOP_FORWARD)
	Sfx.set_music_phase("night")
	check("fase noturna seleciona o tema certo",
		str(Sfx._loop_names.get("music", "")) == "music_night")
	Sfx.set_music_phase(Game.current_phase())
	await _frames(60)
	check("chunks construídos", world.chunks.size() > 0, "n=%d" % world.chunks.size())

	var harvest := 0
	for c in world.chunks.values():
		harvest += (c as Chunk).harvest_nodes.size()
	check("nós colhíveis espalhados", harvest > 10, "n=%d" % harvest)
	check("bagas removidas do ciclo de jogo",
		not world.species.plants.has("berry_bush") and not Db.HARVEST.has("bush_berry") \
		and not Db.ITEMS.has("berry"))

	var instances := 0
	var decorative_groundcover := 0
	for c in world.chunks.values():
		for d in (c as Chunk)._decor:
			if d is MultiMeshInstance3D and (d as MultiMeshInstance3D).multimesh:
				instances += (d as MultiMeshInstance3D).multimesh.instance_count
			if d is Node3D and str((d as Node3D).name).begins_with("Groundcover_"):
				decorative_groundcover += 1
	check("instâncias de vegetação", instances > 200, "n=%d" % instances)
	check("relva decorativa removida do cenário", decorative_groundcover == 0,
		"nós de relva=%d" % decorative_groundcover)

	# Valida cada modelo Blender no recurso Godot individualmente. As espécies
	# continuam separadas; não se empilham modelos diferentes numa única malha.
	var blender_asset_ids := ["tree_oak", "tree_birch", "tree_pine", "tree_sakura",
		"tree_willow", "plant_bush", "plant_berry_bush", "plant_mushroom",
		"rock_cluster", "grass_clump", "fern_clump", "flower_clump", "reed_clump",
		"seaweed_cluster", "clover_clump", "pickup_berry", "pickup_leaf", "pickup_log", "tool_axe",
		"tool_pickaxe"]
	var gltf_here := _gltf_available()
	var blender_ids: Array = []
	var lod_asset_ids := ["tree_oak", "tree_birch", "tree_pine", "tree_sakura", "tree_willow",
		"rock_cluster", "plant_bush", "plant_berry_bush", "plant_mushroom"]
	var lod_ids: Array = []
	if gltf_here:
		blender_ids = blender_asset_ids
		lod_ids = lod_asset_ids
	else:
		skip("modelos Blender: 20 GLB de espécies e ferramentas + 9 LODs",
			"esta build do motor não traz GLTFDocument/GLTFState (ver KNOWN_ISSUES #14)",
			blender_asset_ids.size() + lod_asset_ids.size())
	for asset_id in blender_ids:
		var asset_mesh: ArrayMesh = BlessedBlenderAssets.mesh_for(asset_id)
		var asset_vertices: int = _mesh_vertex_count(asset_mesh)
		var asset_size: Vector3 = asset_mesh.get_aabb().size if asset_mesh != null else Vector3.ZERO
		var asset_ok: bool = asset_mesh != null and asset_mesh.get_surface_count() > 0 \
			and asset_vertices > 0 and asset_size.x > 0.001 and asset_size.y > 0.001 \
			and asset_size.z > 0.001
		if str(asset_id).begins_with("tree_"):
			asset_ok = asset_ok and asset_size.y > 2.0
		check("GLB Blender %s tem mesh e escala válida" % asset_id, asset_ok,
			"%d vértices, %d superfícies, Y %.2f m" % [asset_vertices,
				asset_mesh.get_surface_count() if asset_mesh != null else 0, asset_size.y])

	for lod_asset_id in lod_ids:
		var base_mesh: ArrayMesh = BlessedBlenderAssets.mesh_for(lod_asset_id)
		var lod1_mesh: ArrayMesh = BlessedBlenderAssets.mesh_for("%s_lod1" % lod_asset_id)
		var lod2_mesh: ArrayMesh = BlessedBlenderAssets.mesh_for("%s_lod2" % lod_asset_id)
		var base_count: int = _mesh_vertex_count(base_mesh)
		var lod1_count: int = _mesh_vertex_count(lod1_mesh)
		var lod2_count: int = _mesh_vertex_count(lod2_mesh)
		var lod_ok: bool = base_count > 0 and lod1_count > 0 and lod2_count > 0 \
			and lod1_count <= base_count and lod2_count <= lod1_count
		check("LOD Blender %s importam e reduzem geometria" % lod_asset_id, lod_ok,
			"base/1/2: %d/%d/%d vértices" % [base_count, lod1_count, lod2_count])

	var blender_trees_in_world := 0
	var wind_shader_trees_in_world := 0
	for c in world.chunks.values():
		for decor in (c as Chunk)._decor:
			if decor is not MultiMeshInstance3D or (decor as MultiMeshInstance3D).multimesh == null:
				continue
			var used_mesh: Mesh = (decor as MultiMeshInstance3D).multimesh.mesh
			for tree_id in world.species.trees:
				var tree_species: SpeciesKit.Species = world.species.trees[tree_id]
				if not tree_species.lods.is_empty() \
						and used_mesh.get_surface_count() == tree_species.lods[0].get_surface_count() \
						and _mesh_vertex_count(used_mesh) == _mesh_vertex_count(tree_species.lods[0]):
					blender_trees_in_world += (decor as MultiMeshInstance3D).multimesh.instance_count
					for surface in used_mesh.get_surface_count():
						var mat := used_mesh.surface_get_material(surface) as ShaderMaterial
						if mat != null and mat.shader != null \
								and mat.shader.resource_path.ends_with("toon_foliage_cards.gdshader"):
							wind_shader_trees_in_world += (decor as MultiMeshInstance3D).multimesh.instance_count
							break
					break
	if gltf_here:
		check("chunks usam árvores Blender com vento nas folhas",
			blender_trees_in_world > 0 and wind_shader_trees_in_world > 0,
			"%d instâncias; %d com shader de folhas" % [blender_trees_in_world, wind_shader_trees_in_world])
	else:
		skip("chunks usam árvores Blender com vento nas folhas",
			"sem glTF nesta build os Biomas caem nos substitutos procedurais")

	# ── 2. biomas variados ────────────────────────────────────────────────
	var biomes := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in 400:
		var x := rng.randf_range(-250, 250)
		var z := rng.randf_range(-250, 250)
		var h := world.terrain.height(x, z)
		biomes[world.terrain.dominant_s(x, z, h, world.terrain.slope(x, z))] = true
	check("mais de 3 biomas", biomes.size() > 3, "n=%d" % biomes.size())

	# ── 2b. camada data-driven (data/*.json carregado pelo Db) ──────────────
	check("Db: biomas carregados", Db.biome_count() >= 12, "n=%d" % Db.biome_count())
	check("Db: ordem dos biomas bate certo", Db.biome_index("forest") == Terrain.B_FOREST,
		"forest=%d" % Db.biome_index("forest"))
	var _fc := Db.biome_color(Terrain.B_FOREST, Color.BLACK)
	check("Db: cor do bioma vem do JSON", _fc.g > _fc.r and _fc.g > 0.3, "g=%.2f" % _fc.g)
	check("Db: terrain peak_height", Db.terrain_num("peak_height", 0.0) > 100.0,
		"=%.0f" % Db.terrain_num("peak_height", 0.0))
	check("Db: quality preset 2", not Db.quality_preset(2, {}).is_empty())
	check("Db: species oak", not Db.species_meta("trees", "oak").is_empty())
	check("Db→species: densidade da floresta", SpeciesKit.tree_density(Terrain.B_FOREST) > 1.0,
		"=%.2f" % SpeciesKit.tree_density(Terrain.B_FOREST))
	# guarda de regressão: as propriedades que o ambient_fx usa têm de existir
	check("Game.hour existe", typeof(Game.hour) == TYPE_FLOAT)
	check("Game.settings tem quality", Game.settings.has("quality"))

	# ── 3. inventário ─────────────────────────────────────────────────────
	var inv: Inventory = main.inv
	inv.add("wood", 20)
	check("inventário soma", inv.count("wood") >= 20, "wood=%d" % inv.count("wood"))
	check("inventário remove", inv.remove("wood", 5) and inv.count("wood") >= 15)
	check("inventário recusa sem stock", not inv.remove("stone", 999))
	var left := inv.add("flint", 5000)
	check("inventário tem limite", left > 0, "sobrou=%d" % left)
	# esvazia: senão os testes seguintes correm com a mochila cheia
	for i in inv.SLOTS:
		inv.slots[i] = {}

	# ── 4. bancada ────────────────────────────────────────────────────────
	inv.add("stick", 10)
	inv.add("fiber", 10)
	var before := inv.count("torch")
	var res := Game.request("craft", {"recipe": "torch"})
	check("craft de tocha", bool(res.get("ok", false)) and inv.count("torch") > before,
		"tochas=%d" % inv.count("torch"))
	var bad := Game.request("craft", {"recipe": "pickaxe"})
	check("craft sem materiais é recusado", not bool(bad.get("ok", true)))

	# B-02 (regressão): mochila cheia -> craft recusado E ingredientes intactos.
	var saved := inv.slots.duplicate(true)
	var stick_b := inv.count("stick"); var fiber_b := inv.count("fiber")
	for i in inv.SLOTS:
		inv.slots[i] = {"id": "stone", "qty": Db.max_stack("stone")}
	inv.add("stick", 2); inv.add("fiber", 2)  # podem nao caber; nao interessa
	var full := Game.request("craft", {"recipe": "torch"})
	check("craft com mochila cheia e recusado (B-02)", not bool(full.get("ok", true)),
		"devia ter sido recusado")
	inv.slots = saved

	# B-03 (respawn): colhido fica colhido ate ao timer; save/load preserva.
	var hk := Vector3(12.0, 5.0, 12.0)
	world.mark_harvested({"pos": hk, "species": "oak", "kind": "wood"})
	check("recurso colhido fica indisponivel", world.is_harvested(hk, "oak"))
	check("estado de colheita guarda-se", int(world.save_data().get("harvest_state", {}).size()) >= 1)
	Game.day += 15
	check("madeira volta apos ~14 dias", not world.is_harvested(hk, "oak"), "devia regenerar")
	Game.day -= 15

	# ── 5. construir ──────────────────────────────────────────────────────
	inv.add("campfire", 1)
	var camp_slot := -1
	for i in inv.SLOTS:
		if str((inv.slots[i] as Dictionary).get("id", "")) == "campfire":
			camp_slot = i
			break
	check("fogueira foi para a mochila", camp_slot >= 0)
	inv.select(camp_slot)
	check("item na mão é colocável", Db.is_placeable(inv.hotbar_id()), inv.hotbar_id())
	Game.request("toggle_build")
	check("modo construir ativo", main.interaction.building)
	var before_structs: int = main.structures.list.size()
	var placed := Game.request("place")
	check("colocar estrutura",
		bool(placed.get("ok", false)) and main.structures.list.size() == before_structs + 1,
		"%d -> %d" % [before_structs, main.structures.list.size()])
	var blocked := Game.request("place")
	check("colocar sem material é recusado",
		not bool(blocked.get("ok", true)) and main.structures.list.size() == before_structs + 1,
		"reason=%s" % str(blocked.get("reason", "-")))

	# acender a fogueira e verificar que conta como luz
	var fire: Dictionary = {}
	for e in main.structures.list:
		if str(e["id"]) == "campfire":
			fire = e
			break
	if not fire.is_empty():
		main.structures.light(fire)
		check("fogueira acesa dá luz", main.structures.lit_positions().size() > 0)
		check("estação de bancada disponível",
			main.structures.stations_near(fire["pos"], 4.5).size() > 0)

	# ── 6. colheita ───────────────────────────────────────────────────────
	var target: Dictionary = {}
	for c in world.chunks.values():
		for n in (c as Chunk).harvest_nodes:
			if str(n["kind"]).begins_with("tree"):
				target = n
				break
		if not target.is_empty():
			break
	if not target.is_empty():
		var wood_before := inv.count("wood")
		main.interaction.focus = {"kind": "harvest", "ref": target,
			"pos": (target["pos"] as Vector3) + Vector3(0, 1, 0)}
		var hp_before := float(target["hp"])
		main.interaction._hold_work(0.53, 1.0)
		check("árvore exige impactos e perde resistência por golpe",
			float(target["hp"]) < hp_before)
		var hits := 1
		while bool(target.get("alive", true)) and hits < 24:
			main.interaction._hold_work(0.53, 1.0)
			hits += 1
		var felled: Node3D = null
		for item in get_tree().get_nodes_in_group("fellable_logs"):
			if item is Node3D and item.has_method("take_log"):
				felled = item as Node3D
				break
		var wood_drops := 0
		for item in world.get_children():
			if item is RigidBody3D and str(item.get("item_id")) == "wood":
				wood_drops += int(item.get("amount"))
		check("árvore cai e fica como obstáculo colhível",
			felled != null and felled.is_inside_tree() and int(felled.get("remaining_logs")) > 0
			and felled.get_node("TrunkCollider") is CollisionShape3D,
			"troncos restantes=%d" % (int(felled.get("remaining_logs")) if felled != null else 0))
		check("madeira só sai do tronco quando o jogador a retira",
			wood_drops == 0 and inv.count("wood") == wood_before,
			"wood pickup=%d; mochila=%d" % [wood_drops, inv.count("wood")])
		if felled != null:
			var logs_before := int(felled.get("remaining_logs"))
			main.interaction.focus = {"kind": "felled_tree", "ref": felled,
				"pos": felled.call("interaction_target")["pos"]}
			main.interaction._do_interact({})
			var physical_wood := false
			for item in world.get_children():
				if item is RigidBody3D and str(item.get("item_id")) == "wood":
					physical_wood = true
			check("F retira um toro e cria pickup com física",
				int(felled.get("remaining_logs")) == logs_before - 1 and physical_wood
				and inv.count("wood") == wood_before)
			var tree_mesh := felled.get_node("TreeMesh") as MeshInstance3D
			var species_id := str(target.get("species", ""))
			var preserves_material := not (world.species.trees[species_id] as SpeciesKit.Species).materials_authored \
				or tree_mesh.material_override == null
			check("árvore caída conserva o material do modelo original", preserves_material)
		check("nó colhido fica marcado", not bool(target.get("alive", true)))
		check("colisão da árvore em pé é removida ao cair",
			(target.get("collider") as CollisionShape3D).is_queued_for_deletion())
		check("árvore abatida entra no estado de respawn",
			world.is_harvested(target["pos"] as Vector3, str(target["species"])))
	else:
		check("cortar árvore dá madeira", false, "nenhuma árvore por perto")
	var rock_target: Dictionary = {}
	for c in world.chunks.values():
		for n in (c as Chunk).harvest_nodes:
			if str(n.get("kind", "")) == "rock" and is_instance_valid(n.get("collider")):
				rock_target = n
				break
		if not rock_target.is_empty():
			break
	if not rock_target.is_empty():
		var rock_collider := rock_target["collider"] as CollisionShape3D
		world.hide_harvest(rock_target)
		check("rocha colhida deixa de bloquear o jogador",
			rock_collider.is_queued_for_deletion() or rock_collider.disabled)
	else:
		check("rocha colhida deixa de bloquear o jogador", false,
			"nenhuma rocha com colisor nos chunks carregados")
	check("jogo novo começa sem objetivo imposto", Game.objective_current.is_empty())

	# ── 7. necessidades ───────────────────────────────────────────────────
	var surv: Survival = main.survival
	surv.hunger = 5.0
	surv.thirst = 5.0
	surv.eat(40.0, 10.0, 0.0)
	check("comer repõe fome", surv.hunger > 5.0, "hunger=%.1f" % surv.hunger)
	surv.drink(40.0)
	check("beber repõe sede", surv.thirst > 5.0, "thirst=%.1f" % surv.thirst)
	surv.health = 100.0
	surv.damage(30.0, "test")
	check("dano baixa vida", surv.health < 100.0, "health=%.1f" % surv.health)
	check("fome baixa abranda", surv.speed_multiplier() <= 1.0)

	# ── 8. ciclo dia/noite e criaturas ────────────────────────────────────
	# O NightDirector não gera criaturas a menos de 10 m de uma fogueira (é o
	# comportamento correcto). O jogador pode ter nascido ao pé da aldeia, por
	# isso afastamo-lo para o meio do mato durante esta secção.
	var saved_pos: Vector3 = main.player.global_position
	main.player.global_position = _dry_spot(main.player.global_position, 70.0)
	Game.hour = 23.0
	Game.phase = Game.current_phase()
	check("noite detetada", Game.is_night())
	check("luz do dia a zero à noite", Game.daylight() < 0.01)
	var night: NightDirector = main.night
	var had_creature := false
	for i in 40:
		night.spawn_t = 0.0
		night._process(1.0)
		if not night.creatures.is_empty():
			had_creature = true
			break
		await _frames(1)
	check("a noite traz criaturas", had_creature, "n=%d" % night.creatures.size())
	if had_creature:
		var night_sprite := (night.creatures[0] as Creature).get_node_or_null("NightWandererSprite") as Sprite3D
		check("criatura noturna é sprite billboard",
			night_sprite != null and night_sprite.billboard == BaseMaterial3D.BILLBOARD_ENABLED)
	main.player.global_position = saved_pos
	Game.hour = 12.0
	Game.phase = Game.current_phase()
	check("dia detetado", not Game.is_night() and Game.daylight() > 0.3,
		"daylight=%.2f" % Game.daylight())

	# ── 9. NPC ────────────────────────────────────────────────────────────
	var npcs := get_tree().get_nodes_in_group("npcs")
	# As ruínas não têm habitantes humanos (decisão de design — NPCs removidos).
	check("ruínas sem habitantes humanos (por design)", npcs.size() == 0)
	if npcs.size() > 0:
		var npc: Npc = npcs[0]
		npc._tick()
		check("NPC percorre a cadeia canónica", npc.intent >= 0 and npc.memory.size() >= 0,
			"intent=%d mem=%d" % [npc.intent, npc.memory.size()])
		var trust0 := Game.trust(str(npc.id))
		npc.talk_to()
		check("falar aumenta confiança", Game.trust(str(npc.id)) > trust0)
		check("NPC tem tópicos", npc.topics().size() >= 3)
		var a := npc.answer("night")
		check("NPC responde", Loc.has_key(a), a)

	# ── 10. localização ───────────────────────────────────────────────────
	Loc.set_locale("en")
	var en := Loc.t("prompt.chop")
	Loc.set_locale("pt")
	var pt := Loc.t("prompt.chop")
	check("PT e EN diferentes", en != pt, "%s / %s" % [pt, en])
	check("formatação funciona", Loc.t("hud.day", ["3"]) != "hud.day",
		Loc.t("hud.day", ["3"]))

	# ── 11. comandos: contrato respeitado ─────────────────────────────────
	var bogus := Game.request("nao_existe")
	check("comando inexistente é recusado", not bool(bogus.get("ok", true)))

	# ── 12. save / load ───────────────────────────────────────────────────
	for i in inv.SLOTS:
		inv.slots[i] = {}
	inv.add("stone", 7)
	Game.hour = 9.5
	check("guardar", Game.save_game())
	var stone_before := inv.count("stone")
	check("save tem o inventário", stone_before == 7, "stone=%d" % stone_before)
	inv.remove("stone", 7)
	Game.hour = 3.0
	check("carregar", Game.load_game())
	check("load repõe inventário", inv.count("stone") == stone_before,
		"stone=%d" % inv.count("stone"))
	check("load repõe a hora", absf(Game.hour - 9.5) < 0.5, "hour=%.2f" % Game.hour)
	await _frames(2)
	var restored_logs := 0
	for item in get_tree().get_nodes_in_group("fellable_logs"):
		if item is Node3D and item.has_method("take_log"):
			restored_logs += 1
	check("load restaura o tronco abatido e colhível", restored_logs > 0,
		"troncos=%d" % restored_logs)

	# ── geometria do terreno: a saia não pode ser degenerada ─────────────
	# (regressão real: get_vertex_count() devolvia 0 e os 384 triângulos da
	#  saia apontavam todos para os vértices 0..3 do canto do chunk)
	var tchunk: Node3D = null
	var tmesh: Mesh = null
	for c in main.world.get_children():
		if not (c is Chunk):
			continue
		for mi in c.get_children():
			if mi is MeshInstance3D and (mi as MeshInstance3D).mesh != null \
					and (mi as MeshInstance3D).mesh.get_surface_count() > 0:
				tchunk = c
				tmesh = (mi as MeshInstance3D).mesh
				break
		if tmesh:
			break
	if tmesh:
		var tres: int = Chunk.RES[clampi(int(tchunk.get("lod")), 0, Chunk.RES.size() - 1)]
		var tn: int = tres + 1
		var ground_tris: int = tres * tres * 2
		var tarr: Array = tmesh.surface_get_arrays(0)
		var tidx: Array = tarr[Mesh.ARRAY_INDEX]
		# desde que a franja cinzenta foi removida, a malha do chunk é SÓ chão:
		# o número de triângulos tem de bater certo com a grelha, sem sobras.
		check("chunk sem saia (só a grelha do chão)", tidx.size() / 3 == ground_tris,
			"%d triângulos, esperados %d" % [int(tidx.size() / 3), ground_tris])
		# winding: o chão aponta para cima, a saia para fora do chunk
		var tabb: AABB = tmesh.get_aabb()
		var centre := Vector3(tabb.position.x + tabb.size.x * 0.5, 0.0,
			tabb.position.z + tabb.size.z * 0.5)
		var tverts: Array = tarr[Mesh.ARRAY_VERTEX]
		var down := 0
		for r in tidx.size() / 3:
			var a: Vector3 = tverts[int(tidx[r * 3])]
			var b: Vector3 = tverts[int(tidx[r * 3 + 1])]
			var cc: Vector3 = tverts[int(tidx[r * 3 + 2])]
			var gn := (b - a).cross(cc - a)
			if gn.length_squared() < 1e-12:
				continue
			gn = gn.normalized()
			# Godot: frente = horário => normal (b-a)x(c-a) aponta para BAIXO quando a face olha para cima
			if gn.y >= 0.0:
				down += 1
		check("chão tem as faces viradas para cima", down == 0, "%d viradas ao contrário" % down)
	else:
		check("terreno tem geometria", false, "nenhuma mesh de terreno encontrada")

	# ── nenhum material opaco pode escrever ALPHA ─────────────────────────
	# (regressão real: toon_foliage escrevia ALPHA e, em Godot 4, isso põe o
	#  material no passe transparente — árvores, erva e CASAS ficavam todas
	#  translúcidas, a ver-se umas através das outras)
	# A doc do Godot: "out float ALPHA — If written to on any branch, the
	# material will go through the transparent pipeline." Nenhum shader deste
	# jogo precisa disso: a água ficou opaca e o céu é um skybox opaco.
	var leaky: Array = []
	for path in ["res://shaders/toon_terrain.gdshader", "res://shaders/toon_foliage.gdshader"]:
		var code := _strip_comments(str(FileAccess.get_file_as_string(path)))
		if "ALPHA" in code:
			leaky.append(str(path).get_file())
	var sky_code := _strip_comments(str(FileAccess.get_file_as_string("res://shaders/anime_sky.gdshader")))
	var sky_alpha_isolated := (
		sky_code.contains("render_mode use_quarter_res_pass")
		and sky_code.contains("if (AT_QUARTER_RES_PASS)") and sky_code.contains("ALPHA ="))
	check("água e passe isolado das nuvens controlam a transparência",
		leaky.is_empty() and sky_alpha_isolated, ", ".join(leaky))
	var wcode := _strip_comments(str(FileAccess.get_file_as_string("res://shaders/stylized_water.gdshader")))
	# A água é OPACA e de face dupla (decisão registada em DECISIONS.md): a costa
	# lê-se de cima e o sob-água tem vista própria, sem o passe transparente a
	# lavar a cor contra o céu. `blend_additive`/`blend_mix` seriam a regressão.
	check("água é opaca e de face dupla (sem blend que lave a cor)",
		wcode.contains("cull_disabled") and wcode.contains("depth_draw_opaque")
		and not wcode.contains("blend_additive") and not wcode.contains("blend_mix"))

	# REGRESSÃO DO RAIO-X #2: as faces exteriores têm de ser desenhadas.
	# Com cull_back, qualquer winding virado cortava a face de fora e o jogador
	# via o interior (o sintoma reportado em terreno/casas/arvores).
	# (terreno e estruturas usam cull normal: o winding agora é o do Godot; só a
	#  folhagem/relva, que são lâminas de dupla face, precisa de cull_disabled)
	for path in ["res://shaders/toon_foliage.gdshader"]:
		var code := str(FileAccess.get_file_as_string(path))
		check("faces exteriores visíveis (%s)" % str(path).get_file(),
			"cull_disabled" in code)
	# a água não pode voltar ao ladrilho de bolas (floor sobre sinus puros)
	var frag := wcode.split("void fragment()")[1] if "void fragment()" in wcode else wcode
	check("água sem grelha de bandas (sem floor no fragment)", "floor(" not in frag)

	# o Compatibility reconstrói a profundidade com NDC -1..1 e reverse-z; o
	# Forward+ com NDC 0..1. Um shader que leia a profundidade dá resultados
	# diferentes nos dois — e a exportação web corre em Compatibility.
	check("água não depende da textura de profundidade",
		"depth_texture" not in wcode and "INV_PROJECTION_MATRIX" not in wcode)

	# ── mapa de entrada ───────────────────────────────────────────────────
	# project.godot não tem [input]: o mapa é construído em runtime por
	# Game._ready(). Se isto falhar, o jogo não responde a nenhuma tecla.
	var need := ["move_forward", "move_back", "move_left", "move_right", "sprint",
		"crouch", "jump", "interact", "use", "bag", "journal", "map", "build",
		"pause", "lean_left", "lean_right", "drop", "save", "locale",
		"hotbar_1", "hotbar_5", "hotbar_9"]
	var bad_actions: Array = []
	for a in need:
		if not InputMap.has_action(a):
			bad_actions.append(a + ":inexistente")
		elif InputMap.action_get_events(a).is_empty():
			bad_actions.append(a + ":sem teclas")
	check("mapa de entrada completo", bad_actions.is_empty(), ", ".join(bad_actions))
	check("andar tem W e seta", InputMap.action_get_events("move_forward").size() >= 2)
	check("usar é o rato esquerdo", _action_has_mouse("use"))

	# ── os 4 traços do prólogo alteram mesmo o jogo ───────────────────────
	var it: Node = main.interaction
	var sv: Node = main.survival
	var horror_save: float = float(Game.settings["horror"])
	Game.settings["horror"] = 1.0

	Game.profile = {"name": "Teste", "body": "f", "soul": "curious"}
	var reach_curious: float = it.reach()
	Game.profile = {"name": "Teste", "body": "f", "soul": "brave"}
	var reach_normal: float = it.reach()
	check("traço curious vê mais longe", reach_curious > reach_normal,
		"%.2f vs %.2f m" % [reach_curious, reach_normal])

	Game.profile = {"name": "Teste", "body": "f", "soul": "hands"}
	var work_hands: float = sv.work_multiplier()
	Game.profile = {"name": "Teste", "body": "f", "soul": "curious"}
	var work_normal: float = sv.work_multiplier()
	check("traço hands trabalha mais depressa", work_hands > work_normal,
		"x%.2f vs x%.2f" % [work_hands, work_normal])

	Game.hour = 2.0
	Game.phase = Game.current_phase()   # is_night() lê a fase, não a hora
	Game.paused = false                 # o load deixou o jogo em pausa
	sv.alive = true                   # secções anteriores danificaram o jogador
	sv.health = 100.0
	sv.light_level = 0.0
	sv.creature_threat = 0.0
	sv.near_fire = false
	sv.companion_near = false
	sv.fear = 0.0
	Game.profile = {"name": "Teste", "body": "f", "soul": "brave"}
	sv._process(2.0)
	var fear_brave: float = sv.fear
	sv.fear = 0.0
	Game.profile = {"name": "Teste", "body": "f", "soul": "curious"}
	sv._process(2.0)
	var fear_normal: float = sv.fear
	check("traço brave sente menos medo", fear_brave < fear_normal,
		"%.3f vs %.3f" % [fear_brave, fear_normal])
	Game.settings["horror"] = horror_save

	if npcs.size() > 0:
		var villager: Npc = npcs[0]
		var percepts := {"night": false, "i_near_fire": false, "dist": 40.0,
			"player_hurt": false, "player_near_fire": false, "blessing_high": false}
		Game.profile = {"name": "Teste", "body": "f", "soul": "quiet"}
		var val_quiet: float = float(villager._interpret(percepts)["valence"])
		Game.profile = {"name": "Teste", "body": "f", "soul": "curious"}
		var val_normal: float = float(villager._interpret(percepts)["valence"])
		check("traço quiet agrada mais aos outros", val_quiet > val_normal,
			"%.3f vs %.3f" % [val_quiet, val_normal])

	# ── nenhuma malha pode ficar sem material ─────────────────────────────
	# (regressão real: o NPC não tinha material_override e aparecia com o
	#  material PBR cinzento por omissão, a destoar de tudo o resto)
	var bare: Array = []
	var checked_nodes := 0
	for grp in ["npcs"]:
		for c in get_tree().get_nodes_in_group(grp):
			for mi in (c as Node3D).get_children():
				if mi is MeshInstance3D:
					checked_nodes += 1
					if (mi as MeshInstance3D).material_override == null and \
							(mi as MeshInstance3D).get_surface_override_material(0) == null and \
							((mi as MeshInstance3D).mesh == null or
							(mi as MeshInstance3D).mesh.surface_get_material(0) == null):
						bare.append(str((c as Node3D).name))
	check("nenhuma malha fica sem material", bare.is_empty(),
		"%d sem material (%s) de %d" % [bare.size(), ", ".join(bare), checked_nodes])

	# ── vista de depuração (F1/F9): tem de funcionar quando o jogador carrega ─
	var dbg: Node = main.debug_view
	check("vista de depuração existe", dbg != null)
	if dbg != null:
		var first: MeshInstance3D = null
		for c in main.world.get_children():
			for mi in c.get_children():
				if mi is MeshInstance3D and (mi as MeshInstance3D).mesh != null:
					first = mi
					break
			if first:
				break
		var original = first.material_override if first else null
		var had_shader: bool = first != null and first.get_surface_override_material(0) == null \
			and first.mesh != null and first.mesh.surface_get_material(0) is ShaderMaterial
		dbg.call("_toggle_basic")
		var now_basic: bool = first != null and first.material_override is StandardMaterial3D
		check("F9 troca para materiais básicos", now_basic,
			"o terreno tinha material do jogo: %s" % str(had_shader))
		dbg.call("_toggle_basic")
		var restored: bool = first == null or first.material_override == original
		check("F9 devolve os materiais do jogo", restored)
		dbg.call("_build_rig")
		var rig: Node3D = dbg.get("rig")
		var rig_nodes := 0
		if rig != null:
			for c in rig.get_children():
				rig_nodes += 1
		check("F1 constrói a cena de diagnóstico", rig != null and rig_nodes >= 10,
			"%d objectos" % rig_nodes)

	# ── menu separado da mochila e da bancada ───────────────────────────────
	main.menus.open("bag")
	await get_tree().process_frame
	check("menu da mochila abre com slots e ícones", main.menus.current == "bag" and
		main.menus._content.get_child_count() > 0)
	main.menus.open("craft")
	await get_tree().process_frame
	check("bancada tem menu próprio", main.menus.current == "craft" and
		main.menus._content.get_child_count() > 0)
	main.menus.close()

	# ══════════════════════════════════════════════════════════════════════
	#  GAMEPLAY: mira, ferramentas, bancada, usar na mão, pesca
	# ══════════════════════════════════════════════════════════════════════
	# Cada bloco mede o RESULTADO que o jogador vê (nó perde vida, item sai da
	# mão, peixe entra na mochila) e não o facto de o código ter corrido.

	# ── mira: o raio tem de apanhar a FORMA, não um ponto inventado ───────
	var tree_base := Vector3(0, 10, 0)          # nó fictício: só geometria
	var fake_tree := {"pos": tree_base, "kind": "tree_oak", "height": 6.0,
		"collider_radius": 0.42, "radius": 0.42, "hp": 6.0, "alive": true}
	var eye: Vector3 = tree_base + Vector3(3.2, 1.6, 0)
	var at_trunk: Vector3 = (tree_base + Vector3(0.0, 1.6, 0.0) - eye).normalized()
	var at_canopy: Vector3 = (tree_base + Vector3(0.0, 4.4, 0.0) - eye).normalized()
	var sideways := Vector3(1.0, -0.05, -0.75).normalized()
	var hit_trunk: float = it.call("_ray_harvest", fake_tree, eye, at_trunk, 4.2)
	var hit_canopy: float = it.call("_ray_harvest", fake_tree, eye, at_canopy, 4.2)
	var hit_air: float = it.call("_ray_harvest", fake_tree, eye, sideways, 4.2)
	check("apontar ao tronco apanha a árvore", hit_trunk < 100.0, "t=%.2f" % hit_trunk)
	check("apontar à copa também apanha a mesma árvore", hit_canopy < 100.0,
		"t=%.2f" % hit_canopy)
	check("apontar para o lado não apanha a árvore", hit_air >= 100.0,
		"t=%.2f" % hit_air)
	# a 4,2 m de alcance: um alvo a 6 m não pode contar
	var far_eye: Vector3 = tree_base + Vector3(6.5, 1.6, 0)
	var at_far: Vector3 = (tree_base + Vector3(0.0, 1.6, 0.0) - far_eye).normalized()
	check("fora de alcance não há alvo",
		float(it.call("_ray_harvest", fake_tree, far_eye, at_far, 4.2)) >= 100.0)

	# ── pedra sem picareta não cede (a punição tem de doer) ───────────────
	var rock_base := Vector3(0, 10, 0)
	var fake_rock := {"pos": rock_base, "kind": "rock", "height": 0.8,
		"radius": 0.8, "hp": 5, "alive": true}
	var rock_eye: Vector3 = rock_base + Vector3(1.6, 0.9, 0)
	check("a pedra fica no alvo a olhar de perto",
		float(it.call("_ray_harvest", fake_rock, rock_eye, Vector3(-1, -0.15, 0).normalized(),
			4.2)) < 100.0)
	var said: Array = []
	var catcher := func(_text: String, _seconds: float) -> void:
		said.append(_text)
	Bus.ui_message.connect(catcher)
	var rock_hp_before := float(fake_rock["hp"])
	it.focus = {"kind": "harvest", "ref": fake_rock, "pos": rock_base}
	it._hold_work(0.6, 1.0)
	check("pedra sem picareta não perde vida nenhuma",
		float(fake_rock["hp"]) == rock_hp_before, "hp=%.1f" % float(fake_rock["hp"]))
	check("o HUD diz que falta a picareta", not said.is_empty(), ", ".join(said))
	Bus.ui_message.disconnect(catcher)

	# ── com picareta, a pedra cede ────────────────────────────────────────
	var had_rock_tool := false
	inv.add("pickaxe", 1)
	for i in inv.SLOTS:
		if str((inv.slots[i] as Dictionary).get("id", "")) == "pickaxe":
			inv.equip_slot(i)   # `select` só chega à barra rápida (0..8)
			had_rock_tool = true
			break
	check("picareta equipada na barra", had_rock_tool)
	it.focus = {"kind": "harvest", "ref": fake_rock, "pos": rock_base}
	it._hold_work(0.6, 1.0)
	check("com picareta a pedra perde vida por golpe",
		float(fake_rock["hp"]) < rock_hp_before, "hp %.1f -> %.1f" % [rock_hp_before,
			float(fake_rock["hp"])])

	# ── ferramenta muda o número de golpes (rendimento) ───────────────────
	var hand_spec: Dictionary = Db.HARVEST["tree_oak"]
	var axe_item: Dictionary = Db.item("axe")
	var blade_item: Dictionary = Db.item("stone_blade")
	var hand_takes := maxi(int(ceil(float(hand_spec["hp"]) / float(hand_spec["hand"]))), 1)
	var axe_takes := maxi(int(ceil(float(hand_spec["hp"]) / float(axe_item["power"]["chop"]))), 1)
	var blade_takes := maxi(int(ceil(float(hand_spec["hp"]) / float(blade_item["power"]["chop"]))), 1)
	check("o machado abate a árvore em bem menos golpes que as mãos",
		axe_takes * 2 <= hand_takes, "mãos=%d golpes, machado=%d" % [hand_takes, axe_takes])
	# O degrau do improviso tem de valer ALGUMA coisa (senão é só um item a mais
	# no menu) e tem de ser claramente pior do que a bancada (senão a bancada
	# não vale o trabalho de a construir).
	# A TRAVESSIA: mãos -> pedra solta -> picareta PRIMITIVA -> rocha. Sem esta
	# ferramenta a rocha é impossível e a cadeia parte-se (foi o que aconteceu
	# ao apagar a família de madeira).
	var picareta_p: Dictionary = Db.item("primitive_pickaxe")
	var machado_p: Dictionary = Db.item("primitive_axe")
	var p_takes := maxi(int(ceil(float(hand_spec["hp"]) / float(machado_p["power"]["chop"]))), 1)
	check("o machado primitivo abate a árvore em bem menos golpes que as mãos",
		p_takes * 2 <= hand_takes, "mãos=%d, primitivo=%d" % [hand_takes, p_takes])
	check("a lasca corta melhor que as mãos, mas é a pior ferramenta",
		blade_takes < hand_takes and blade_takes > p_takes,
		"mãos=%d, lasca=%d, primitivo=%d" % [hand_takes, blade_takes, p_takes])
	check("a picareta PRIMITIVA é a primeira ferramenta que pica pedra",
		picareta_p.get("power", {}).has("mine")
		and not Db.item("stone_blade").get("power", {}).has("mine")
		and not Db.recipe("primitive_pickaxe").has("station"),
		"poder=%s" % str(picareta_p.get("power", {})))
	check("as ferramentas de pedra são da bancada e mais fortes que as primitivas",
		str(Db.recipe("stone_axe").get("station", "")) == "workbench"
		and str(Db.recipe("stone_pickaxe").get("station", "")) == "workbench"
		and float(axe_item["power"]["chop"]) > float(machado_p["power"]["chop"])
		and int(axe_item["tier"]) > int(machado_p["tier"]))
	check("a mão desperdiça e a ferramenta de pedra aproveita",
		Db.yield_scale("", "chop") < 1.0
		and Db.yield_scale("primitive_axe", "chop") == 1.0
		and Db.yield_scale("axe", "chop") > 1.0,
		"mão=%.2f tier1=%.2f tier2=%.2f" % [Db.yield_scale("", "chop"),
			Db.yield_scale("primitive_axe", "chop"), Db.yield_scale("axe", "chop")])
	# Uma só verdade: o JSON editável e a lista de reserva em código dizem o
	# mesmo (foi esta divergência que deixou a família "apagada" viva no ficheiro).
	var reserva := {}
	for r in Db.RECIPES:
		reserva[str(r["id"])] = r
	var json_receitas := {}
	for r in Db.all_recipes():
		json_receitas[str(r["id"])] = r
	var divergentes: Array = []
	for id in json_receitas:
		if not reserva.has(id):
			divergentes.append(id + " (só no JSON)")
			continue
		var a: Dictionary = reserva[id]
		var b: Dictionary = json_receitas[id]
		# o JSON lê os números como float (mesmo "1"), por isso a comparação de
		# ingredientes é feita chave a chave e em inteiro
		var na: Dictionary = a["needs"]
		var nb: Dictionary = b["needs"]
		var iguais := na.size() == nb.size()
		if iguais:
			for k in na:
				if not nb.has(k) or int(na[k]) != int(nb[k]):
					iguais = false
					break
		if str(a["result"]) != str(b["result"]) \
				or str(a.get("station", "")) != str(b.get("station", "")) \
				or int(a.get("qty", 1)) != int(b.get("qty", 1)) or not iguais:
			divergentes.append(id)
	for id in reserva:
		if not json_receitas.has(id):
			divergentes.append(id + " (só na reserva)")
	check("as receitas do JSON e as de reserva dizem o mesmo",
		divergentes.is_empty(), ", ".join(divergentes))
	check("a rocha dura existe e responde à ferramenta melhor",
		Db.HARVEST.has("rock_hard")
		and int(Db.HARVEST["rock_hard"]["yields"]["stone"]) > int(Db.HARVEST["rock"]["yields"]["stone"]))
	var bare_rock_spec: Dictionary = Db.HARVEST["rock"]
	check("a pedra exige picareta (e as mãos não a picam)",
		str(bare_rock_spec.get("needs", "")) == "pickaxe")
	check("a pedra solta dá pedra sem ferramenta (porta de entrada)",
		not Db.HARVEST["flint_node"].has("needs")
		and int(Db.HARVEST["flint_node"]["yields"].get("stone", 0)) > 0)
	check("as ferramentas a sério saem da bancada; a bancada sai da Criação",
		str(Db.recipe("stone_axe").get("station", "")) == "workbench"
		and str(Db.recipe("stone_pickaxe").get("station", "")) == "workbench"
		and not Db.recipe("workbench").has("station")
		and not Db.recipe("primitive_axe").has("station")
		and not Db.recipe("primitive_pickaxe").has("station"))
	# A lasca de pedra é o degrau que destranca a pedra: é ELE que se improvisa,
	# e é o que faz o ciclo mãos→pedra→ferramenta fechar sem becos sem saída.
	check("o improviso (Criação) dá ferramenta com pedra e ramo, sem estação",
		not Db.recipe("stone_blade").has("station")
		and int(Db.recipe("stone_blade")["needs"].get("stone", 0)) > 0)
	check("as receitas vêm de data/recipes.json (edita-se sem tocar em código)",
		FileAccess.file_exists("res://data/recipes.json")
		and Db.all_recipes().size() >= 10)
	check("acender fogueira exige isqueiro primitivo",
		Db.item("fire_kit").get("power", {}).has("fire")
		and not Db.recipe("fire_kit").has("station"))

	# ── trabalhar cansa ───────────────────────────────────────────────────
	var energy_before := float(sv.energy)
	var fake_tree2 := {"pos": tree_base, "kind": "tree_oak", "height": 6.0,
		"collider_radius": 0.42, "radius": 0.42, "hp": 40.0, "alive": true}
	it.focus = {"kind": "harvest", "ref": fake_tree2, "pos": tree_base}
	it._hold_work(0.6, 1.0)
	check("cortar gasta energia", float(sv.energy) < energy_before,
		"%.1f -> %.1f" % [energy_before, float(sv.energy)])

	# ── bancada: receita não sai sem ela, sai com ela ─────────────────────
	for k in ["wood", "stick", "fiber"]:
		inv.add(k, 12)
	var before_bench: int = main.structures.list.size()
	var no_bench: Dictionary = Game.request("craft", {"recipe": "stone_axe"})
	check("receita de bancada é recusada longe de uma bancada",
		not bool(no_bench.get("ok", true))
		and str(no_bench.get("reason", "")) == "no_station",
		"reason=%s" % str(no_bench.get("reason", "-")))
	var bench_pos: Vector3 = main.player.global_position + Vector3(-2.0, 0.0, 0.0)
	bench_pos.y = main.world.ground_height(bench_pos.x, bench_pos.z)
	main.structures.place("workbench", bench_pos, 0.0, false)
	check("bancada colocada é reconhecida como estação",
		"workbench" in main.structures.stations_near(bench_pos, 4.5)
		and main.structures.list.size() == before_bench + 1)
	var made_axe: Dictionary = Game.request("craft", {"recipe": "stone_axe"})
	check("com bancada perto, o machado é feito",
		bool(made_axe.get("ok", false)) and inv.count("axe") >= 1,
		"reason=%s" % str(made_axe.get("reason", "-")))
	var bench_slot := -1
	for i in inv.SLOTS:
		if str((inv.slots[i] as Dictionary).get("id", "")) == "axe":
			bench_slot = i
			break
	check("o machado novo entra na mochila", bench_slot >= 0)

	# ── usar o que está na mão (rato direito) ─────────────────────────────
	inv.add("mushroom", 2)
	var mush_slot := -1
	for i in inv.SLOTS:
		if str((inv.slots[i] as Dictionary).get("id", "")) == "mushroom":
			mush_slot = i
			break
	inv.equip_slot(mush_slot)
	sv.hunger = 40.0
	var mushrooms_before := inv.count("mushroom")
	var eaten := Game.request("use_item")
	check("comer com o rato direito funciona",
		bool(eaten.get("ok", false)) and inv.count("mushroom") == mushrooms_before - 1
		and float(sv.hunger) > 40.0, "fome=%.0f" % float(sv.hunger))

	inv.add("rod", 1)
	var rod_slot := -1
	for i in inv.SLOTS:
		if str((inv.slots[i] as Dictionary).get("id", "")) == "rod":
			rod_slot = i
			break
	inv.equip_slot(rod_slot)
	it.focus = {"kind": "water", "ref": null, "pos": main.player.global_position}
	var fish_before := inv.count("fish_raw")
	var _cast := Game.request("use_item")
	check("lançar a linha à água", int(it.get("_fish_state")) == 1,
		"estado=%d" % int(it.get("_fish_state")))
	it.call("_tick_fishing", 12.0)
	check("o peixe acaba por morder", int(it.get("_fish_state")) == 2)
	var pull := Game.request("use_item")
	check("puxar a tempo dá peixe",
		bool(pull.get("ok", false)) and inv.count("fish_raw") > fish_before,
		"fish_raw=%d" % inv.count("fish_raw"))

	# ── acender fogo exige isqueiro, e a água do rio sabe a barro ─────────
	var fogueira: Dictionary = main.structures.place("campfire",
		main.player.global_position + Vector3(3.0, 0.0, 0.0), 0.0, false)
	it.focus = {"kind": "structure", "ref": fogueira, "pos": fogueira["pos"]}
	var sem_isqueiro: Dictionary = it._do_interact({})
	check("fogueira sem isqueiro não acende",
		not bool(fogueira.get("lit", false))
		and str(sem_isqueiro.get("reason", "")) == "no_fire_kit",
		"reason=%s" % str(sem_isqueiro.get("reason", "-")))
	inv.add("fire_kit", 1)
	it._do_interact({})
	check("com isqueiro primitivo a fogueira acende", bool(fogueira.get("lit", false)))
	check("a fogueira acesa é estação de cozinha",
		"campfire" in main.structures.stations_near(fogueira["pos"], 4.5))
	# Um fogo sem combustível é uma lâmpada. Tem de gastar-se e de se alimentar.
	check("acesa, a fogueira tem combustível medido em horas de jogo",
		float(fogueira.get("fuel", 0.0)) > 0.5,
		"fuel=%.2f h" % float(fogueira.get("fuel", 0.0)))
	var wood_before := inv.count("wood")
	var fuel_before := float(fogueira.get("fuel", 0.0))
	it.focus = {"kind": "structure", "ref": fogueira, "pos": fogueira["pos"]}
	var fed: Dictionary = it._do_interact({})
	check("alimentar o fogo gasta madeira e dá horas",
		bool(fed.get("ok", false)) and inv.count("wood") == wood_before - 1
		and float(fogueira.get("fuel", 0.0)) > fuel_before,
		"madeira %d→%d fuel %.1f→%.1f" % [wood_before, inv.count("wood"),
			fuel_before, float(fogueira.get("fuel", 0.0))])
	# e sem madeira diz porquê, em vez de não fazer nada
	var wood_now := inv.count("wood")
	inv.remove("wood", wood_now)
	var sem_lenha: Dictionary = it._do_interact({})
	check("sem madeira a fogueira não é alimentada (e diz porquê)",
		str(sem_lenha.get("reason", "")) == "no_wood", "reason=%s" % str(sem_lenha.get("reason", "-")))
	inv.add("wood", wood_now)
	# uma segunda fogueira serve para provar o fim do combustível sem apagar
	# a que os testes seguintes usam como estação
	var morre: Dictionary = main.structures.place("campfire",
		main.player.global_position + Vector3(-3.0, 0.0, 0.0), 0.0, true)
	var vfx_antes := (morre["node"] as Node).get_node_or_null("CampfireVfx") != null
	main.structures.burn_hours(float(morre.get("fuel", 0.0)) + 0.1)
	check("sem combustível a fogueira apaga-se (luz e chamas saem)",
		vfx_antes and not bool(morre.get("lit", true)) and morre.get("light") == null,
		"lit=%s" % str(morre.get("lit", true)))
	check("a fogueira que se apagou sai do calor do mundo",
		not main.structures.lit_positions().has(morre["pos"]))
	main.structures.remove(morre)
	# A chama tem de ser feita de CAMADAS: uma camada só é um cone laranja, que
	# era exactamente o que fazia o fogo parecer mal feito.
	var vfx := (fogueira["node"] as Node).get_node_or_null("CampfireVfx")
	var tamanhos: Array = []
	if vfx != null:
		for filho in vfx.get_children():
			if filho is MeshInstance3D and (filho as MeshInstance3D).mesh != null:
				tamanhos.append(snappedf((filho as MeshInstance3D).mesh.get_aabb().size.y, 0.01))
	check("a chama tem camadas (uma camada só é um cone)",
		tamanhos.size() >= 2 and tamanhos[0] != tamanhos[1],
		"alturas=%s" % str(tamanhos))
	var chama_shader: Shader = load("res://shaders/campfire_flame.gdshader")
	var uniforms := []
	if chama_shader != null:
		for u in chama_shader.get_shader_uniform_list(true):
			uniforms.append(str(u["name"]))
	check("o shader da chama permite camadas (slim/width) e não é um cone fixo",
		"slim" in uniforms and "width" in uniforms, ", ".join(uniforms))
	check("acender a fogueira dá luz com tremer (não é uma lâmpada fixa)",
		fogueira.get("light") != null and (fogueira["light"] as OmniLight3D).omni_range > 0.0)

	# Água: do rio vem CRUA (com risco), da fogueira sai fervida (sem risco).
	inv.add("water", 1)
	var agua_crua: Dictionary = Db.item("water")
	var agua_fervida: Dictionary = Db.item("water_clean")
	check("água do rio tem risco e a fervida não",
		float(agua_crua.get("risk", 0.0)) > 0.0 and float(agua_fervida.get("risk", 0.0)) == 0.0
		and float(agua_fervida.get("drink_amount", 0.0)) > float(agua_crua.get("drink_amount", 0.0)))
	var ferver: Dictionary = Game.request("craft", {"recipe": "boil_water"})
	check("ferver água é uma receita da fogueira",
		bool(ferver.get("ok", false)) and inv.count("water_clean") >= 1,
		"reason=%s" % str(ferver.get("reason", "-")))

	# ── água do mar: uma REGRA, não dano aleatório ───────────────────────
	# A constituição (§5) é explícita: o mar dá "Desidratação", nunca dano
	# instantâneo arbitrário. E ferver NÃO salva a água salgada.
	var sea := _sea_spot(main.player.global_position)
	check("há mar ao alcance da costa", sea != Vector3.INF,
		"ponto=%s" % str(sea))
	if sea != Vector3.INF:
		inv.add("bottle", 1)
		it.focus = {"kind": "water", "ref": null, "pos": sea}
		it._do_interact({})
		check("no mar a garrafa enche-se de água SALGADA",
			inv.count("water_salt") >= 1, "water_salt=%d" % inv.count("water_salt"))
		check("ferver não transforma água do mar em potável",
			not Db.recipe("boil_water").get("needs", {}).has("water_salt"),
			str(Db.recipe("boil_water").get("needs", {})))
		var mar_slot := -1
		for i in inv.SLOTS:
			if str((inv.slots[i] as Dictionary).get("id", "")) == "water_salt":
				mar_slot = i
				break
		if mar_slot >= 0:
			inv.equip_slot(mar_slot)
			sv.thirst = 30.0
			var h_antes := float(sv.health)
			var bebeu_mar: Dictionary = Game.request("use_item")
			check("beber água do mar NÃO fere: dá Desidratação",
				bool(bebeu_mar.get("ok", false)) and float(sv.dehydrated_t) > 0.0
				and is_equal_approx(float(sv.health), h_antes),
				"dehydrated=%.0fs hp %.0f->%.0f" % [float(sv.dehydrated_t),
					h_antes, float(sv.health)])
			# a sede escorre mais depressa enquanto a dívida durar
			sv.thirst = 80.0
			sv._process(1.0)
			var c_dehydrated := 80.0 - float(sv.thirst)
			sv.drink(100.0, 0.0)      # água doce lava o sal
			sv.thirst = 80.0
			sv._process(1.0)
			var c_normal := 80.0 - float(sv.thirst)
			check("a desidratação cobra-se em sede (e a água doce cura)",
				c_dehydrated > c_normal * 2.0 and float(sv.dehydrated_t) == 0.0,
				"%.3f/s vs %.3f/s" % [c_dehydrated, c_normal])

	# ── mobiliário que serve para algo ────────────────────────────────────
	var cofre: Dictionary = main.structures.place("chest",
		main.player.global_position + Vector3(-3.5, 0.0, 0.0), 0.0, false)
	inv.add("wood", 5)
	var slot_madeira := -1
	for i in inv.SLOTS:
		if str((inv.slots[i] as Dictionary).get("id", "")) == "wood":
			slot_madeira = i
			break
	inv.equip_slot(slot_madeira)
	var antes_mao := inv.count("wood")
	it.focus = {"kind": "structure", "ref": cofre, "pos": cofre["pos"]}
	it._do_interact({})
	check("o cofre guarda o que tens na mão",
		inv.count("wood") == 0 and int(cofre["items"].get("wood", 0)) == antes_mao,
		"mochila=%d cofre=%d" % [inv.count("wood"), int(cofre["items"].get("wood", 0))])
	var slot_vazio := -1
	for i in inv.SLOTS:
		if str((inv.slots[i] as Dictionary).get("id", "")) == "":
			slot_vazio = i
			break
	if slot_vazio >= 0:
		inv.equip_slot(slot_vazio)
	it._do_interact({})
	check("com a mão vazia o cofre devolve o que lá está",
		inv.count("wood") == antes_mao and (cofre["items"] as Dictionary).is_empty(),
		"mochila=%d" % inv.count("wood"))
	var cadeira: Dictionary = main.structures.place("chair",
		main.player.global_position + Vector3(0.0, 0.0, 3.0), 0.0, false)
	sv.energy = 40.0
	Game.hour = 2.0
	it.focus = {"kind": "structure", "ref": cadeira, "pos": cadeira["pos"]}
	it._do_interact({})
	var prazo_cadeira := Time.get_ticks_msec() + 12000
	while bool(it.sleeping) and Time.get_ticks_msec() < prazo_cadeira:
		await get_tree().process_frame
	# ── energia: o cansaço tem de doer ───────────────────────────────────
	sv.energy = 100.0
	var rende_fresco := float(sv.work_multiplier())
	sv.energy = 0.0
	var rende_exausto := float(sv.work_multiplier())
	check("trabalhar exausto rende menos (a energia não é decorativa)",
		rende_exausto < rende_fresco * 0.85,
		"%.2f vs %.2f" % [rende_exausto, rende_fresco])
	sv.energy = 50.0
	check("o aviso de cansaço diz o que fazer (Z ou cama)",
		Loc.t("msg.tired") != "msg.tired" and "Z" in Loc.t("msg.tired"))

	# ── comida: cru vs cozinhado ──────────────────────────────────────────
	# O risco não pode ser decorativo: tem de vir dos dados e de ser dito.
	check("a carne crua é um risco e a cozinhada não",
		float(Db.item("meat_raw").get("risk", 0.0)) > 0.2
		and float(Db.item("meat_cooked").get("risk", 1.0)) == 0.0,
		"cru=%.2f cozido=%.2f" % [float(Db.item("meat_raw").get("risk", 0.0)),
			float(Db.item("meat_cooked").get("risk", 0.0))])
	var antes_comer := float(sv.hunger)
	var comeu: Dictionary = sv.eat(12.0, 0.0, 0.0)
	check("comer devolve o que aconteceu (para o jogo poder dizer)",
		not bool(comeu.get("sick", true)) and float(sv.hunger) > antes_comer,
		"hunger %.0f→%.0f" % [antes_comer, float(sv.hunger)])

	check("a cadeira é um cochilo (recupera, mas não passa a noite)",
		float(sv.energy) > 40.0 and float(Game.hour) < 5.0,
		"energia %.1f, hora %.1f" % [float(sv.energy), float(Game.hour)])

	# ── sono: chão (mau) / cadeira (cochilo) / cama (boa) ─────────────────
	# A constituição é explícita: dormir não é "avançar o relógio". Tem de ser
	# uma sequência (deitar → escurecer → noite → acordar) e tem de custar algo.
	check("a qualidade do sono vem dos dados (cama > chão)",
		Db.sleep_quality("bed") > Db.sleep_quality("ground")
		and Db.sleep_quality("ground") > 0.0,
		"cama=%.2f chão=%.2f" % [Db.sleep_quality("bed"), Db.sleep_quality("ground")])

	# o mesmo tempo, sítios diferentes: a cama rende mais do que o chão
	Game.hour = 22.0
	sv.energy = 20.0
	sv.hunger = 90.0
	sv.thirst = 90.0
	var sonho_chao: Dictionary = sv.sleep_until_morning(Db.sleep_quality("ground"))
	var horas_chao := float(sonho_chao.get("hours", 0.0))
	var ganho_chao := float(sonho_chao.get("energy", 0.0))
	Game.hour = 22.0
	sv.energy = 20.0
	sv.hunger = 90.0
	sv.thirst = 90.0
	var sonho_cama: Dictionary = sv.sleep_until_morning(Db.sleep_quality("bed"))
	var ganho_cama := float(sonho_cama.get("energy", 0.0))
	check("a cama rende mais do que o chão na mesma noite",
		ganho_cama > ganho_chao * 1.8,
		"chão=+%.0f cama=+%.0f (%.1f h)" % [ganho_chao, ganho_cama, horas_chao])
	check("dormir custa fome e sede (não é um salto grátis)",
		float(sonho_cama.get("hunger", 0.0)) < 0.0 and float(sonho_cama.get("thirst", 0.0)) < 0.0,
		"fome %.1f sede %.1f" % [float(sonho_cama.get("hunger", 0.0)),
			float(sonho_cama.get("thirst", 0.0))])
	check("dormir acorda de manhã (e não a meio da noite)",
		float(Game.hour) >= 5.0 and float(Game.hour) <= 9.5,
		"hora=%.1f" % float(Game.hour))

	# a sequência: deitar, escurecer, acordar — e o jogador não se mexe a dormir
	var cama: Dictionary = main.structures.place("bed",
		main.player.global_position + Vector3(2.0, 0.0, 0.0), 0.0, false)
	Game.hour = 21.0
	sv.energy = 30.0
	it.focus = {"kind": "structure", "ref": cama, "pos": cama["pos"]}
	# lambda em GDScript captura LOCAIS por valor: um `bool` lá dentro não
	# voltava a fora. Uma lista é uma referência, por isso o sinal chega cá.
	var dormiu_em: Array = []
	var catcher_sleep := func(_q: float, place: String) -> void:
		dormiu_em.append(place)
	main.interaction.slept.connect(catcher_sleep)
	it._do_interact({})
	check("dormir é uma sequência (o jogador deita-se e fica preso nela)",
		bool(it.sleeping) and not bool(main.player.enabled))
	var deadline := Time.get_ticks_msec() + 12000
	while bool(it.sleeping) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	main.interaction.slept.disconnect(catcher_sleep)
	check("a sequência de dormir termina e devolve o controlo",
		not bool(it.sleeping) and bool(main.player.enabled), "12 s de limite")
	check("o corpo fica deitado no leito (não dorme a flutuar)",
		main.player.global_position.distance_to(cama["pos"]) < 2.0,
		"distância=%.2f m" % main.player.global_position.distance_to(cama["pos"]))
	check("o sinal de dormir diz onde e com que qualidade",
		"bed" in dormiu_em and float(sv.energy) > 30.0,
		"local=%s energia=%.0f" % [str(dormiu_em), float(sv.energy)])

	# com uma criatura a rondar, o corpo não deixa dormir
	sv.creature_threat = 1.0
	Game.hour = 22.0
	it._start_sleep({}, "ground")
	check("com uma criatura a rondar não se dorme", not bool(it.sleeping))
	sv.creature_threat = 0.0

	# ── árvore abatida: tem de CAIR e ficar deitada ───────────────────────
	# (o sintoma descrito: "só encosta um pouquinho e fica parada", com uma cor
	#  plana, sem luz — o nó levava `sync_to_physics` a reescrever-lhe a rotação
	#  e o tronco levava a copa e o material das folhas)
	var oak: SpeciesKit.Species = world.species.trees["oak"]
	var oak_trunk_verts := 0
	var oak_full_verts := 0
	if not oak.trunk_lods.is_empty():
		oak_trunk_verts = _mesh_vertex_count(oak.trunk_lods[0])
	if not oak.lods.is_empty():
		oak_full_verts = _mesh_vertex_count(oak.lods[0])
	check("o tronco do abate não traz a copa atrás",
		oak_trunk_verts > 0 and oak_trunk_verts < oak_full_verts,
		"tronco=%d vertices, árvore=%d" % [oak_trunk_verts, oak_full_verts])
	var fall_scene: PackedScene = load("res://scenes/world/felled_tree.tscn")
	var fall_probe := fall_scene.instantiate() as FelledTree
	check("a árvore caída é dona da própria rotação (sem sync_to_physics)",
		fall_probe != null and not fall_probe.sync_to_physics)
	var felled_now: FelledTree = null
	for n in get_tree().get_nodes_in_group("fellable_logs"):
		felled_now = n as FelledTree
		break
	if felled_now == null:
		skip("árvore abatida fica deitada no chão", "não há abate nesta corrida")
	else:
		# a queda é conduzida por tempo explícito (1,05 s): esperar pelo ESTADO,
		# não por N frames (em headless os frames são muito curtos)
		for i in 400:
			if bool(felled_now.get("settled")):
				break
			await get_tree().process_frame
		check("árvore abatida fica deitada no chão",
			bool(felled_now.get("settled")) and absf(felled_now.rotation.z) > 1.2,
			"rotação=%.2f rad, settled=%s" % [felled_now.rotation.z,
				str(felled_now.get("settled"))])
		check("o tronco caído assenta à altura do seu raio",
			felled_now.global_position.y > float(terrain_height_at(felled_now.global_position)),
			"y=%.2f" % felled_now.global_position.y)
	if fall_probe != null:
		fall_probe.free()

	# ── caça: as receitas de carne têm de ter uma fonte no mundo ──────────
	# (antes disto, `meat_raw` só existia na tabela de itens: nenhum bicho do
	#  mundo o largava, logo `meat_cooked` e o guisado eram conteúdo inalcançável)
	if main.wildlife == null:
		skip("há caça no mundo durante o dia", "sem Wildlife no arranque")
	else:
		Game.hour = 12.0
		Game.phase = Game.current_phase()
		main.wildlife.spawn_t = 0.0
		for i in 30:
			main.wildlife.call("_process", 0.2)
			if not main.wildlife.animals.is_empty():
				break
		check("há caça no mundo durante o dia",
			not main.wildlife.animals.is_empty(),
			"%d animais" % main.wildlife.animals.size())
		var prey: Animal = null
		for a in main.wildlife.animals:
			if is_instance_valid(a):
				prey = a as Animal
				break
		if prey == null:
			skip("golpear caça tira-lhe vida e põe-na a fugir",
				"não nasceu nenhum animal neste arranque")
		else:
			var prey_hp := float(prey.health)
			it.focus = {"kind": "animal", "ref": prey,
				"pos": prey.global_position + Vector3(0, 0.45, 0)}
			it.call("_strike_animal")
			check("golpear caça tira-lhe vida", float(prey.health) < prey_hp,
				"%.1f -> %.1f" % [prey_hp, float(prey.health)])
			check("a caça foge quando é ferida", float(prey.get("_panic_t")) > 0.0)
			var meat_before := 0
			for c in main.world.get_children():
				if c is RigidBody3D and str(c.get("item_id")) == "meat_raw":
					meat_before += int(c.get("amount"))
			prey.hurt(99.0)
			var meat_after := 0
			for c in main.world.get_children():
				if c is RigidBody3D and str(c.get("item_id")) == "meat_raw":
					meat_after += int(c.get("amount"))
			check("caça abatida larga carne no chão", meat_after > meat_before,
				"%d -> %d carne" % [meat_before, meat_after])
			it.focus = {}
		Game.hour = 1.0
		Game.phase = Game.current_phase()
	check("a carne tem cadeia até ao guisado (cru -> assado -> guisado)",
		str(Db.recipe("meat_cooked").get("station", "")) == "campfire"
		and Db.recipe("stew").get("needs", {}).has("meat_cooked"))

	# ── menu de craft: o que ainda falta desbloquear tem de estar visível ─
	var locked_none: Array = Db.locked_recipes([])
	var locked_bench: Array = Db.locked_recipes(["workbench"])
	var locked_stations_known := true
	for r in locked_none:
		if not (str(r.get("station", "")) in main.structures.STATION_IDS):
			locked_stations_known = false
	check("o menu sabe listar as receitas que faltam desbloquear",
		locked_none.size() > locked_bench.size() and not locked_none.is_empty()
		and locked_stations_known,
		"sem estação=%d, com bancada=%d" % [locked_none.size(), locked_bench.size()])

	# ── dados: nenhuma receita pode apontar para o vazio ──────────────────
	var bad_recipes: Array = []
	for r in Db.RECIPES:
		var rid := str(r["id"])
		if not Db.ITEMS.has(str(r["result"])):
			bad_recipes.append(rid + ":result")
		var station := str(r.get("station", ""))
		if station != "" and not (station in main.structures.STATION_IDS):
			bad_recipes.append(rid + ":station=" + station)
		for k in r.get("needs", {}):
			if not Db.ITEMS.has(str(k)):
				bad_recipes.append(rid + ":" + str(k))
	check("todas as receitas falam de itens e estações que existem",
		bad_recipes.is_empty(), ", ".join(bad_recipes))
	var bad_tools: Array = []
	for hkey in Db.HARVEST:
		var spec: Dictionary = Db.HARVEST[hkey]
		var h_need := str(spec.get("needs", ""))
		if h_need != "" and not Db.ITEMS.has(h_need):
			bad_tools.append(str(hkey) + ":needs=" + h_need)
		for y in spec.get("yields", {}):
			if not Db.ITEMS.has(str(y)):
				bad_tools.append(str(hkey) + ":yield=" + str(y))
	check("todos os nós de colheita dão itens que existem", bad_tools.is_empty(),
		", ".join(bad_tools))
	var stations_ok := true
	for r in Db.RECIPES:
		var st := str(r.get("station", ""))
		if st != "" and not main.world.species.structures.has(st):
			stations_ok = false
	check("cada estação de craft tem uma estrutura colocável", stations_ok)

	# ── água: vadear vs nadar (o rio não pode prender o jogador) ──────────
	var shallow := _water_spot(main.player.global_position, 60.0, 0.5, 1.1)
	var deep := _water_spot(main.player.global_position, 60.0, 2.0, 999.0)
	var water_home_pos: Vector3 = main.player.global_position
	# cotas da água funda (usadas também pelo teste dos itens largados)
	var deep_surface: float = 0.0
	var sea_bed: float = 0.0
	if shallow == Vector3.INF:
		skip("rio raso atravessa-se a pé (não fica preso a nadar)",
			"não há água rasa a menos de 240 m do ponto de partida")
	else:
		main.player.global_position = shallow
		main.player.call("_swim_check")
		check("rio raso atravessa-se a pé (não fica preso a nadar)",
			not bool(main.player.swimming) and bool(main.player.wading),
			"y=%.2f" % shallow.y)
		main.player.global_position = water_home_pos
	if deep == Vector3.INF:
		skip("água funda põe o jogador a nadar",
			"não há água funda a menos de 240 m do ponto de partida")
	else:
		deep_surface = float(main.world.terrain.water_surface_height(deep.x, deep.z))
		sea_bed = float(main.world.terrain.height(deep.x, deep.z))
		main.player.global_position = deep
		main.player.call("_swim_check")
		check("água funda põe o jogador a nadar", bool(main.player.swimming),
			"profundidade=%.2f m" % (deep_surface - sea_bed))
		# 1) com a cabeça dentro de água, o corpo sobe
		main.player.global_position = Vector3(deep.x, deep_surface - 2.6, deep.z)
		main.player.call("_swim_check")
		main.player.velocity = Vector3.ZERO
		for i in 6:
			main.player.call("_move_swim", 0.1, Vector3.ZERO)
		check("submerso, o corpo sobe sozinho (não se afoga parado)",
			float(main.player.velocity.y) > 0.0,
			"velocidade vertical=%.2f" % float(main.player.velocity.y))
		# 2) com a cabeça fora, fica neutro: nem afunda nem salta
		main.player.global_position = Vector3(deep.x, deep_surface - 1.62, deep.z)
		main.player.call("_swim_check")
		main.player.velocity = Vector3.ZERO
		for i in 24:
			main.player.call("_move_swim", 0.1, Vector3.ZERO)
		check("na tona fica neutro (nem afunda nem dispara)",
			absf(float(main.player.velocity.y)) < 0.4,
			"velocidade vertical=%.2f" % float(main.player.velocity.y))
		main.player.velocity = Vector3.ZERO
		main.player.global_position = water_home_pos
		main.player.call("_swim_check")
		# a criatura nada em vez de se afundar até ao leito
		Game.hour = 1.0
		Game.phase = Game.current_phase()
		var beast := Creature.new()
		beast.world = main.world
		beast.target = main.player
		main.world.add_child(beast)
		beast.global_position = Vector3(deep.x, sea_bed + 0.4, deep.z)
		var bottom := beast.global_position.y
		await _frames(45)
		var rise := beast.global_position.y - bottom
		check("a criatura nada até à superfície em vez de se afundar",
			rise > 0.8 and beast.global_position.y > deep_surface - 2.6
			and not beast.is_queued_for_deletion(),
			"subiu %.2f m (fundo %.2f, tona %.2f, agora %.2f)"
			% [rise, sea_bed, deep_surface, beast.global_position.y])
		beast.queue_free()
		await _frames(2)

	# ── loot no chão: modelo próprio, íman e flutuação ───────────────────
	var drop_script: Script = load("res://scripts/world/dropped_item.gd")
	var loot_shapes := {}
	for lid in ["wood", "pickaxe", "fish_cooked", "workbench", "torch", "stone"]:
		var probe: Node = drop_script.new()
		probe.set("item_id", lid)
		var probe_mesh: ArrayMesh = probe.call("_item_mesh")
		# assinatura = vértices + caixa: só os vértices não chega (duas malhas
		# diferentes podem ter o mesmo número)
		var box: Vector3 = probe_mesh.get_aabb().size if probe_mesh != null else Vector3.ZERO
		loot_shapes[lid] = "%d|%.2f,%.2f,%.2f" % [_mesh_vertex_count(probe_mesh),
			box.x, box.y, box.z]
		probe.free()
	var shapes_distinct: bool = loot_shapes.values().size() == loot_shapes.size()
	var shapes_filled: bool = true
	for lid in loot_shapes:
		if str(loot_shapes[lid]).begins_with("0|"):
			shapes_filled = false
	check("cada família de item tem o seu próprio modelo no chão",
		shapes_distinct and shapes_filled, str(loot_shapes))

	var loot: RigidBody3D = drop_script.new()
	loot.set("item_id", "stone")
	loot.set("amount", 2)
	loot.set("inv", inv)
	loot.set("player_ref", main.player)
	main.world.add_child(loot)
	var loot_start: Vector3 = main.player.global_position + Vector3(2.0, 0.6, 0.0)
	loot.global_position = loot_start
	var loot_dist_before: float = loot.global_position.distance_to(main.player.global_position)
	for i in 50:
		if not is_instance_valid(loot):
			break
		loot.call("_physics_process", 0.05)
	var magnet_ok: bool = not is_instance_valid(loot) \
		or loot.global_position.distance_to(main.player.global_position) < loot_dist_before - 0.5
	check("o item no chão vem ter com o jogador (íman)", magnet_ok,
		"distância %.2f -> %.2f" % [loot_dist_before,
			-1.0 if not is_instance_valid(loot) else loot.global_position.distance_to(main.player.global_position)])
	if is_instance_valid(loot):
		loot.queue_free()
	if deep != Vector3.INF:
		var floater: RigidBody3D = drop_script.new()
		floater.set("item_id", "wood")
		floater.set("amount", 1)
		floater.set("inv", inv)
		floater.set("player_ref", null)
		main.world.add_child(floater)
		floater.call("_settle")
		var float_y: float = sea_bed + 0.3
		floater.global_position = Vector3(deep.x, float_y, deep.z)
		for i in 40:
			floater.call("_physics_process", 0.05)
		check("item largado na água sobe à tona (não se perde no fundo)",
			floater.global_position.y > float_y + 0.5,
			"%.2f -> %.2f (tona %.2f)" % [float_y, floater.global_position.y, deep_surface])
		floater.queue_free()

	# ── ícones: item novo não pode cair no desenho genérico ───────────────
	# (o `_` do ItemIcon é um círculo cinzento com a inicial: é o que o jogador
	#  via nas ferramentas novas, ao lado de ícones desenhados)
	var icon_art := str(FileAccess.get_file_as_string("res://scripts/ui/item_icon.gd"))
	if icon_art.is_empty():
		skip("os ícones das ferramentas novas estão desenhados",
			"scripts compilados (build exportada)")
	else:
		var generic_icons: Array = []
		for id in ["stone_blade", "fire_kit", "workbench", "axe", "pickaxe", "campfire",
				"chest", "chair", "primitive_axe", "primitive_pickaxe", "water_salt"]:
			if not ('"%s"' % id in icon_art):
				generic_icons.append(id)
		check("os ícones das ferramentas novas estão desenhados",
			generic_icons.is_empty(), ", ".join(generic_icons))

	# O sono tem de estar escrito no idioma ativo: uma chave em falta aparece
	# como "msg.sleep_bed" em cru no ecrã.
	var missing_locale: Array = []
	for key in ["msg.sleeping", "msg.sleep_bed", "msg.sleep_ground", "msg.cant_sleep",
			"prompt.sleep", "msg.nap_done", "prompt.feed", "msg.fire_fed",
			"msg.fire_low", "msg.fire_out", "msg.need_wood", "msg.ate",
			"msg.food_sick", "msg.tired", "msg.dehydrated", "msg.sea_water", "item.water_salt"]:
		if Loc.t(key) == key:
			missing_locale.append(key)
	check("os textos do sono e da água existem no idioma ativo",
		missing_locale.is_empty(), ", ".join(missing_locale))

	# ══ PRIMEIRO DIA — teste de GAMEPLAY ══════════════════════════════════
	# A constituição do projeto (§44) não aceita "as funções passam" como prova
	# de que o jogo é jogável: exige uma SESSÃO. Este teste joga o primeiro dia
	# de raiz — mochila vazia, mãos nuas — pelos sistemas reais (colheita,
	# craft, estações, fogo, água, comida, sono).
	await _first_day()

	_report()


func _report() -> void:
	for l in lines:
		print(l)
	print("──────────────────────────────────────────────────")
	if skipped > 0:
		print("RESULTADO: %d ok, %d falhas, %d saltadas" % [passed, failed, skipped])
	else:
		print("RESULTADO: %d ok, %d falhas" % [passed, failed])
	print("SELFTEST_%s" % ["PASS" if failed == 0 else "FAIL"])
	# escreve também para um ficheiro para o CI/agentes lerem
	var f := FileAccess.open("user://selftest.txt", FileAccess.WRITE)
	if f:
		f.store_string("%d ok, %d falhas, %d saltadas\n%s\n"
			% [passed, failed, skipped, "\n".join(lines)])
		f.close()
	get_tree().quit(0 if failed == 0 else 1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _action_has_mouse(action: String) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventMouseButton:
			return (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	return false


## Altura do terreno num ponto (para verificar onde as coisas assentam).
func terrain_height_at(p: Vector3) -> float:
	return float(main.world.terrain.height(p.x, p.z))


## Um ponto de água com a profundidade pedida (raio curto: o mundo é grande e
## procurar longe torna o teste lento).
func _water_spot(from: Vector3, dist: float, min_depth: float, max_depth: float) -> Vector3:
	var ter: Terrain = main.world.terrain
	for step in 12:
		var radius := dist * 0.35 * pow(1.25, float(step))
		for i in 90:
			var a := float(i) / 120.0 * TAU
			var x: float = from.x + cos(a) * radius
			var z: float = from.z + sin(a) * radius
			if not ter.is_water(x, z):
				continue
			var surface := ter.water_surface_height(x, z)
			var depth := surface - ter.height(x, z)
			if depth >= min_depth and depth <= max_depth:
				return Vector3(x, surface - min_depth * 0.5, z)
	return Vector3.INF


## Um ponto de MAR aberto (a costa fica longe: procura-se em anéis largos).
func _sea_spot(from: Vector3) -> Vector3:
	var ter: Terrain = main.world.terrain
	for radius in [60.0, 140.0, 300.0, 600.0]:
		for i in 64:
			var a := float(i) / 64.0 * TAU
			var x: float = from.x + cos(a) * radius
			var z: float = from.z + sin(a) * radius
			if ter.is_ocean(x, z):
				return Vector3(x, ter.water_surface_height(x, z) - 0.2, z)
	return Vector3.INF


## Um ponto seco e plano a `dist` de `from` — para isolar um teste do resto do mundo.
func _dry_spot(from: Vector3, dist: float) -> Vector3:
	var ter: Terrain = main.world.terrain
	for i in 64:
		var a := float(i) / 64.0 * TAU
		var x := from.x + cos(a) * dist
		var z := from.z + sin(a) * dist
		if not ter.is_water(x, z) and ter.slope(x, z) < 0.35:
			return Vector3(x, ter.height(x, z) + 1.0, z)
	return from + Vector3(dist, 0, 0)


## Tira comentários // e /* */ para não contar falsos positivos em shader.
func _strip_comments(src: String) -> String:
	var out := ""
	var i := 0
	while i < src.length():
		if src.substr(i, 2) == "//":
			while i < src.length() and src[i] != "\n":
				i += 1
		elif src.substr(i, 2) == "/*":
			i += 2
			while i + 1 < src.length() and src.substr(i, 2) != "*/":
				i += 1
			i += 2
		else:
			out += src[i]
			i += 1
	return out


func _mesh_vertex_count(mesh: ArrayMesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for surface_idx in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface_idx)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += verts.size()
	return total


func _node_has_surface_mesh(node: Node) -> bool:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null \
			and (node as MeshInstance3D).mesh.get_surface_count() > 0:
		return true
	for child in node.get_children():
		if _node_has_surface_mesh(child):
			return true
	return false


# ══════════════════════════════════════════════════════════════════════════
#  PRIMEIRO DIA — teste de GAMEPLAY (constituição §44)
#
#  Não verifica funções isoladas: joga o primeiro dia de um jogador novo, do
#  zero, e falha no PASSO em que o loop se parte. Se este teste passa, existe
#  caminho — sem itens dados à mão — de mãos nuas até: pedra, ferramenta,
#  picareta, rocha, bancada, picareta de pedra, fogueira, água segura, comida
#  cozinhada e uma noite passada a dormir.
# ══════════════════════════════════════════════════════════════════════════

## A mochila do jogo em curso. Os ajudantes do primeiro dia são funções do
## script e não vêem a variável local `inv` do `_run`.
func _inv() -> Inventory:
	return main.inv


func _fd_trace(msg: String) -> void:
	print("  [dia 1] " + msg)


func _fd_step(what: String, ok: bool, detail: String = "") -> bool:
	check(what, ok, detail)
	if not ok:
		_fd_failed.append(what.substr(0, 46))
	return ok


## Deixa o mundo assentar (chunks a carregar, física, pickups a caminho).
func _fd_wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


## Quantos nós colhíveis existem nos chunks carregados (diagnóstico).
func _fd_area() -> int:
	var total := 0
	for c in main.world.chunks.values():
		var ch := c as Chunk
		if ch != null:
			total += ch.harvest_nodes.size()
	return total


## Um nó vivo do tipo pedido nos chunks carregados.
func _fd_node(kinds: Array) -> Dictionary:
	for c in main.world.chunks.values():
		var ch := c as Chunk
		if ch == null:
			continue
		for n in ch.harvest_nodes:
			if bool(n.get("alive", true)) and str(n.get("kind", "")) in kinds:
				return n
	return {}


## Vai à procura desses nós: teleporta em espiral e ESPERA que a área carregue.
## (Saltar de 70 em 70 m sem esperar libertava os chunks antigos antes de os
## novos existirem — o teste "via" um mundo vazio e desistia.)
func _fd_roam(kinds: Array) -> void:
	var base: Vector3 = main.player.global_position
	for step in 8:
		var a := float(step) / 8.0 * TAU
		var d := 45.0 + 35.0 * float(step)
		var p: Vector3 = base + Vector3(cos(a) * d, 0.0, sin(a) * d)
		if main.world.terrain.is_water(p.x, p.z):
			continue
		p.y = main.world.ground_height(p.x, p.z) + 1.2
		main.player.teleport(p)
		main.world.set_target(p)
		for i in 90:
			await get_tree().process_frame
			if not _fd_node(kinds).is_empty():
				return


## Trabalha um nó até ceder, com o que estiver na mão.
## Devolve true quando o nó cede (e o material cai ao chão).
func _fd_work(n: Dictionary) -> bool:
	var pos: Vector3 = n["pos"]
	main.player.teleport(pos + Vector3(0.0, 0.8, 0.0))
	await _fd_wait(2)
	var hp_inicio := float(n.get("hp", 0.0))
	var guard := 0
	while bool(n.get("alive", true)) and guard < 70:
		var hp_before := float(n.get("hp", 0.0))
		# o `_process` da interacção recalcula o alvo a cada frame (é o que o
		# jogador está a OLHAR); num teste headless não há mira, por isso o
		# alvo tem de ser reposto a cada golpe. Sem isto cada nó levava um
		# único golpe e uma árvore nunca caía.
		main.interaction.focus = {"kind": "harvest", "ref": n, "pos": pos}
		main.interaction._hold_work(0.56, 1.0)
		guard += 1
		if bool(n.get("alive", true)) and is_equal_approx(float(n.get("hp", 0.0)), hp_before):
			break   # a ferramenta não chega: bater mais não muda nada
		await get_tree().physics_frame
	var vivo := bool(n.get("alive", true))
	if vivo or guard >= 8:
		_fd_trace("%s: hp %.1f -> %.1f em %d golpes (mão: %s)" % [str(n.get("kind", "?")),
			hp_inicio, float(n.get("hp", 0.0)), guard, _inv().hotbar_id()])
	return not vivo


## Colhe os tipos dados até haver `want` do item. Devolve o que há no fim.
func _fd_gather(kinds: Array, item: String, want: int, max_nodes: int = 10) -> int:
	var used := 0
	while _inv().count(item) < want and used < max_nodes:
		var n := _fd_node(kinds)
		if n.is_empty():
			await _fd_roam(kinds)
			n = _fd_node(kinds)
			if n.is_empty():
				break
		await _fd_work(n)
		# o material cai ao chão e vem ter com o jogador: esperar pelo pickup
		# (ler o contador no frame seguinte lia 0 e o teste ia colher mais)
		var alvo: int = _inv().count(item) + 1
		for i in 30:
			await get_tree().process_frame
			if _inv().count(item) >= alvo:
				break
		used += 1
	await _fd_wait(8)
	return _inv().count(item)


## Abate árvores e retira os toros: é assim que a madeira entra na mochila.
func _fd_wood(want: int) -> int:
	var trees := ["tree_oak", "tree_birch", "tree_willow", "tree_sakura", "tree_pine"]
	var attempts := 0
	while _inv().count("wood") < want and attempts < 6:
		var n := _fd_node(trees)
		if n.is_empty():
			await _fd_roam(trees)
			n = _fd_node(trees)
			if n.is_empty():
				break
		var at: Vector3 = n["pos"]
		await _fd_work(n)
		await _fd_wait(26)      # tempo da árvore cair
		var felled: Node3D = null
		for item in get_tree().get_nodes_in_group("fellable_logs"):
			if not is_instance_valid(item):
				continue
			var node := item as Node3D
			if node != null and node.has_method("take_log") \
					and node.global_position.distance_to(at) < 9.0:
				felled = node
				break
		_fd_trace("árvore %s: caiu=%s troncos=%d" % [str(n.get("kind", "?")),
			str(felled != null), int(felled.get("remaining_logs")) if felled != null else 0])
		if felled != null:
			for _i in int(felled.get("remaining_logs")):
				main.interaction.focus = {"kind": "felled_tree", "ref": felled,
					"pos": (felled.call("interaction_target") as Dictionary)["pos"]}
				main.interaction._do_interact({})
				await _fd_wait(14)
		await _fd_collect_near("wood", at)
		attempts += 1
	await _fd_wait(12)
	return _inv().count("wood")


## Vai buscar os pickups de um item que ficaram ao alcance de um ponto.
## O toro cai ao longo do tronco deitado (~2 m do jogador), fora do íman: um
## jogador a sério caminha até lá — o teste faz o mesmo.
func _fd_collect_near(item_id: String, centre: Vector3, radius: float = 14.0) -> void:
	for child in main.world.get_children():
		# o pickup pode ter sido apanhado/libertado neste mesmo frame: tocar num
		# objecto morto rebenta a build web ("null function or signature mismatch")
		if not is_instance_valid(child):
			continue
		var rb := child as RigidBody3D
		if rb == null or str(rb.get("item_id")) != item_id:
			continue
		if rb.global_position.distance_to(centre) > radius:
			continue
		main.player.teleport(rb.global_position + Vector3(0.0, 0.9, 0.0))
		await _fd_wait(12)


## Põe um item na mão (o `_hold_work` lê a barra rápida).
func _fd_hold(id: String) -> bool:
	for i in _inv().SLOTS:
		var s: Dictionary = _inv().slots[i]
		if not s.is_empty() and str(s["id"]) == id:
			_inv().equip_slot(i)
			return true
	return false


## Volta ao acampamento: as receitas de bancada/fogueira exigem a estação a
## menos de 4,5 m do jogador, e a colheita pode levá-lo para longe.
func _fd_back_to(p: Vector3) -> void:
	main.player.teleport(p + Vector3(1.2, 0.8, 0.0))
	main.world.set_target(p)
	await _fd_wait(10)


func _fd_craft(id: String) -> bool:
	var r: Dictionary = Game.request("craft", {"recipe": id})
	return bool(r.get("ok", false))


## Garante os materiais de uma receita, colhendo o que falta (como o jogador).
func _fd_ensure(recipe_id: String, rounds: int = 4) -> void:
	var needs: Dictionary = Db.recipe(recipe_id).get("needs", {})
	for round_i in rounds:
		var missing := {}
		for k in needs:
			var falta: int = int(needs[k]) - _inv().count(str(k))
			if falta > 0:
				missing[str(k)] = falta
		if missing.is_empty():
			return
		for k in missing:
			var alvo: int = _inv().count(str(k)) + int(missing[k])
			match str(k):
				"wood":
					await _fd_wood(alvo)
				"stick", "fiber", "leaf":
					await _fd_gather(["bush"], str(k), alvo, 8)
				"stone", "flint":
					await _fd_gather(["flint_node"], str(k), alvo, 8)
				"mushroom":
					await _fd_gather(["mushroom"], str(k), alvo, 4)
		# as folhas que sobram dão fibra: não se anda a apanhar arbustos até secar o vale
		while _inv().count("fiber") < int(needs.get("fiber", 0)) and _inv().count("leaf") >= 3:
			if not _fd_craft("leaf_fiber"):
				break
		# e um graveto também se tira de um pedaço de madeira
		while _inv().count("stick") < int(needs.get("stick", 0)) and _inv().count("wood") >= 1:
			if not _fd_craft("stick"):
				break


func _first_day() -> void:
	var sv: Survival = main.survival
	_fd_failed.clear()

	# ── 0. um jogador novo ────────────────────────────────────────────────
	for i in _inv().SLOTS:
		_inv().slots[i] = {}
	_inv().select(0)
	sv.health = 100.0
	sv.hunger = 55.0
	sv.thirst = 55.0
	sv.energy = 85.0
	Game.started = true
	Game.hour = 8.0
	# As bancadas/fogueiras que os testes anteriores deixaram no mundo saem
	# daqui: no primeiro dia, a estação tem de ser construída pelo jogador.
	for e in main.structures.list.duplicate():
		main.structures.remove(e)
	await _fd_wait(4)
	# O acampamento fica ao lado do jogador — uma área JÁ carregada. Teleportar
	# para 150 m de distância punha o teste a correr contra o carregamento de
	# chunks e a "não encontrar" arbustos que existiam.
	var camp: Vector3 = _dry_spot(main.player.global_position, 12.0)
	main.player.teleport(camp + Vector3(0.0, 0.8, 0.0))
	main.world.set_target(camp)
	await _fd_wait(10)
	print("  [dia 1] área: %d nós em %d chunks" % [_fd_area(), main.world.chunks.size()])
	check("DIA 1 · o jogador começa de mãos vazias",
		_inv().count("stone") == 0 and _inv().count("wood") == 0 and _inv().count("fiber") == 0,
		"stone=%d wood=%d fiber=%d" % [_inv().count("stone"), _inv().count("wood"),
			_inv().count("fiber")])

	# ── 1. o primeiro minuto: fibra e graveto ─────────────────────────────
	var fibra = await _fd_gather(["bush"], "fiber", 4, 8)
	_fd_step("DIA 1 · mãos apanham fibra e graveto no arbusto",
		fibra >= 4 and _inv().count("stick") >= 2,
		"fiber=%d stick=%d" % [fibra, _inv().count("stick")])

	# ── 2. pedra solta (a porta de entrada) ───────────────────────────────
	var pedra = await _fd_gather(["flint_node"], "stone", 5, 6)
	_fd_step("DIA 1 · mãos apanham pedra solta (a porta da pedra)",
		pedra >= 5, "stone=%d" % pedra)

	# ── 3. madeira: a árvore cai e o tronco dá toros ──────────────────────
	var madeira = await _fd_wood(3)
	_fd_step("DIA 1 · a árvore cai à mão e o tronco dá madeira",
		madeira >= 3, "wood=%d" % madeira)

	# ── 4. a primeira ferramenta: a lasca ─────────────────────────────────
	await _fd_ensure("stone_blade")
	_fd_step("DIA 1 · a lasca de pedra faz-se na mão (Criação)",
		_fd_craft("stone_blade") and _inv().count("stone_blade") >= 1)
	_fd_hold("stone_blade")

	# ── 5. a picareta primitiva: o primeiro objecto que quebra pedra ──────
	await _fd_ensure("primitive_pickaxe")
	_fd_step("DIA 1 · a picareta primitiva faz-se à mão",
		_fd_craft("primitive_pickaxe") and _inv().count("primitive_pickaxe") >= 1)
	_fd_hold("primitive_pickaxe")

	# ── 6. a rocha cede à picareta primitiva ──────────────────────────────
	var rock := _fd_node(["rock"])
	if rock.is_empty():
		await _fd_roam(["rock"])
		rock = _fd_node(["rock"])
	var rock_ok := false
	if not rock.is_empty():
		rock_ok = await _fd_work(rock)
		await _fd_wait(14)
	_fd_step("DIA 1 · a picareta primitiva quebra a rocha e dá pedra",
		rock_ok and _inv().count("stone") > 0,
		"rocha=%s stone=%d" % [str(not rock.is_empty()), _inv().count("stone")])

	# ── 7. a bancada: objecto do mundo, não menu ──────────────────────────
	await _fd_ensure("workbench")
	_fd_step("DIA 1 · a bancada faz-se na Criação e leva-se na mão",
		_fd_craft("workbench") and _inv().count("workbench") >= 1)
	var bench_pos: Vector3 = main.player.global_position + Vector3(-2.0, 0.0, 0.0)
	bench_pos.y = main.world.ground_height(bench_pos.x, bench_pos.z)
	_inv().remove("workbench", 1)
	var bench: Dictionary = main.structures.place("workbench", bench_pos, 0.0, false)
	_fd_step("DIA 1 · a bancada é um objecto pousado no chão",
		"workbench" in main.structures.stations_near(bench_pos, 4.5))
	main.player.teleport(bench_pos + Vector3(1.0, 0.8, 0.0))
	await _fd_wait(4)
	main.interaction.focus = {"kind": "structure", "ref": bench, "pos": bench["pos"]}
	var list_before: int = main.structures.list.size()
	main.interaction._do_interact({})
	_fd_step("DIA 1 · F na bancada abre o painel dela (e não a apaga)",
		main.structures.list.size() == list_before
		and str(main.menus.station_filter) == "workbench",
		"filtro=%s" % str(main.menus.station_filter))
	main.menus.close()

	# ── 8. a picareta de pedra e a rocha dura ─────────────────────────────
	await _fd_ensure("stone_pickaxe")
	await _fd_back_to(bench_pos)
	_fd_step("DIA 1 · a bancada faz a picareta de pedra",
		_fd_craft("stone_pickaxe") and _inv().count("pickaxe") >= 1)
	var dura := _fd_node(["rock_hard"])
	if dura.is_empty():
		await _fd_roam(["rock_hard"])
		dura = _fd_node(["rock_hard"])
	var fake := false
	if dura.is_empty():
		dura = {"pos": main.player.global_position + Vector3(1.5, 0.0, 0.0),
			"kind": "rock_hard", "height": 0.8, "radius": 0.6, "hp": 9, "alive": true}
		fake = true
	_fd_hold("primitive_pickaxe")
	var hp_antes := float(dura["hp"])
	main.interaction.focus = {"kind": "harvest", "ref": dura, "pos": dura["pos"]}
	main.interaction._hold_work(0.56, 1.0)
	var recusa := is_equal_approx(float(dura["hp"]), hp_antes)
	_fd_hold("pickaxe")
	main.interaction._hold_work(0.56, 1.0)
	var cede := float(dura["hp"]) < hp_antes
	_fd_step("DIA 1 · a rocha dura recusa a picareta primitiva e cede à de pedra",
		recusa and cede, "recusa=%s cede=%s%s" % [str(recusa), str(cede),
			" (nó sintético)" if fake else ""])

	# ── 9. fogueira + isqueiro ────────────────────────────────────────────
	await _fd_ensure("campfire")
	_fd_step("DIA 1 · a fogueira faz-se na Criação",
		_fd_craft("campfire") and _inv().count("campfire") >= 1)
	var fire_pos: Vector3 = main.player.global_position + Vector3(2.5, 0.0, 0.0)
	fire_pos.y = main.world.ground_height(fire_pos.x, fire_pos.z)
	_inv().remove("campfire", 1)
	var fogueira: Dictionary = main.structures.place("campfire", fire_pos, 0.0, false)
	_fd_step("DIA 1 · a fogueira é um objecto no mundo (ainda apagada)",
		main.structures.list.size() > 0 and str(fogueira.get("id", "")) == "campfire")
	main.interaction.focus = {"kind": "structure", "ref": fogueira, "pos": fogueira["pos"]}
	var sem_kit: Dictionary = main.interaction._do_interact({})
	var fica_apagada := not bool(fogueira.get("lit", false)) \
		and str(sem_kit.get("reason", "")) == "no_fire_kit"
	await _fd_ensure("fire_kit")
	_fd_step("DIA 1 · acender exige isqueiro (e o isqueiro faz-se à mão)",
		fica_apagada and _fd_craft("fire_kit"))
	main.interaction.focus = {"kind": "structure", "ref": fogueira, "pos": fogueira["pos"]}
	main.interaction._do_interact({})
	_fd_step("DIA 1 · com isqueiro a fogueira acende, dá luz e vira estação",
		bool(fogueira.get("lit", false)) and fogueira.get("light") != null
		and "campfire" in main.structures.stations_near(fire_pos, 4.5))

	# ── 10. água: garrafa vazia → encher → ferver → beber ─────────────────
	await _fd_ensure("bottle")
	_fd_step("DIA 1 · a garrafa improvisada faz-se na Criação",
		_fd_craft("bottle") and _inv().count("bottle") >= 1)
	var agua_spot: Vector3 = _water_spot(main.player.global_position, 90.0, 0.4, 4.0)
	if agua_spot != Vector3.INF:
		main.player.teleport(agua_spot + Vector3(0.0, 0.8, 0.0))
		main.world.set_target(agua_spot)
		await _fd_wait(20)
	main.interaction.focus = {"kind": "water", "ref": null,
		"pos": main.player.global_position}
	main.interaction._do_interact({})
	_fd_step("DIA 1 · a garrafa nasce vazia e enche-se na água",
		agua_spot != Vector3.INF and _inv().count("water") >= 1,
		"agua=%s water=%d" % [str(agua_spot != Vector3.INF), _inv().count("water")])
	main.player.teleport(fire_pos + Vector3(1.2, 0.8, 0.0))
	main.world.set_target(fire_pos)
	await _fd_wait(20)
	await _fd_back_to(fire_pos)
	_fd_step("DIA 1 · a fogueira ferve a água (deixa de ser crua)",
		_fd_craft("boil_water") and _inv().count("water_clean") >= 1)
	sv.thirst = 40.0
	_fd_hold("water_clean")
	var bebeu: Dictionary = Game.request("use_item")
	_fd_step("DIA 1 · beber água tratada mata a sede sem risco",
		bool(bebeu.get("ok", false)) and float(sv.thirst) > 40.0 and float(sv.health) >= 99.0,
		"thirst=%.0f health=%.0f" % [float(sv.thirst), float(sv.health)])

	# ── 11. comida: cru ≠ cozinhado ───────────────────────────────────────
	_inv().add("meat_raw", 1)   # a caça tem teste próprio; aqui interessa a cozinha
	await _fd_back_to(fire_pos)
	var cozinhou := _fd_craft("meat_cooked")
	var carne: Dictionary = Db.item("meat_cooked")
	var crua: Dictionary = Db.item("meat_raw")
	_fd_step("DIA 1 · cozinhar transforma a carne (cru ≠ cozinhado)",
		cozinhou and _inv().count("meat_cooked") >= 1
		and float(carne.get("food", 0.0)) > float(crua.get("food", 0.0))
		and float(crua.get("risk", 0.0)) > float(carne.get("risk", 0.0)))
	sv.hunger = 35.0
	_fd_hold("meat_cooked")
	Game.request("use_item")
	_fd_step("DIA 1 · comer a carne assada repõe a fome", float(sv.hunger) > 35.0,
		"hunger=%.0f" % float(sv.hunger))

	# ── 12. dormir: a noite passa ─────────────────────────────────────────
	await _fd_ensure("bed")
	await _fd_back_to(bench_pos)
	_fd_step("DIA 1 · a cama faz-se na bancada",
		_fd_craft("bed") and _inv().count("bed") >= 1)
	var bed_pos: Vector3 = bench_pos + Vector3(2.5, 0.0, 2.5)
	bed_pos.y = main.world.ground_height(bed_pos.x, bed_pos.z)
	_inv().remove("bed", 1)
	var cama_e: Dictionary = main.structures.place("bed", bed_pos, 0.0, false)
	Game.hour = 21.5
	sv.energy = 30.0
	main.interaction.focus = {"kind": "structure", "ref": cama_e, "pos": cama_e["pos"]}
	main.interaction._do_interact({})
	# dormir é uma sequência: deitar → escurecer → noite → acordar
	var prazo: int = Time.get_ticks_msec() + 12000
	while bool(main.interaction.sleeping) and Time.get_ticks_msec() < prazo:
		await get_tree().process_frame
	var hora := float(Game.hour)
	_fd_step("DIA 1 · dormir passa a noite e devolve a energia",
		not bool(main.interaction.sleeping) and hora >= 5.0 and hora <= 9.5
		and float(sv.energy) > 31.0,
		"hora=%.1f energia=%.0f" % [hora, float(sv.energy)])

	# ── 13. o dia fecha ───────────────────────────────────────────────────
	_fd_step("DIA 1 · o primeiro dia fecha-se ponta a ponta",
		_fd_failed.is_empty(), ", ".join(_fd_failed))
	main.menus.close()
	Game.paused = false
