class_name PropDef
extends Resource
## Objeto/cenario editavel no Inspector. Atribui um mesh .glb do Blender
## arrastando-o para o campo `mesh` — sem escrever codigo.
@export var id := ""                 ## id unico
@export var mesh: Mesh               ## arrasta aqui o .glb importado
@export var scale := 1.0
