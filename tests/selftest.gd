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
var lines: Array = []


func check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
		lines.append("  OK   %s%s" % [what, "" if detail.is_empty() else "  (" + detail + ")"])
	else:
		failed += 1
		lines.append("  FALHA %s%s" % [what, "" if detail.is_empty() else "  (" + detail + ")"])


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
	check("terreno tem altura", absf(world.terrain.height(0, 0)) < 500.0,
		"h(0,0)=%.2f" % world.terrain.height(0, 0))
	check("aldeia existe", world.terrain.village_distance(
		world.terrain.village_center().x, world.terrain.village_center().y) < 0.01)
	await _frames(60)
	check("chunks construídos", world.chunks.size() > 0, "n=%d" % world.chunks.size())

	var harvest := 0
	for c in world.chunks.values():
		harvest += (c as Chunk).harvest_nodes.size()
	check("nós colhíveis espalhados", harvest > 10, "n=%d" % harvest)

	var instances := 0
	for c in world.chunks.values():
		for d in (c as Chunk)._decor:
			if d is MultiMeshInstance3D and (d as MultiMeshInstance3D).multimesh:
				instances += (d as MultiMeshInstance3D).multimesh.instance_count
	check("instâncias de vegetação", instances > 200, "n=%d" % instances)

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
		main.interaction._harvest_done()
		check("cortar árvore dá madeira", inv.count("wood") > wood_before,
			"wood %d -> %d" % [wood_before, inv.count("wood")])
		check("nó colhido fica marcado", not bool(target.get("alive", true)))
	else:
		check("cortar árvore dá madeira", false, "nenhuma árvore por perto")

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
	Game.hour = 12.0
	Game.phase = Game.current_phase()
	check("dia detetado", not Game.is_night() and Game.daylight() > 0.3,
		"daylight=%.2f" % Game.daylight())

	# ── 9. NPC ────────────────────────────────────────────────────────────
	var npcs := get_tree().get_nodes_in_group("npcs")
	check("aldeia tem habitante", npcs.size() > 0)
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

	# ── relatório ─────────────────────────────────────────────────────────
	for l in lines:
		print(l)
	print("──────────────────────────────────────────────────")
	print("RESULTADO: %d ok, %d falhas" % [passed, failed])
	print("SELFTEST_%s" % ["PASS" if failed == 0 else "FAIL"])
	# escreve também para um ficheiro para o CI/agentes lerem
	var f := FileAccess.open("user://selftest.txt", FileAccess.WRITE)
	if f:
		f.store_string("%d ok, %d falhas\n%s\n" % [passed, failed, "\n".join(lines)])
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
