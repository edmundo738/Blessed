class_name ItemDef
extends Resource
## Definicao de item editavel no Inspector do Godot (sem GDScript).
## Cria em: FileSystem > direito > New Resource > ItemDef > guarda como .tres em content/.
@export var id := ""                 ## id unico (ex.: "reliquia")
@export var kind := "resource"       ## resource | food | tool | ...
@export var stack := 20              ## pilha maxima
@export var icon := ""               ## nome do icone
@export_multiline var display_name := ""  ## nome mostrado no jogo
