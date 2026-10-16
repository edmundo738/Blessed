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
var biomes := {}       # id -> {color, tree_density, grass_density}
var terrain := {}      # chaves de afinação do terreno (data/terrain.json)
var quality := {}      # presets/valores de qualidade (data/quality.json)
var species := {}      # kind -> id -> {biomes, weight, harvest, scale, ...}
var loaded := []       # nomes dos mods carregados
var tres_loaded := 0   # recursos .tres carregados


func _ready() -> void:
	name = "Mods"
	_scan("res://content")
	_scan("user://mods")
	print("[Mods] %d mod(s): %s | items=%d recipes=%d props=%d" % [
		loaded.size(), ", ".join(loaded) if not loaded.is_empty() else "nenhum",
		items.size(), recipes.size(), props.size() + tres_loaded])


func _scan(base: String) -> void:
	var d := DirAccess.open(base)
	if d == null:
		return
	_load_resources(base)
	for entry in d.get_directories():
		var sub := base.path_join(entry)
		_load(sub)
		_load_resources(sub)


## Carrega Recursos (.tres) editados no Inspector: ItemDef / RecipeDef / PropDef.
## E o caminho "sem GDScript": crias o .tres no editor, preenches os campos e pronto.
func _load_resources(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		if f.get_extension() != "tres":
			continue
		var res = load(path.path_join(f))
		if res is ItemDef:
			items[res.id] = {"kind": res.kind, "stack": res.stack, "icon": res.icon, "name": res.display_name}
			tres_loaded += 1
		elif res is RecipeDef:
			recipes.append({"id": res.id, "result": res.result, "qty": res.qty, "needs": res.needs, "station": res.station})
			tres_loaded += 1
		elif res is PropDef:
			props[res.id] = {"mesh": res.mesh, "scale": res.scale}
			tres_loaded += 1


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
	# ── mundo data-driven: biomas, terreno, qualidade, espécies ──
	var bm = parsed.get("biomes", {})
	if typeof(bm) == TYPE_DICTIONARY:
		for k in bm:
			biomes[str(k)] = bm[k]
	var tn = parsed.get("terrain", {})
	if typeof(tn) == TYPE_DICTIONARY:
		for k in tn:
			terrain[str(k)] = tn[k]
	var ql = parsed.get("quality", {})
	if typeof(ql) == TYPE_DICTIONARY:
		for k in ql:
			quality[str(k)] = ql[k]
	var sp = parsed.get("species", {})
	if typeof(sp) == TYPE_DICTIONARY:
		for kind in sp:
			if typeof(species.get(kind, null)) != TYPE_DICTIONARY:
				species[kind] = {}
			if typeof(sp[kind]) == TYPE_DICTIONARY:
				for id in sp[kind]:
					species[kind][str(id)] = sp[kind][id]


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
