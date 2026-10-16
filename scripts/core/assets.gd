class_name Assets
extends RefCounted
## Assets — carregar recursos sem depender da cache de importação do editor.
##
## PORQUE É QUE ISTO EXISTE
## Um projeto Godot normal tem `.godot/imported/` (gitignored) e é o *editor* que
## converte os PNG em `.ctex` e os `.gltf` em `.scn`. Sem essa cache — clone novo,
## CI, build web, contentor sem editor — `preload("...png")` **falha na análise**
## do script ("Could not preload resource file") e derruba tudo o que o script
## toca: `materials.gd` levava consigo o mundo inteiro, `fx.gd` os efeitos.
## Foi assim que o build web e qualquer arranque a frio ficavam partidos.
##
## Regra: tentar sempre o caminho rápido do motor (`ResourceLoader`) e só depois
## o caminho cru (ler os bytes do ficheiro e construir o recurso à mão). No
## editor nada muda; sem editor o jogo arranca.
##
## Uso:
##     var tex := Assets.texture("res://content/fx/kenney/sky/skybox-day.png")
##     var mesh := Assets.gltf_mesh("res://content/models/runtime/tree_oak.glb")

const _IMG_EXT := ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga", "exr", "hdr"]
const _GLTF_EXT := ["gltf", "glb"]

static var _cache: Dictionary = {}
static var _warned: Dictionary = {}


static func _ext(path: String) -> String:
	return path.get_extension().to_lower()


## Existe mesmo? Verdadeiro quando o ficheiro cru existe, tenha ou não passado
## pelo importador do editor.
static func exists(path: String) -> bool:
	return FileAccess.file_exists(path) or _product(path) != ""


## O produto que o editor escreveu para este ficheiro (`.import` → `[remap] path`).
## Vazio quando o recurso nunca foi importado, e é essa a diferença que interessa:
## `ResourceLoader.exists()` responde SIM só por existir o `.import`, mesmo que o
## `.ctex`/`.scn` não exista — e depois falha com três linhas de erro no log por
## cada recurso. Perguntar pelo produto evita os erros e a ordem de tentativas.
static func _product(path: String) -> String:
	var key := "prod|" + path
	if _cache.has(key):
		return _cache[key] as String
	var product := ""
	var sidecar := path + ".import"
	if FileAccess.file_exists(sidecar):
		var text := FileAccess.get_file_as_string(sidecar)
		var marker := "path=\"res://"
		var at := text.find(marker)
		if at >= 0:
			var start := at + marker.length() - len("res://")
			var end := text.find("\"", start)
			if end > start:
				var candidate := text.substr(start, end - start)
				if FileAccess.file_exists(candidate):
					product = candidate
	_cache[key] = product
	return product


## Carrega o recurso importado se existir; caso contrário devolve null.
static func _imported(path: String) -> Resource:
	# Nomes de classe por string: em algumas builds (a web) o motor traz as
	# classes mas o analisador de GDScript não as conhece.
	return ResourceLoader.load(path) if _product(path) != "" else null


static func _warn(what: String, path: String, why: String) -> void:
	var key := what + "|" + path
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning("Assets: %s de %s falhou (%s)" % [what, path, why])


## Textura: produto importado se existir, senão o PNG/JPG cru.
static func texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path] as Texture2D
	var result: Texture2D = _imported(path) as Texture2D
	if result == null:
		var img := _image(path)
		if img != null:
			result = ImageTexture.create_from_image(img)
	if result == null:
		_warn("textura", path, "não é recurso importado nem imagem legível")
	_cache[path] = result
	return result


## Imagem crua (para quem precisa dos píxeis, não da textura).
static func image(path: String) -> Image:
	return _image(path)


static func _image(path: String) -> Image:
	var key := "img|" + path
	if _cache.has(key):
		return _cache[key] as Image
	var img: Image = null
	if _ext(path) in _IMG_EXT or FileAccess.file_exists(path):
		# `Image.load_from_file` lê bytes crus: funciona a partir de .pck e fora do editor.
		if FileAccess.file_exists(path):
			img = Image.load_from_file(path)
	if img == null:
		var tex := _imported(path) as Texture2D
		if tex != null:
			img = tex.get_image()
	if img == null:
		_warn("imagem", path, "ilegível")
	_cache[key] = img
	return img


## Cena instanciável. Aceita `.tscn`/`.scn` importado e, em último caso, um
## glTF/GLB carregado em runtime.
static func scene(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path] as PackedScene
	var result: PackedScene = _imported(path) as PackedScene
	if result == null and _ext(path) in _GLTF_EXT:
		var root := gltf_root(path)
		if root != null:
			var packed := PackedScene.new()
			if packed.pack(root) == OK:
				result = packed
			root.free()
	if result == null:
		_warn("cena", path, "não é cena importada nem glTF legível")
	_cache[path] = result
	return result


## Malha do primeiro MeshInstance3D de uma cena/glTF.
static func mesh(path: String) -> ArrayMesh:
	if path.is_empty():
		return null
	var root := gltf_root(path) if _product(path) == "" else null
	if root != null:
		var found := _first_mesh(root)
		var mesh: ArrayMesh = found.mesh as ArrayMesh if found != null else null
		root.free()
		return mesh
	var packed := scene(path)
	if packed == null:
		return null
	root = packed.instantiate()
	var node := _first_mesh(root)
	var result: ArrayMesh = node.mesh as ArrayMesh if node != null else null
	root.free()
	return result


static func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is ArrayMesh:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


# ══════════════════════════════════════════════════════════════════════════
#  glTF sem editor
# ══════════════════════════════════════════════════════════════════════════
## Carrega um .gltf/.glb em runtime (geometria + materiais de base). Só é usado
## quando não há `.scn` importado — o produto do editor continua a ganhar.
##
## O importador do motor desiste das texturas quando os PNG não foram importados
## (`ResourceLoader` recusa fontes cruas). Aqui as imagens são lidas por
## `Image.load_from_file`, pelo que as folhas mantêm a máscara alfa e as cascas
## mantêm a cor — exatamente o que faltava no build web.
static func gltf_root(path: String) -> Node:
	var key := "gltf|" + path
	if _cache.has(key):
		var cached := _cache[key] as Node
		return cached.duplicate() if cached != null else null
	# `ClassDB.instantiate` em vez de `GLTFDocument.new()`: há builds do motor
	# (a web, por exemplo) que trazem as classes mas onde o analisador de GDScript
	# não as conhece — com o nome escrito no código, o script inteiro falhava na
	# análise e derrubava tudo o que dependesse dele.
	var root: Node = null
	# O motivo da falha vai no aviso: sem ele, "não abriu" obriga a adivinhar se
	# o problema é a build não trazer o módulo glTF, o ficheiro faltar ou o
	# analisador recusar o conteúdo — e adivinhar foi o que produziu semanas de
	# correcções erradas neste projecto.
	var why := ""
	if not FileAccess.file_exists(path):
		why = "ficheiro ausente"
	elif not ClassDB.class_exists("GLTFDocument") or not ClassDB.class_exists("GLTFState"):
		why = "esta build do motor não traz GLTFDocument/GLTFState"
	else:
		var doc: Object = ClassDB.instantiate("GLTFDocument")
		var state: Object = ClassDB.instantiate("GLTFState")
		if doc == null or state == null:
			why = "GLTFDocument não instanciou"
		else:
			# 3 = HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED: as imagens que o
			# motor não conseguir ler são substituídas à mão logo a seguir.
			state.set("handle_binary_image_mode", 3)
			var err := int(doc.call("append_from_file", path, state))
			if err != OK:
				why = "append_from_file devolveu %d" % err
			else:
				root = doc.call("generate_scene", state) as Node
				if root == null:
					why = "generate_scene devolveu nulo"
				else:
					_repair_gltf_materials(path, root)
	if root == null:
		_warn("glTF", path, why)
	_cache[key] = root
	return root.duplicate() if root != null else null


## Os materiais cujas imagens o motor não conseguiu carregar ficam sem textura.
## Aqui voltamos a ligar-lhes o PNG de origem, lido cru do disco.
##
## O mapeamento material→imagem vem do próprio JSON: `materials[i]` →
## `pbrMetallicRoughness.baseColorTexture.index` → `textures[..].source` →
## `images[..].uri`. O motor dá ao material o nome do glTF, e é por esse nome
## que o ligamos de volta à superfície.
static func _repair_gltf_materials(path: String, root: Node) -> void:
	var wanted := _gltf_material_uris(path)
	if wanted.is_empty():
		return
	var base_dir := path.get_base_dir()
	var images: Dictionary = {}
	var nodes: Array[Node] = [root]
	while not nodes.is_empty():
		var node: Node = nodes.pop_back()
		for child in node.get_children():
			nodes.append(child)
		if not (node is MeshInstance3D):
			continue
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var mat := mesh.surface_get_material(surface) as BaseMaterial3D
			if mat == null or mat.albedo_texture != null:
				continue
			var uri := str(wanted.get(mat.resource_name, ""))
			if uri.is_empty():
				continue
			if not images.has(uri):
				images[uri] = _image(base_dir.path_join(uri))
			var img: Image = images[uri]
			if img != null:
				mat.albedo_texture = ImageTexture.create_from_image(img)


## {nome do material glTF: uri da imagem de cor base}
static func _gltf_material_uris(path: String) -> Dictionary:
	var out: Dictionary = {}
	if _ext(path) == "glb":
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var images: Variant = parsed.get("images", [])
	var textures: Variant = parsed.get("textures", [])
	var materials: Variant = parsed.get("materials", [])
	if typeof(images) != TYPE_ARRAY or typeof(textures) != TYPE_ARRAY \
			or typeof(materials) != TYPE_ARRAY:
		return out
	for material in materials:
		if typeof(material) != TYPE_DICTIONARY:
			continue
		var name := str(material.get("name", ""))
		var pbr: Variant = material.get("pbrMetallicRoughness", {})
		if name.is_empty() or typeof(pbr) != TYPE_DICTIONARY:
			continue
		var base: Variant = pbr.get("baseColorTexture", {})
		if typeof(base) != TYPE_DICTIONARY:
			continue
		var tex_index := int(base.get("index", -1))
		if tex_index < 0 or tex_index >= textures.size():
			continue
		var texture: Variant = textures[tex_index]
		if typeof(texture) != TYPE_DICTIONARY:
			continue
		var source := int(texture.get("source", -1))
		if source < 0 or source >= images.size():
			continue
		var image: Variant = images[source]
		if typeof(image) != TYPE_DICTIONARY:
			continue
		var uri := str(image.get("uri", ""))
		if uri.is_empty() or uri.begins_with("data:"):
			continue
		out[name] = uri
	return out
