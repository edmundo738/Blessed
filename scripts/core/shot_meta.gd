class_name ShotMeta
extends RefCounted

## Espelho dos dados de instância para o dump headless.
##
## O `--headless` do Godot arranca com o servidor de render "dummy": os buffers
## de MultiMesh vivem no servidor, e o dummy não os guarda. Resultado medido:
## `MultiMesh.get_instance_transform(i)` devolvia a IDENTIDADE para todas as
## instâncias, portanto o dump de diagnóstico (tests/shot.gd) não continha
## cartas de relva nem árvores — aparecia só o terreno e a relva por níveis, e
## qualquer leitura visual da imagem era sobre metade da cena.
##
## Aqui guarda-se uma cópia das transformações/cores nos metadados do nó. Só
## se liga quando a linha de comandos pede o dump (a sonda `shot`, ver
## scripts/main.gd) ou num Godot headless nativo, por isso o jogo normal não
## paga nada: nem memória, nem um ramo no caminho quente.
const KEY_XFORM := "shot_xforms"
const KEY_COLOR := "shot_colors"
const KEY_CUSTOM := "shot_custom"


## Ligado por main.gd antes de o mundo ser construído. A exportação web corre
## dentro do Node no harness de diagnóstico: `OS.has_feature("headless")` é falso
## lá, e o servidor de render não guarda os MultiMesh, daí o interruptor.
static var mirror := false


static func enabled() -> bool:
	return mirror or OS.has_feature("headless")


## Guarda as instâncias de um MultiMeshInstance3D. `transforms` é obrigatório;
## cores e dados por instância só se existirem.
static func keep(node: Node, transforms: Array, colors: Array = [],
		customs: Array = []) -> void:
	if not enabled() or node == null or transforms.is_empty():
		return
	var count := transforms.size()
	var xf := PackedFloat32Array()
	xf.resize(count * 12)
	for i in count:
		var t: Transform3D = transforms[i]
		var b := t.basis
		var o := i * 12
		xf[o + 0] = b.x.x; xf[o + 1] = b.x.y; xf[o + 2] = b.x.z
		xf[o + 3] = b.y.x; xf[o + 4] = b.y.y; xf[o + 5] = b.y.z
		xf[o + 6] = b.z.x; xf[o + 7] = b.z.y; xf[o + 8] = b.z.z
		xf[o + 9] = t.origin.x; xf[o + 10] = t.origin.y; xf[o + 11] = t.origin.z
	node.set_meta(KEY_XFORM, xf)
	if colors.size() == count:
		var col := PackedColorArray()
		col.resize(count)
		for i in count:
			col[i] = colors[i]
		node.set_meta(KEY_COLOR, col)
	if customs.size() == count:
		var cus := PackedColorArray()
		cus.resize(count)
		for i in count:
			cus[i] = customs[i]
		node.set_meta(KEY_CUSTOM, cus)


static func has(node: Node) -> bool:
	return node != null and node.has_meta(KEY_XFORM)


static func transform_at(node: Node, i: int) -> Transform3D:
	var xf: PackedFloat32Array = node.get_meta(KEY_XFORM)
	var o := i * 12
	var b := Basis(
		Vector3(xf[o + 0], xf[o + 1], xf[o + 2]),
		Vector3(xf[o + 3], xf[o + 4], xf[o + 5]),
		Vector3(xf[o + 6], xf[o + 7], xf[o + 8]))
	return Transform3D(b, Vector3(xf[o + 9], xf[o + 10], xf[o + 11]))


static func color_at(node: Node, i: int) -> Color:
	if not node.has_meta(KEY_COLOR):
		return Color.WHITE
	var col: PackedColorArray = node.get_meta(KEY_COLOR)
	return col[i] if i < col.size() else Color.WHITE


static func custom_at(node: Node, i: int) -> Color:
	if not node.has_meta(KEY_CUSTOM):
		return Color(0, 0, 0, 0)
	var cus: PackedColorArray = node.get_meta(KEY_CUSTOM)
	return cus[i] if i < cus.size() else Color(0, 0, 0, 0)


static func count(node: Node) -> int:
	if not has(node):
		return 0
	var xf: PackedFloat32Array = node.get_meta(KEY_XFORM)
	return xf.size() / 12
