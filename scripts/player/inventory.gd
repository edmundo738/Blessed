class_name Inventory
extends Node
## Inventory — mochila, barra rápida e bancada.
##
## Regra: a mochila não sabe o que os itens fazem. Sabe contar. Quem decide o
## efeito de usar um item é o `Interaction` (através do `Db`). Assim acrescentar
## um item novo é acrescentar uma linha ao `Db`, não um caso especial aqui.

const SLOTS := 24

var slots: Array = []          # [{id, qty}] ou {}
var hotbar_index := 0


func _ready() -> void:
	name = "Inventory"
	slots.resize(SLOTS)
	for i in SLOTS:
		slots[i] = {}
	Game.register_saver(self)


func add(id: String, qty: int = 1) -> int:
	## Devolve o que não coube (0 = coube tudo).
	if qty <= 0:
		return 0
	var left := qty
	var maxs := Db.max_stack(id)
	# primeiro empilha
	for i in SLOTS:
		if left <= 0:
			break
		var s: Dictionary = slots[i]
		if s.is_empty() or str(s["id"]) != id:
			continue
		var room := maxs - int(s["qty"])
		if room <= 0:
			continue
		var take := mini(room, left)
		s["qty"] = int(s["qty"]) + take
		left -= take
		Bus.item_added.emit(id, take)
	# depois espaços vazios
	for i in SLOTS:
		if left <= 0:
			break
		var s: Dictionary = slots[i]
		if not s.is_empty():
			continue
		var take := mini(maxs, left)
		slots[i] = {"id": id, "qty": take}
		left -= take
		Bus.item_added.emit(id, take)
	if qty - left > 0:
		Bus.resource_changed.emit(id, qty - left, count(id))
	return left


func remove(id: String, qty: int = 1) -> bool:
	if count(id) < qty:
		return false
	var left := qty
	for i in SLOTS:
		if left <= 0:
			break
		var s: Dictionary = slots[i]
		if s.is_empty() or str(s["id"]) != id:
			continue
		var take := mini(int(s["qty"]), left)
		s["qty"] = int(s["qty"]) - take
		left -= take
		if int(s["qty"]) <= 0:
			slots[i] = {}
		Bus.item_removed.emit(id, take)
	Bus.resource_changed.emit(id, -qty, count(id))
	return true


func count(id: String) -> int:
	var t := 0
	for s in slots:
		if not (s as Dictionary).is_empty() and str((s as Dictionary)["id"]) == id:
			t += int((s as Dictionary)["qty"])
	return t


func has_all(needs: Dictionary) -> bool:
	for k in needs:
		if count(str(k)) < int(needs[k]):
			return false
	return true


## Consome tudo o que estiver na barra rápida primeiro (o que tens na mão).
func remove_any(id: String, qty: int) -> bool:
	return remove(id, qty)


func hotbar() -> Dictionary:
	return slots[clampi(hotbar_index, 0, SLOTS - 1)]


func hotbar_id() -> String:
	var s := hotbar()
	return "" if s.is_empty() else str(s["id"])


func select(i: int) -> void:
	hotbar_index = clampi(i, 0, 8)
	Sfx.play("ui_click", -14.0, 1.2)


func next_slot(dir: int = 1) -> void:
	hotbar_index = wrapi(hotbar_index + dir, 0, 9)
	Sfx.play("ui_click", -16.0, 1.1)


# ══════════════════════════════════════════════════════════════════════════
#  BANCADA
# ══════════════════════════════════════════════════════════════════════════
func can_craft(recipe: Dictionary) -> bool:
	return has_all(recipe.get("needs", {}))


func craft(recipe: Dictionary) -> bool:
	if not can_craft(recipe):
		Bus.say("msg.no_recipe", 2.5)
		return false
	var needs: Dictionary = recipe.get("needs", {})
	for k in needs:
		remove(str(k), int(needs[k]))
	var made := str(recipe["result"])
	var qty := int(recipe.get("qty", 1))
	var left := add(made, qty)
	if left > 0:
		Bus.say("msg.bag_full", 2.5)
	Sfx.play("craft", -6.0)
	Bus.toast.emit("msg.crafted", 2.5)
	Bus.ui_message.emit(Loc.t("msg.crafted", [Db.item_name(made)]), 2.5)
	Game.bump("craft_" + made)
	if made == "campfire":
		Game.bump("place_campfire", 0)
	return true


func save_data() -> Dictionary:
	var out := []
	for s in slots:
		out.append({"id": str((s as Dictionary).get("id", "")), "qty": int((s as Dictionary).get("qty", 0))})
	return {"slots": out, "hotbar": hotbar_index}


func load_data(d: Dictionary) -> void:
	var arr: Array = d.get("slots", [])
	for i in SLOTS:
		if i < arr.size():
			var e: Dictionary = arr[i]
			slots[i] = {} if str(e.get("id", "")).is_empty() else {"id": str(e["id"]), "qty": int(e["qty"])}
		else:
			slots[i] = {}
	hotbar_index = int(d.get("hotbar", 0))
