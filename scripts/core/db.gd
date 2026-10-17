extends Node
## Db — todas as definições de dados do jogo, num sítio só.
##
## É a caixa de LEGO: poucas peças boas (recursos, ferramentas, comida,
## estruturas) + regras de combinação (receitas) . Tudo o que é "conteúdo"
## entra aqui; o código dos sistemas não conhece nomes de itens.

## Receitas em vigor (data/recipes.json). Vazio = usa-se a lista em código.
var recipes: Array = []
## Nome de cada estação, como o menu o mostra ("Criação", "Bancada", "Fogueira").
var station_labels: Dictionary = {}

const ITEMS := {
	# ── recursos ────────────────────────────────────────────────────────────
	"wood":         {"kind": "resource", "stack": 40, "icon": "wood"},
	"stone":        {"kind": "resource", "stack": 40, "icon": "stone"},
	"flint":        {"kind": "resource", "stack": 20, "icon": "flint"},
	"fiber":        {"kind": "resource", "stack": 40, "icon": "fiber"},
	"leaf":         {"kind": "resource", "stack": 60, "icon": "leaf"},
	"stick":        {"kind": "resource", "stack": 40, "icon": "stick"},
	# ── comida ──────────────────────────────────────────────────────────────
	"mushroom":     {"kind": "food", "stack": 20, "icon": "mushroom",
					 "food": 18, "drink": 0, "risk": 0.25},
	"meat_raw":     {"kind": "food", "stack": 10, "icon": "meat_raw",
					 "food": 20, "drink": 0, "risk": 0.4},
	"meat_cooked":  {"kind": "food", "stack": 10, "icon": "meat_cooked",
					 "food": 45, "drink": 0, "risk": 0.0},
	"fish_raw":     {"kind": "food", "stack": 10, "icon": "fish_raw",
					 "food": 18, "drink": 0, "risk": 0.35},
	"fish_cooked":  {"kind": "food", "stack": 10, "icon": "fish_cooked",
					 "food": 40, "drink": 0, "risk": 0.0},
	"stew":         {"kind": "food", "stack": 5, "icon": "stew",
					 "food": 70, "drink": 25, "risk": 0.0},
	# ── ferramentas / utilidades ────────────────────────────────────────────
	# TRÊS degraus, e cada um existe por uma RAZÃO, não por um número:
	#   CRIAÇÃO (na mão)
	#     `stone_blade`      — lasca amarrada a um ramo: corta plantas, arbustos
	#                          e caça melhor que os punhos. NÃO pica pedra.
	#     `primitive_axe`    — machado primitivo (pau + pedra + fibra): abate
	#                          árvores em 6 golpes em vez de 18.
	#     `primitive_pickaxe`— picareta primitiva: é A FERRAMENTA QUE ABRE O
	#                          MUNDO. A primeira com `mine`: sem ela a rocha é
	#                          impossível e a pedra fica presa na pedra solta.
	#   BANCADA
	#     `axe` / `pickaxe`  — pedra trabalhada: mais potência, MENOS
	#                          desperdício por nó (ver `yield_scale`) e acesso
	#                          à rocha dura, que só cede a tier >= 2.
	# A família de madeira tinha exactamente esta função (era a travessia para a
	# pedra) e foi apagada por parecer "um passo intermédio". O nome estava
	# errado; a função não. Aqui fica com o nome certo: PRIMITIVA.
	"stone_blade":  {"kind": "tool", "stack": 4, "icon": "stone_blade",
					 "power": {"chop": 0.62}, "tier": 1, "tool": "blade"},
	"primitive_axe": {"kind": "tool", "stack": 1, "icon": "primitive_axe",
					 "power": {"chop": 1.15}, "tier": 1, "tool": "axe"},
	"primitive_pickaxe": {"kind": "tool", "stack": 1, "icon": "primitive_pickaxe",
					 "power": {"mine": 1.0}, "tier": 1, "tool": "pickaxe"},
	"axe":          {"kind": "tool", "stack": 1, "icon": "axe", "power": {"chop": 2.2},
					 "tier": 2, "tool": "axe"},
	"pickaxe":      {"kind": "tool", "stack": 1, "icon": "pickaxe", "power": {"mine": 2.4},
					 "tier": 2, "tool": "pickaxe"},
	# Isqueiro primitivo: acender uma fogueira não pode ser um botão mágico.
	"fire_kit":     {"kind": "tool", "stack": 1, "icon": "fire_kit",
					 "power": {"fire": 1.0}, "tier": 1, "tool": "fire"},
	"rod":          {"kind": "tool", "stack": 1, "icon": "rod", "power": {"fish": 1.0}},
	"torch":        {"kind": "tool", "stack": 5, "icon": "torch", "light": 5.0, "fuel": 180.0},
	"bottle":       {"kind": "tool", "stack": 1, "icon": "bottle", "capacity": 100.0},
	# Água do rio é ÁGUA CRUA: bebe-se, mata a sede toda, mas arrisca-se. A
	# fervida é o mesmo frasco depois de passar pela fogueira — é esta a razão
	# de existir uma fogueira no primeiro dia (e de o ciclo fechar).
	"water":        {"kind": "tool", "stack": 1, "icon": "water", "drink_amount": 55.0,
					 "risk": 0.45, "raw": true},
	"water_clean":  {"kind": "tool", "stack": 1, "icon": "water", "drink_amount": 80.0,
					 "risk": 0.0, "boiled": true},
	# Água do mar. Alivia a boca por um instante e COBRA-O em sede: ferve-la não
	# a salva (o sal não evapora numa panela) — o mar obriga a procurar água doce.
	# É por isto que o mar tem uma REGRA e não é só "água azul".
	"water_salt":   {"kind": "tool", "stack": 1, "icon": "water_salt", "drink_amount": 8.0,
					 "risk": 0.0, "salty": true},
	# ── estruturas (colocáveis) ─────────────────────────────────────────────
	"campfire":     {"kind": "structure", "stack": 3, "icon": "campfire",
					 "place": "campfire", "light": 9.0},
	"wall":         {"kind": "structure", "stack": 20, "icon": "wall", "place": "wall"},
	"floor":        {"kind": "structure", "stack": 20, "icon": "floor", "place": "floor"},
	"pillar":       {"kind": "structure", "stack": 20, "icon": "pillar", "place": "pillar"},
	"bed":          {"kind": "structure", "stack": 2, "icon": "bed", "place": "bed"},
	"workbench":    {"kind": "structure", "stack": 4, "icon": "workbench",
					 "place": "workbench"},
	# Mobiliário que SERVE para algo (não é decoração): o cofre guarda, a cadeira
	# deixa descansar sem deitar.
	"chest":        {"kind": "structure", "stack": 4, "icon": "chest",
					 "place": "chest", "storage": 24},
	"chair":        {"kind": "structure", "stack": 4, "icon": "chair",
					 "place": "chair", "rest": 8.0},
}

## Receitas: vivem em `data/recipes.json` (editável sem tocar em código).
## `needs` são consumidos, `result` é criado e `station` decide ONDE se faz:
##   ""          → CRIAÇÃO, na mão, com o que se apanha do chão
##   "workbench" → BANCADA: ferramentas a sério, mobiliário, peças de construção
##   "campfire"  → FOGUEIRA: cozinhar e ferver água
## O degrau não é burocracia: é o que separa "apanhei isto agora" de "construí
## uma oficina". Esta lista é a RESERVA do data/recipes.json — as duas têm de
## dizer o mesmo, e há um teste que o verifica ("as receitas do JSON e as de
## reserva dizem o mesmo"): foi por ficarem dessincronizadas que apareceu uma
## família de ferramentas "apagada" a continuar a existir no ficheiro.
const RECIPES := [
	{"id": "stick", "result": "stick", "qty": 2, "needs": {"wood": 1}},
	{"id": "leaf_fiber", "result": "fiber", "qty": 1, "needs": {"leaf": 3}},
	{"id": "torch", "result": "torch", "qty": 2, "needs": {"stick": 1, "fiber": 1}},
	{"id": "fire_kit", "result": "fire_kit", "qty": 1, "needs": {"flint": 2, "stone": 1, "fiber": 2}},
	{"id": "stone_blade", "result": "stone_blade", "qty": 1, "needs": {"stone": 2, "stick": 1, "fiber": 2}},
	{"id": "workbench", "result": "workbench", "qty": 1, "needs": {"wood": 4, "stick": 2}},
	{"id": "campfire", "result": "campfire", "qty": 1, "needs": {"stone": 4, "stick": 3, "wood": 2}},
	{"id": "stone_axe", "result": "axe", "qty": 1, "needs": {"stick": 2, "stone": 3, "fiber": 1}, "station": "workbench"},
	{"id": "stone_pickaxe", "result": "pickaxe", "qty": 1, "needs": {"stick": 2, "stone": 4, "fiber": 1}, "station": "workbench"},
	{"id": "bottle", "result": "bottle", "qty": 1, "needs": {"fiber": 4, "wood": 1}},
	{"id": "primitive_axe", "result": "primitive_axe", "qty": 1, "needs": {"stick": 2, "stone": 2, "fiber": 2}},
	{"id": "primitive_pickaxe", "result": "primitive_pickaxe", "qty": 1, "needs": {"stick": 2, "stone": 3, "fiber": 2}},
	{"id": "rod", "result": "rod", "qty": 1, "needs": {"stick": 3, "fiber": 3}, "station": "workbench"},
	{"id": "chest", "result": "chest", "qty": 1, "needs": {"wood": 6, "fiber": 2}, "station": "workbench"},
	{"id": "chair", "result": "chair", "qty": 1, "needs": {"wood": 3, "fiber": 1}, "station": "workbench"},
	{"id": "bed", "result": "bed", "qty": 1, "needs": {"fiber": 12, "stick": 4}, "station": "workbench"},
	{"id": "wall", "result": "wall", "qty": 1, "needs": {"wood": 3}, "station": "workbench"},
	{"id": "floor", "result": "floor", "qty": 1, "needs": {"wood": 2}, "station": "workbench"},
	{"id": "pillar", "result": "pillar", "qty": 2, "needs": {"wood": 2, "fiber": 1}, "station": "workbench"},
	{"id": "boil_water", "result": "water_clean", "qty": 1, "needs": {"water": 1}, "station": "campfire"},
	{"id": "fish_cooked", "result": "fish_cooked", "qty": 1, "needs": {"fish_raw": 1}, "station": "campfire"},
	{"id": "meat_cooked", "result": "meat_cooked", "qty": 1, "needs": {"meat_raw": 1}, "station": "campfire"},
	{"id": "stew", "result": "stew", "qty": 1, "needs": {"meat_cooked": 1, "mushroom": 2, "water": 1}, "station": "campfire"},
]

## Etiquetas das estações (o menu mostra estas palavras, não os ids).
const STATION_LABELS := {"": "menu.craft_handmade", "workbench": "menu.craft_bench",
	"campfire": "menu.craft_fire"}


## As receitas em vigor: as de data/recipes.json quando existirem.
func all_recipes() -> Array:
	return recipes if not recipes.is_empty() else RECIPES


## O que sai de cada nó do mundo quando é colhido.
##
##   "hand"     — dano de cada golpe com as MÃOS (o machado manda no `power`).
##   "needs"    — ferramenta mínima: sem ela o nó não cede, e a barra diz porquê.
##                É isto que faz a picareta valer alguma coisa.
##   "tool"     — ferramenta que acelera (não obriga).
const HARVEST := {
	"tree_oak":    {"action": "chop", "tool": "axe", "hand": 0.34, "hp": 6,
					"yields": {"wood": 3, "stick": 1, "leaf": 3}},
	"tree_pine":   {"action": "chop", "tool": "axe", "hand": 0.30, "hp": 8,
					"yields": {"wood": 4, "leaf": 2}},
	"tree_birch":  {"action": "chop", "tool": "axe", "hand": 0.34, "hp": 5,
					"yields": {"wood": 2, "stick": 2, "leaf": 3}},
	"tree_sakura": {"action": "chop", "tool": "axe", "hand": 0.38, "hp": 6,
					"yields": {"wood": 2, "leaf": 2}},
	"tree_willow":{"action": "chop", "tool": "axe", "hand": 0.32, "hp": 7,
					"yields": {"wood": 3, "stick": 2, "leaf": 4}},
	"rock":        {"action": "mine", "tool": "pickaxe", "needs": "pickaxe", "hp": 5,
					"yields": {"stone": 2, "flint": 1}},
	# Rocha dura: a pedra consolidada. Cede a qualquer picareta (tier 1) mas
	# devolve pouco; com picareta de pedra (tier 2) parte depressa e rende o
	# DOBRO. É isto que faz a picareta de pedra valer a bancada — sem um nó que
	# responda à ferramenta melhor, "tier 2" era só um número maior.
	"rock_hard":   {"action": "mine", "tool": "pickaxe", "needs": "pickaxe",
					"needs_tier": 2, "hp": 9,
					"yields": {"stone": 4, "flint": 2}},
	# Arbusto: o "primeiro minuto" do jogo tem de dar para fibra, folha e um
	# graveto seco. Antes dava 1 fibra e o jogador precisava de 12 arbustos
	# para uma cama — ou de abater uma árvore à mão só para ter um graveto.
	"bush":        {"action": "pick", "tool": "", "hp": 1,
					"yields": {"fiber": 2, "leaf": 3, "stick": 1}},
	"tuft":        {"action": "pick", "tool": "", "hp": 1, "yields": {"fiber": 2}},
	"mushroom":    {"action": "pick", "tool": "", "hp": 1, "yields": {"mushroom": 1}},
	# Pedra solta: apanha-se com as mãos e dá PEDRA. É a porta de entrada da
	# progressão — sem ela não havia como chegar à primeira picareta.
	"flint_node":  {"action": "pick", "tool": "", "hp": 1,
					"yields": {"stone": 3, "flint": 1}},
}

## Objectivos do prólogo/primeiras horas. `goal` é verificável pelo Game.
const OBJECTIVES := [
	{"id": "wood",     "target": 8,  "track": "item_wood",     "next": "campfire"},
	{"id": "campfire", "target": 1,  "track": "place_campfire", "next": "light"},
	{"id": "light",    "target": 1,  "track": "light_campfire", "next": "survive"},
	{"id": "survive",  "target": 1,  "track": "night_survived", "next": "talk"},
	{"id": "talk",     "target": 1,  "track": "npc_talked",     "next": ""},
]


func item(id: String) -> Dictionary:
	if Mods.has_item(id):
		return Mods.item(id)
	return ITEMS.get(id, {})


func item_name(id: String) -> String:
	var custom = item(id).get("name", "")
	if str(custom) != "":
		return str(custom)
	return Loc.t("item." + id)


func item_kind(id: String) -> String:
	return str(item(id).get("kind", ""))


func max_stack(id: String) -> int:
	return int(item(id).get("stack", 1))


## Quanto material sai de um nó conforme a ferramenta na mão.
##
## É aqui que a diferença entre MÃO e FERRAMENTA deixa de ser "mais depressa":
## a mão estraga parte do que apanha e a ferramenta de pedra aproveita mais do
## que o nó dá. Sem isto, tier era decoração.
## Qualidade de descanso de um sítio ("ground", "chair", "bed").
##
## Sem data/sleep.json há uma reserva sensata — mas o JSON manda, para se poder
## afinar o sono sem recompilar nada.
func sleep_quality(place: String) -> float:
	var places = sleep_cfg.get("places", {})
	if typeof(places) == TYPE_DICTIONARY and (places as Dictionary).has(place):
		var entry = (places as Dictionary)[place]
		if typeof(entry) == TYPE_DICTIONARY:
			return float((entry as Dictionary).get("quality", 0.3))
	var fallback := {"ground": 0.30, "chair": 0.45, "bed": 1.0}
	return float(fallback.get(place, 0.30))


## Um número do data/sleep.json (secção + chave), com reserva.
func sleep_num(section: String, key: String, fallback: float) -> float:
	var sec = sleep_cfg.get(section, {})
	if typeof(sec) == TYPE_DICTIONARY and (sec as Dictionary).has(key):
		return float((sec as Dictionary)[key])
	return fallback


func yield_scale(tool_id: String, action: String) -> float:
	var def := item(tool_id)
	if def.is_empty() or not def.get("power", {}).has(action):
		# Mãos nuas. Apanhar é o que as mãos fazem bem (bagas, fibra, pedra
		# solta): não se perde nada. ARRANCAR madeira ou pedra sem ferramenta
		# estraga parte do material — é aí que a mão perde.
		# Sem esta distinção o primeiro minuto era colher arbustos até secar o
		# vale só para juntar fibra: o jogador desistia antes da 1ª ferramenta.
		if action == "chop" or action == "mine":
			return 0.7
		return 1.0
	match int(def.get("tier", 1)):
		1: return 1.0
		2: return 1.35
		_: return 1.7


func is_placeable(id: String) -> bool:
	return item(id).has("place")


## Como se chama esta estação no ecrã. Vem de data/recipes.json quando lá está;
## caso contrário usa a etiqueta embutida. Nunca mostra o id cru ao jogador.
func station_label(id: String) -> String:
	var key := str(station_labels.get(id, STATION_LABELS.get(id, "")))
	if key.is_empty():
		return id
	var nome := Loc.t(key)
	if nome == key:
		name = nome if id.is_empty() else id
	return nome if nome != key else id


func recipe(id: String) -> Dictionary:
	for r in all_recipes():
		if str(r["id"]) == id:
			return r
	return Mods.recipe(id)


## Receitas visíveis dado o que está por perto (`near` = ids de estações).
func recipes_for(near: Array = []) -> Array:
	var out := []
	for r in all_recipes():
		var st := str(r.get("station", ""))
		if st.is_empty() or st in near:
			out.append(r)
	for r in Mods.all_recipes():
		var st2 := str(r.get("station", ""))
		if st2.is_empty() or st2 in near:
			out.append(r)
	return out


## Receitas que existem mas exigem uma estação que não está ao lado. O menu
## mostra-as à parte ("precisas de bancada") em vez de as esconder: sem isto o
## jogador não sabia que havia mais degraus de ferramentas para desbloquear.
func locked_recipes(near: Array = []) -> Array:
	var out := []
	for lista in [all_recipes(), Mods.all_recipes()]:
		for r in lista:
			var st := str(r.get("station", ""))
			if st != "" and not (st in near):
				out.append(r)
	return out


# ══════════════════════════════════════════════════════════════════════════
#  CAMADA DATA-DRIVEN — data/*.json (+ overrides de Mods)
#
#  Biomas, afinação do terreno, qualidade e espécies vivem em JSON editável
#  (data/). Cada accessor aceita um `fallback`: se o JSON faltar ou for
#  inválido, devolve o valor embutido e o jogo comporta-se EXATAMENTE como
#  antes. É 100% aditivo — não parte nada.
# ══════════════════════════════════════════════════════════════════════════
var biomes: Array = []
var terrain_cfg: Dictionary = {}
var quality_cfg: Dictionary = {}
var species_cfg: Dictionary = {}
## Regras do sono (data/sleep.json): qualidades do chão/cadeira/cama, horas e
## custo em fome/sede. O desenho do projeto é chão (mau) → cadeira (cochilo) →
## cama (boa); aqui ficam os números, para se afinarem sem tocar em código.
var sleep_cfg: Dictionary = {}
var _biome_idx: Dictionary = {}


func _ready() -> void:
	name = "Db"
	reload_data()


## (Re)carrega os dados de data/. Chamado no arranque; pode ser chamado de
## novo após instalar/desativar mods para aplicar overrides.
func reload_data() -> void:
	var bd := _json_dict("res://data/biomes.json")
	var arr = bd.get("biomes", [])
	biomes = arr if typeof(arr) == TYPE_ARRAY else []
	terrain_cfg = _json_dict("res://data/terrain.json")
	quality_cfg = _json_dict("res://data/quality.json")
	sleep_cfg = _json_dict("res://data/sleep.json")
	species_cfg = _json_dict("res://data/species.json")
	var rc := _json_dict("res://data/recipes.json")
	var lista = rc.get("recipes", [])
	recipes = []
	if typeof(lista) == TYPE_ARRAY:
		# só entram entradas com id/result: o JSON é editável à mão e uma linha
		# a mais não pode rebentar o menu
		for r in lista:
			if typeof(r) == TYPE_DICTIONARY and r.has("id") and r.has("result"):
				recipes.append(r)
	var labs = rc.get("stations", {})
	station_labels = labs if typeof(labs) == TYPE_DICTIONARY else {}
	_rebuild_biome_idx()
	_apply_mods()
	print("[Db] data-driven: biomas=%d | terrain=%d chaves | quality=%s | espécies=%d | receitas=%d" % [
		biomes.size(), terrain_cfg.size(),
		"sim" if not quality_cfg.is_empty() else "não", _count_species(), all_recipes().size()])
	if not sleep_cfg.is_empty():
		print("[Db] sono: cama=%.2f chão=%.2f | acordar às %.1fh" % [
			sleep_quality("bed"), sleep_quality("ground"), sleep_num("hours", "wake_at", 6.8)])


func _json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[Db] JSON inválido: " + path)
		return {}
	return parsed


func _rebuild_biome_idx() -> void:
	_biome_idx.clear()
	for i in biomes.size():
		if typeof(biomes[i]) == TYPE_DICTIONARY:
			_biome_idx[str(biomes[i].get("id", ""))] = i


func _count_species() -> int:
	var n := 0
	for kind in ["trees", "rocks", "plants"]:
		var k = species_cfg.get(kind, {})
		if typeof(k) == TYPE_DICTIONARY:
			n += k.size()
	return n


## Overrides vindos dos mods (Mods.biomes/terrain/quality/species).
func _apply_mods() -> void:
	for id in Mods.biomes:
		var idx := biome_index(str(id))
		var ov = Mods.biomes[id]
		if idx >= 0 and typeof(ov) == TYPE_DICTIONARY:
			for k in ov:
				biomes[idx][k] = ov[k]
	for k in Mods.terrain:
		terrain_cfg[k] = Mods.terrain[k]
	for k in Mods.quality:
		quality_cfg[k] = Mods.quality[k]
	for kind in Mods.species:
		if typeof(species_cfg.get(kind, null)) != TYPE_DICTIONARY:
			species_cfg[kind] = {}
		for id in Mods.species[kind]:
			if typeof(species_cfg[kind].get(id, null)) != TYPE_DICTIONARY:
				species_cfg[kind][id] = {}
			var ov2 = Mods.species[kind][id]
			if typeof(ov2) == TYPE_DICTIONARY:
				for k2 in ov2:
					species_cfg[kind][id][k2] = ov2[k2]


# ── accessors (todos com fallback para o valor embutido) ──────────────────
func biome_count() -> int:
	return biomes.size()


## Índice de um bioma pelo id ("forest"); -1 se não existir.
func biome_index(id: String) -> int:
	return int(_biome_idx.get(id, -1))


func biome_color(i: int, fallback: Color) -> Color:
	if i >= 0 and i < biomes.size() and typeof(biomes[i]) == TYPE_DICTIONARY:
		var c = biomes[i].get("color", null)
		if typeof(c) == TYPE_ARRAY and c.size() >= 3:
			return Color(float(c[0]), float(c[1]), float(c[2]))
	return fallback


## kind = "tree" ou "grass".
func biome_density(i: int, kind: String, fallback: float) -> float:
	if i >= 0 and i < biomes.size() and typeof(biomes[i]) == TYPE_DICTIONARY:
		var key := "tree_density" if kind == "tree" else "grass_density"
		if biomes[i].has(key):
			return float(biomes[i][key])
	return fallback


func terrain_num(key: String, fallback: float) -> float:
	if terrain_cfg.has(key):
		return float(terrain_cfg[key])
	return fallback


func terrain_noise(nm: String, key: String, fallback: float) -> float:
	var n = terrain_cfg.get("noise", {})
	if typeof(n) == TYPE_DICTIONARY and typeof(n.get(nm, null)) == TYPE_DICTIONARY:
		if n[nm].has(key):
			return float(n[nm][key])
	return fallback


func continent_spline(fallback: Array) -> Array:
	var s = terrain_cfg.get("continent_spline", null)
	if typeof(s) == TYPE_ARRAY and not s.is_empty():
		return s
	return fallback


func quality_preset(q: int, fallback: Dictionary) -> Dictionary:
	var p = quality_cfg.get("presets", {})
	if typeof(p) == TYPE_DICTIONARY and typeof(p.get(str(q), null)) == TYPE_DICTIONARY:
		return p[str(q)]
	return fallback


func quality_value(key: String, fallback: float) -> float:
	var v = quality_cfg.get("values", {})
	if typeof(v) == TYPE_DICTIONARY and v.has(key):
		return float(v[key])
	return fallback


## Metadados data-driven de uma espécie ({} se não houver).
func species_meta(kind: String, id: String) -> Dictionary:
	var k = species_cfg.get(kind, {})
	if typeof(k) == TYPE_DICTIONARY and typeof(k.get(id, null)) == TYPE_DICTIONARY:
		return k[id]
	return {}
