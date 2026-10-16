extends Node
## Loc — localização em runtime (PT-PT + EN).
##
## Porque não uso os .po/.csv do Godot: esses passam pelo import do editor e
## geram .translation. Este projeto não tem **nenhum** asset importado, por isso
## corre igual no editor, num export desktop e num .pck feito por script.
## As strings vivem em `res://locale/*.json` e trocam-se a quente.

const SUPPORTED := ["pt", "en"]
const FALLBACK := "pt"

var code: String = FALLBACK
var _tables: Dictionary = {}


func _ready() -> void:
	for c in SUPPORTED:
		_tables[c] = _load_table(c)
	# Preferência guardada de uma sessão anterior.
	var saved := _read_pref()
	if saved in SUPPORTED:
		code = saved


func _load_table(c: String) -> Dictionary:
	var path := "res://locale/%s.json" % c
	if not FileAccess.file_exists(path):
		push_warning("Loc: falta %s" % path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Loc: %s não é um objeto JSON válido" % path)
		return {}
	return parsed


func _read_pref() -> String:
	var path := "user://prefs.json"
	if not FileAccess.file_exists(path):
		return FALLBACK
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("locale"):
		return String(parsed["locale"])
	return FALLBACK


func _write_pref() -> void:
	var f := FileAccess.open("user://prefs.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"locale": code}, "\t"))
		f.close()


## Traduz. `vars` substitui `%s`/`%d` por ordem, ou `{nome}` por chave.
func t(key: String, vars: Variant = null) -> String:
	var table: Dictionary = _tables.get(code, {})
	var s: String = str(table.get(key, ""))
	if s.is_empty():
		var fb: Dictionary = _tables.get(FALLBACK, {})
		s = str(fb.get(key, ""))
	if s.is_empty():
		return key  # chave visível > crash silencioso
	return _fill(s, vars)


func has_key(key: String) -> bool:
	return (_tables.get(code, {}) as Dictionary).has(key)


func _fill(s: String, vars: Variant) -> String:
	if vars == null:
		return s
	if typeof(vars) == TYPE_DICTIONARY:
		for k in (vars as Dictionary):
			s = s.replace("{%s}" % str(k), str((vars as Dictionary)[k]))
		return s
	if typeof(vars) == TYPE_ARRAY:
		# Substituição posicional: só o primeiro "%s" de cada vez
		# (String.replace do Godot não tem limite de ocorrências).
		for v in (vars as Array):
			s = _replace_first(s, "%s", str(v))
		return s
	return _replace_first(s, "%s", str(vars))


func _replace_first(s: String, what: String, with: String) -> String:
	var i := s.find(what)
	if i < 0:
		return s
	return s.substr(0, i) + with + s.substr(i + what.length())


func set_locale(c: String) -> void:
	if not (c in SUPPORTED):
		return
	code = c
	_write_pref()
	Bus.locale_changed.emit(code)


func cycle_locale() -> String:
	var i := SUPPORTED.find(code)
	set_locale(SUPPORTED[(i + 1) % SUPPORTED.size()])
	return code


func native_name(c: String = "") -> String:
	var target := c if c != "" else code
	return "Português" if target == "pt" else "English"
