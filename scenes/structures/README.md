# Cenas de estruturas (prefabs editáveis no Godot)

O jogo carrega automaticamente `res://scenes/structures/<id>.tscn` quando esse
ficheiro existe (ver `scripts/world/structures.gd`). Se não existir, usa o
procedural — ou seja, é **aditivo, não parte nada**.

## Como substituir uma estrutura por uma cena editável
1. Descobre o **id** da estrutura (ex.: `house`, `campfire` — vê `species.gd`).
2. Cria/abre uma cena no Godot e guarda-a como `scenes/structures/<id>.tscn`
   (ex.: `scenes/structures/house.tscn`).
3. Edita-a visualmente: meshes, materiais, o teu `.glb` do Blender, colisões, luzes.
4. O nó **raiz deve ser `Node3D`** (ou derivado). O jogo posiciona-o e roda-o.
5. Pronto — o jogo passa a usar a tua cena em vez do procedural.

## Modelo
`_exemplo_ruin_column.tscn` é um **template** (o `_` inicial faz com que não seja
carregado). Copia-o, renomeia para `<id>.tscn` e edita no Inspector.
