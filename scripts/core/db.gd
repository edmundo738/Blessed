extends Node
## Db — todas as definições de dados do jogo, num sítio só.
##
## É a caixa de LEGO: poucas peças boas (recursos, ferramentas, comida,
## estruturas) + regras de combinação (receitas) . Tudo o que é "conteúdo"
## entra aqui; o código dos sistemas não conhece nomes de itens.

const ITEMS := {
	# ── recursos ────────────────────────────────────────────────────────────
	"wood":         {"kind": "resource", "stack": 40, "icon": "wood"},
	"stone":        {"kind": "resource", "stack": 40, "icon": "stone"},
	"flint":        {"kind": "resource", "stack": 20, "icon": "flint"},
	"fiber":        {"kind": "resource", "stack": 40, "icon": "fiber"},
	"stick":        {"kind": "resource", "stack": 40, "icon": "stick"},
	# ── comida ──────────────────────────────────────────────────────────────
	"berry":        {"kind": "food", "stack": 20, "icon": "berry",
					 "food": 12, "drink": 6, "risk": 0.0},
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
	"axe":          {"kind": "tool", "stack": 1, "icon": "axe", "power": {"chop": 2.2}},
	"pickaxe":      {"kind": "tool", "stack": 1, "icon": "pickaxe", "power": {"mine": 2.4}},
	"rod":          {"kind": "tool", "stack": 1, "icon": "rod", "power": {"fish": 1.0}},
	"torch":        {"kind": "tool", "stack": 5, "icon": "torch", "light": 5.0, "fuel": 180.0},
	"bottle":       {"kind": "tool", "stack": 1, "icon": "bottle", "capacity": 100.0},
	"water":        {"kind": "tool", "stack": 1, "icon": "water", "drink_amount": 60.0},
	# ── estruturas (colocáveis) ─────────────────────────────────────────────
	"campfire":     {"kind": "structure", "stack": 3, "icon": "campfire",
					 "place": "campfire", "light": 9.0},
	"wall":         {"kind": "structure", "stack": 20, "icon": "wall", "place": "wall"},
	"floor":        {"kind": "structure", "stack": 20, "icon": "floor", "place": "floor"},
	"pillar":       {"kind": "structure", "stack": 20, "icon": "pillar", "place": "pillar"},
	"bed":          {"kind": "structure", "stack": 2, "icon": "bed", "place": "bed"},
}

## Receitas: `needs` são consumidos, `result` é criado. `station` vazio = mãos.
const RECIPES := [
	{"id": "stick",     "result": "stick",       "qty": 2, "needs": {"wood": 1}},
	{"id": "torch",     "result": "torch",       "qty": 2, "needs": {"stick": 1, "fiber": 1}},
	{"id": "axe",       "result": "axe",         "qty": 1, "needs": {"stick": 2, "stone": 2, "fiber": 2}},
	{"id": "pickaxe",   "result": "pickaxe",     "qty": 1, "needs": {"stick": 2, "stone": 3, "fiber": 1}},
	{"id": "rod",       "result": "rod",         "qty": 1, "needs": {"stick": 3, "fiber": 3}},
	{"id": "bottle",    "result": "bottle",      "qty": 1, "needs": {"fiber": 4}},
	{"id": "campfire",  "result": "campfire",    "qty": 1, "needs": {"stone": 4, "stick": 3, "wood": 2}},
	{"id": "wall",      "result": "wall",        "qty": 2, "needs": {"wood": 3}},
	{"id": "floor",     "result": "floor",       "qty": 2, "needs": {"wood": 2}},
	{"id": "pillar",    "result": "pillar",      "qty": 2, "needs": {"wood": 2, "fiber": 1}},
	{"id": "bed",       "result": "bed",         "qty": 1, "needs": {"fiber": 12, "stick": 4}, "station": "campfire"},
	{"id": "meat_cooked", "result": "meat_cooked", "qty": 1, "needs": {"meat_raw": 1}, "station": "campfire"},
	{"id": "fish_cooked", "result": "fish_cooked", "qty": 1, "needs": {"fish_raw": 1}, "station": "campfire"},
	{"id": "stew",      "result": "stew",        "qty": 1,
	 "needs": {"meat_cooked": 1, "mushroom": 2, "berry": 2}, "station": "campfire"},
]

## O que sai de cada nó do mundo quando é colhido.
const HARVEST := {
	"tree_oak":    {"action": "chop", "tool": "axe", "hp": 6, "yields": {"wood": 3, "stick": 1}},
	"tree_pine":   {"action": "chop", "tool": "axe", "hp": 8, "yields": {"wood": 4}},
	"tree_birch":  {"action": "chop", "tool": "axe", "hp": 5, "yields": {"wood": 2, "stick": 2}},
	"tree_sakura": {"action": "chop", "tool": "axe", "hp": 6, "yields": {"wood": 2, "berry": 2}},
	"rock":        {"action": "mine", "tool": "pickaxe", "hp": 5, "yields": {"stone": 2, "flint": 1}},
	"bush":        {"action": "pick", "tool": "", "hp": 1, "yields": {"berry": 2, "fiber": 1}},
	"tuft":        {"action": "pick", "tool": "", "hp": 1, "yields": {"fiber": 2}},
	"mushroom":    {"action": "pick", "tool": "", "hp": 1, "yields": {"mushroom": 1}},
	"flint_node":  {"action": "pick", "tool": "", "hp": 1, "yields": {"flint": 2}},
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
	return ITEMS.get(id, {})


func item_name(id: String) -> String:
	return Loc.t("item." + id)


func item_kind(id: String) -> String:
	return str(item(id).get("kind", ""))


func max_stack(id: String) -> int:
	return int(item(id).get("stack", 1))


func is_placeable(id: String) -> bool:
	return item(id).has("place")


func recipe(id: String) -> Dictionary:
	for r in RECIPES:
		if str(r["id"]) == id:
			return r
	return {}


## Receitas visíveis dado o que está por perto (`near` = ids de estações).
func recipes_for(near: Array = []) -> Array:
	var out := []
	for r in RECIPES:
		var st := str(r.get("station", ""))
		if st.is_empty() or st in near:
			out.append(r)
	return out
