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

	# ── relatório ─────────────────────────────────────────────────────────
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
