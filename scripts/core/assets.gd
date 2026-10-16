class_name Assets
extends RefCounted
## Assets — carregar recursos sem depender da cache de importação do editor.
##
## PORQUE É QUE ISTO EXISTE
## Um projeto Godot normal tem `.godot/imported/` (gitignored) e é o *editor*
## que converte os PNG em `.ctex`. Sem essa cache — clone novo, CI, build web,
## contentor sem editor — `preload(".../skybox-day.png")` **falha na análise do
## script** ("Could not preload resource file") e derruba tudo o que o script
## toca: o `materials.gd` levava consigo o mundo inteiro. Foi exatamente isto
## que aconteceu: o jogo não arrancava fora do editor.
##
## Regra: no editor nada muda (o produto importado ganha); fora dele o ficheiro
## é lido cru do disco/pck e convertido à mão. Uma função, um caminho.

const _IMG_EXT := ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga", "exr", "hdr"]

static var _cache: Dictionary = {}
static var _warned: Dictionary = {}


## O produto que o importador escreveu para este ficheiro (`.import` → `[remap] path`).
## Vazio quando o recurso nunca foi importado.
static func _product(path: String) -> String:
	var key := "prod|" + path
	if _cache.has(key):
		return _cache[key] as String
	var product := ""
	var sidecar := path + ".import"
	if FileAccess.file_exists(sidecar):
		var text := FileAccess.get_file_as_string(sidecar)
		var at := text.find("path=\"res://")
		if at >= 0:
			var start := at + len("path=\"")
			var end := text.find("\"", start)
			if end > start:
				var candidate := text.substr(start, end - start)
				if FileAccess.file_exists(candidate):
					product = candidate
	_cache[key] = product
	return product


static func _warn(path: String, why: String) -> void:
	if _warned.has(path):
		return
	_warned[path] = true
	push_warning("Assets: %s ilegível (%s)" % [path, why])


## Textura: produto importado se existir, senão o PNG cru lido do disco/pck.
static func texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path] as Texture2D
	var key := _product(path)
	if not key.is_empty():
		var imported := ResourceLoader.load(key) as Texture2D
		if imported != null:
			_cache[path] = imported
			return imported
	var result: Texture2D = null
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			result = ImageTexture.create_from_image(img)
	if result == null:
		_warn(path, "não é recurso importado nem imagem legível")
	_cache[path] = result
	return result
