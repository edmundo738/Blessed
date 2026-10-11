extends Node
## Mods — camada data-driven que torna o BLESSED modificavel SEM tocar em codigo.
##
## Como funciona
##   - Le definicoes JSON de `res://content/<mod>/mod.json` (pasta do projeto,
##     importada pelo editor -> aceita meshes `.glb`/`.gltf` do Blender) e de
##     `user://mods/<mod>/mod.json` (so JSON, para tweaks rapidos).
##   - Faz MERGE/OVERRIDE sobre os dados embutidos (Db). Sem mods, o jogo comporta-se
##     EXATAMENTE como antes — e 100% aditivo, nao parte nada.
##
## Formato de um mod.json
## {
##   "name": "O Meu Mod",
##   "items": {
##     "reliquia": { "kind": "resource", "stack": 10, "icon": "stone", "name": "Reliquia Antiga" }
##   },
##   "recipes": [
##     { "id": "reliquia_polida", "result": "reliquia", "qty": 1,
##       "needs": { "stone": 2, "fiber": 1 }, "station": "" }
##   ],
##   "props": {
##     "ruina_arco": { "mesh": "ruina_arco.glb", "scale": 1.0 }
##   }
## }
##
## `mesh` e relativo a pasta do mod. O Godot importa `.glb` automaticamente quando
## estao dentro do projeto (res://content/...).

var items := {}        # id -> Dictionary (override de Db.item)
var recipes := []      # receitas adicionais
var props := {}        # id -> {mesh=caminho, scale=...}
var loaded := []       # nomes dos mods carregados


func _ready() -> void:
	name = "Mods"
	_scan("res://content")
	_scan("user://mods")
	print("[Mods] %d mod(s): %s | items=%d recipes=%d props=%d" % [
		loaded.size(), ", ".join(loaded) if not loaded.is_empty() else "nenhum",
		items.size(), recipes.size(), props.size()])


func _scan(base: String) -> void:
	var d := DirAccess.open(base)
	if d == null:
		return
	for entry in d.get_directories():
		_load(base.path_join(entry))


func _load(path: String) -> void:
	var f := path.path_join("mod.json")
	if not FileAccess.file_exists(f):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(f))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[Mods] mod.json invalido em " + f)
		return
	loaded.append(str(parsed.get("name", path.get_file())))
	var it = parsed.get("items", {})
	if typeof(it) == TYPE_DICTIONARY:
		for k in it:
			items[str(k)] = it[k]
	var rc = parsed.get("recipes", [])
	if typeof(rc) == TYPE_ARRAY:
		recipes.append_array(rc)
	var pr = parsed.get("props", {})
	if typeof(pr) == TYPE_DICTIONARY:
		for k in pr:
			var v = pr[k]
			if typeof(v) == TYPE_DICTIONARY:
				if v.has("mesh"):
					v["mesh"] = path.path_join(str(v["mesh"]))
				props[str(k)] = v


func has_item(id: String) -> bool:
	return items.has(id)


func item(id: String) -> Dictionary:
	return items.get(id, {})


func all_recipes() -> Array:
	return recipes


func recipe(id: String) -> Dictionary:
	for r in recipes:
		if str(r.get("id", "")) == id:
			return r
	return {}


func prop(id: String) -> Dictionary:
	return props.get(id, {})
