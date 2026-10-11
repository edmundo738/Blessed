# CONVENTIONS — regras rápidas para quem toca no código

- **Eixos/escala:** Y é cima; 1 unidade = 1 m; jogador ~1.8 m; olho 1.62 m.
- **Chunks:** 48 m, 3 LODs (`Chunk.RES`); mundo em coordenadas absolutas com o
  nó do chunk na origem (por isso medir distância pelo AABB, nunca por
  `global_position` do nó).
- **Materiais:** um `ShaderMaterial` partilhado por tipo em `materials.gd`
  (`terrain`, `foliage`, `grass`, `structure`, `water`, `sky`). Trocar uma
  uniform muda o mundo inteiro.
- **Cores:** sem texturas de imagem; cor de vértice + bandas toon no shader.
  Paleta: relva verde-claro, água azul-verde, céu azul-claro, sombras azuladas.
- **Nomes:** scripts em PT, `snake_case.gd`; classes `class_name` em PascalCase.
- **Nunca escrever `ALPHA` num shader espacial** (põe o material no passe
  transparente) — exceção: `stylized_water.gdshader`. O selftest impõe isto.
- **API Godot 4:** MultiMesh usa `set_instance_*` (não `instance_set_*`);
  `render_priority` é do material; `int(Vector3)` é inválido.
- **Antes de dizer "pronto":** `./tools/check.sh` verde + ler as linhas `ERROR:`
  do arranque + (se visual) uma imagem do `tools/render_shot.py`.
