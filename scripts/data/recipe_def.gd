class_name RecipeDef
extends Resource
## Receita editavel no Inspector do Godot (sem GDScript).
@export var id := ""                 ## id unico da receita
@export var result := ""             ## id do item produzido
@export var qty := 1                 ## quantos produz
@export var needs := {}              ## { "id_item": quantidade }
@export var station := ""            ## "" = qualquer lugar; ou id de estacao
