class_name Interaction
extends Node
## Interaction — a ponte entre o jogador e o mundo.
##
## Um só sítio decide "o que estou a olhar" e "o que acontece se carregar".
## Cada alvo devolve um contrato simples: tipo, prompt e uma ação. Assim
## acrescentar pesca, uma porta ou um NPC novo não toca em mais nada.

const REACH := 4.2
const CURIOUS_REACH_MULT := 1.35
## Ajuda só para o que é pequeno (plantas, cogumelos): sem isto obrigava a
## acertar no pixel. Árvores e rochas não precisam de ajuda — o raio bate na
## forma (tronco, copa, pedra) e apontar ao TRONCO funciona.
const PLANT_ASSIST := 0.30
const TREE_ASSIST := 0.14        # só se o raio falhar a forma toda

var player: Player
var world: World
var survival: Survival
var menus: Node
var inv: Inventory
var structures: Structures
var fx: Node3D
var npc_root: Node3D

var focus: Dictionary = {}
var progress := 0.0
var building := false
var build_rot := 0.0
var ghost: MeshInstance3D
var ghost_mat: StandardMaterial3D
var _hold := false
var _was_holding := false
var _impact_t := 0.0
var _tool_hint_t := 0.0
# Pesca: 0 = parado, 1 = linha na água, 2 = a morder (janela para puxar).
var _fish_state := 0
var _fish_t := 0.0

# ── sono ────────────────────────────────────────────────────────────────
## Dormir é uma AÇÃO com princípio, meio e fim, não um salto no relógio:
## deitar → escurecer → o tempo passa → amanhecer → levantar.
signal slept(quality: float, place: String)
var sleeping := false
var _sleep_layer: CanvasLayer
var _sleep_rect: ColorRect
var _eye_y := -1.0


func _ready() -> void:
	name = "Interaction"
	_make_ghost()
	Game.register_command("interact", self, _can_interact, _do_interact, "prompt.use")
	# Dormir no chão é a alternativa de quem ainda não construiu cama: sem isto
	# a primeira noite não tinha saída nenhuma (a cama exige bancada + 12 de fibra).
	Game.register_command("sleep", self, _can_sleep, _do_sleep, "prompt.sleep")
	Game.register_command("craft", self, _can_craft, _do_craft, "tab.crafting")
	Game.register_command("place", self, _can_place, _do_place, "prompt.place")
	Game.register_command("use_item", self, _can_use_item, _do_use_item, "prompt.use")
	Game.register_command("remove_structure", self, _can_remove, _do_remove, "prompt.remove")
	Game.register_command("toggle_build", self, _can_toggle_build, _do_toggle_build, "prompt.place")


func _make_ghost() -> void:
	ghost_mat = StandardMaterial3D.new()
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.albedo_color = Color(0.6, 0.95, 0.7, 0.45)
	ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ghost = MeshInstance3D.new()
	ghost.name = "BuildGhost"
	ghost.material_override = ghost_mat
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.visible = false
	add_child(ghost)


func _unhandled_input(event: InputEvent) -> void:
	if Game.paused or not Game.started:
		return
	if event.is_action_pressed("build"):
		Game.request("toggle_build")
	elif event.is_action_pressed("interact") and building:
		# Em modo de construção o F roda a peça; o rato esquerdo coloca.
		build_rot += PI * 0.25
		Sfx.play("ui_click", -16.0, 0.9)
	elif event.is_action_pressed("interact"):
		Game.request("interact")
	elif event.is_action_pressed("use_item"):
		Game.request("use_item")
	elif event.is_action_pressed("sleep"):
		Game.request("sleep")


func _process(delta: float) -> void:
	if Game.paused or not Game.started:
		return
	_tool_hint_t = maxf(0.0, _tool_hint_t - delta)
	if sleeping:
		# a dormir não se colhe, não se constrói e não se abre a mochila
		return
	_tick_fishing(delta)
	_update_focus()
	_handle_use(delta)
	_update_ghost()


# ══════════════════════════════════════════════════════════════════════════
#  O QUE ESTOU A OLHAR
# ══════════════════════════════════════════════════════════════════════════
## Alcance efetivo. A alma "curious" vê mais longe: é a promessa do prólogo
## ("Encontras mais ao explorar") tornada mecânica observável.
func reach() -> float:
	if str(Game.profile.get("soul", "")) == "curious":
		return REACH * CURIOUS_REACH_MULT
	return REACH


func _update_focus() -> void:
	var cam := player.camera
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var r := reach()
	var best := {}
	# Escolha por ORDEM NO RAIO (o mais perto à frente ganha). A versão anterior
	# usava um ponto médio inventado (`pos + altura*0.45`) com um cone de 35°:
	# apontar ao tronco de uma árvore não a apanhava (o ponto médio ficava na
	# copa) e o cone largo trazia um arbusto que estava mais perto do centro do
	# ecrã. Era isto o "mira para uma coisa e apanha outra".
	var best_t := 1e18

	# nós colhíveis (árvores, rochas, plantas)
	for n in world.harvestables_near(from, r + 9.0):
		if not bool(n.get("alive", true)):
			continue
		var t := _ray_harvest(n, from, dir, r)
		if t < best_t:
			best_t = t
			best = {"kind": "harvest", "ref": n, "pos": _aim_point(n, from, dir)}

	# estruturas (caixa do tamanho real)
	for e in structures.near(from, r + 2.0):
		var t2 := _ray_structure(e, from, dir, r)
		if t2 < best_t:
			best_t = t2
			best = {"kind": "structure", "ref": e, "pos": e["pos"] + Vector3(0, 0.7, 0)}

	# Troncos abatidos: o alvo é a LINHA do tronco caído, não um ponto no chão.
	# Assim basta estar perto e olhar para o tronco, de qualquer lado.
	for c in get_tree().get_nodes_in_group("fellable_logs"):
		if not is_instance_valid(c) or not c.has_method("interaction_target"):
			continue
		var data: Dictionary = c.call("interaction_target")
		if data.is_empty():
			continue
		var t3 := _ray_felled(c, from, dir, r * 1.5)
		if t3 < best_t:
			best_t = t3
			best = {"kind": "felled_tree", "ref": c, "pos": data["pos"]}

	# caça: bate-se com o rato esquerdo, como em tudo o resto
	for a in get_tree().get_nodes_in_group("animals"):
		if not (a is Node3D) or not bool(a.get("alive")):
			continue
		var ap: Vector3 = (a as Node3D).global_position + Vector3(0, 0.95, 0)
		if a.has_method("aim_point"):
			ap = a.call("aim_point")
		var ta := _ray_sphere(from, dir, ap, 0.82, r)
		if ta < best_t:
			best_t = ta
			best = {"kind": "animal", "ref": a, "pos": ap}

	# pessoas
	if npc_root != null:
		for c in npc_root.get_children():
			if not (c is Node3D) or not c.has_method("interaction_target"):
				continue
			var p: Vector3 = (c as Node3D).global_position + Vector3(0, 1.0, 0)
			var t4 := _ray_sphere(from, dir, p, 0.85, r)
			if t4 < best_t:
				best_t = t4
				best = {"kind": "npc", "ref": c, "pos": p + Vector3(0, 0.4, 0)}

	# água (só se não houver mais nada)
	if best.is_empty():
		var hit := _ray_water_surface(from, dir, r * 1.6)
		if hit != Vector3.INF:
			best = {"kind": "water", "ref": null, "pos": hit}

	var changed := not _same(best)
	focus = best
	if changed:
		progress = 0.0
		_impact_t = 0.0
		_tool_hint_t = 0.0
		Bus.focus_changed.emit(self, prompt_key())


## Onde mostrar as partículas/feedback de um nó: no ponto da forma mais próximo
## do jogador (tronco de uma árvore, pedra, arbusto), não numa altura fixa.
func _aim_point(n: Dictionary, from: Vector3, _dir: Vector3) -> Vector3:
	var base: Vector3 = n["pos"]
	var h := float(n.get("height", 1.0))
	var kind := str(n.get("kind", ""))
	if kind.begins_with("tree"):
		return base + Vector3(0, clampf(from.y - base.y, 0.6, h * 0.8), 0)
	if kind == "rock":
		return base + Vector3(0, h * 0.45, 0)
	return base + Vector3(0, maxf(h * 0.5, 0.25), 0)


## Raio contra um nó colhível. Devolve a distância do primeiro toque (INF se
## nada). A forma depende do tipo: tronco + copa para árvores, elipsoide para
## rochas, esfera para plantas.
func _ray_harvest(n: Dictionary, from: Vector3, dir: Vector3, max_d: float) -> float:
	var base: Vector3 = n["pos"]
	var h := float(n.get("height", 1.0))
	var kind := str(n.get("kind", ""))
	if kind.begins_with("tree"):
		var trunk_r := maxf(float(n.get("collider_radius", 0.0)), 0.22)
		var trunk_h := maxf(h * 0.82, 1.2)
		var t := _ray_cylinder(from, dir, base, trunk_r, trunk_h, max_d)
		# copa: também conta como alvo (é a árvore toda que responde)
		var canopy := _ray_sphere(from, dir, base + Vector3(0, h * 0.74, 0),
			maxf(h * 0.34, 1.0), max_d)
		t = minf(t, canopy)
		if t == INF and from.distance_to(base) <= max_d \
				and _angle_to(base + Vector3(0, h * 0.4, 0), from, dir) <= TREE_ASSIST:
			t = from.distance_to(base)
		return t
	if kind == "rock":
		var rad := maxf(float(n.get("radius", 0.8)), 0.35)
		return _ray_sphere(from, dir, base + Vector3(0, h * 0.45, 0), rad * 1.15, max_d)
	# plantas pequenas: esfera + ajuda cónica (são pequenas demais para exigir
	# precisão de pixel)
	var pr := maxf(h * 0.6, 0.3)
	var tp := _ray_sphere(from, dir, base + Vector3(0, h * 0.5, 0), pr, max_d)
	if tp == INF and from.distance_to(base) <= max_d \
			and _angle_to(base + Vector3(0, h * 0.5, 0), from, dir) <= PLANT_ASSIST:
		tp = from.distance_to(base)
	return tp


func _ray_structure(e: Dictionary, from: Vector3, dir: Vector3, max_d: float) -> float:
	var id := str(e.get("id", ""))
	if not world.species.structures.has(id):
		return INF
	var st: SpeciesKit.Structure = world.species.structures[id]
	var pos: Vector3 = e["pos"]
	var half := st.size * 0.5
	var lo := pos + Vector3(0, st.size.y * 0.5, 0) - half
	var hi := pos + Vector3(0, st.size.y * 0.5, 0) + half
	return _ray_box(from, dir, lo, hi, max_d)


## Tronco caído: distância do raio ao SEGMENTO do tronco (grosso, para perdoar).
func _ray_felled(node: Node3D, from: Vector3, dir: Vector3, max_d: float) -> float:
	var base := node.global_position
	var h := float(node.get("height"))
	var d := float(node.get("fall_direction"))
	# depois de tombado, o tronco segue ±X (a rotação é em torno de Z)
	var tip := base + Vector3(d * h * 0.85, 0.0, 0.0)
	var radius := maxf(float(node.get("trunk_radius")) * 1.6, 0.55)
	var nearest := _closest_on_ray_to_segment(from, dir, base, tip)
	var point := from + dir * maxf(nearest, 0.0)
	# distância do ponto ao segmento
	var ab := tip - base
	var ap := point - base
	var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	var on_line := base + ab * t
	if point.distance_to(on_line) > radius:
		return INF
	if nearest > max_d or nearest < 0.15:
		return INF
	return nearest


# ── geometria ────────────────────────────────────────────────────────────────
func _angle_to(p: Vector3, from: Vector3, dir: Vector3) -> float:
	var to := p - from
	if to.length_squared() < 1e-6:
		return 0.0
	return to.normalized().angle_to(dir)


## Cilindro vertical (eixo Y) por dentro do raio.
func _ray_cylinder(from: Vector3, dir: Vector3, base: Vector3, radius: float,
		height: float, max_d: float) -> float:
	var dx := dir.x
	var dz := dir.z
	var ox := from.x - base.x
	var oz := from.z - base.z
	var a := dx * dx + dz * dz
	if a < 1e-9:
		return INF
	var b := 2.0 * (ox * dx + oz * dz)
	var c := ox * ox + oz * oz - radius * radius
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return INF
	var sq := sqrt(disc)
	var t0 := (-b - sq) / (2.0 * a)
	var t1 := (-b + sq) / (2.0 * a)
	for tc in [t0, t1]:
		var t := float(tc)
		if t <= 0.15 or t > max_d:
			continue
		var y: float = from.y + dir.y * t - base.y
		if y >= 0.0 and y <= height:
			return t
	return INF


func _ray_sphere(from: Vector3, dir: Vector3, centre: Vector3, radius: float,
		max_d: float) -> float:
	var oc := from - centre
	var b := oc.dot(dir)
	var c := oc.dot(oc) - radius * radius
	var disc := b * b - c
	if disc < 0.0:
		return INF
	var t := -b - sqrt(disc)
	if t <= 0.15 or t > max_d:
		return INF
	return t


func _ray_box(from: Vector3, dir: Vector3, lo: Vector3, hi: Vector3, max_d: float) -> float:
	var tmin := 0.0
	var tmax := max_d
	for axis in 3:
		var o: float = from[axis]
		var d: float = dir[axis]
		var l: float = lo[axis]
		var hg: float = hi[axis]
		if absf(d) < 1e-6:
			if o < l or o > hg:
				return INF
			continue
		var t1 := (l - o) / d
		var t2 := (hg - o) / d
		if t1 > t2:
			var swap := t1
			t1 = t2
			t2 = swap
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return INF
	return tmin if tmin > 0.15 else INF


## Distância ao longo do raio do ponto mais próximo de um segmento (a-b).
## Devolve 0.0 quando o segmento está todo atrás da câmara.
func _closest_on_ray_to_segment(from: Vector3, dir: Vector3, a: Vector3, b: Vector3) -> float:
	var u := dir.normalized()
	var v := b - a
	var e := from - a
	var uu := u.dot(u)
	var uv := u.dot(v)
	var vv := v.dot(v)
	var ue := u.dot(e)
	var ve := v.dot(e)
	var denom := uu * vv - uv * uv
	var s := 0.0
	if absf(denom) > 1e-8:
		s = clampf((uu * ve - uv * ue) / denom, 0.0, 1.0)
	return maxf((s * uv - ue) / maxf(uu, 1e-8), 0.0)


func _same(other: Dictionary) -> bool:
	if other.is_empty() and focus.is_empty():
		return true
	if other.is_empty() or focus.is_empty():
		return false
	return other.get("kind") == focus.get("kind") and other.get("ref") == focus.get("ref")


func _ray_terrain(from: Vector3, dir: Vector3, max_d: float) -> Vector3:
	# marcha curta: barato e não precisa de física para o terreno
	var t := 0.0
	while t < max_d:
		var p := from + dir * t
		var g: float = world.ground_height(p.x, p.z)
		if p.y <= g + 0.1:
			return Vector3(p.x, g, p.z)
		t += 0.25
	return Vector3.INF


func _ray_water_surface(from: Vector3, dir: Vector3, max_d: float) -> Vector3:
	# Procura a superfície real do rio ou do mar, sem confundir o leito com água.
	if world == null or not world.has_method("water_surface_height"):
		return Vector3.INF
	var previous_t := 0.0
	var previous_surface: float = world.call("water_surface_height", from.x, from.z)
	var previous_valid := previous_surface > -99999.0
	var previous_delta := from.y - previous_surface if previous_valid else 0.0
	var t := 0.25
	while t <= max_d:
		var p := from + dir * t
		var surface: float = world.call("water_surface_height", p.x, p.z)
		if surface > -99999.0:
			var delta := p.y - surface
			if previous_valid and delta <= 0.0 and previous_delta > 0.0:
				var fraction := previous_delta / maxf(previous_delta - delta, 0.001)
				var hit_t := lerpf(previous_t, t, fraction)
				var hit := from + dir * hit_t
				hit.y = world.call("water_surface_height", hit.x, hit.z)
				return hit
			if absf(delta) <= 0.12:
				var near_hit := p
				near_hit.y = surface
				return near_hit
			previous_delta = delta
			previous_valid = true
		else:
			previous_valid = false
		previous_t = t
		t += 0.25
	return Vector3.INF


func prompt_key() -> String:
	if focus.is_empty():
		return ""
	match str(focus["kind"]):
		"harvest":
			var spec: Dictionary = Db.HARVEST.get(str(focus["ref"]["kind"]), {})
			return "prompt." + str(spec.get("action", "pick"))
		"structure":
			var e: Dictionary = focus["ref"]
			if str(e["id"]) == "campfire":
				return "prompt.feed" if bool(e.get("lit", false)) else "prompt.light"
			if str(e["id"]) == "bed":
				return "prompt.rest"
			if str(e["id"]) == "chair":
				return "prompt.sit"
			if str(e["id"]) == "chest":
				return "prompt.open_chest"
			if str(e["id"]) in Structures.STATION_IDS:
				return "prompt.open_station"
			return "prompt.remove"
		"npc":
			return "prompt.talk"
		"animal":
			return "prompt.hunt"
		"felled_tree":
			return "prompt.take_log"
		"water":
			return "prompt.drink" if inv.count("bottle") == 0 else "prompt.fill"
	return "prompt.use"


func _can_interact(_a: Dictionary) -> bool:
	return not focus.is_empty()


## F = PEGAR / INTERAGIR. É um verbo só e diferente dos outros dois:
##   • rato esquerdo — trabalhar no alvo (cortar, picar) enquanto se segura
##   • F             — pegar, encher, acender, dormir, falar, tirar toro
##   • rato direito  — usar o que se tem na mão (comer, beber, colocar)
## Antes, F e o rato faziam o mesmo e o jogador não tinha como saber qual usar.
func _do_interact(_a: Dictionary) -> Dictionary:
	if sleeping:
		return {"handled": false, "reason": "sleeping"}
	if focus.is_empty():
		return {"handled": false, "ok": false}
	match str(focus["kind"]):
		"npc", "water":
			_fire_once()
		"harvest":
			var harvest_kind := str(focus["ref"].get("kind", ""))
			if harvest_kind.begins_with("tree") or harvest_kind == "rock":
				# Árvores e rochas não caem com um toque: o F aponta o caminho
				# (a dica diz qual é) e o trabalho é contínuo, com o rato.
				_tool_hint_t = 3.0
				Bus.toast.emit("prompt.hold_harvest", 2.5)
				return {"handled": true, "ok": true}
			# Plantas são recolhidas num gesto.
			_harvest_done()
		"felled_tree":
			_take_felled_log()
		"structure":
			var e: Dictionary = focus["ref"]
			if str(e["id"]) == "campfire" and bool(e.get("lit", false)):
				# Fogo aceso: mete-se madeira. Sem isto a fogueira era uma
				# lâmpada permanente e não havia razão para juntar lenha.
				return _feed_fire(e)
			if str(e["id"]) == "campfire" and not bool(e.get("lit", false)):
				# Acender fogo não é um botão mágico: é preciso um isqueiro
				# primitivo (sílex + pedra + fibra, feito na Criação).
				if not _has_fire_starter():
					if _tool_hint_t <= 0.0:
						_tool_hint_t = 3.0
						Bus.ui_message.emit(Loc.t("msg.need_fire_kit"), 2.5)
					return {"failed": true, "reason": "no_fire_kit"}
				structures.light(e)
				Sfx.play("craft", -10.0, 1.3)
			elif str(e["id"]) == "bed":
				_rest_in_bed(e)
			elif str(e["id"]) == "chair":
				_rest_in_chair()
			elif str(e["id"]) == "chest":
				_use_chest(e)
			elif str(e["id"]) in Structures.STATION_IDS:
				# A bancada/fogueira acesa são ESTAÇÕES: apontar e F abre a
				# interface DO OBJETO que está no mundo. Antes o F "removia" a
				# estrutura — quem apontasse a uma bancada e carregasse em F
				# destruía a bancada, e o craft só existia dentro do inventário.
				_open_station(str(e["id"]))
			else:
				Game.request("remove_structure", {"entry": e})
	return {"handled": true, "ok": true}


## Abre a interface daquela estação (as receitas dela, e só as dela).
func _open_station(id: String) -> void:
	if menus == null:
		return
	menus.call("open_station", id)
	Sfx.play("ui_open", -12.0, 1.1)


## Este ponto de água é MAR? (o rio e o mar não são a mesma água)
func _is_sea(p: Vector3) -> bool:
	if world == null:
		return false
	var ter: Terrain = world.terrain
	return ter != null and ter.is_ocean(p.x, p.z)


## Tem isqueiro na mão (ou no saco)? Acender fogueiras é a única coisa que ele
## faz — não se gasta, é uma ferramenta.
func _has_fire_starter() -> bool:
	if Db.item(inv.hotbar_id()).get("power", {}).has("fire"):
		return true
	return inv.count("fire_kit") > 0


## Dormir na cama: alinha o corpo ao leito e arranca a sequência do sono.
func _rest_in_bed(e: Dictionary) -> void:
	_start_sleep(e, "bed")


# ══════════════════════════════════════════════════════════════════════════
#  SONO — uma acção, não um teletransporte de tempo
# ══════════════════════════════════════════════════════════════════════════

func _can_sleep(_a: Dictionary) -> bool:
	return not sleeping and survival != null and survival.alive


## Dormir no chão (tecla Z). A cama usa o mesmo caminho, mas com outra
## qualidade e o corpo alinhado ao leito.
func _do_sleep(_a: Dictionary) -> Dictionary:
	if sleeping:
		return {"failed": true, "reason": "already_sleeping"}
	_start_sleep({}, "ground")
	return {"sleeping": true, "place": "ground"}


## Arranca a sequência. `entry` vazio = chão; com entrada = deitar no leito.
func _start_sleep(entry: Dictionary, place: String, short: bool = false) -> void:
	if sleeping or survival == null or not survival.alive:
		return
	# Com uma criatura a rondar, o corpo não deixa: o medo é a única coisa que
	# nenhuma cama resolve. É esta regra que dá peso a ter fogo e abrigo.
	var block := Db.sleep_num("context", "threat_blocks_sleep", 0.35)
	if float(survival.creature_threat) >= block:
		Bus.ui_message.emit(Loc.t("msg.cant_sleep"), 3.0)
		Sfx.play("ui_click", -16.0, 0.6)
		return
	sleeping = true
	player.enabled = false
	player.velocity = Vector3.ZERO
	if not entry.is_empty():
		# deitar NO leito, virado como ele
		var pos: Vector3 = entry["pos"]
		var rot := float(entry.get("rot", 0.0))
		player.teleport(pos + Vector3(0.0, 0.55, 0.0))
		player.yaw = rot
		player.target_yaw = rot
		player.pitch = 0.0
		player.target_pitch = 0.0
	var quality := Db.sleep_quality(place)
	var context := 0.0
	if survival.near_fire:
		context += Db.sleep_num("context", "near_fire", 0.25)
	if survival.sheltered:
		context += Db.sleep_num("context", "sheltered", 0.20)
	Bus.ui_message.emit(Loc.t("msg.sleeping"), 2.0)
	Sfx.play("ui_click", -14.0, 0.7)
	await _sleep_pose(true, short)
	await _sleep_fade(1.0, 0.35 if short else 0.55)
	# O TEMPO passa aqui — e cobra-se (fome, sede) em `survival`.
	var esforco := float(player.exertion) if player != null else 0.0
	var res := survival.nap(quality, context) if short \
		else survival.sleep_until_morning(quality, context, esforco)
	# O esforço é gasto ao dormir (um dia, um cansaço) e o corpo continua.
	if player != null:
		player.exertion = maxf(0.0, float(player.exertion) - 80.0)
	# O fogo também queima enquanto se dorme. Sem esta linha, o fogo seria o
	# único sistema do jogo a quem a noite não passa.
	if structures != null:
		structures.burn_hours(float(res.get("hours", 0.0)))
	await get_tree().create_timer(0.3 if short else 0.45).timeout
	await _sleep_fade(0.0, 0.5 if short else 0.75)
	await _sleep_pose(false, short)
	player.enabled = true
	sleeping = false
	if short:
		Bus.ui_message.emit(Loc.t("msg.nap_done", {"h": "%.1f" % float(res.get("hours", 0.0))}), 3.0)
	else:
		Bus.say("msg.sleep_bed" if place == "bed" else "msg.sleep_ground", 3.0)
	Sfx.play("ui_click", -12.0, 1.0)
	slept.emit(float(res.get("quality", quality)), place)


## Deita/levanta: a câmara desce até ao chão e volta à altura dos olhos.
func _sleep_pose(down: bool, short: bool = false) -> void:
	if player == null or player.cam_pivot == null:
		return
	if _eye_y < 0.0:
		_eye_y = player.cam_pivot.position.y
	var target := (0.62 if short else 0.42) if down else _eye_y
	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(player.cam_pivot, "position:y", target, 0.4 if short else 0.75)
	await t.finished


## Escurece/clareia o ecrã. Sem isto "dormir" era um corte seco.
func _sleep_fade(target: float, secs: float) -> void:
	_ensure_sleep_layer()
	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_sleep_rect, "color:a", target, secs)
	await t.finished


func _ensure_sleep_layer() -> void:
	if _sleep_layer != null:
		return
	_sleep_layer = CanvasLayer.new()
	_sleep_layer.name = "SleepFade"
	_sleep_layer.layer = 120
	add_child(_sleep_layer)
	_sleep_rect = ColorRect.new()
	_sleep_rect.name = "Black"
	_sleep_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_sleep_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sleep_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sleep_layer.add_child(_sleep_rect)


## Cofre: guarda o que tens na mão e devolve o que lá está.
##
## É o par do inventário de 24 slots: a mochila enche-se depressa, e sem um
## sítio onde deixar as coisas o jogador acaba a largar madeira no chão a
## meio da floresta — que é o mesmo que deitá-la fora. Por isso o cofre guarda
## por TIPO (um monte por item), e o F alterna entre pôr e tirar.
func _use_chest(e: Dictionary) -> void:
	if not e.has("items"):
		e["items"] = {}
	var guardado: Dictionary = e["items"]
	var mao := inv.hotbar_id()
	if not mao.is_empty():
		var q: int = inv.count(mao)
		if q <= 0:
			return
		inv.remove(mao, q)
		guardado[mao] = int(guardado.get(mao, 0)) + q
		Bus.ui_message.emit("%s x%d" % [Db.item_name(mao), int(guardado[mao])], 1.6)
		Sfx.play("ui_click", -10.0, 0.85)
		return
	# Mão vazia: devolve o último tipo que lá entrou (não é lotaria).
	for id in guardado.keys():
		var n: int = int(guardado[id])
		if n <= 0:
			guardado.erase(id)
			continue
		inv.add(str(id), n)
		guardado.erase(id)
		Bus.ui_message.emit("%s x%d" % [Db.item_name(str(id)), n], 1.6)
		Sfx.play("ui_click", -10.0, 1.05)
		return
	Bus.ui_message.emit(Loc.t("msg.chest_empty"), 1.6)


## Alimentar uma fogueira acesa: uma unidade de madeira por vez. Devolve o
## combustível que ficou (em horas) para o teste e para o HUD.
func _feed_fire(e: Dictionary) -> Dictionary:
	if inv == null or inv.count("wood") < 1:
		if _tool_hint_t <= 0.0:
			_tool_hint_t = 3.0
			Bus.ui_message.emit(Loc.t("msg.need_wood"), 2.5)
		return {"failed": true, "reason": "no_wood"}
	inv.remove("wood", 1)
	var left := structures.feed(e)
	Bus.ui_message.emit(Loc.t("msg.fire_fed", {"h": "%.1f" % left}), 2.5)
	Sfx.play("craft", -14.0, 0.8)
	return {"ok": true, "fuel": left}


## Sentar numa cadeira: um cochilo, não uma noite. Passa uma hora e meia, não
## acorda de manhã e paga fome e sede como qualquer sono. A cadeira serve para
## aguentar a noite sem cama — não para a saltar.
func _rest_in_chair() -> void:
	_start_sleep({}, "chair", true)


# ══════════════════════════════════════════════════════════════════════════
#  USAR (com progresso para cortar/minar)
# ══════════════════════════════════════════════════════════════════════════
func _handle_use(delta: float) -> void:
	# Rato esquerdo = TRABALHAR (segurar). O F não repete isto: o F pega,
	# acende, dorme, fala (ver _do_interact).
	var work := Input.is_action_pressed("use") and not building
	if focus.is_empty():
		_hold = false
		progress = 0.0
		_impact_t = 0.0
		return
	var kind := str(focus["kind"])
	match kind:
		"npc", "water", "felled_tree":
			progress = 0.0
			_impact_t = 0.0
		"animal":
			# caça: golpes secos, um a um, sem barra de progresso (o bicho foge)
			progress = 0.0
			if work:
				_impact_t -= delta
				if _impact_t <= 0.0:
					_impact_t = 0.45
					_strike_animal()
			else:
				_impact_t = 0.0
		"structure":
			var e: Dictionary = focus["ref"]
			if str(e["id"]) in ["campfire", "bed"]:
				progress = 0.0
				_impact_t = 0.0
			elif work:
				_work_tick(delta, 0.9)
			else:
				progress = maxf(0.0, progress - delta * 0.16)
				_impact_t = 0.0
		"harvest":
			var harvest_kind := str(focus["ref"].get("kind", ""))
			if harvest_kind.begins_with("tree") or harvest_kind == "rock":
				if work:
					_work_tick(delta, 1.0)
				else:
					progress = maxf(0.0, _progress_decay(delta))
			else:
				# Plantas/frutos: só o F (um gesto). O rato não repete a ação.
				progress = 0.0
				_impact_t = 0.0
	_hold = work


## O progresso de um golpe interrompido cai depressa — mas não instantaneamente:
## largar o botão a meio de uma série não deve apagar tudo, senão o trabalho
## contínuo nunca compensa.
func _progress_decay(delta: float) -> float:
	return progress - delta * 0.55


func _work_tick(delta: float, seconds: float) -> void:
	if str(focus["kind"]) == "harvest":
		_hold_work(delta, seconds)
	elif str(focus["kind"]) == "structure":
		_hold_work(delta, seconds)
		if progress < 1.0 or focus.is_empty():
			return
		Game.request("remove_structure", {"entry": focus["ref"]})
		progress = 0.0
		_impact_t = 0.0


func _hold_work(delta: float, seconds: float) -> void:
	_hold = true
	if focus.is_empty():
		return
	if str(focus["kind"]) == "harvest":
		var node: Dictionary = focus["ref"]
		var kind := str(node.get("kind", ""))
		var spec: Dictionary = Db.HARVEST.get(kind, {})
		var max_hp := maxf(float(node.get("max_hp", spec.get("hp", 1))), 1.0)
		node["max_hp"] = max_hp
		_impact_t -= delta
		if _impact_t > 0.0:
			return
		_impact_t = 0.52
		var tool_id := inv.hotbar_id()
		var action := str(spec.get("action", ""))
		var tool: Dictionary = Db.item(tool_id)
		var power: Dictionary = tool.get("power", {})
		var has_tool := power.has(action)
		var needs := str(spec.get("needs", ""))
		if needs != "" and not has_tool:
			# Sem a ferramenta certa o nó não cede NADA — e diz-se porquê, uma
			# vez, em vez de deixar o jogador a bater numa pedra para sempre.
			if _tool_hint_t <= 0.0:
				_tool_hint_t = 3.0
				Bus.ui_message.emit(Loc.t("hud.needs_tool", [Db.item_name(needs)]), 2.5)
				Sfx.play_at("ui_click", focus["pos"], -14.0, 0.7)
			player.hands.swing(0.28)
			return
		# Um nó pode exigir uma ferramenta MELHOR, não só uma qualquer: é assim
		# que a picareta de pedra passa a valer mais do que a primitiva (a rocha
		# dura não cede de outra forma).
		var need_tier := int(spec.get("needs_tier", 0))
		if need_tier > 0 and int(tool.get("tier", 0)) < need_tier:
			if _tool_hint_t <= 0.0:
				_tool_hint_t = 3.0
				Bus.ui_message.emit(Loc.t("hud.needs_better_tool", [Db.item_name(needs)]), 2.5)
				Sfx.play_at("ui_click", focus["pos"], -14.0, 0.6)
			player.hands.swing(0.28)
			return
		# Mãos nuas cortam, mas devagar (o machado tem `power`): é a diferença
		# que faz o primeiro machado de madeira valer a pena.
		var damage := float(power[action]) if has_tool else float(spec.get("hand", 0.5))
		node["hp"] = maxf(0.0, float(node.get("hp", max_hp)) - damage)
		progress = 1.0 - float(node["hp"]) / max_hp
		player.hands.swing(0.35)
		player.hands.recoil_kick(0.35 if has_tool and damage >= 2.0 else 0.2)
		_hit_feedback()
		# Trabalhar cansa: sem isto, cortar era um clique infinito sem custo.
		# E cansa MAIS de barriga vazia — bater com fome quase não rende.
		if survival != null:
			var esforco := 0.55
			if float(survival.hunger) < 25.0:
				esforco *= 1.45
			if float(survival.thirst) < 20.0:
				esforco *= 1.3
			survival.energy = maxf(0.0, survival.energy - esforco)
		if float(node["hp"]) <= 0.0:
			_harvest_done()
		return
	var tool_id := inv.hotbar_id()
	var power := 1.0
	# A fome e a sede pesam nos braços ANTES de o jogador as ler: um golpe com
	# fome sai mais lento. `work_multiplier()` já junta energia e doença.
	progress = minf(1.0, progress + delta * power * survival.work_multiplier() / maxf(seconds, 0.05))
	_impact_t -= delta
	if _impact_t <= 0.0:
		_impact_t = 0.52
		player.hands.swing(0.32)
		_hit_feedback()


## Golpe num animal. Qualquer ferramenta serve; as mãos são as mais fracas —
## caçar com machado poupa golpes (e o animal foge, por isso cada falha dói).
func _strike_animal() -> void:
	if focus.is_empty() or str(focus["kind"]) != "animal":
		return
	var animal := focus["ref"] as Node
	if not is_instance_valid(animal) or not bool(animal.get("alive")):
		return
	var tool_id := inv.hotbar_id()
	var power: Dictionary = Db.item(tool_id).get("power", {})
	var damage := 1.6 if power.has("chop") else (1.0 if power.has("mine") else 0.7)
	if float(power.get("chop", 0.0)) >= 2.0:
		damage = 2.6
	animal.call("hurt", damage)
	player.hands.swing(0.3)
	player.hands.recoil_kick(0.3)
	player.camera_kick(0.18)
	fx.burst(focus["pos"], Color(0.75, 0.35, 0.32), 10)
	if not bool(animal.get("alive")):
		Bus.ui_message.emit(Loc.t("msg.hunted", [Db.item_name("meat_raw")]), 2.5)


func _hit_feedback() -> void:
	if focus.is_empty():
		return
	var p: Vector3 = focus["pos"]
	match str(focus["kind"]):
		"harvest":
			var id := str(focus["ref"]["kind"])
			if id.begins_with("tree"):
				Sfx.play_at("chop", p, -8.0, randf_range(0.95, 1.08))
				# Duas leituras no mesmo golpe: lascas de madeira e folhas a
				# tremer. O som e a cor dizem que aquilo é uma árvore, não uma
				# parede de madeira maciça.
				fx.burst(p, Color(0.55, 0.38, 0.24), 8)
				fx.burst(p + Vector3(0, 0.45, 0), Color(0.30, 0.52, 0.24), 5)
				Sfx.play_at("leaf_rustle", p + Vector3(0, 0.45, 0), -17.0,
					randf_range(0.9, 1.15))
				player.camera_kick(0.10 if float(focus["ref"].get("hp", 1.0)) > 0.0 else 0.18)
			elif id == "rock":
				Sfx.play_at("mine", p, -8.0, randf_range(0.95, 1.1))
				fx.burst(p, Color(0.7, 0.7, 0.76), 10)
				player.camera_kick(0.14)
			else:
				Sfx.play_at("pick", p, -12.0)
				fx.burst(p, Color(0.45, 0.7, 0.35), 6)
		"structure":
			Sfx.play_at("chop", p, -10.0, 1.2)
			fx.burst(p, Color(0.6, 0.42, 0.28), 6)
			player.camera_kick(0.08)


func _harvest_done() -> void:
	var n: Dictionary = focus["ref"]
	var harvest_kind := str(n["kind"])
	var is_tree := harvest_kind.begins_with("tree")
	var spec: Dictionary = Db.HARVEST.get(harvest_kind, {})
	var yields: Dictionary = spec.get("yields", {})
	var dropped_total := 0
	for k in yields:
		# Madeira fica no tronco abatido; o jogador retira cada toro com F.
		if is_tree and str(k) == "wood":
			continue
		var qty := int(yields[k])
		var bonus := 0.35 if str(Game.profile.get("soul", "")) != "curious" else 0.6
		if randf() < bonus:
			qty += 1
		# As mãos desperdiçam, a ferramenta aproveita. É uma diferença que se vê
		# no material que entra na mochila, não no texto do menu.
		var escala := Db.yield_scale(inv.hotbar_id(), str(spec.get("action", "")))
		qty = maxi(int(round(float(qty) * escala)), 1)
		# Colher altera o mundo; não teletransporta o recurso para a mochila.
		# Cada tipo de material cria um pickup físico visível para o jogador.
		_drop_resource(str(k), qty, n["pos"] as Vector3)
		dropped_total += qty
	n["alive"] = false
	world.hide_harvest(n)
	world.mark_harvested(n)
	Sfx.play_at("chop", focus["pos"], -4.0, 0.72)
	fx.burst(focus["pos"], Color(0.6, 0.45, 0.3), 16)
	Bus.node_harvested.emit(str(n["species"]), str(n["kind"]), focus["pos"])
	Game.bump("harvest_" + str(n["kind"]))
	progress = 0.0
	focus = {}


func _drop_resource(id: String, qty: int, at: Vector3) -> void:
	DroppedItem.spawn(world, id, qty, at, inv, player)


func _take_felled_log() -> void:
	if focus.is_empty() or str(focus.get("kind", "")) != "felled_tree":
		return
	var tree := focus.get("ref") as Node3D
	if not is_instance_valid(tree) or not tree.has_method("take_log") \
			or not bool(tree.call("take_log")):
		focus = {}
		return
	var at := tree.global_position + Vector3(float(tree.get("fall_direction")) \
		* float(tree.get("height")) * 0.30, float(tree.get("trunk_radius")) + 0.48, 0.18)
	_drop_resource("wood", 1, at)
	Game.bump("item_wood")
	Sfx.play_at("chop", at, -12.0, randf_range(0.94, 1.08))
	if int(tree.get("remaining_logs")) <= 0:
		focus = {}


func _fire_once() -> void:
	match str(focus["kind"]):
		"npc":
			var npc: Node = focus["ref"]
			if npc.has_method("talk_to"):
				npc.call("talk_to")
		"water":
			var salgada := _is_sea(focus["pos"] as Vector3)
			if inv.count("bottle") > 0:
				inv.remove("bottle", 1)
				# Água do mar enche a garrafa — mas com sal. O jogador vê a
				# diferença no ícone e no nome; ferver NÃO a salva (o sal não
				# evapora numa panela), o que o obriga a procurar água doce.
				inv.add("water_salt" if salgada else "water", 1)
				Sfx.play("splash", -10.0, 1.2)
				Bus.say("msg.water_salt_filled" if salgada else "msg.water_filled", 2.2)
			elif salgada:
				# Beber do mar sem garrafa: alivia a boca e cobra-se em SEDE,
				# nunca em dano instantâneo.
				survival.drink(8.0, 0.0)
				survival.dehydrate(45.0)
				Sfx.play("drink", -9.0)
				Bus.say("msg.sea_water", 2.8)
			else:
				# Direto da fonte: mata a sede, mas é água crua.
				survival.drink(22.0, 0.35)
				Sfx.play("drink", -9.0)
				Bus.say("msg.drink_raw", 2.4)


# ══════════════════════════════════════════════════════════════════════════
#  CONSTRUIR
# ══════════════════════════════════════════════════════════════════════════
func _can_toggle_build(_a: Dictionary) -> bool:
	return true


func _do_toggle_build(_a: Dictionary) -> Dictionary:
	if building:
		building = false
		ghost.visible = false
		return {"building": false}
	var id := inv.hotbar_id()
	if not Db.is_placeable(id):
		# mensagem certa: não é "faltam materiais", é "isso não se coloca"
		Bus.say("prompt.blocked", 2.0)
		return {"building": false, "failed": true, "reason": "not_placeable"}
	building = true
	build_rot = snappedf(player.yaw + PI, PI * 0.25)
	return {"building": true}


func _ghost_place() -> Dictionary:
	var cam := player.camera
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var hit := _ray_terrain(from, dir, 8.0)
	if hit == Vector3.INF:
		var flat := from + dir * 3.0
		hit = Vector3(flat.x, world.ground_height(flat.x, flat.z), flat.z)
	hit.x = snappedf(hit.x, 0.5)
	hit.z = snappedf(hit.z, 0.5)
	return {"pos": hit, "rot": build_rot}


func _update_ghost() -> void:
	if not building:
		ghost.visible = false
		return
	var id := inv.hotbar_id()
	if not Db.is_placeable(id):
		building = false
		ghost.visible = false
		return
	var st: SpeciesKit.Structure = world.species.structures[str(Db.item(id)["place"])]
	if ghost.mesh != st.mesh:
		ghost.mesh = st.mesh
		ghost.position = Vector3.ZERO
	var place := _ghost_place()
	ghost.global_position = place["pos"] + Vector3(0, st.size.y * 0.5, 0)
	ghost.rotation.y = place["rot"]
	ghost.visible = true
	var ok := inv.count(id) > 0
	ghost_mat.albedo_color = Color(0.6, 0.95, 0.7, 0.45) if ok else Color(1.0, 0.4, 0.4, 0.45)


func _can_place(_a: Dictionary) -> bool:
	return building and inv.count(inv.hotbar_id()) > 0


func _do_place(_a: Dictionary) -> Dictionary:
	var id := inv.hotbar_id()
	var place := _ghost_place()
	if not inv.remove(id, 1):
		return {"failed": true}
	structures.place(str(Db.item(id)["place"]), place["pos"], place["rot"], false)
	Sfx.play_at("place", place["pos"], -6.0)
	Game.bump("place_" + str(Db.item(id)["place"]))
	player.hands.swing(0.2)
	if inv.count(id) <= 0:
		building = false
	return {"placed": str(id), "pos": place["pos"]}


func _can_remove(_a: Dictionary) -> bool:
	return _a.has("entry")


func _do_remove(args: Dictionary) -> Dictionary:
	var e: Dictionary = args["entry"]
	structures.remove(e)
	inv.add(str(e["id"]), 1)
	Sfx.play_at("chop", e["pos"], -8.0, 1.1)
	fx.burst(e["pos"] + Vector3(0, 0.6, 0), Color(0.6, 0.44, 0.3), 12)
	return {"removed": str(e["id"])}


# ══════════════════════════════════════════════════════════════════════════
#  BANCADA
# ══════════════════════════════════════════════════════════════════════════
# ══════════════════════════════════════════════════════════════════════════
#  USAR O QUE ESTÁ NA MÃO (rato direito)
# ══════════════════════════════════════════════════════════════════════════
# Antes, comer/beber só acontecia dentro da mochila, com o jogo parado. Agora
# o item da barra usa-se no mundo, que é onde o jogador está a olhar.
func _can_use_item(_a: Dictionary) -> bool:
	return true


func _do_use_item(_a: Dictionary) -> Dictionary:
	var id := inv.hotbar_id()
	if id.is_empty():
		player.hands.swing(0.3)
		return {"failed": true, "reason": "empty_hand"}
	var def := Db.item(id)
	# 1) colocável: põe a peça onde a sombra está (o B continua a rodá-la)
	if Db.is_placeable(id):
		if not building:
			building = true
			build_rot = snappedf(player.yaw + PI, PI * 0.25)
		return _do_place({})
	# 2) comida e água: um gesto, no sítio onde se está
	if id == "water_salt":
		if inv.remove(id, 1):
			inv.add("bottle", 1)
			survival.drink(8.0, 0.0)      # o alívio da boca
			survival.dehydrate(45.0)      # e a factura, em sede
			Bus.ui_message.emit(Loc.t("msg.sea_water"), 2.8)
			Sfx.play("drink", -9.0)
			return {"used": id, "dehydrated": true}
		return {"failed": true, "reason": "no_water"}
	if id == "water" or id == "water_clean":
		if inv.remove(id, 1):
			inv.add("bottle", 1)
			survival.drink(float(def.get("drink_amount", 50.0)), float(def.get("risk", 0.0)))
			Bus.ui_message.emit(Loc.t("msg.drink_flask"), 2.0)
			return {"used": id}
		return {"failed": true, "reason": "no_water"}
	if str(def.get("kind", "")) == "food":
		if inv.remove(id, 1):
			var ate: Dictionary = survival.eat(float(def.get("food", 0.0)),
				float(def.get("drink", 0.0)), float(def.get("risk", 0.0)))
			# O resultado tem de ser visível: quem come cru tem de perceber por
			# que é que se sentiu mal — e que a fogueira resolve isso.
			if bool(ate.get("sick", false)):
				Bus.ui_message.emit(Loc.t("msg.food_sick", {"item": Db.item_name(id)}), 3.2)
			else:
				Bus.ui_message.emit(Loc.t("msg.ate", {"item": Db.item_name(id)}), 2.0)
			return {"used": id, "ate": true, "sick": bool(ate.get("sick", false))}
		return {"failed": true, "reason": "no_food"}
	# 3) cana de pesca
	if float(def.get("power", {}).get("fish", 0.0)) > 0.0:
		return _fish_action()
	# 4) garrafa vazia: enche-se na água que se está a olhar
	if id == "bottle" and not focus.is_empty() and str(focus["kind"]) == "water":
		if inv.remove("bottle", 1):
			inv.add("water", 1)
			Sfx.play_at("splash", focus["pos"], -10.0)
			Bus.ui_message.emit(Loc.t("msg.filled_flask"), 2.0)
			return {"used": id, "filled": true}
	# 5) ferramenta: dizer para que serve, em vez de não fazer nada
	if not str(def.get("power", {})).is_empty():
		Bus.ui_message.emit(Loc.t("msg.tool_hint", [Db.item_name(id)]), 2.0)
		player.hands.swing(0.25)
		return {"used": id, "hint": true}
	# 6) tocha: acende/apaga a luz da mão (o main faz o resto ao trocar de item)
	if id == "torch":
		Bus.ui_message.emit(Loc.t("msg.torch_lit"), 2.0)
		player.hands.swing(0.2)
		return {"used": id}
	player.hands.swing(0.3)
	return {"failed": true, "reason": "nothing_to_do"}


## Pesca: lançar / puxar. O peixe só vem se o jogador puxar na janela em que o
## flutuador se afunda — sem isto a cana era um item morto no inventário.
func _fish_action() -> Dictionary:
	if _fish_state == 2:
		_fish_state = 0
		var qty := 1
		var luck := 0.5 if str(Game.profile.get("soul", "")) == "curious" else 0.3
		if randf() < luck:
			qty = 2
		var left := inv.add("fish_raw", qty)
		if left > 0:
			# mochila cheia: o que não coube cai aos pés, não desaparece
			_drop_resource("fish_raw", left, player.global_position)
		Sfx.play("pick", -7.0, 1.15)
		Bus.ui_message.emit(Loc.t("msg.caught", [Db.item_name("fish_raw")]), 2.2)
		Game.bump("fish_caught")
		player.hands.swing(0.3)
		return {"used": "rod", "caught": qty}
	if _fish_state == 1:
		_fish_state = 0
		Sfx.play("ui_click", -14.0, 1.1)
		Bus.toast.emit("msg.reel", 1.2)
		return {"used": "rod", "reeled": true}
	if not _near_water():
		Bus.ui_message.emit(Loc.t("prompt.need_water"), 2.0)
		return {"failed": true, "reason": "no_water"}
	_fish_state = 1
	_fish_t = randf_range(2.5, 8.0)
	Sfx.play_at("splash", player.global_position, -12.0, 1.2)
	Bus.toast.emit("prompt.fish_wait", 2.0)
	Game.bump("fish_cast")
	return {"used": "rod", "cast": true}


func _near_water() -> bool:
	if not focus.is_empty() and str(focus["kind"]) == "water":
		return true
	if world.is_in_water(player.global_position):
		return true
	var ahead := player.global_position - Vector3(0, 1.2, 0) \
		+ -player.camera.global_transform.basis.z * 3.5
	return world.is_in_water(ahead)


func _tick_fishing(delta: float) -> void:
	if _fish_state == 0:
		return
	if inv.hotbar_id() != "rod":
		_fish_state = 0
		return
	if _fish_state == 1:
		_fish_t -= delta
		if _fish_t <= 0.0:
			_fish_state = 2
			_fish_t = 1.6
			Sfx.play("splash", -6.0, 0.85)
			Bus.toast.emit("prompt.reel_now", 1.6)
		return
	# a morder: se não puxar a tempo, o peixe foge
	_fish_t -= delta
	if _fish_t <= 0.0:
		_fish_state = 1
		_fish_t = randf_range(2.0, 5.0)
		Bus.toast.emit("msg.fish_lost", 1.6)


func nearby_stations() -> Array:
	return structures.stations_near(player.global_position, 4.5)


## A receita existe? A ESTAÇÃO decide-se no `_do_craft`: negar aqui dava
## "denied" sem explicação. O menu já só mostra receitas da estação que está
## ao lado (`Db.recipes_for(nearby_stations())`), por isso não há risco de
## oferecer o que não se pode fazer.
func _can_craft(args: Dictionary) -> bool:
	return not Db.recipe(str(args.get("recipe", ""))).is_empty()


func _do_craft(args: Dictionary) -> Dictionary:
	var r := Db.recipe(str(args.get("recipe", "")))
	if r.is_empty():
		return {"failed": true, "reason": "no_recipe"}
	# A estação é verificada AQUI outra vez: um craft pedido por fora (atalho,
	# save, script) não pode ignorar a bancada que a receita exige.
	var station := str(r.get("station", ""))
	if station != "" and not (station in nearby_stations()):
		Bus.ui_message.emit(Loc.t("msg.need_station", [Db.item_name(station)]), 2.4)
		return {"failed": true, "reason": "no_station", "station": station}
	# importante: um craft que não aconteceu TEM de vir como falha,
	# senão o OBSERVABLE RESULT mente a quem chamou o comando
	var ok := inv.craft(r)
	if not ok:
		return {"failed": true, "crafted": false, "reason": "no_materials"}
	return {"crafted": true, "result": str(r["result"])}
